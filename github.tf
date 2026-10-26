# Branch protection for `main` is intentionally NOT managed by Terraform.
#
# The gated apply pipeline runs with a least-privilege GITHUB_TOKEN
# (`contents: read`). GitHub Actions has no `permissions:` scope that grants a
# token the repo-admin access needed to read or write branch protection, so
# managing this resource here forced `terraform apply` to fail with
# "Resource not accessible by integration" on every run. The alternative —
# handing the deploy pipeline a long-lived admin PAT — would let the pipeline
# rewrite the very guardrails that gate it, which we don't want.
#
# So branch protection for `main` is managed directly in
# Settings -> Branches. The policy and its rationale are documented in
# docs/branch-protection.md so they stay in version control even though the
# rule is applied by hand.
#
# Removed from Terraform state on 2026-08-12 via
#   terraform state rm github_branch_protection.main
# The live protection rule was left in place.
