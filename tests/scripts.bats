#!/usr/bin/env bats
# BATS unit tests for Example Jamf scripts
#
# Tests focus on exit-code correctness — the class of bug that caused
# repeated policy failures across the fleet (scripts exiting 1 in
# expected/pre-enrollment conditions).
#
# Run locally:  bats tests/scripts.bats
# Dependencies: bats-core (brew install bats-core)

# ── Helpers ──────────────────────────────────────────────────────────────────

SCRIPTS_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../scripts" && pwd)"

# Stub a command to print a fixed string and exit 0
stub_cmd() {
    local cmd="$1"; shift
    local output="$*"
    eval "function $cmd() { echo \"$output\"; return 0; }"
    export -f "$cmd"
}

# ── verify_secure_token.sh ───────────────────────────────────────────────────

@test "verify_secure_token: exits 0 when FileVault is off and no SecureToken" {
    # Simulate a fresh-enrolled device: FV off, no users with SecureToken
    export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
    mkdir -p "$BATS_TEST_TMPDIR/bin"

    # Stub fdesetup to report FV off
    cat > "$BATS_TEST_TMPDIR/bin/fdesetup" << 'EOF'
#!/bin/bash
echo "FileVault is Off."
exit 0
EOF
    chmod +x "$BATS_TEST_TMPDIR/bin/fdesetup"

    # Stub sysadminctl to report no SecureToken
    cat > "$BATS_TEST_TMPDIR/bin/sysadminctl" << 'EOF'
#!/bin/bash
echo "No SecureToken."
exit 0
EOF
    chmod +x "$BATS_TEST_TMPDIR/bin/sysadminctl"

    run bash "$SCRIPTS_DIR/verify_secure_token.sh"
    [ "$status" -eq 0 ]
}

@test "verify_secure_token: exits 1 when FileVault is ON and no SecureToken" {
    export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
    mkdir -p "$BATS_TEST_TMPDIR/bin"

    cat > "$BATS_TEST_TMPDIR/bin/fdesetup" << 'EOF'
#!/bin/bash
echo "FileVault is On."
exit 0
EOF
    chmod +x "$BATS_TEST_TMPDIR/bin/fdesetup"

    cat > "$BATS_TEST_TMPDIR/bin/sysadminctl" << 'EOF'
#!/bin/bash
echo "No SecureToken."
exit 0
EOF
    chmod +x "$BATS_TEST_TMPDIR/bin/sysadminctl"

    run bash "$SCRIPTS_DIR/verify_secure_token.sh"
    [ "$status" -eq 1 ]
}

# ── fix_npm_global_prefix.sh ─────────────────────────────────────────────────

@test "fix_npm_global_prefix: exits 0 when no user is logged in" {
    export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
    mkdir -p "$BATS_TEST_TMPDIR/bin"

    # Stub scutil to return empty (no console user)
    cat > "$BATS_TEST_TMPDIR/bin/scutil" << 'EOF'
#!/bin/bash
exit 0
EOF
    chmod +x "$BATS_TEST_TMPDIR/bin/scutil"

    run bash "$SCRIPTS_DIR/fix_npm_global_prefix.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"No user logged in"* ]]
}

@test "fix_npm_global_prefix: exits 0 when npm is not installed" {
    # Restrict PATH to exclude /usr/local/bin (where npm lives on ubuntu-latest)
    # so command -v npm finds nothing, simulating a machine without npm
    export PATH="$BATS_TEST_TMPDIR/bin:/usr/sbin:/usr/bin:/sbin:/bin"
    mkdir -p "$BATS_TEST_TMPDIR/bin"

    # Stub scutil to return a real user
    cat > "$BATS_TEST_TMPDIR/bin/scutil" << 'EOF'
#!/bin/bash
echo "  Name : testuser"
exit 0
EOF
    chmod +x "$BATS_TEST_TMPDIR/bin/scutil"

    # Stub dscl
    cat > "$BATS_TEST_TMPDIR/bin/dscl" << 'EOF'
#!/bin/bash
echo "NFSHomeDirectory: /Users/testuser"
exit 0
EOF
    chmod +x "$BATS_TEST_TMPDIR/bin/dscl"

    # npm does NOT exist in PATH — script should exit 0 gracefully
    run bash "$SCRIPTS_DIR/fix_npm_global_prefix.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"npm not found"* ]]
}

# ── disable_screensaver.sh ───────────────────────────────────────────────────

@test "disable_screensaver: exits 0 when wallpaper file does not exist" {
    export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
    mkdir -p "$BATS_TEST_TMPDIR/bin"

    # Stub stat to return a non-root user
    cat > "$BATS_TEST_TMPDIR/bin/stat" << 'EOF'
#!/bin/bash
echo "testuser"
exit 0
EOF
    chmod +x "$BATS_TEST_TMPDIR/bin/stat"

    # Wallpaper path does not exist — script must exit 0
    run bash "$SCRIPTS_DIR/disable_screensaver.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"skipping"* ]]
}

# ── configure_docker.sh ──────────────────────────────────────────────────────

@test "configure_docker: exits 0 when Docker.app is not installed" {
    run bash "$SCRIPTS_DIR/configure_docker.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"not installed"* ]]
}

