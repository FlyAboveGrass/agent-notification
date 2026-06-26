# Remote Bootstrap Install Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let users install Codex Notifier with one `curl | bash` command while keeping local `./install.sh` installs working.

**Architecture:** `install.sh` detects whether repository assets are available next to the script. If they are present, it copies local files; otherwise it downloads the notifier script, sound, and uninstaller from GitHub raw into the existing `~/.codex/hooks/codex-notifier/` layout before merging hook entries.

**Tech Stack:** Bash, curl, Ruby JSON parser, GitHub raw files, Codex hooks.

---

### Task 1: Dual-Mode Installer

**Files:**
- Modify: `install.sh`

- [x] Add asset resolution helpers for local files and remote GitHub raw URLs.
- [x] Keep the existing install layout: `~/.codex/hooks/codex-notifier/` and `~/.codex/hooks/codex-stop-notify.sh`.
- [x] Preserve existing hook merge behavior for `Stop` and `PermissionRequest`.
- [x] Fail with a clear error when remote installation cannot download required files.

### Task 2: Documentation

**Files:**
- Modify: `README.md`
- Modify: `docs/implementation.md`

- [x] Make `curl -fsSL https://raw.githubusercontent.com/FlyAboveGrass/agent-notification/main/install.sh | bash` the primary install command.
- [x] Keep local clone installation as a development option.
- [x] Document `AGENT_NOTIFICATION_BASE_URL` for version pinning or mirrors.
- [x] Explain that remote install downloads only the runtime assets, not the whole repository.

### Task 3: Verification

**Files:**
- No production files.

- [x] Run local install against a temporary `HOME` with `CODEX_NOTIFIER_INSTALL_SKIP_TEST=1`.
- [x] Run remote-style install by piping the current `install.sh` through `bash` with a local file URL base.
- [x] Parse generated `hooks.json` and run the installed hook in dry-run mode.
