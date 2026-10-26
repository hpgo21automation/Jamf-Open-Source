#!/bin/bash
# Reports Homebrew package installs whose most recent run failed, read from the
# per-formula status files written by homebrew_package_installer.sh. Output is
# "FAIL: <comma-separated formulas>" when something failed, else "None". The
# "FAIL" prefix lets the "Homebrew Install - Failing" smart group match on
# "like FAIL" — so a device with an empty/never-collected value is NOT caught
# (which "is not None" would wrongly do). Surfaces failing package(s) to the
# daily compliance check.
# Status file format: STATE|timestamp|formula|reason
STATUS_DIR="/Library/Application Support/Example/jamf-status"
failures=""
if [ -d "$STATUS_DIR" ]; then
    for f in "$STATUS_DIR"/homebrew-install-*.status; do
        [ -e "$f" ] || continue
        IFS='|' read -r state _ formula _ < "$f"
        if [ "$state" = "FAIL" ]; then
            failures="${failures:+$failures, }${formula:-unknown}"
        fi
    done
fi
if [ -n "$failures" ]; then
    echo "<result>FAIL: $failures</result>"
else
    echo "<result>None</result>"
fi