# ── install_podman.sh ────────────────────────────────────────────────────────

@test "install_podman: exits 0 on GitHub API rate limit" {
    export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
    mkdir -p "$BATS_TEST_TMPDIR/bin"

    # Stub curl to return a rate-limit response
    cat > "$BATS_TEST_TMPDIR/bin/curl" << 'EOF'
#!/bin/bash
echo '{"message":"API rate limit exceeded","documentation_url":"https://docs.github.com/rest/overview/resources-in-the-rest-api#rate-limiting"}'
exit 0
EOF
    chmod +x "$BATS_TEST_TMPDIR/bin/curl"

    run bash "$SCRIPTS_DIR/install_podman.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"rate limit"* ]]
}

# ── update_gcloud_cli.sh ─────────────────────────────────────────────────────

@test "update_gcloud_cli: exits 0 when no user is logged in" {
    export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
    mkdir -p "$BATS_TEST_TMPDIR/bin"

    # Stub stat to return empty (no console user)
    cat > "$BATS_TEST_TMPDIR/bin/stat" << 'EOF'
#!/bin/bash
exit 0
EOF
    chmod +x "$BATS_TEST_TMPDIR/bin/stat"

    run bash "$SCRIPTS_DIR/update_gcloud_cli.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"skipping"* ]]
}

@test "update_gcloud_cli: exits 0 when gcloud is not installed" {
    export PATH="$BATS_TEST_TMPDIR/bin:/usr/sbin:/usr/bin:/sbin:/bin"
    mkdir -p "$BATS_TEST_TMPDIR/bin"

    cat > "$BATS_TEST_TMPDIR/bin/stat" << 'EOF'
#!/bin/bash
echo "testuser"
exit 0
EOF
    chmod +x "$BATS_TEST_TMPDIR/bin/stat"

    cat > "$BATS_TEST_TMPDIR/bin/dscl" << 'EOF'
#!/bin/bash
echo "NFSHomeDirectory: /Users/testuser"
exit 0
EOF
    chmod +x "$BATS_TEST_TMPDIR/bin/dscl"

    # gcloud does NOT exist anywhere — script should exit 0
    run bash "$SCRIPTS_DIR/update_gcloud_cli.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"not installed"* ]]
}

# ── homebrew_monitor_daemon log rotation ─────────────────────────────────────

@test "install_homebrew_monitor_daemon: embedded script has log rotation" {
    # The daemon script must call rotate_log — absence means the crash loop fix is missing
    grep -q "rotate_log" "$SCRIPTS_DIR/install_homebrew_monitor_daemon.sh"
}

@test "install_homebrew_monitor_daemon: rotate_log truncates log at 10MB" {
    grep -q "10 \* 1024 \* 1024" "$SCRIPTS_DIR/install_homebrew_monitor_daemon.sh"
}

# ── configure_splunk_inputs.sh ───────────────────────────────────────────────

@test "configure_splunk_inputs: uses retry loop not single pgrep" {
    # Must have a retry loop — single pgrep after 5s causes false failures on slow machines
    grep -q "seq 1 10" "$SCRIPTS_DIR/configure_splunk_inputs.sh"
}

@test "configure_splunk_inputs: exits 0 when Splunk is not installed" {
    run bash "$SCRIPTS_DIR/configure_splunk_inputs.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"not installed"* ]]
}

# ── manage_crowdstrike.sh ────────────────────────────────────────────────────

@test "manage_crowdstrike: exits 1 when CID not provided" {
    export PATH="$BATS_TEST_TMPDIR/bin:/usr/sbin:/usr/bin:/sbin:/bin"
    mkdir -p "$BATS_TEST_TMPDIR/bin"

    run bash "$SCRIPTS_DIR/manage_crowdstrike.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"CID not provided"* ]]
}

@test "manage_crowdstrike: exits 1 when not installed and jamf binary absent" {
    # No Falcon.app, no jamf binary — install path fails fast with a clear error
    export PATH="$BATS_TEST_TMPDIR/bin:/usr/sbin:/usr/bin:/sbin:/bin"
    mkdir -p "$BATS_TEST_TMPDIR/bin"

    run bash "$SCRIPTS_DIR/manage_crowdstrike.sh" "" "" "" "TESTCID"
    [ "$status" -eq 1 ]
    [[ "$output" == *"falconctl not found after pkg install"* ]]
}

# ── add_to_developer_group ───────────────────────────────────────────────────

@test "add_to_developer_group: exits 0 and adds user when not already a member" {
    export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
    mkdir -p "$BATS_TEST_TMPDIR/bin"

    # scutil stub: returns a logged-in user
    cat > "$BATS_TEST_TMPDIR/bin/scutil" << 'EOF'
#!/bin/bash
echo "   Name : testuser"
EOF
    chmod +x "$BATS_TEST_TMPDIR/bin/scutil"

    # dsmemberutil stub: reports not a member
    cat > "$BATS_TEST_TMPDIR/bin/dsmemberutil" << 'EOF'
#!/bin/bash
echo "not a member"
EOF
    chmod +x "$BATS_TEST_TMPDIR/bin/dsmemberutil"

    # dscl stub: records the append call
    cat > "$BATS_TEST_TMPDIR/bin/dscl" << 'EOF'
#!/bin/bash
echo "dscl $*"
EOF
    chmod +x "$BATS_TEST_TMPDIR/bin/dscl"

    run bash "$SCRIPTS_DIR/add_to_developer_group.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Added testuser to _developer group"* ]]
}

