#!/usr/bin/env bash
set -euo pipefail

CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
INSTALL_DIR="${CODEX_NOTIFIER_INSTALL_DIR:-$CODEX_HOME/hooks/codex-notifier}"
HOOK_COMMAND="${CODEX_NOTIFIER_HOOK_COMMAND:-$CODEX_HOME/hooks/codex-stop-notify.sh}"
HOOKS_JSON="${CODEX_NOTIFIER_HOOKS_JSON:-$CODEX_HOME/hooks.json}"

if [ -f "$HOOKS_JSON" ]; then
  cp "$HOOKS_JSON" "$HOOKS_JSON.bak.$(date '+%Y%m%d%H%M%S')"
  HOOKS_JSON="$HOOKS_JSON" /usr/bin/ruby -rjson -e '
    path = ENV.fetch("HOOKS_JSON")
    data = JSON.parse(File.read(path))
    next_data = data
    if next_data["hooks"].is_a?(Hash)
      ["PermissionRequest", "Stop"].each do |event|
        groups = Array(next_data["hooks"][event])
        groups.each do |group|
          hooks = Array(group["hooks"])
          group["hooks"] = hooks.reject do |hook|
            hook.is_a?(Hash) && hook["command"].to_s.match?(%r{codex-(stop-)?notifier|codex-stop-notify\.sh})
          end
        end
        groups = groups.reject { |group| Array(group["hooks"]).empty? }
        if groups.empty?
          next_data["hooks"].delete(event)
        else
          next_data["hooks"][event] = groups
        end
      end
    end
    File.write(path, JSON.pretty_generate(next_data) + "\n")
  '
fi

if [ -L "$HOOK_COMMAND" ]; then
  rm "$HOOK_COMMAND"
fi
rm -rf "$INSTALL_DIR"

cat <<EOF
Codex notifier uninstalled.

Updated hooks config:
  $HOOKS_JSON
EOF
