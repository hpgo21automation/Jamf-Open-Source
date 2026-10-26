# Branch protection — `main`

Branch protection for `main` is enforced in **Settings → Branches**, not
Terraform. See the comment in `github.tf` for why it isn't Terraform-managed
(least-privilege deploy pipeline; no token scope for branch-protection admin).

Keep the repo setting in sync with the policy below. This is the intended
configuration (a snapshot of the `github_branch_protection` resource that used
to be applied here):

- **Require a pull request before merging** — no direct pushes to `main`;
  force-pushes and branch deletion blocked.
- **Required approvals:** 1.
- **Dismiss stale approvals** when new commits are pushed.
- **Require review from Code Owners** — see `.github/CODEOWNERS` (your code-owners team).
- **Require conversation resolution** before merging.
- **Require branches to be up to date** before merging (strict status checks).
- **Signed commits:** not required (the team's workflow produces unsigned
  commits; requiring it would block all merges).

**Required status checks** (bare job names, must match the workflow job `name:`):

- Secret detection
- ShellCheck
- Script unit tests (BATS)
- Terraform lint & validate
- tflint
- Script shebang check
- Script ↔ Terraform sync
- Jamf exit-code audit
- BATS coverage gate
- Terraform security scan (Checkov)
- Trivy — CVE and misconfiguration scan
- Gitleaks — full history scan
- ShellCheck — full script audit
- Hardcoded credential scan
- macOS API deprecation audit

**Deliberately NOT required:** `Terraform plan preview` — advisory only.

> Changing branch protection is now a manual (click-ops) action. Update this
> file in the same PR whenever you change the rule in Settings, so the two
> don't drift.