@test "add_to_developer_group: exits 0 without calling dscl when already a member" {
    export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
    mkdir -p "$BATS_TEST_TMPDIR/bin"

    cat > "$BATS_TEST_TMPDIR/bin/scutil" << 'EOF'
#!/bin/bash
echo "   Name : testuser"
EOF
    chmod +x "$BATS_TEST_TMPDIR/bin/scutil"

    cat > "$BATS_TEST_TMPDIR/bin/dsmemberutil" << 'EOF'
#!/bin/bash
echo "testuser is a member of _developer"
EOF
    chmod +x "$BATS_TEST_TMPDIR/bin/dsmemberutil"

    run bash "$SCRIPTS_DIR/add_to_developer_group.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"already in the _developer group"* ]]
}

@test "add_to_developer_group: exits 1 when no user is logged in" {
    export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
    mkdir -p "$BATS_TEST_TMPDIR/bin"

    cat > "$BATS_TEST_TMPDIR/bin/scutil" << 'EOF'
#!/bin/bash
echo ""
EOF
    chmod +x "$BATS_TEST_TMPDIR/bin/scutil"

    run bash "$SCRIPTS_DIR/add_to_developer_group.sh"
    [ "$status" -eq 1 ]
}

# ── reset_loom_tcc ────────────────────────────────────────────────────────────

@test "reset_loom_tcc: exits 0 when tccutil succeeds" {
    export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
    mkdir -p "$BATS_TEST_TMPDIR/bin"
    printf '#!/bin/bash\nexit 0\n' > "$BATS_TEST_TMPDIR/bin/tccutil"
    chmod +x "$BATS_TEST_TMPDIR/bin/tccutil"

    run bash "$SCRIPTS_DIR/reset_loom_tcc.sh"
    [ "$status" -eq 0 ]
}

@test "reset_loom_tcc: exits 0 even when tccutil returns non-zero (entry not present)" {
    export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
    mkdir -p "$BATS_TEST_TMPDIR/bin"
    printf '#!/bin/bash\nexit 1\n' > "$BATS_TEST_TMPDIR/bin/tccutil"
    chmod +x "$BATS_TEST_TMPDIR/bin/tccutil"

    run bash "$SCRIPTS_DIR/reset_loom_tcc.sh"
    [ "$status" -eq 0 ]
}

# ── install_splunk_uf.sh ──────────────────────────────────────────────────────

@test "install_splunk_uf: exits 1 (FATAL) when not installed and no credentials file present" {
    # Fresh machine with no forwarder and no SplunkCloud .spl: the package step
    # must be treated as failed and the script fails fast with diagnostics
    # rather than burning install attempts.
    export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
    mkdir -p "$BATS_TEST_TMPDIR/bin"

    # Stub curl so the package-failure diagnostics make no real network calls.
    cat > "$BATS_TEST_TMPDIR/bin/curl" << 'EOF'
#!/bin/bash
echo "000"
exit 0
EOF
    chmod +x "$BATS_TEST_TMPDIR/bin/curl"

    run bash "$SCRIPTS_DIR/install_splunk_uf.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"credentials file not found"* ]]
}

@test "install_splunk_uf: targets darwin-arm64 and never synthesises a version-only URL" {
    # Regression for the 404 download bug: the URL must carry the real arm64
    # asset (hash included), not a constructed splunkforwarder-<ver>-universal2.
    grep -q 'darwin-arm64\.tgz' "$SCRIPTS_DIR/install_splunk_uf.sh"
    run grep -F 'splunkforwarder-${VERSION}' "$SCRIPTS_DIR/install_splunk_uf.sh"
    [ "$status" -ne 0 ]
}

@test "install_splunk_uf: has version-gated upgrade logic" {
    # The in-place upgrade path must exist (compare installed vs target, upgrade).
    grep -q 'version_lt' "$SCRIPTS_DIR/install_splunk_uf.sh"
    grep -q 'upgrade_splunk_uf' "$SCRIPTS_DIR/install_splunk_uf.sh"
    grep -q 'get_installed_version' "$SCRIPTS_DIR/install_splunk_uf.sh"
}

# ── ea_splunk_uf_version.sh ───────────────────────────────────────────────────

@test "ea_splunk_uf_version: reports Not Installed when forwarder absent" {
    run bash "$SCRIPTS_DIR/ea_splunk_uf_version.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == "<result>Not Installed</result>" ]]
}

# ── ea_splunk_mcp_status.sh ───────────────────────────────────────────────────

@test "ea_splunk_mcp_status: reports NO_CONFIG when managed-mcp.json absent" {
    export MCP_FILE="$BATS_TEST_TMPDIR/does-not-exist.json"
    run bash "$SCRIPTS_DIR/ea_splunk_mcp_status.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == "<result>NO_CONFIG</result>" ]]
}

