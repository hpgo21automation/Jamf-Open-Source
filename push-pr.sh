#!/bin/bash
# Creates two clean PRs:
#   PR 1 — papercut-hive → main         (your pending work)
#   PR 2 — fix/policy-script-failures → papercut-hive  (Claude's 8 bug fixes)
#
# Usage: cd ~/jamf-tf && bash push-pr.sh

set -e

echo "=== Pushing both branches ==="
git push origin papercut-hive
git push --set-upstream origin fix/policy-script-failures

echo ""
echo "=== PR 1: your pending work (papercut-hive → main) ==="
EXISTING_1=$(gh pr list --head papercut-hive --json number --jq '.[0].number' 2>/dev/null)
if [[ -n "$EXISTING_1" ]]; then
    echo "Already exists: $(gh pr view "$EXISTING_1" --json url --jq '.url')"
else
    gh pr create \
        --head papercut-hive \
        --base main \
        --title "papercut-hive: Homebrew CLT fixes, PaperCut, RingCentral, fleet improvements" \
        --body "$(cat <<BODY
## Summary

$(git log --reverse main..papercut-hive --pretty=format:"- %s")

## Test plan

- [ ] Verify Homebrew Package Installer CLT check works on fresh enrolment
- [ ] Confirm PaperCut Hive installs cleanly
- [ ] Confirm RingCentral screen recording PPPC approval applies

🤖 Generated with [Claude Code](https://claude.com/claude-code)
BODY
)"
fi

echo ""
echo "=== PR 2: script bug fixes (fix/policy-script-failures → papercut-hive) ==="
EXISTING_2=$(gh pr list --head fix/policy-script-failures --json number --jq '.[0].number' 2>/dev/null)
if [[ -n "$EXISTING_2" ]]; then
    echo "Already exists: $(gh pr view "$EXISTING_2" --json url --jq '.url')"
else
    gh pr create \
        --head fix/policy-script-failures \
        --base papercut-hive \
        --title "fix: resolve all 8 script bugs causing repeated policy failures" \
        --body "$(cat <<BODY
## Summary

Analysed Jamf policy failure logs across the 14-device fleet. Eight root-cause bugs found and fixed. All scripts now exit 0 gracefully when a prerequisite is absent so Once-per-computer policies are not permanently marked failed.

- **verify_secure_token.sh** – only exit 1 when FileVault is ON with no SecureToken; pre-enrollment devices exit 0
- **install_podman.sh** – graceful exit on GitHub API rate-limit; arch-aware .pkg URL with universal fallback
- **configure_docker.sh** – treat install as success when helper files exist (newer Docker Desktop returns non-zero even on success)
- **disable_screensaver.sh** – exit 0 when wallpaper not yet deployed (Ongoing policy retries on next check-in)
- **update_gcloud_cli.sh** – dynamic gcloud discovery across 4 paths; run \`components update\` as console user not root
- **fix_npm_global_prefix.sh** – exit 0 when npm not yet installed (keeps Once-per-computer retryable)
- **install_homebrew_monitor_daemon.sh** – log rotation in embedded daemon (10 MB cap → last 500 lines); stops launchd throttling crash loop firing ~800x/day on some devices
- **configure_splunk_inputs.sh** – 10-iteration retry loop for splunkd startup (50 s max) instead of single 5-second wait

## Test plan

- [ ] Trigger \`Verify Secure Token Status\` on a device where FV is off — confirm it passes
- [ ] Confirm \`Remediate Homebrew Monitor Daemon\` stops firing every 15 min on devices 12, 18, 25
- [ ] Confirm \`Fix npm Global Prefix\` passes on a fresh enrolment

🤖 Generated with [Claude Code](https://claude.com/claude-code)
BODY
)"
fi

echo ""
echo "Done. Merge PR 1 first, then PR 2 will fast-forward cleanly."
