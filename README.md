# Codex Notifier

Codex Notifier 是一个 macOS Codex hook 通知包，用来在后台 Codex session 完成或需要处理时弹出系统通知、播放自定义声音，并在点击通知时跳回执行任务的应用。

## 安装

```sh
curl -fsSL https://raw.githubusercontent.com/FlyAboveGrass/agent-notification/main/install.sh | bash
```

安装脚本会自动完成这些操作：

- 从 GitHub raw 下载运行所需文件，不需要 clone 整个仓库
- 复制通知脚本和默认声音到 `~/.codex/hooks/codex-notifier/`
- 安装卸载脚本到 `~/.codex/hooks/codex-notifier/uninstall.sh`
- 创建稳定 hook 命令路径 `~/.codex/hooks/codex-stop-notify.sh`
- 合并 `Stop` 和 `PermissionRequest` 到 `~/.codex/hooks.json`
- 备份原 `hooks.json`
- 发送一条安装测试通知

如果 Codex 提示 hook 需要 review，在 Codex 里输入 `/hooks`，信任 user-level 的 `Stop` 和 `PermissionRequest` hook。

固定到特定版本或使用镜像：

```sh
curl -fsSL https://raw.githubusercontent.com/FlyAboveGrass/agent-notification/main/install.sh \
  | AGENT_NOTIFICATION_BASE_URL=https://raw.githubusercontent.com/FlyAboveGrass/agent-notification/v0.1.0 bash
```

把 `v0.1.0` 换成实际发布的 tag；如果使用镜像，`AGENT_NOTIFICATION_BASE_URL` 指向镜像里的仓库根目录即可。

本地开发安装：

```sh
git clone https://github.com/FlyAboveGrass/agent-notification.git
cd agent-notification
./install.sh
```

## 功能

- `Stop`：Codex 一轮任务完成时通知。
- `PermissionRequest`：Codex 需要批准命令或人工处理时通知。
- 通知标题区分完成和待处理。
- 通知副标题包含项目名和 session 前缀。
- 通知正文优先显示 session 任务摘要（从 transcript 提取最后一条用户消息）。
- 点击通知会尽量跳回来源应用（VS Code/iTerm2/Warp/Codex）。
- 默认播放 bundled 的 `sounds/default.mp3`，可自定义或关闭。

## 点击跳转

脚本按以下顺序决定点击通知后激活哪个应用：

1. `CODEX_NOTIFIER_TARGET_BUNDLE`
2. `TERM_PROGRAM`
3. 父进程链
4. 默认 `com.openai.codex`

已内置映射：

| 来源 | Bundle ID |
| --- | --- |
| VS Code | `com.microsoft.VSCode` |
| iTerm2 | `com.googlecode.iterm2` |
| Warp | `dev.warp.Warp-Stable` |
| Terminal | `com.apple.Terminal` |
| Codex App | `com.openai.codex` |

点击跳转由 `terminal-notifier -activate` 提供。`osascript` 兜底通知没有点击跳转能力，所以只有找不到或无法派发 `terminal-notifier` 时才使用。

## 自定义

临时覆盖点击目标：

```sh
CODEX_NOTIFIER_TARGET_BUNDLE=com.microsoft.VSCode ~/.codex/hooks/codex-stop-notify.sh
```

临时覆盖声音：

```sh
CODEX_NOTIFIER_SOUND=/path/to/sound.mp3 ~/.codex/hooks/codex-stop-notify.sh
```

关闭声音：

```sh
CODEX_NOTIFIER_SOUND=none ~/.codex/hooks/codex-stop-notify.sh
```

自定义图标：

```sh
CODEX_NOTIFIER_ICON=/path/to/icon.png ~/.codex/hooks/codex-stop-notify.sh
```

自定义日志：

```sh
CODEX_NOTIFIER_LOG=/tmp/codex-notifier.log ~/.codex/hooks/codex-stop-notify.sh
```

自定义通知通道内部超时，默认 3 秒：

```sh
CODEX_NOTIFIER_CHANNEL_TIMEOUT_SECONDS=2 ~/.codex/hooks/codex-stop-notify.sh
```

自定义 `terminal-notifier` 后台进程 watchdog，默认 30 秒：

```sh
CODEX_NOTIFIER_TERMINAL_NOTIFIER_WATCHDOG_SECONDS=20 ~/.codex/hooks/codex-stop-notify.sh
```

## 验证

手动触发测试：

```sh
printf '{"hook_event_name":"Stop","session_id":"manual-test","cwd":"%s","last_assistant_message":"测试通知"}' "$PWD" | ~/.codex/hooks/codex-stop-notify.sh
```

查看日志：

```sh
tail -40 ~/.codex/codex-notifier.log
```

日志里应看到：

```text
terminal_notifier_status=0
afplay_status=0
```

`terminal-notifier` 会后台派发，所以正常日志会看到：

```text
terminal_notifier_status=0
terminal_notifier_output=dispatched pid=12345 watchdog=30s
```

不弹窗、不出声的 dry-run 测试：

```sh
CODEX_NOTIFIER_DRY_RUN=1 printf '{"hook_event_name":"Stop","session_id":"manual-test","cwd":"%s","last_assistant_message":"测试通知"}' "$PWD" | CODEX_NOTIFIER_DRY_RUN=1 ~/.codex/hooks/codex-stop-notify.sh
```

## 卸载

执行安装到 Codex hooks 目录里的卸载脚本：

```sh
~/.codex/hooks/codex-notifier/uninstall.sh
```

卸载脚本会从 `~/.codex/hooks.json` 移除 Codex Notifier hook，并删除安装目录。

## 文件结构

```
agent-notification/
├── README.md              # 本文档
├── install.sh             # 一键安装脚本
├── uninstall.sh           # 一键卸载脚本
├── bin/
│   └── codex-notifier.sh  # 通知核心脚本
├── sounds/
│   └── default.mp3        # 默认通知声音
├── examples/
│   └── hooks.json         # hooks 配置示例
└── docs/
    └── implementation.md  # 实现原理文档
```

## 先决条件

- macOS 系统
- Codex App 已安装
- `terminal-notifier` 已安装（通过 `brew install terminal-notifier` 或 `npm install -g node-notifier`，本包也自动查找 yarn 全局安装路径）

## 依赖

| 工具 | 用途 | 安装方式 |
| --- | --- | --- |
| `terminal-notifier` | 显示弹窗通知 | `brew install terminal-notifier` 或 `npm install -g node-notifier` |
| `osascript` | 弹窗兜底 | macOS 内置 |
| `afplay` | 播放自定义声音 | macOS 内置 |
| Ruby + json | JSON 处理 | macOS 内置 |

## License

MIT