@test "ea_splunk_mcp_status: reports NO_CONFIG when file has no splunk server" {
    echo '{"mcpServers":{}}' > "$BATS_TEST_TMPDIR/managed-mcp.json"
    export MCP_FILE="$BATS_TEST_TMPDIR/managed-mcp.json"
    run bash "$SCRIPTS_DIR/ea_splunk_mcp_status.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == "<result>NO_CONFIG</result>" ]]
}

# ── install_gcloud_cli_with_setup.sh ──────────────────────────────────────────

@test "install_gcloud_cli_with_setup: uses plain darwin tarballs (no bundled-python 404)" {
    # Regression: Google removed the *-bundled-python tarballs (now 404); the
    # download URLs must use the plain tarballs.
    run grep -F 'bundled-python.tar.gz' "$SCRIPTS_DIR/install_gcloud_cli_with_setup.sh"
    [ "$status" -ne 0 ]
    grep -q 'google-cloud-cli-darwin-arm\.tar\.gz' "$SCRIPTS_DIR/install_gcloud_cli_with_setup.sh"
    grep -q 'google-cloud-cli-darwin-x86_64\.tar\.gz' "$SCRIPTS_DIR/install_gcloud_cli_with_setup.sh"
}

# ── deploy_papercut_hive.sh ───────────────────────────────────────────────────

@test "deploy_papercut_hive: exits 1 when no papercut-hive zip is staged" {
    run bash "$SCRIPTS_DIR/deploy_papercut_hive.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"No papercut-hive"* ]]
}

@test "deploy_papercut_hive: copies (not destructively moves) the zip out of Waiting Room" {
    # Regression: previous mv -f consumed the source so a failed install left
    # nothing for the retry. Must copy.
    grep -qF 'cp -f "$ZIP"' "$SCRIPTS_DIR/deploy_papercut_hive.sh"
    run grep -F 'mv -f "$ZIP"' "$SCRIPTS_DIR/deploy_papercut_hive.sh"
    [ "$status" -ne 0 ]
}

# ── upgrade_homebrew_packages.sh ──────────────────────────────────────────────

@test "upgrade_homebrew_packages: increments FAILED without C-style ((FAILED++)) under set -e" {
    # Regression: ((FAILED++)) evaluates to 0 (non-zero exit) when FAILED=0,
    # which aborts the script under set -e. Must use arithmetic assignment.
    grep -qF 'FAILED=$((FAILED + 1))' "$SCRIPTS_DIR/upgrade_homebrew_packages.sh"
    # No C-style ((FAILED++)) in actual code (a comment may still reference it).
    run bash -c "grep -nF '((FAILED++))' '$SCRIPTS_DIR/upgrade_homebrew_packages.sh' | grep -vE '^[0-9]+:[[:space:]]*#'"
    [ "$status" -ne 0 ]
}

# ── configure_docker.sh ───────────────────────────────────────────────────────

@test "configure_docker: keeps the Docker >= 4.35 no-helper version gate" {
    # Docker 4.35+ removed the privileged helper (user-space networking); the
    # script must short-circuit to exit 0 on those versions instead of failing
    # to install a helper that no longer exists. Guard that the gate stays.
    grep -q '4\.35' "$SCRIPTS_DIR/configure_docker.sh"
}

# ── remediation status reporting (EA observability) ───────────────────────────

@test "upgrade_homebrew_packages: writes last-run status for the Homebrew Upgrade Status EA" {
    # Regression: failures were invisible to the compliance check. The script
    # must record OK/FAIL to the shared jamf-status dir via write_status.
    grep -q 'jamf-status' "$SCRIPTS_DIR/upgrade_homebrew_packages.sh"
    grep -q 'homebrew-upgrade.status' "$SCRIPTS_DIR/upgrade_homebrew_packages.sh"
    grep -q 'write_status' "$SCRIPTS_DIR/upgrade_homebrew_packages.sh"
}

@test "upgrade_homebrew_packages: early dir-setup chown/chmod can't abort under set -e" {
    # Regression: a chown/chmod failure on the cache/log/tmp dirs aborted the
    # whole upgrade. Those steps must be best-effort (|| true).
    grep -qF 'chown "$SERVICE_USER:staff" "$DIR" 2>/dev/null || true' "$SCRIPTS_DIR/upgrade_homebrew_packages.sh"
}

