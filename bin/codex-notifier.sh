#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOG_FILE="${CODEX_NOTIFIER_LOG:-$HOME/.codex/codex-notifier.log}"
DEFAULT_SOUND="$SCRIPT_DIR/../sounds/default.mp3"
SOUND_FILE="${CODEX_NOTIFIER_SOUND:-$DEFAULT_SOUND}"
TERMINAL_NOTIFIER="${CODEX_NOTIFIER_TERMINAL_NOTIFIER:-}"
SENDER_BUNDLE="${CODEX_NOTIFIER_SENDER_BUNDLE:-com.openai.codex}"
ICON_PATH="${CODEX_NOTIFIER_ICON:-}"
INPUT="$(cat)"
NOW="$(date '+%Y-%m-%d %H:%M:%S')"

find_terminal_notifier() {
  if [ -n "$TERMINAL_NOTIFIER" ] && [ -x "$TERMINAL_NOTIFIER" ]; then
    printf '%s\n' "$TERMINAL_NOTIFIER"
    return
  fi

  if command -v terminal-notifier >/dev/null 2>&1; then
    command -v terminal-notifier
    return
  fi

  local bundled="$HOME/.config/yarn/global/node_modules/node-notifier/vendor/mac.noindex/terminal-notifier.app/Contents/MacOS/terminal-notifier"
  if [ -x "$bundled" ]; then
    printf '%s\n' "$bundled"
    return
  fi

  printf '\n'
}

detect_target_bundle() {
  if [ -n "${CODEX_NOTIFIER_TARGET_BUNDLE:-}" ]; then
    printf '%s\n' "$CODEX_NOTIFIER_TARGET_BUNDLE"
    return
  fi

  case "${TERM_PROGRAM:-}" in
    vscode) printf '%s\n' "com.microsoft.VSCode"; return ;;
    iTerm.app) printf '%s\n' "com.googlecode.iterm2"; return ;;
    WarpTerminal|Warp) printf '%s\n' "dev.warp.Warp-Stable"; return ;;
    Apple_Terminal) printf '%s\n' "com.apple.Terminal"; return ;;
  esac

  local pid=$PPID
  local depth=0
  while [ -n "$pid" ] && [ "$pid" -gt 1 ] 2>/dev/null && [ "$depth" -lt 10 ]; do
    local command
    command="$(ps -p "$pid" -o comm= 2>/dev/null || true)"
    case "$command" in
      *"Visual Studio Code"*|*"Code Helper"*|*"Code.app"*) printf '%s\n' "com.microsoft.VSCode"; return ;;
      *"iTerm"*|*"iTerm2"*) printf '%s\n' "com.googlecode.iterm2"; return ;;
      *"Warp"*) printf '%s\n' "dev.warp.Warp-Stable"; return ;;
      *"Codex"*) printf '%s\n' "com.openai.codex"; return ;;
    esac
    pid="$(ps -p "$pid" -o ppid= 2>/dev/null | tr -d ' ' || true)"
    depth=$((depth + 1))
  done

  printf '%s\n' "com.openai.codex"
}

json_field() {
  local field="$1"
  printf '%s' "$PARSED_JSON" | /usr/bin/ruby -rjson -e "data = JSON.parse(STDIN.read); puts(data.fetch('$field', '').to_s)" 2>/dev/null || true
}

parse_payload() {
  printf '%s' "$INPUT" | /usr/bin/ruby -rjson -e '
    data = JSON.parse(STDIN.read)
    event = data["hook_event_name"].to_s
    cwd = (data["cwd"] || Dir.pwd).to_s
    project = File.basename(cwd)
    session = data["session_id"].to_s
    turn = data["turn_id"].to_s
    tool = data["tool_name"].to_s
    transcript = data["transcript_path"].to_s
    last = data["last_assistant_message"].to_s.gsub(/\s+/, " ").strip
    last_user = ""

    if !transcript.empty? && File.file?(transcript)
      File.foreach(transcript) do |line|
        begin
          item = JSON.parse(line)
        rescue JSON::ParserError
          next
        end

        payload = item["payload"]
        next unless payload.is_a?(Hash)

        if payload["type"] == "message" && payload["role"] == "user"
          content = Array(payload["content"]).map { |part| part.is_a?(Hash) ? part["text"] || part["input_text"] : part }.join(" ")
          content = content.gsub(/\s+/, " ").strip
          last_user = content unless content.empty?
        elsif payload["type"] == "user_message"
          content = payload["message"].to_s.gsub(/\s+/, " ").strip
          last_user = content unless content.empty?
        end
      end
    end

    title =
      if event == "PermissionRequest"
        "Codex 需要处理"
      elsif event == "Stop"
        "Codex 任务完成"
      else
        "Codex 通知"
      end

    summary =
      if event == "PermissionRequest" && !tool.empty?
        last_user.empty? ? "请求批准 #{tool}" : "请求批准 #{tool}: #{last_user}"
      elsif !last_user.empty?
        last_user
      elsif !last.empty?
        last
      else
        "#{project} 的 Codex 会话已停止"
      end

    summary = summary[0, 117] + "..." if summary.length > 120
    message = "任务: #{summary}"
    subtitle = session.empty? ? project : "#{project} · session #{session[0, 8]}"

    print JSON.generate({
      "title" => title,
      "subtitle" => subtitle,
      "message" => message,
      "event" => event,
      "project" => project,
      "session" => session,
      "turn" => turn,
      "cwd" => cwd,
      "transcript" => transcript
    })
  ' 2>/dev/null || printf '{}'
}

