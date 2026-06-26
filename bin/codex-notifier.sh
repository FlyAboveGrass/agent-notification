#!/usr/bin/env bash
set -euo pipefail

SCRIPT_PATH="$0"
while [ -L "$SCRIPT_PATH" ]; do
  SCRIPT_DIR="$(cd -P "$(dirname "$SCRIPT_PATH")" && pwd)"
  SCRIPT_TARGET="$(readlink "$SCRIPT_PATH")"
  case "$SCRIPT_TARGET" in
    /*) SCRIPT_PATH="$SCRIPT_TARGET" ;;
    *) SCRIPT_PATH="$SCRIPT_DIR/$SCRIPT_TARGET" ;;
  esac
done
SCRIPT_DIR="$(cd -P "$(dirname "$SCRIPT_PATH")" && pwd)"
LOG_FILE="${CODEX_NOTIFIER_LOG:-$HOME/.codex/codex-notifier.log}"
DEFAULT_SOUND="$SCRIPT_DIR/sounds/default.mp3"
LEGACY_SOUND="$SCRIPT_DIR/../sounds/default.mp3"
if [ -n "${CODEX_NOTIFIER_SOUND:-}" ]; then
  SOUND_FILE="$CODEX_NOTIFIER_SOUND"
elif [ -f "$DEFAULT_SOUND" ]; then
  SOUND_FILE="$DEFAULT_SOUND"
else
  SOUND_FILE="$LEGACY_SOUND"
fi
TERMINAL_NOTIFIER="${CODEX_NOTIFIER_TERMINAL_NOTIFIER:-}"
AFPLAY_BIN="${CODEX_NOTIFIER_AFPLAY:-/usr/bin/afplay}"
SENDER_BUNDLE="${CODEX_NOTIFIER_SENDER_BUNDLE:-com.openai.codex}"
ICON_PATH="${CODEX_NOTIFIER_ICON:-}"
CHANNEL_TIMEOUT_SECONDS="${CODEX_NOTIFIER_CHANNEL_TIMEOUT_SECONDS:-3}"
TERMINAL_NOTIFIER_WATCHDOG_SECONDS="${CODEX_NOTIFIER_TERMINAL_NOTIFIER_WATCHDOG_SECONDS:-30}"
INPUT="$(cat)"
NOW="$(date '+%Y-%m-%d %H:%M:%S')"

case "$CHANNEL_TIMEOUT_SECONDS" in
  ''|*[!0-9]*) CHANNEL_TIMEOUT_SECONDS=3 ;;
esac
if [ "$CHANNEL_TIMEOUT_SECONDS" -lt 1 ]; then
  CHANNEL_TIMEOUT_SECONDS=1
fi
case "$TERMINAL_NOTIFIER_WATCHDOG_SECONDS" in
  ''|*[!0-9]*) TERMINAL_NOTIFIER_WATCHDOG_SECONDS=30 ;;
esac

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

RUN_WITH_TIMEOUT_STATUS=0
RUN_WITH_TIMEOUT_OUTPUT=""
run_with_timeout() {
  local timeout_seconds="$1"
  shift

  local output_file
  output_file="$(mktemp "${TMPDIR:-/tmp}/codex-notifier.XXXXXX" 2>/dev/null || printf '%s/codex-notifier.%s.%s' "${TMPDIR:-/tmp}" "$$" "$RANDOM")"

  /usr/bin/ruby -rtimeout -e '
    timeout_seconds = Integer(ARGV.shift)
    output_file = ARGV.shift
    command = ARGV
    pid = Process.spawn(*command, out: output_file, err: [:child, :out])

    begin
      Timeout.timeout(timeout_seconds) { Process.wait(pid) }
      status = $?
      exit(status.exitstatus || 1)
    rescue Timeout::Error
      begin
        Process.kill("TERM", pid)
      rescue Errno::ESRCH
      end
      sleep 0.2
      begin
        Process.kill("KILL", pid)
      rescue Errno::ESRCH
      end
      begin
        Process.wait(pid)
      rescue Errno::ECHILD
      end
      exit 124
    end
  ' "$timeout_seconds" "$output_file" "$@"
  RUN_WITH_TIMEOUT_STATUS=$?
  RUN_WITH_TIMEOUT_OUTPUT="$(cat "$output_file" 2>/dev/null || true)"
  if [ "$RUN_WITH_TIMEOUT_STATUS" = "124" ]; then
    if [ -n "$RUN_WITH_TIMEOUT_OUTPUT" ]; then
      RUN_WITH_TIMEOUT_OUTPUT="$RUN_WITH_TIMEOUT_OUTPUT; "
    fi
    RUN_WITH_TIMEOUT_OUTPUT="${RUN_WITH_TIMEOUT_OUTPUT}command timed out after ${timeout_seconds}s"
  fi
  rm -f "$output_file"
}

DISPATCH_DETACHED_PID=""
dispatch_notifier_with_sound() {
  local watchdog_seconds="$1"
  local sound_file="$2"
  shift
  shift

  DISPATCH_DETACHED_PID="$(/usr/bin/ruby -rtimeout -e '
    watchdog_seconds = Integer(ARGV.shift)
    sound_file = ARGV.shift
    command = ARGV

    worker = fork do
      notifier_pid = Process.spawn(*command, out: "/dev/null", err: "/dev/null", pgroup: true)
      completed = false

      begin
        if watchdog_seconds > 0
          Timeout.timeout(watchdog_seconds) { Process.wait(notifier_pid) }
        else
          Process.wait(notifier_pid)
        end
        completed = true
      rescue Timeout::Error
        begin
          Process.kill("TERM", -notifier_pid)
        rescue Errno::ESRCH, Errno::EPERM
        end
        sleep 0.2
        begin
          Process.kill("KILL", -notifier_pid)
        rescue Errno::ESRCH, Errno::EPERM
        end
        begin
          Process.wait(notifier_pid)
        rescue Errno::ECHILD
        end
      end

      if completed && sound_file != "none" && File.file?(sound_file)
        afplay_bin = ENV.fetch("CODEX_NOTIFIER_AFPLAY", "/usr/bin/afplay")
        Process.spawn(afplay_bin, sound_file, out: "/dev/null", err: "/dev/null")
      end
    end

    Process.detach(worker)
    print worker
  ' "$watchdog_seconds" "$sound_file" "$@" 2>/dev/null)"
}

prepare_sound_status() {
  AFPLAY_STATUS=127
  AFPLAY_OUTPUT=""

  if [ "${SOUND_FILE:-}" = "none" ]; then
    AFPLAY_STATUS=0
    AFPLAY_OUTPUT="disabled"
    return
  fi

  if [ ! -f "${SOUND_FILE:-}" ]; then
    AFPLAY_STATUS=66
    AFPLAY_OUTPUT="sound file not found"
    return
  fi

  AFPLAY_STATUS=0
  AFPLAY_OUTPUT="queued after terminal-notifier"
}

play_sound_now() {
  prepare_sound_status
  if [ "$AFPLAY_STATUS" = "0" ] && [ "${SOUND_FILE:-}" != "none" ] && [ -f "${SOUND_FILE:-}" ]; then
    "$AFPLAY_BIN" "$SOUND_FILE" >/dev/null 2>&1 &
    AFPLAY_OUTPUT="dispatched pid=$!"
  fi
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
    prepare_sound_status
    if dispatch_notifier_with_sound "$TERMINAL_NOTIFIER_WATCHDOG_SECONDS" "$SOUND_FILE" "$NOTIFIER_BIN" "${NOTIFIER_ARGS[@]}"; then
      TERMINAL_NOTIFIER_STATUS=0
      TERMINAL_NOTIFIER_OUTPUT="dispatched pid=$DISPATCH_DETACHED_PID watchdog=${TERMINAL_NOTIFIER_WATCHDOG_SECONDS}s"
    else
      TERMINAL_NOTIFIER_STATUS=$?
      TERMINAL_NOTIFIER_OUTPUT="dispatch failed"
    fi
  fi

  OSASCRIPT_STATUS=127
  OSASCRIPT_OUTPUT="skipped because terminal-notifier was dispatched"
  if [ "$TERMINAL_NOTIFIER_STATUS" != "0" ]; then
    run_with_timeout "$CHANNEL_TIMEOUT_SECONDS" /usr/bin/osascript \
      -e 'on run argv' \
      -e 'display notification (item 1 of argv) with title (item 2 of argv) subtitle (item 3 of argv)' \
      -e 'end run' \
      "$MESSAGE" "$TITLE" "$SUBTITLE"
    OSASCRIPT_STATUS=$RUN_WITH_TIMEOUT_STATUS
    OSASCRIPT_OUTPUT="$RUN_WITH_TIMEOUT_OUTPUT"
    play_sound_now
  fi

  if [ "$TERMINAL_NOTIFIER_STATUS" = "0" ] && [ -z "$AFPLAY_OUTPUT" ]; then
    prepare_sound_status
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
  printf 'channel_timeout_seconds=%s\n' "$CHANNEL_TIMEOUT_SECONDS"
  printf 'terminal_notifier_watchdog_seconds=%s\n' "$TERMINAL_NOTIFIER_WATCHDOG_SECONDS"
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