@test "upgrade_homebrew_packages: purges orphaned status markers for retired formulas" {
    # Regression: a package retired via enabled=false in homebrew.auto.tfvars
    # (e.g. kubens, docker-credential-gcloud in #153) stops running its install
    # policy, so the FAIL marker read by ea_homebrew_install_failures.sh is never
    # cleared and the device stays pinned in "Homebrew Install - Failing" forever.
    # The weekly upgrade must delete the markers for the retired formulas.
    grep -q 'RETIRED_FORMULAS' "$SCRIPTS_DIR/upgrade_homebrew_packages.sh"
    grep -qF 'homebrew-install-${RETIRED_FORMULA}.status' "$SCRIPTS_DIR/upgrade_homebrew_packages.sh"
    grep -q 'Removed orphaned status marker for retired formula' "$SCRIPTS_DIR/upgrade_homebrew_packages.sh"

    # Functional: run the real cleanup block against a temp status dir and assert
    # it removes a retired marker while leaving a still-managed one (redpanda).
    STATUS_DIR="$BATS_TEST_TMPDIR/jamf-status"
    mkdir -p "$STATUS_DIR"
    printf 'FAIL|t|kubens|x\n'   > "$STATUS_DIR/homebrew-install-kubens.status"
    printf 'FAIL|t|redpanda|x\n' > "$STATUS_DIR/homebrew-install-redpanda.status"
    block=$(sed -n '/^RETIRED_FORMULAS=(/,/^done$/p' "$SCRIPTS_DIR/upgrade_homebrew_packages.sh")
    LOG=/dev/null STATUS_DIR="$STATUS_DIR" bash -euo pipefail -c "$block"
    [ ! -e "$STATUS_DIR/homebrew-install-kubens.status" ]
    [ -e "$STATUS_DIR/homebrew-install-redpanda.status" ]
}

@test "homebrew_package_installer: records per-formula install status on exit" {
    grep -q 'homebrew-install-' "$SCRIPTS_DIR/homebrew_package_installer.sh"
    grep -q 'jamf-status' "$SCRIPTS_DIR/homebrew_package_installer.sh"
    grep -q 'trap on_exit EXIT' "$SCRIPTS_DIR/homebrew_package_installer.sh"
}

@test "homebrew_package_installer: purges the cached download before retrying a failed install" {
    # Regression: a corrupt/partial cached archive makes every retry fail
    # identically with a SHA256 mismatch, so a plain retry loops forever
    # (observed on "redpanda"). The failed-install path must purge the formula's
    # cached download and clean up before retrying so brew re-fetches a clean copy.
    grep -q 'run_brew --cache' "$SCRIPTS_DIR/homebrew_package_installer.sh"
    grep -q 'Purging cached download before retry' "$SCRIPTS_DIR/homebrew_package_installer.sh"
    grep -q 'run_brew cleanup' "$SCRIPTS_DIR/homebrew_package_installer.sh"
}

@test "install_splunk_uf: records last-run status for the Splunk UF Status EA" {
    grep -q 'splunk-uf.status' "$SCRIPTS_DIR/install_splunk_uf.sh"
    grep -q 'trap on_exit EXIT' "$SCRIPTS_DIR/install_splunk_uf.sh"
}

@test "ea_homebrew_upgrade_status: reports No Data when status file absent" {
    run bash "$SCRIPTS_DIR/ea_homebrew_upgrade_status.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == "<result>No Data</result>" ]]
}

@test "ea_homebrew_install_failures: reports None when no failures recorded" {
    run bash "$SCRIPTS_DIR/ea_homebrew_install_failures.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == "<result>None</result>" ]]
}

@test "ea_homebrew_install_failures: prefixes failures with FAIL: (smart group matches 'like FAIL')" {
    # Regression: the smart group used 'is not None', which wrongly matched
    # devices with an empty/never-collected EA value. Failures must carry a
    # positive 'FAIL:' marker so the group can match 'like FAIL' instead.
    grep -qF '<result>FAIL: $failures</result>' "$SCRIPTS_DIR/ea_homebrew_install_failures.sh"
}

@test "ea_splunk_uf_status: reports No Data when status file absent" {
    run bash "$SCRIPTS_DIR/ea_splunk_uf_status.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == "<result>No Data</result>" ]]
}

# ── install_logi_options.sh ───────────────────────────────────────────────────

@test "install_logi_options: runs vendor installer directly with --quiet and verifies signature" {
    # Regression: the logi-options+ Homebrew cask fails because it runs the
    # vendor installer via interactive sudo. This script runs it directly as
    # root (Jamf) with the silent flag, and verifies it's Logitech-signed first.
    grep -qF 'logioptionsplus_installer' "$SCRIPTS_DIR/install_logi_options.sh"
    grep -qF -- '--quiet' "$SCRIPTS_DIR/install_logi_options.sh"
    grep -qiF 'codesign' "$SCRIPTS_DIR/install_logi_options.sh"
    # Must run the installer binary directly, not shell out to `brew`.
    # Word-boundary on `brew` so prose like "Homebrew install" in comments
    # (e.g. the stale-marker cleanup note) does not trip the guard.
    run grep -qE '(sudo -u|\bbrew (install|upgrade))' "$SCRIPTS_DIR/install_logi_options.sh"
    [ "$status" -ne 0 ]
}

@test "install_logi_options: idempotent — exits 0 when already installed" {
    grep -qF '/Applications/logioptionsplus.app' "$SCRIPTS_DIR/install_logi_options.sh"
}

