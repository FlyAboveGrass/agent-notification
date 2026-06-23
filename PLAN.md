# Codex Notifier Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a reusable one-command macOS notification package for Codex lifecycle hooks.

**Architecture:** The package installs one hook command into the user Codex home and merges `Stop` and `PermissionRequest` entries into `~/.codex/hooks.json`. The hook script reads Codex hook JSON from stdin, derives a readable title/message from the event payload, sends a rich notification through `terminal-notifier`, activates the most likely source app on click, and plays a configurable mp3 sound.

**Tech Stack:** POSIX shell/Bash, Ruby JSON parser, Codex hooks, macOS `terminal-notifier`, `osascript`, `afplay`.

---

### Task 1: Package Layout

**Files:**
- Create: `tmp/codex-notifier/bin/codex-notifier.sh`
- Create: `tmp/codex-notifier/install.sh`
- Create: `tmp/codex-notifier/uninstall.sh`
- Create: `tmp/codex-notifier/examples/hooks.json`
- Create: `tmp/codex-notifier/README.md`
- Create: `tmp/codex-notifier/docs/implementation.md`

- [x] **Step 1: Create the package directories**

Run: `mkdir -p tmp/codex-notifier/bin tmp/codex-notifier/docs tmp/codex-notifier/examples`

Expected: package folders exist under `tmp/codex-notifier`.

- [x] **Step 2: Add the notifier script**

The notifier reads hook JSON, formats the notification, dispatches through `terminal-notifier`, falls back to `osascript`, plays the configured sound, and logs channel status.

- [x] **Step 3: Add one-command installer and uninstaller**

The installer copies the notifier into `~/.codex/hooks/codex-notifier/`, creates a stable command path at `~/.codex/hooks/codex-stop-notify.sh`, merges hooks into `~/.codex/hooks.json`, and sends a test notification.

- [x] **Step 4: Add docs**

Document install, uninstall, configuration, click behavior, sound behavior, and troubleshooting.

- [x] **Step 5: Verify in a temporary HOME**

Run installer with `HOME=/tmp/...` and `CODEX_NOTIFIER_INSTALL_SKIP_TEST=1`, then parse generated JSON and run the installed hook with a sample payload.
