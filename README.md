# github-actions-aws-oidc

Terraform for letting GitHub Actions assume an AWS role via OIDC — no access keys stored in GitHub,
nothing to rotate, nothing to leak.

Plus the answer to the failure that sends most people back to static keys:

> `Could not assume role with OIDC: Not authorized to perform sts:AssumeRoleWithWebIdentity`
>
> …with a trust policy that looks completely correct.

---

## The gotcha, up front

Every guide tells you the subject claim looks like this:

```
repo:my-org/my-app:ref:refs/heads/main
```

**GitHub is rolling out "immutable" subject claims that embed numeric org and repo IDs instead:**

```
repo:my-org@263259538/my-app@1304746927:ref:refs/heads/main
```

If your trust policy matches the documented name-based form and GitHub sends the ID-based one,
`StringEquals` never matches and you get an authorization error that tells you nothing useful. The
policy is right. The claim changed.

Find out what *your* repo actually sends:

```bash
gh api repos/OWNER/REPO/actions/oidc/customization/sub
```

```json
{
  "use_default": true,
  "use_immutable_subject": false,
  "sub_claim_prefix": "repo:my-org@263259538/my-app@1304746927"
}
```

Note that `use_immutable_subject: false` and the prefix *still* carries IDs. Trust both forms:

```hcl
module "oidc" {
  source = "github.com/Doot-Workspaces/github-actions-aws-oidc//terraform"

  github_repo                = "my-org/my-app"
  immutable_sub_claim_prefix = "repo:my-org@263259538/my-app@1304746927"
  subjects                   = ["ref:refs/heads/main"]
}
```

Both are exact `StringEquals` matches — no wildcards. The ID form is arguably *stronger*, since it
survives a repository rename that would otherwise silently break, or silently transfer trust to
whoever claims the old name.

## Usage

```hcl
provider "aws" {
  region = "ap-south-1"
}

module "oidc" {
  source = "github.com/Doot-Workspaces/github-actions-aws-oidc//terraform"

  github_repo                = "my-org/my-app"
  immutable_sub_claim_prefix = "repo:my-org@263259538/my-app@1304746927"
  role_name                  = "github-actions-deploy"

  inline_policy_json = data.aws_iam_policy_document.deploy.json
}

data "aws_iam_policy_document" "deploy" {
  statement {
    actions   = ["s3:PutObject", "s3:DeleteObject", "s3:ListBucket"]
    resources = ["arn:aws:s3:::my-bucket", "arn:aws:s3:::my-bucket/*"]
  }

  statement {
    actions   = ["cloudfront:CreateInvalidation"]
    resources = ["arn:aws:cloudfront::123456789012:distribution/E1XXXXXXXXXXXX"]
  }
}
```

Then in the workflow — note `id-token: write`, without which no token is issued at all:

```yaml
permissions:
  contents: read
  id-token: write

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ secrets.AWS_DEPLOY_ROLE_ARN }}
          aws-region: ap-south-1

      - run: aws sts get-caller-identity
```

## Scoping the trust

`subjects` controls which workflow runs may assume the role.

| Subject | Allows |
|---|---|
| `ref:refs/heads/main` | Pushes to main. The usual default |
| `environment:production` | Jobs bound to a GitHub Environment — pairs well with required reviewers |
| `ref:refs/tags/*` | Tag builds. Needs `StringLike`; see the caveat below |
| `pull_request` | PR runs. **Think hard first** |

**On `pull_request`:** a fork can open a PR and, if that claim is trusted, obtain your AWS
credentials. Only allow it for roles that can do nothing dangerous.

**On wildcards:** this module uses `StringEquals` deliberately. Something like
`repo:my-org/*:ref:refs/heads/main` grants every repository in the org — including one created later
by anyone with repo-creation rights.

## Debugging a failure

1. **Is `id-token: write` set?** Missing permission is the most common cause after the claim format.
2. **Compare the actual claim.** `terraform output allowed_subjects` shows what the role trusts;
   `gh api repos/OWNER/REPO/actions/oidc/customization/sub` shows what GitHub sends. Diff them
   character by character.
3. **Branch mismatch.** A run on `develop` will not match a policy trusting `refs/heads/main`.
   `workflow_dispatch` on main *does* produce `ref:refs/heads/main`.
4. **Provider already exists.** AWS permits one OIDC provider per URL per account. Set
   `create_oidc_provider = false` if another stack made it.
5. **Give it a minute.** IAM is eventually consistent; a role created seconds before the run can
   genuinely not be there yet. If it fails once and then works, that was it.

## Inputs

| Name | Type | Default | Description |
|---|---|---|---|
| `github_repo` | `string` | — | **Required.** `owner/name` |
| `immutable_sub_claim_prefix` | `string` | `null` | ID-embedded prefix; trust both forms |
| `subjects` | `list(string)` | `["ref:refs/heads/main"]` | Claim suffixes to allow |
| `role_name` | `string` | `"github-actions-deploy"` | IAM role name |
| `create_oidc_provider` | `bool` | `true` | False if the provider already exists |
| `inline_policy_json` | `string` | `null` | Least-privilege policy for the role |
| `managed_policy_arns` | `list(string)` | `[]` | Managed policies to attach |
| `max_session_duration` | `number` | `3600` | Session length in seconds |

## Outputs

`role_arn` · `role_name` · `oidc_provider_arn` · `allowed_subjects`

## Why bother

Static access keys in GitHub secrets are valid until someone revokes them, work from anywhere, and
show up in incident reports. An OIDC token is minted per run, expires in minutes, and is bound to a
specific repository and ref. The migration is an afternoon.

## License

MIT