@test "install_logi_options: clears the stale Homebrew status marker before the already-installed short-circuit" {
    # Regression: #115 migrated the install off the Homebrew path, freezing the
    # FAIL marker that ea_homebrew_install_failures.sh reads, so devices stayed
    # pinned in the "Homebrew Install - Failing" smart group. The script must
    # remove the stale marker, and must do so *before* the already-installed
    # exit 0 so previously-migrated machines still recover on the next run.
    grep -qF 'homebrew-install-logi-options+.status' "$SCRIPTS_DIR/install_logi_options.sh"
    grep -qF 'rm -f "$STALE_BREW_STATUS"' "$SCRIPTS_DIR/install_logi_options.sh"

    # The marker cleanup must appear ahead of the "already installed" guard.
    cleanup_line=$(grep -nF 'rm -f "$STALE_BREW_STATUS"' "$SCRIPTS_DIR/install_logi_options.sh" | head -1 | cut -d: -f1)
    guard_line=$(grep -nF 'if [ -d "$APP" ]; then' "$SCRIPTS_DIR/install_logi_options.sh" | head -1 | cut -d: -f1)
    [ -n "$cleanup_line" ]
    [ -n "$guard_line" ]
    [ "$cleanup_line" -lt "$guard_line" ]
}

# ── Xcode CLT version gate (Homebrew source builds) ──────────────────────────
# Regression: the gate was `if ! xcode-select -p`, a presence-only check. A CLT
# left behind by a macOS upgrade satisfies it, so the install path was skipped
# and brew failed much later with "Your Command Line Tools are too outdated"
# mid-build — the failure mode that broke `Install Node.js`.

# Extract the real gate functions from a script and exercise them with stubs.
_clt_gate_harness() {
    local script="$1" clt_version="$2" macos_version="$3"

    export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
    mkdir -p "$BATS_TEST_TMPDIR/bin"

    cat > "$BATS_TEST_TMPDIR/bin/xcode-select" << 'EOF'
#!/bin/bash
[ "$1" = "-p" ] && echo "/Library/Developer/CommandLineTools"
exit 0
EOF
    cat > "$BATS_TEST_TMPDIR/bin/pkgutil" << EOF
#!/bin/bash
echo "package-id: com.apple.pkg.CLTools_Executables"
echo "version: $clt_version"
exit 0
EOF
    cat > "$BATS_TEST_TMPDIR/bin/sw_vers" << EOF
#!/bin/bash
echo "$macos_version"
EOF
    chmod +x "$BATS_TEST_TMPDIR/bin/"*

    sed -n '/^clt_installed_version()/,/^}/p;/^clt_needs_install()/,/^}/p' \
        "$SCRIPTS_DIR/$script" > "$BATS_TEST_TMPDIR/clt_fn.sh"

    bash -c "source '$BATS_TEST_TMPDIR/clt_fn.sh'; if clt_needs_install; then echo NEEDS; else echo OK; fi"
}

@test "homebrew_package_installer: stale CLT after a macOS upgrade needs install" {
    run _clt_gate_harness homebrew_package_installer.sh "16.2.0.0.1700000000" "26.6"
    [ "$status" -eq 0 ]
    [[ "$output" == "NEEDS" ]]
}

@test "homebrew_package_installer: CLT matching the running macOS needs no install" {
    run _clt_gate_harness homebrew_package_installer.sh "26.5.0.0.1777544298" "26.6"
    [ "$status" -eq 0 ]
    [[ "$output" == "OK" ]]
}

@test "homebrew_package_installer: unparseable CLT version fails safe toward installing" {
    run _clt_gate_harness homebrew_package_installer.sh "not-a-version" "26.6"
    [ "$status" -eq 0 ]
    [[ "$output" == "NEEDS" ]]
}

@test "example_it_tooling: stale CLT after a macOS upgrade needs install" {
    run _clt_gate_harness example_it_tooling.sh "16.2.0.0.1700000000" "26.6"
    [ "$status" -eq 0 ]
    [[ "$output" == "NEEDS" ]]
}

@test "CLT gate: both brew scripts check the version, not just xcode-select -p" {
    # The post-install verification must re-check the version too, otherwise a
    # failed *update* still reports success.
    for s in homebrew_package_installer.sh example_it_tooling.sh; do
        grep -q 'clt_needs_install()' "$SCRIPTS_DIR/$s"
        grep -qF 'com.apple.pkg.CLTools_Executables' "$SCRIPTS_DIR/$s"
        # at least two call sites: the gate and the post-install verification
        [ "$(grep -c '^\s*if clt_needs_install; then' "$SCRIPTS_DIR/$s")" -ge 2 ]
    done
}

# ── Jamf Connect login plugin version enforcement ────────────────────────────
# The login plugin ships in a static pkg and does not auto-update, and its
# install policy is only fired by Setup Manager at provisioning — so enrolled
# Macs keep whatever plugin they enrolled with. A plugin older than 3.6 ignores
# SharedTokenTrustedApplications, which is what makes Self Service+ prompt for
# the login keychain password repeatedly.

# Exercise the real version comparator extracted from a script.
_version_ge() {
    local script="$1" a="$2" b="$3"
    sed -n '/^version_ge()/,/^}/p' "$SCRIPTS_DIR/$script" > "$BATS_TEST_TMPDIR/ver.sh"
    bash -c "source '$BATS_TEST_TMPDIR/ver.sh'; if version_ge '$a' '$b'; then echo GE; else echo LT; fi"
}

