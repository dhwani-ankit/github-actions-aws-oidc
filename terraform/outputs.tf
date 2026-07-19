output "role_arn" {
  description = "Pass to aws-actions/configure-aws-credentials as role-to-assume."
  value       = aws_iam_role.deploy.arn
}

output "role_name" {
  value = aws_iam_role.deploy.name
}

output "oidc_provider_arn" {
  value = local.provider_arn
}

output "allowed_subjects" {
  description = "Exact sub claims this role trusts. Compare against the failing token when debugging."
  value       = local.allowed_subjects
}
