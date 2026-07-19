variable "github_repo" {
  description = "owner/name of the repository allowed to assume the role."
  type        = string

  validation {
    condition     = can(regex("^[^/]+/[^/]+$", var.github_repo))
    error_message = "github_repo must be in owner/name form."
  }
}

variable "immutable_sub_claim_prefix" {
  description = <<-EOT
    GitHub's immutable subject prefix, embedding numeric org and repo IDs:
      repo:Owner@123456/name@789012

    Read it with:
      gh api repos/OWNER/REPO/actions/oidc/customization/sub

    Leave null to trust only the classic name-based claim. Supply it and both
    forms are trusted, which is what you want during the rollout.
  EOT
  type        = string
  default     = null
}

variable "subjects" {
  description = <<-EOT
    Claim suffixes to allow, appended to the repo prefix. Examples:
      ref:refs/heads/main        pushes to main
      environment:production     jobs bound to an environment
      pull_request               PR runs (careful — forks can trigger these)
  EOT
  type        = list(string)
  default     = ["ref:refs/heads/main"]
}

variable "role_name" {
  description = "Name of the IAM role GitHub Actions assumes."
  type        = string
  default     = "github-actions-deploy"
}

variable "role_description" {
  description = "Role description."
  type        = string
  default     = "Assumed by GitHub Actions via OIDC"
}

variable "create_oidc_provider" {
  description = <<-EOT
    Create the IAM OIDC provider. AWS allows only one per URL per account, so
    set false if another stack already created it.

    Check with: aws iam list-open-id-connect-providers
  EOT
  type        = bool
  default     = true
}

variable "inline_policy_json" {
  description = "Inline policy for the role. Scope it to the resources CI touches."
  type        = string
  default     = null
}

variable "managed_policy_arns" {
  description = "Managed policies to attach. Prefer an inline least-privilege policy."
  type        = list(string)
  default     = []
}

variable "max_session_duration" {
  description = "Maximum assumed-session length, seconds. Keep it near job length."
  type        = number
  default     = 3600
}

variable "tags" {
  description = "Tags applied to created resources."
  type        = map(string)
  default     = {}
}