@test "update_jamf_connect_login: 3.5.0 is below the 3.6 minimum" {
    run _version_ge update_jamf_connect_login.sh "3.5.0" "3.6"
    [ "$status" -eq 0 ]
    [[ "$output" == "LT" ]]
}

@test "update_jamf_connect_login: 3.25.0 is above 3.6 (not a lexical compare)" {
    # Regression guard: a string compare — or `sort` without -V — orders "3.25"
    # below "3.6", which would make the script downgrade-loop on current Macs.
    run _version_ge update_jamf_connect_login.sh "3.25.0" "3.6"
    [ "$status" -eq 0 ]
    [[ "$output" == "GE" ]]
}

@test "update_jamf_connect_login: exact minimum counts as met" {
    run _version_ge update_jamf_connect_login.sh "3.6" "3.6"
    [ "$status" -eq 0 ]
    [[ "$output" == "GE" ]]
}

@test "update_jamf_connect_login: 3.6.1 is above 3.6" {
    run _version_ge update_jamf_connect_login.sh "3.6.1" "3.6"
    [ "$status" -eq 0 ]
    [[ "$output" == "GE" ]]
}

@test "reset_jamf_connect_keychain: uses the same numeric comparator" {
    run _version_ge reset_jamf_connect_keychain.sh "3.25.0" "3.6"
    [ "$status" -eq 0 ]
    [[ "$output" == "GE" ]]
    run _version_ge reset_jamf_connect_keychain.sh "3.5.0" "3.6"
    [ "$status" -eq 0 ]
    [[ "$output" == "LT" ]]
}

@test "update_jamf_connect_login: triggers the install event when below minimum" {
    grep -qF 'policy -event "$INSTALL_EVENT"' "$SCRIPTS_DIR/update_jamf_connect_login.sh"
    grep -qF 'install-jamfconnect' "$SCRIPTS_DIR/update_jamf_connect_login.sh"
}

@test "update_jamf_connect_login: reports failure via status file, not a non-zero exit" {
    # Runs on an Ongoing check-in policy fleet-wide; exiting 1 while the package
    # in Jamf is still stale would flag every Mac Failed on every check-in.
    grep -qF 'jamf-connect-login.status' "$SCRIPTS_DIR/update_jamf_connect_login.sh"
    grep -q 'trap on_exit EXIT' "$SCRIPTS_DIR/update_jamf_connect_login.sh"
    run grep -nE '^\s*exit 1' "$SCRIPTS_DIR/update_jamf_connect_login.sh"
    [ "$status" -ne 0 ]
}

@test "reset_jamf_connect_keychain: refuses to reset while the plugin is still old" {
    # Deleting the item under an old plugin just recreates the same broken ACL.
    guard_line=$(grep -nF 'if ! version_ge "$CURRENT" "$MIN_VERSION"; then' "$SCRIPTS_DIR/reset_jamf_connect_keychain.sh" | head -1 | cut -d: -f1)
    delete_line=$(grep -nF 'security delete-generic-password' "$SCRIPTS_DIR/reset_jamf_connect_keychain.sh" | head -1 | cut -d: -f1)
    [ -n "$guard_line" ]
    [ -n "$delete_line" ]
    [ "$guard_line" -lt "$delete_line" ]
}

@test "reset_jamf_connect_keychain: requires a console user and is one-shot" {
    # The item lives in the console user's login keychain, and the delete must run
    # inside their GUI session or the keychain is locked to it.
    grep -qF 'stat -f%Su /dev/console' "$SCRIPTS_DIR/reset_jamf_connect_keychain.sh"
    grep -qF 'launchctl asuser' "$SCRIPTS_DIR/reset_jamf_connect_keychain.sh"
    grep -qF 'MARKER=' "$SCRIPTS_DIR/reset_jamf_connect_keychain.sh"

    # The console-user guard must precede the delete.
    user_line=$(grep -nF 'stat -f%Su /dev/console' "$SCRIPTS_DIR/reset_jamf_connect_keychain.sh" | head -1 | cut -d: -f1)
    delete_line=$(grep -nF 'security delete-generic-password' "$SCRIPTS_DIR/reset_jamf_connect_keychain.sh" | head -1 | cut -d: -f1)
    [ "$user_line" -lt "$delete_line" ]
}

@test "ea_jamf_connect_version: emits a well-formed single result" {
    run bash "$SCRIPTS_DIR/ea_jamf_connect_version.sh"
    [ "$status" -eq 0 ]
    # Exactly one <result> line, and no stray pre-result output (the old version
    # echoed a bare "jamfConnectLoginVersion" line before the result).
    [ "$(echo "$output" | wc -l | tr -d ' ')" -eq 1 ]
    [[ "$output" =~ ^\<result\>.*\</result\>$ ]]
}

@test "ea_jamf_connect_version: has a Not Installed sentinel for the smart-group query" {
    # Without a definite sentinel an absent plugin yields an empty EA value, which
    # cannot be distinguished from "never collected".
    grep -qF '<result>Not Installed</result>' "$SCRIPTS_DIR/ea_jamf_connect_version.sh"
    grep -qF 'SecurityAgentPlugins/JamfConnectLogin.bundle' "$SCRIPTS_DIR/ea_jamf_connect_version.sh"
}