mkdir -p "$(dirname "$LOG_FILE")"
PARSED_JSON="$(parse_payload)"
TITLE="$(json_field title)"
SUBTITLE="$(json_field subtitle)"
MESSAGE="$(json_field message)"
EVENT="$(json_field event)"
PROJECT="$(json_field project)"
SESSION_ID="$(json_field session)"
TARGET_BUNDLE="$(detect_target_bundle)"
NOTIFIER_BIN="$(find_terminal_notifier)"

if [ -z "$TITLE" ]; then
  TITLE="Codex 通知"
fi
if [ -z "$MESSAGE" ]; then
  MESSAGE="Codex hook event: ${EVENT:-unknown}"
fi
if [ -z "$SUBTITLE" ]; then
  SUBTITLE="${PROJECT:-Codex}"
fi

if [ "${CODEX_NOTIFIER_DRY_RUN:-0}" = "1" ]; then
  TERMINAL_NOTIFIER_STATUS=0
  TERMINAL_NOTIFIER_OUTPUT="dry run"
  OSASCRIPT_STATUS=0
  OSASCRIPT_OUTPUT="dry run"
  AFPLAY_STATUS=0
  AFPLAY_OUTPUT="dry run"
else
  set +e
  TERMINAL_NOTIFIER_STATUS=127
  TERMINAL_NOTIFIER_OUTPUT=""
  if [ -n "$NOTIFIER_BIN" ] && [ -x "$NOTIFIER_BIN" ]; then
    NOTIFIER_ARGS=(
      -title "$TITLE"
      -subtitle "$SUBTITLE"
      -message "$MESSAGE"
      -group "codex-${SESSION_ID:-hook}"
      -sender "$SENDER_BUNDLE"
      -activate "$TARGET_BUNDLE"
    )
    if [ -n "$ICON_PATH" ] && [ -f "$ICON_PATH" ]; then
      NOTIFIER_ARGS+=(-appIcon "file://$ICON_PATH")
    fi
    TERMINAL_NOTIFIER_OUTPUT="$("$NOTIFIER_BIN" "${NOTIFIER_ARGS[@]}" 2>&1)"
    TERMINAL_NOTIFIER_STATUS=$?
  fi

  OSASCRIPT_OUTPUT="$(/usr/bin/osascript \
    -e 'on run argv' \
    -e 'display notification (item 1 of argv) with title (item 2 of argv) subtitle (item 3 of argv)' \
    -e 'end run' \
    "$MESSAGE" "$TITLE" "$SUBTITLE" 2>&1)"
  OSASCRIPT_STATUS=$?

  AFPLAY_STATUS=127
  AFPLAY_OUTPUT=""
  if [ "${SOUND_FILE:-}" != "none" ] && [ -f "$SOUND_FILE" ]; then
    AFPLAY_OUTPUT="$(/usr/bin/afplay "$SOUND_FILE" 2>&1)"
    AFPLAY_STATUS=$?
  elif [ "${SOUND_FILE:-}" = "none" ]; then
    AFPLAY_STATUS=0
  fi
  set -e
fi

{
  printf '%s\tcwd=%s\n' "$NOW" "$PWD"
  printf 'event=%s\n' "$EVENT"
  printf 'session_id=%s\n' "$SESSION_ID"
  printf 'title=%s\n' "$TITLE"
  printf 'subtitle=%s\n' "$SUBTITLE"
  printf 'message=%s\n' "$MESSAGE"
  printf 'target_bundle=%s\n' "$TARGET_BUNDLE"
  printf 'terminal_notifier=%s\n' "$NOTIFIER_BIN"
  printf 'terminal_notifier_status=%s\n' "$TERMINAL_NOTIFIER_STATUS"
  if [ -n "$TERMINAL_NOTIFIER_OUTPUT" ]; then
    printf 'terminal_notifier_output=%s\n' "$TERMINAL_NOTIFIER_OUTPUT"
  fi
  printf 'osascript_status=%s\n' "$OSASCRIPT_STATUS"
  if [ -n "$OSASCRIPT_OUTPUT" ]; then
    printf 'osascript_output=%s\n' "$OSASCRIPT_OUTPUT"
  fi
  printf 'sound_file=%s\n' "$SOUND_FILE"
  printf 'afplay_status=%s\n' "$AFPLAY_STATUS"
  if [ -n "$AFPLAY_OUTPUT" ]; then
    printf 'afplay_output=%s\n' "$AFPLAY_OUTPUT"
  fi
  printf '%s\n' "$INPUT"
} >> "$LOG_FILE"

printf '{}\n'
