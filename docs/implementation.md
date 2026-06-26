# Codex Notifier 实现原理

## 数据流

Codex hook 触发时，会把事件 JSON 通过 stdin 传给命令脚本。Codex Notifier 接收这段 JSON，提取以下字段：

- `hook_event_name`
- `session_id`
- `turn_id`
- `cwd`
- `tool_name`
- `last_assistant_message`
- `transcript_path`

然后生成通知内容：

- `PermissionRequest` -> 标题为 `Codex 需要处理`
- `Stop` -> 标题为 `Codex 任务完成`
- 正文优先读取 `transcript_path` 指向的 JSONL 文件，提取最后一条用户消息作为任务摘要
- 没有 transcript 或无法读取时，退回 `last_assistant_message`
- `cwd` 的 basename 作为项目名

## 通知通道

主通道是 `terminal-notifier`，原因是它支持：

- `-title`
- `-subtitle`
- `-message`
- `-sender`
- `-appIcon`
- `-activate`

其中 `-activate` 用于点击通知后激活目标应用。

备用通道是 `osascript display notification`。它在部分 macOS 通知权限配置下可能只返回成功但不显示弹窗，所以只作为兜底。

声音由 `afplay` 播放。`terminal-notifier -sound` 只支持系统声音名，不能直接播放任意 mp3，因此自定义声音必须用 `afplay`。

## 点击跳转

脚本会调用 `detect_target_bundle` 推断目标应用：

1. 如果设置了 `CODEX_NOTIFIER_TARGET_BUNDLE`，直接使用。
2. 根据 `TERM_PROGRAM` 映射 VS Code、iTerm2、Warp、Terminal。
3. 遍历父进程链，查找 VS Code、iTerm2、Warp、Codex。
4. 兜底使用 `com.openai.codex`。

这个推断不是强保证，因为 Codex hook 由 Codex 进程启动，父进程链在不同入口里不完全一致。需要强制跳转时，设置 `CODEX_NOTIFIER_TARGET_BUNDLE`。

## 安装策略

推荐安装命令是：

```sh
curl -fsSL https://raw.githubusercontent.com/FlyAboveGrass/agent-notification/main/install.sh | bash
```

`install.sh` 支持两种运行方式：

1. 在仓库目录里执行 `./install.sh` 时，直接复制本地 `bin/codex-notifier.sh`、`sounds/default.mp3` 和 `uninstall.sh`。
2. 通过 `curl | bash` 执行时，脚本没有本地仓库上下文，会从 `AGENT_NOTIFICATION_BASE_URL` 下载运行所需文件。默认地址是 `https://raw.githubusercontent.com/FlyAboveGrass/agent-notification/main`。

这样用户不需要 clone 整个仓库，也不需要保留源码目录。需要固定版本或使用镜像时，可以覆盖 `AGENT_NOTIFICATION_BASE_URL`。

安装脚本把真实脚本放到：

```text
~/.codex/hooks/codex-notifier/codex-notifier.sh
```

同时把卸载脚本放到：

```text
~/.codex/hooks/codex-notifier/uninstall.sh
```

同时创建稳定命令路径：

```text
~/.codex/hooks/codex-stop-notify.sh
```

`hooks.json` 使用稳定命令路径。这样当前机器已经信任过这个 hook 定义时，更新脚本内容不会改变 hook 定义，通常不需要重复 `/hooks` 信任。

## 日志

默认日志位置：

```text
~/.codex/codex-notifier.log
```

每次触发会记录：

- 时间
- 当前工作目录
- event
- session id
- 通知标题、正文
- 点击目标 bundle
- `terminal-notifier` 状态
- `osascript` 状态
- 声音文件和 `afplay` 状态
- 原始 hook JSON

## 常见问题

### 有声音但没有弹窗

检查 macOS「系统设置 > 通知 > terminal-notifier」，确认允许通知，提醒样式不是「无」。

### 有弹窗但点击没有回到正确应用

设置显式目标：

```sh
CODEX_NOTIFIER_TARGET_BUNDLE=com.microsoft.VSCode
```

常用 bundle id：

- VS Code: `com.microsoft.VSCode`
- iTerm2: `com.googlecode.iterm2`
- Warp: `dev.warp.Warp-Stable`
- Codex App: `com.openai.codex`

### 没有触发

检查 Codex 是否启用 hooks：

```toml
[features]
hooks = true
```

然后在 Codex 里输入 `/hooks`，确认 user-level 的 `Stop` 和 `PermissionRequest` 已信任。
