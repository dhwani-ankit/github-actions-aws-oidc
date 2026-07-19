###############################################################################
# GitHub Actions -> AWS via OIDC.
#
# The workflow exchanges a short-lived OIDC token for temporary AWS
# credentials. Nothing long-lived is stored in GitHub, so there is no key to
# leak, rotate, or find in a repo three years from now.
###############################################################################

# One provider per AWS account. If it already exists, import it rather than
# creating a second — AWS permits only one provider per URL per account.
resource "aws_iam_openid_connect_provider" "github" {
  count = var.create_oidc_provider ? 1 : 0

  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]

  # AWS validates GitHub's certificate chain itself now, but the API still
  # requires this field to be present.
  thumbprint_list = [
    "6938fd4d98bab03faadb97b34396831e3780aea1",
    "1c58a3a8518e8759bf075b76b750d4f2df264fcd",
  ]

  tags = var.tags
}

data "aws_iam_openid_connect_provider" "existing" {
  count = var.create_oidc_provider ? 0 : 1
  url   = "https://token.actions.githubusercontent.com"
}

locals {
  provider_arn = var.create_oidc_provider ? aws_iam_openid_connect_provider.github[0].arn : data.aws_iam_openid_connect_provider.existing[0].arn

  # GitHub is migrating to "immutable" subject claims that embed numeric org
  # and repo IDs alongside the classic name-based form. Which one arrives
  # depends on rollout state, so both are trusted when the immutable prefix is
  # supplied. Both are exact matches — no wildcards.
  #
  # Read the immutable prefix for a repo with:
  #   gh api repos/OWNER/REPO/actions/oidc/customization/sub
  #
  # This is the single most common reason a correct-looking trust policy still
  # returns "Not authorized to perform sts:AssumeRoleWithWebIdentity".
  classic_subjects = [for r in var.subjects : "repo:${var.github_repo}:${r}"]

  immutable_subjects = var.immutable_sub_claim_prefix == null ? [] : [
    for r in var.subjects : "${var.immutable_sub_claim_prefix}:${r}"
  ]

  allowed_subjects = concat(local.classic_subjects, local.immutable_subjects)
}

data "aws_iam_policy_document" "assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # StringEquals, not StringLike. A wildcard here — say
    # repo:my-org/*:ref:refs/heads/main — lets any repo in the org assume this
    # role, which is almost never what is intended.
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = local.allowed_subjects
    }
  }
}

resource "aws_iam_role" "deploy" {
  name                 = var.role_name
  description          = var.role_description
  assume_role_policy   = data.aws_iam_policy_document.assume.json
  max_session_duration = var.max_session_duration
  tags                 = var.tags
}

resource "aws_iam_role_policy" "inline" {
  count = var.inline_policy_json == null ? 0 : 1

  name   = "${var.role_name}-inline"
  role   = aws_iam_role.deploy.id
  policy = var.inline_policy_json
}

resource "aws_iam_role_policy_attachment" "managed" {
  for_each = toset(var.managed_policy_arns)

  role       = aws_iam_role.deploy.name
  policy_arn = each.value
}
