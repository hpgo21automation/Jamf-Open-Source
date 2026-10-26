# jamf-tf

Terraform configuration for managing Example's entire Jamf Pro environment as code. All policies, scripts, configuration profiles, smart groups, extension attributes, and app deployments are defined here — changes to Jamf go through this repo, not the Jamf UI.

## What's managed

| Resource | File(s) | Count |
|---|---|---|
| Policies | `policies.tf` | 40+ |
| Scripts | `scripts.tf` + `scripts/` | 50+ bash scripts |
| Configuration Profiles | `configuration_profiles.tf` + `profiles/` | 30+ mobileconfigs |
| Smart Groups | `smart_groups.tf` | 20+ |
| Extension Attributes | `extension_attributes.tf` | 10+ |
| App Catalog installers | `app_installers.tf` | 15+ |
| Homebrew packages | `homebrew_installers.tf` | varies |
| Devices | `devices.tf` | 14 Macs |

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/downloads) >= 1.5.0
- [terraform-provider-jamfpro](https://registry.terraform.io/providers/deploymenttheory/jamfpro/latest) ~> 0.30.0
- Jamf Pro API Client (OAuth2) with the permissions listed below
- GCP credentials with access to the Terraform state bucket (see [Remote state](#remote-state-gcs)) — `gcloud auth application-default login`
- [ShellCheck](https://www.shellcheck.net/) for script linting (`brew install shellcheck`)
- [pre-commit](https://pre-commit.com/) for local hooks (`brew install pre-commit`)

### Required Jamf Pro API permissions

Create an API Role at **Settings → System → API Roles and Clients** with:

- Categories: Create, Read, Update, Delete
- Scripts: Create, Read, Update, Delete
- Policies: Create, Read, Update, Delete
- Configuration Profiles (Computer): Create, Read, Update, Delete, Deploy
- Smart Computer Groups: Create, Read, Update, Delete
- Computer Extension Attributes: Create, Read, Update, Delete
- App Installers: Create, Read, Update, Delete
- Computers: Read, Update

## Setup

### 1. Configure credentials

```bash
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` with your instance details and API credentials — this file is gitignored and never committed.

```hcl
jamfpro_instance_fqdn = "https://example.jamfcloud.com"
jamfpro_client_id     = "your-client-id"
jamfpro_client_secret = "your-client-secret"
```

### 2. Initialize and validate

```bash
gcloud auth application-default login  # one-time — state lives in GCS (see "Remote state")
terraform init
terraform validate
terraform fmt -check
```

### 3. Plan before applying

Always review the plan before applying, especially for policies and profiles which deploy to live devices:

```bash
terraform plan -parallelism=1
```

### 4. Apply

```bash
terraform apply -parallelism=1
```

> `-parallelism=1` is required — the Jamf Pro API has strict rate limits and ordering dependencies between resources.

## Remote state (GCS)

Terraform state for this repo lives in a remote, versioned GCS backend (`backend.tf`), using a shared state bucket (replace `your-terraform-state-bucket` with your own) with a per-repo prefix.

```hcl
terraform {
  backend "gcs" {
    bucket = "your-terraform-state-bucket"
    prefix = "jamf-tf"
  }
}
```

- **Versioning** — object versioning on the bucket keeps prior state revisions recoverable.
- **Locking** — the GCS backend does native state locking (a `.tflock` object written next to the state in the same bucket), so concurrent applies are blocked without any separate lock table. This is the "cloud bucket for the lock file" — no DynamoDB-equivalent is needed.
- **Access** — you need GCP credentials with read/write on the bucket prefix: `gcloud auth application-default login` before `terraform init`.

### One-time migration from local state (human runbook — do not automate)

Run these on the machine that currently holds the authoritative local `terraform.tfstate`, after the backend PR merges:

1. `git pull` so `backend.tf` is present, then authenticate: `gcloud auth application-default login`
2. Back up local state first: `cp terraform.tfstate terraform.tfstate.pre-migration-backup`
3. Migrate: `terraform init -migrate-state` — answer `yes` when Terraform asks to copy existing state to the new `gcs` backend
4. Verify the remote copy exists: `gsutil ls gs://your-terraform-state-bucket/jamf-tf/` (expect `default.tfstate`)
5. Verify a clean plan against the remote backend: `terraform plan -parallelism=1` → expect **no changes** (cosmetic provider drift excepted — see Troubleshooting)
6. Only after steps 4–5 look good, delete local state copies: `rm terraform.tfstate terraform.tfstate.* *.backup` — the remote copy is now the single source of truth

### CI note

The `Terraform plan preview` job in `pr-checks.yml` initializes with `terraform init -backend=false -input=false`: that PR-preview job has no GCP credentials for the state bucket and intentionally plans from empty state. The real, state-aware plan/apply happens in the gated apply workflow below.

### Deployments & approvals (GitHub Actions)

Deployments run through GitHub Actions, using a standard GitHub Actions flow — plan on PR, gated apply on merge:

1. **Plan on every PR** — `pr-checks.yml` posts a Terraform plan preview as a PR comment (advisory; see CI note above).
2. **Gated apply on merge to `main`** — `.github/workflows/terraform-apply.yml` runs `terraform apply -parallelism=1` against the GCS backend, but only after a reviewer approves the **`prod` GitHub Environment**. That approval is the deploy gate; nothing is applied to Jamf until it is granted.

One-time setup:

- Create the **`prod`** Environment (**Settings → Environments**) with a **required reviewer** — this is the apply approval.
- Add repo secrets (**Settings → Secrets and variables → Actions → Secrets**):
  - `GOOGLE_CREDENTIALS` — JSON key for a GCP SA with read/write on `your-terraform-state-bucket`.
  - `JAMF_CLIENT_ID` / `JAMF_CLIENT_SECRET` — Jamf Pro API client credentials (already used by `pr-checks.yml`).
  - `CROWDSTRIKE_CID` — CrowdStrike CID (sensitive; required Terraform variable).
- Add repo variables (**Settings → Secrets and variables → Actions → Variables**):
  - `SLACK_CHANNEL_ID` / `SLACK_TEAM_ID` / `SLACK_IT_LEAD_USER_ID`  Slack IDs used by the alert and compliance workflows (optional; skip the Slack workflows if you don't use Slack).
  - `LENS_PACKAGE_ID` — Jamf package id for the Lens installer (not sensitive; required Terraform variable).

The GCS backend is what the apply workflow reads, locks, and writes — Actions stores no state itself.

## Repository structure

```
jamf-tf/
├── .github/
│   └── workflows/
│       ├── pr-checks.yml        # Runs on every PR: lint, validate, plan preview, security scan
│       ├── terraform-apply.yml  # Gated apply on merge to main (prod Environment approval)
│       └── security-scan.yml    # Weekly scheduled secret and CVE scan
├── profiles/                   # .mobileconfig files (configuration profiles)
├── scripts/                    # Bash scripts deployed as Jamf policies
├── tests/                      # BATS tests for script exit-code behaviour
│   └── scripts.bats
├── app_installers.tf            # Jamf App Catalog deployments
├── apps.auto.tfvars             # App catalog configuration (committed)
├── backend.tf                   # Remote state backend (GCS) — see "Remote state"
├── configuration_profiles.tf    # Profile resources
├── data.tf                      # Data sources (categories, groups, etc.)
├── devices.tf                   # Static device records
├── extension_attributes.tf      # Extension attribute resources
├── global_settings.tf           # Org-wide Jamf settings
├── homebrew.auto.tfvars         # Homebrew package list (committed)
├── homebrew_installers.tf       # Per-formula Self Service policies
├── main.tf                      # Provider configuration
├── outputs.tf                   # Output values
├── policies.tf                  # All policy resources
├── resources.tf                 # Categories and shared resources
├── scripts.tf                   # Script resources (inlines scripts/ content)
├── smart_groups.tf              # Smart group resources
├── terraform.tfvars             # Secrets — gitignored, never commit
├── terraform.tfvars.example     # Template for new contributors
├── variables.tf                 # Variable schema
└── versions.tf                  # Provider version constraints
```

## Making changes

### Adding or editing a script

1. Edit or create the file in `scripts/`
2. Run ShellCheck locally: `shellcheck scripts/your_script.sh`
3. The script is referenced in `scripts.tf` — check that the `templatefile()` call passes any required variables
4. `terraform plan` to preview — Terraform will show the script diff
5. Open a PR; CI will run ShellCheck and BATS tests automatically

### Adding a configuration profile

1. Export the `.mobileconfig` from Jamf or create it manually
2. Place it in `profiles/`
3. Add a `jamfpro_macos_configuration_profile_plist` resource in `configuration_profiles.tf`
4. Reference the correct smart group for scope

### Updating policy scope or triggers

Edit the relevant resource block in `policies.tf` and run `terraform plan` to confirm only the intended resource changes.

### Script versioning (Splunk pattern)

Scripts that need to self-track their version (e.g. `configure_splunk_inputs.sh`) inject a hash via `templatefile()` in `scripts.tf`. Changing the script content automatically changes the hash, which triggers Jamf's EA-based smart group to re-run the policy on all devices. Do not edit those scripts directly in Jamf.

## CI / CD

Every PR runs the following checks automatically (see `.github/workflows/pr-checks.yml`):

| Check | Tool | What it catches |
|---|---|---|
| Script linting | ShellCheck | Quoting bugs, unbound variables, exit code mistakes |
| Script tests | BATS | Exit code regressions on key scripts |
| Terraform format | `terraform fmt -check` | Unformatted HCL |
| Terraform validation | `terraform validate` | Schema errors, missing references |
| Terraform plan preview | `terraform plan` | Advisory diff posted as a PR comment (empty-state preview) |
| Secret detection | Gitleaks | Accidentally committed credentials |
| Security scan | Checkov | Terraform misconfigurations and policy violations |

A weekly scan also runs Trivy for CVEs in any provider binaries.

On merge to `main`, `.github/workflows/terraform-apply.yml` runs the real `terraform apply` against the GCS backend, gated behind the `prod` GitHub Environment's required-reviewer approval (see [Deployments & approvals](#deployments--approvals-github-actions)).

### Running checks locally

```bash
# Install hooks (one-time)
pre-commit install

# Run all checks against staged files
pre-commit run

# Run all checks against every file
pre-commit run --all-files

# Run BATS tests
bats tests/scripts.bats

# ShellCheck all scripts
shellcheck scripts/*.sh
```

## Security notes

- `terraform.tfvars` is gitignored — credentials never touch git
- Terraform state lives in GCS and can contain resource attributes — access to the state bucket is IAM-restricted; never commit state files or copy them out of the bucket
- Sensitive variables (`jamfpro_client_secret`, `crowdstrike_cid`, `crowdstrike_provisioning_token`) are marked `sensitive = true` in `variables.tf` and redacted from plan output
- Avoid setting sensitive defaults directly in `variables.tf`; use `terraform.tfvars` instead
- The Gitleaks step in CI will block any PR that accidentally includes a secret
- FileVault keys are reissued via `filevault_reissue_key.sh` and transmitted only over the Jamf management channel — never logged

## Common commands

```bash
# Format all HCL
terraform fmt -r

# Validate without connecting to Jamf
terraform validate

# Preview all changes
terraform plan -parallelism=1

# Apply
terraform apply -parallelism=1

# Target a single resource (use sparingly)
terraform apply -target=jamfpro_script.configure_splunk_inputs -parallelism=1

# Inspect state
terraform state list
terraform state show jamfpro_policy.verify_secure_token

# Import an existing Jamf resource into state
terraform import jamfpro_script.my_script <jamf_script_id>
```

## Troubleshooting

**`terraform apply` fails with 409 Conflict**
Jamf's API occasionally returns 409 when resources are modified in quick succession. Re-run with `-parallelism=1` (should already be set). If it persists, wait 30 seconds and retry.

**`Error acquiring the state lock`**
Someone (or the apply workflow) is mid-apply — wait for them to finish. If a lock is genuinely stale (crashed run), confirm nobody is applying, then `terraform force-unlock <LOCK_ID>`.

**Policy shows as Failed in Jamf but script logic looks correct**
Check whether the policy frequency is *Once per computer* — a single failed run permanently marks it failed and it will not retry. Use *Ongoing* for remediation policies or fix the exit code and flush the policy log from the device record.

**`terraform plan` shows unexpected drift**
The Jamf provider occasionally reads back values in a different format than it wrote them (e.g. scope ordering). Run `terraform apply` — if the change is cosmetic the drift will clear after one apply with no real effect on devices.

**ShellCheck SC2086 / SC2046 warnings**
Always double-quote variable expansions in scripts: `"$VAR"` not `$VAR`. See the [ShellCheck wiki](https://github.com/koalaman/shellcheck/wiki) for explanations.

## Resources

- [Jamf Pro Terraform Provider docs](https://registry.terraform.io/providers/deploymenttheory/jamfpro/latest/docs)
- [Terraform CLI docs](https://developer.hashicorp.com/terraform/docs)
- [Terraform GCS backend docs](https://developer.hashicorp.com/terraform/language/backend/gcs)
- [ShellCheck](https://www.shellcheck.net/)
- [BATS — Bash Automated Testing System](https://github.com/bats-core/bats-core)
- [Mac Admins Slack — #terraform-provider-jamfpro](https://macadmins.slack.com)
- [Jamf Nation](https://community.jamf.com/)

## Adapting this repo

This was extracted from a real deployment, so some values are specific to the original environment and need to be replaced with your own:

- **Hostnames** — `example.jamfcloud.com`, `example.okta.com`, `example.splunkcloud.com` are placeholders.
- **Jamf IDs** — package and smart-group IDs in `policies.tf` and the `*.auto.tfvars` files (e.g. `id = 6 # ...pkg`) are tenant-specific; look yours up in Jamf Pro.
- **Redacted credentials** — the CrowdStrike CID/token, Jamf Connect license, and Okta client ID in `profiles/` are `REDACTED`. Supply your own.
- **GitHub / GCS** — `your-github-org` in `main.tf`, `your-org/your-team` in `.github/CODEOWNERS`, and `your-terraform-state-bucket` in `backend.tf`.

## License

Released under the [MIT License](LICENSE).
