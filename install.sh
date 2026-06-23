#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
INSTALL_DIR="${CODEX_NOTIFIER_INSTALL_DIR:-$CODEX_HOME/hooks/codex-notifier}"
HOOK_COMMAND="${CODEX_NOTIFIER_HOOK_COMMAND:-$CODEX_HOME/hooks/codex-stop-notify.sh}"
HOOKS_JSON="${CODEX_NOTIFIER_HOOKS_JSON:-$CODEX_HOME/hooks.json}"

mkdir -p "$INSTALL_DIR" "$(dirname "$HOOK_COMMAND")" "$CODEX_HOME"
cp "$ROOT_DIR/bin/codex-notifier.sh" "$INSTALL_DIR/codex-notifier.sh"
cp -r "$ROOT_DIR/sounds" "$INSTALL_DIR/sounds"
chmod +x "$INSTALL_DIR/codex-notifier.sh"
ln -sf "$INSTALL_DIR/codex-notifier.sh" "$HOOK_COMMAND"

if [ -f "$HOOKS_JSON" ]; then
  cp "$HOOKS_JSON" "$HOOKS_JSON.bak.$(date '+%Y%m%d%H%M%S')"
fi

HOOK_COMMAND="$HOOK_COMMAND" HOOKS_JSON="$HOOKS_JSON" /usr/bin/ruby -rjson -e '
  path = ENV.fetch("HOOKS_JSON")
  command = ENV.fetch("HOOK_COMMAND")
  data = if File.exist?(path) && !File.read(path).strip.empty?
    JSON.parse(File.read(path))
  else
    {}
  end
  data["hooks"] ||= {}

  specs = {
    "PermissionRequest" => "Sending Codex approval notification",
    "Stop" => "Sending Codex completion notification"
  }

  specs.each do |event, status|
    groups = Array(data["hooks"][event])
    groups.each do |group|
      hooks = Array(group["hooks"])
      group["hooks"] = hooks.reject do |hook|
        hook.is_a?(Hash) && hook["command"].to_s.match?(%r{codex-(stop-)?notifier|codex-stop-notify\.sh})
      end
    end
    groups = groups.reject { |group| Array(group["hooks"]).empty? }
    groups << {
      "hooks" => [
        {
          "type" => "command",
          "command" => command,
          "timeout" => 10,
          "statusMessage" => status
        }
      ]
    }
    data["hooks"][event] = groups
  end

  File.write(path, JSON.pretty_generate(data) + "\n")
'

if [ "${CODEX_NOTIFIER_INSTALL_SKIP_TEST:-0}" != "1" ]; then
  CODEX_NOTIFIER_DRY_RUN=1 printf '{"hook_event_name":"Stop","session_id":"install-test","cwd":"%s","last_assistant_message":"Codex notifier installed successfully."}' "$PWD" | CODEX_NOTIFIER_DRY_RUN=1 "$HOOK_COMMAND" >/dev/null
fi

cat <<EOF
Codex notifier installed.

Hook command:
  $HOOK_COMMAND

Hooks config:
  $HOOKS_JSON

Log file:
  $CODEX_HOME/codex-notifier.log

If Codex reports that hooks need review, open /hooks once and trust the user-level Stop and PermissionRequest hooks.
EOF
