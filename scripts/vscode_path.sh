#!/bin/bash
# scripts/vscode_path.sh

# Add VS Code bin directory to system PATH via paths.d
# This allows users to run 'code' command without admin rights

VSCODE_APP="/Applications/Visual Studio Code.app"
PATHS_FILE="/etc/paths.d/vscode"

if [[ -d "$VSCODE_APP" ]]; then
  echo "$VSCODE_APP/Contents/Resources/app/bin" > "$PATHS_FILE"
  chmod 644 "$PATHS_FILE"
  echo "VS Code PATH entry created at $PATHS_FILE"

  # Create symlink so VS Code doesn't prompt for admin to "Install 'code' command in PATH"
  ln -sf "$VSCODE_APP/Contents/Resources/app/bin/code" /usr/local/bin/code
  echo "VS Code 'code' symlink created at /usr/local/bin/code"
  exit 0
else
  echo "VS Code not installed, skipping PATH setup"
  exit 0
fi