# ── configure_splunk_mcp.sh ───────────────────────────────────────────────────
# Claude Code cannot be configured by a .mobileconfig the way Cursor and iTerm2
# are — it does not read CFPreferences, so there is no preference domain for a
# profile payload to target. Its managed equivalent is a pair of root-owned files
# under /Library/Application Support/ClaudeCode.

@test "configure_splunk_mcp: defines the server in managed-mcp.json, not managed-settings.json" {
    # Regression guard: "mcpServers" is NOT a valid key in managed-settings.json.
    # Putting the server there would save cleanly and silently do nothing.
    grep -qF 'MCP_FILE="$MANAGED_DIR/managed-mcp.json"' "$SCRIPTS_DIR/configure_splunk_mcp.sh"
    grep -qF 'SETTINGS_FILE="$MANAGED_DIR/managed-settings.json"' "$SCRIPTS_DIR/configure_splunk_mcp.sh"
    grep -qF '/Library/Application Support/ClaudeCode' "$SCRIPTS_DIR/configure_splunk_mcp.sh"
}

@test "configure_splunk_mcp: preserves claude.ai connectors by default" {
    # Deploying managed-mcp.json puts Claude Code into exclusive-control lockdown
    # and suppresses claude.ai connectors. Engineers here rely on ~10 of them, so
    # allowAllClaudeAiMcps must be set unless the lockdown is explicitly opted into.
    grep -qF 'allowAllClaudeAiMcps' "$SCRIPTS_DIR/configure_splunk_mcp.sh"
    grep -qF 'MCP_EXCLUSIVE' "$SCRIPTS_DIR/configure_splunk_mcp.sh"
}

@test "configure_splunk_mcp: never passes the token on a command line" {
    # argv is world-visible via ps for the life of the call.
    grep -qF 'export MCP_ENDPOINT="$ENDPOINT" MCP_TOKEN' "$SCRIPTS_DIR/configure_splunk_mcp.sh"
    run grep -nE 'Bearer .*\$(MCP_)?TOKEN' "$SCRIPTS_DIR/configure_splunk_mcp.sh"
    [ "$status" -ne 0 ]
    # and it must not shell out to `claude mcp add`, which takes --header as argv
    run grep -qF 'claude mcp add' "$SCRIPTS_DIR/configure_splunk_mcp.sh"
    [ "$status" -ne 0 ]
}

@test "configure_splunk_mcp: writes atomically and refuses to clobber malformed JSON" {
    grep -qF 'tempfile.mkstemp' "$SCRIPTS_DIR/configure_splunk_mcp.sh"
    grep -qF 'os.replace(tmp, path)' "$SCRIPTS_DIR/configure_splunk_mcp.sh"
    grep -q 'is not valid JSON — leaving it alone' "$SCRIPTS_DIR/configure_splunk_mcp.sh"
}

@test "configure_splunk_mcp: exercises the merge — create, idempotent, rotate" {
    # Run the real embedded python against a temp dir.
    python3 - "$SCRIPTS_DIR/configure_splunk_mcp.sh" "$BATS_TEST_TMPDIR/m.py" <<'PY'
import sys, pathlib
src = pathlib.Path(sys.argv[1]).read_text()
body = src.split("/usr/bin/python3 <<'PY'\n", 1)[1].split("\nPY\n", 1)[0]
pathlib.Path(sys.argv[2]).write_text(body.replace("    os.chown(path, 0, 0)\n", ""))
PY
    export MCP_FILE="$BATS_TEST_TMPDIR/managed-mcp.json"
    export SETTINGS_FILE="$BATS_TEST_TMPDIR/managed-settings.json"
    export SERVER_NAME=splunk MCP_ENDPOINT="https://e/mcp" EXCLUSIVE=0

    MCP_TOKEN=TOK1 run python3 "$BATS_TEST_TMPDIR/m.py"
    [[ "$output" == UPDATED* ]]

    MCP_TOKEN=TOK1 run python3 "$BATS_TEST_TMPDIR/m.py"
    [[ "$output" == UNCHANGED* ]]

    MCP_TOKEN=TOK2 run python3 "$BATS_TEST_TMPDIR/m.py"
    [[ "$output" == UPDATED* ]]

    grep -qF 'TOK2' "$MCP_FILE"
    grep -qF '"allowAllClaudeAiMcps": true' "$SETTINGS_FILE"
}

# ── Tenable Nessus decommission (IN-484) ─────────────────────────────────────

@test "ea_nessus_agent_status: reports Not Installed when the agent is absent" {
    # No /Library/NessusAgent on the CI runner — the EA must return the definite
    # sentinel so the "Nessus - Installed" smart group can match on it.
    run bash "$SCRIPTS_DIR/ea_nessus_agent_status.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == "<result>Not Installed</result>" ]]
}

@test "remove_nessus_agent: exits 0 (no-op) when the Nessus agent is not present" {
    # Idempotent uninstaller: a machine without the agent must succeed so the
    # Ongoing removal policy never marks clean Macs as Failed.
    run bash "$SCRIPTS_DIR/remove_nessus_agent.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"No Nessus Agent components found"* ]]
}
