# Design: CmdBook — macOS 原生命令行工具手册

Status: approved for implementation
Date: 2026-11-06
Supersedes: `docs/design.md`（网页快照方案）、`docs/superpowers/plans/2026-11-06-cli-tool-scanner.md`（Node 扫描器计划）

## Goal

在本机提供一个 macOS 原生应用，回答三个问题：我装过哪些命令行工具、每个工具怎么用、有没有能直接照抄并执行的示例。扫描、查询、执行全程离线。

## Confirmed decisions

| # | 决策 | 选择 |
|---|------|------|
| 1 | 设计来源 | 重新设计，旧网页方案作废 |
| 2 | 示例来源 | 内置精选库为主 + man `EXAMPLES` 段自动提取为辅，完全离线 |
| 3 | 扫描范围 | 全量 `PATH`，按路径标记来源，默认优先展示「用户安装」 |
| 4 | 交付形态 | macOS 原生应用，不使用网页/WebView |
| 5 | 技术栈 | 原生 Swift（SwiftUI + AppKit），`swiftc` 直接编译成 `.app` |
| 6 | 执行边界 | 白名单式：仅内置示例与用户保存的示例，参数表可编辑、执行前二次确认，禁止自由 shell 字符串 |

## Non-goals

- 无 WebView、无本地服务器、无浏览器依赖。
- 扫描与运行阶段均无网络访问。
- 不做 Mac App Store 沙盒、签名公证、自动更新。
- 不支持自由输入任意命令行；交互式 TUI 不在应用内执行。
- 不支持 Windows / Linux。

## Measured environment facts

以下结论均来自 2026-11-06 本机实测，是设计的硬输入：

- Swift 6.4 + Command Line Tools SDK 可用；`swiftc` 实测可编译 `import SwiftUI` / `import AppKit`。**无完整 Xcode、无 `xcodebuild`**，因此必须手写 `Info.plist` 与 `.app` bundle，并用 `codesign -s -` 做临时签名。
- `PATH` 共 48 项（含大量重复）；`/usr/bin` 884 个可执行文件、`/usr/sbin` 193、`/bin` 37、`/opt/homebrew/bin` 90。
- `ffmpeg`、`ffprobe`、`photorec`、`testdisk`、`rg`、`yt-dlp` 位于 `/opt/homebrew/bin`；`jq` 位于 `/usr/bin`。
- `man -P cat ffmpeg` **没有 `EXAMPLES` 段**。因此「内置精选示例库」是主数据源，man 提取只能作为补充，否则用户最关心的 ffmpeg 会一条示例都没有。
- `photorec` / `testdisk` 是交互式 TUI，管道捕获 stdout 会挂起且无有效退出码。
- Rust 1.95 / npm 10.9.7 已装且本地缓存了 Tauri 2.11.6 主 crate，但 `cargo-tauri` CLI 缺失、`crates.io/api` 与 `static.crates.io` 返回 403。该路径未被选用。

## Architecture

```
                    CmdBook.app (SwiftUI + AppKit, no WebView)
  ┌──────────────────────────────────────────────────────────────────┐
  │ AppModel (ObservableObject)                                       │
  │   ├─ Scanner      PATH 发现 / 来源分类 / --help → man 探测         │
  │   ├─ Store        ~/Library/Application Support/CmdBook/*.json    │
  │   ├─ ExampleRepo  内置 examples.json + man EXAMPLES 提取           │
  │   └─ Runner       白名单执行：argv 数组 / 超时 / 流式输出 / kill    │
  └──────────────────────────────────────────────────────────────────┘
        │                       │                        │
   ~/bin, /opt/homebrew   Process(absolute path)   /usr/bin/open -a Terminal
   系统目录                 参数数组 + 注入 PATH       （交互式工具）
```

扫描器、示例库、执行器均为应用内 Swift 模块，不依赖外部脚本或语言运行时。应用同时保留无界面入口 `--scan` / `--verify`，用于构建后的自动化验证。

## Data

三份 JSON，均位于 `~/Library/Application Support/CmdBook/`：

- `tools.json`：扫描快照，`{"version":1,"scannedAt","loginPath","summary","tools":[...]}`。每个工具含 `name, path, allPaths, category, description, usage, usageSource, manExamples, interactive, titleZh, summaryZh, categoryZh, keywords`（后四个为向后兼容的可缺省字段）。
- `saved.json`：用户从内置示例另存的自定义参数，结构为示例 ID + 字段值覆盖，不含任意 argv。
- `examples.json`、`tool-zh.json`：随 app 打包的只读精选示例库与中文词典（应用内资源）。
- `CmdBook.icns`：随 app 打包的原生图标，由 `Scripts/MakeIcon.swift` + `make-icon.sh` 生成。

`category` 取值：`user`（Homebrew、`~/.local`、`~/.cargo`、`~/.nvm`、`/usr/local` 及 `$HOME` 下路径等）、`system`（`/usr/bin`、`/bin`、`/usr/sbin`、`/sbin`、`/System/Cryptexes` 等）、`runtime`（应用自带/工具链 shim 目录）。默认筛选项为 `user`。

## Discovery and usage resolution

1. 取用户真实 PATH：以 `/bin/zsh -l -i -c 'printf "%s" "$PATH"'` 为主、`-l -c` 为备，并把结果、`/etc/paths` + `/etc/paths.d/*`、`ProcessInfo.environment["PATH"]` 三源合并去重。**`-l` 不可省略**：`/etc/paths.d/homebrew`（提供 `/opt/homebrew/bin`）只由 `path_helper` 在登录 shell 中加载，早期用 `-i -c` 导致 ffmpeg/photorec 全部漏扫。GUI 应用从 Finder 启动时不继承 shell PATH，这一步不可省略。
2. 按 `:` 拆分、去空、去重目录；遍历条目，保留具有可执行位的普通文件，解析符号链接；按 basename 去重，首个 PATH 命中作为 `path`，其余记入 `allPaths`；按名称排序保证快照稳定。
3. 用法探测顺序：`--help` → `man -P cat <name>`。交互工具跳过 `--help`，仅尝试 man。
4. 子进程环境固定：`PAGER=cat, MANPAGER=cat, GIT_PAGER=cat, LC_ALL=C, TERM=dumb, COLUMNS=80`，stdin 忽略；stdout/stderr 写入临时文件（避免管道死锁），单进程 1.5 秒超时后 `SIGKILL`，并发上限 12，捕获上限 256 KiB。
5. 清理：去 ANSI、折叠空行、最多 80 行或 8192 字符；`description` 取第一段像散文的行（≥3 词、≥12 字符、不以 `usage`/`synopsis`/`-` 开头），截断到 160 字符。
6. 同时从 man 文本中提取 `EXAMPLES` / `EXAMPLE` 段，作为 `examplesFromMan` 纯文本补充。

## Example library and whitelist execution

每条内置示例不是一条 shell 字符串，而是 `argv` 模板加字段定义：

```json
{
  "id": "ffmpeg-to-mp4", "tool": "ffmpeg",
  "title": "转码为 MP4（H.264 + AAC）",
  "argv": ["-y", "-i", "{{input}}", "-c:v", "libx264", "-crf", "23", "-c:a", "aac", "{{output}}"],
  "fields": [
    {"key": "input", "label": "输入文件", "value": "input.mov"},
    {"key": "output", "label": "输出文件", "value": "output.mp4"}
  ],
  "risk": "write"
}
```

执行链路：选择示例 → 展开为可编辑字段表单 → 显示最终 argv 预览并二次确认 → `Process(executableURL: tool.path, arguments: argv)`。要点：

- **绝不构造 shell 命令字符串**；占位符只在单个 argv 元素内替换，拒绝含 NUL 的输入。
- `environment` 显式注入扫描时记录的 `loginPath`，避免 `ffmpeg` 等调用外部程序时找不到依赖。
- `currentDirectoryURL` 默认为用户主目录，可通过 `NSOpenPanel` 修改。
- stdout / stderr 经 `readabilityHandler` 流式进入控制台，缓冲上限 200 KiB；显示退出码；支持手动「停止」与 60 秒自动超时（`SIGKILL`）。
- 危险工具（`rm`、`sudo`、`dd`、`diskutil`、`mkfs`、`sh`、`bash`、`zsh` 等）拒绝执行；`risk: "write"` 与 `danger` 在确认框中标红提示。
- 交互式工具（含 `photorec`、`testdisk`、`top`、`vim`、`ssh` 等）不进入 Runner，改为生成 `.command` 临时脚本并用 `/usr/bin/open -a Terminal` 打开。

## 中文说明与中文搜索（2026-11-06 追加需求）

用户明确要求「中文说明一定要完善，且可以用中文描述搜索」，验收用例是
搜索「数据恢复」必须出现 `photorec`。实现分三层，全部离线、无翻译 API：

1. `Resources/tool-zh.json` 的 `tools` 精确词条：中文名、中文说明、中文分类、中文关键词数组。
   `photorec` 的关键词包含「数据恢复 / 文件恢复 / 误删恢复 / 照片恢复 / 格式化恢复」等。
2. `rules` 名称前缀规则：覆盖 PostgreSQL、PDF、WebP、JPEG XL、OpenEXR、TIFF、
   zstd/xz/lz4、Whisper、llama.cpp、OCR 训练、NSS/mbedTLS 等工具族。
3. `fallback` 按来源分类兜底，并拼接英文说明，保证每个工具都有中文可读文本。

中文元数据在扫描时写入快照字段（`titleZh` / `summaryZh` / `categoryZh` / `keywords`），
同时在 `AppModel.load()` 重新套用词典，因此**编辑词典后重启应用即生效，无需重新编译或重扫**。
`Search.swift` 是纯函数排序器，中文关键词精确命中优先级高于英文名称命中；
当前筛选无结果时自动扩大到全部工具并在界面提示。
`--verify` 与 `--search` 提供回归验证与命令行检索入口。

## UI

单个主窗口，`NavigationSplitView` 三栏：

- **侧栏**：工具总数与扫描时间、「重新扫描」按钮、搜索框、`用户安装 / 全部 / 系统` 筛选、工具列表（名称、路径、来源徽标、描述；最多渲染 300 行并显示计数）。
- **详情**：名称、绝对路径、`allPaths`、分类与用法来源徽标、描述、等宽字体用法块（可复制）、示例列表、man 补充示例。
- **运行控制台**：字段表单、工作目录、argv 预览、执行/停止、流式输出、退出码。

键盘：`⌘F` 聚焦搜索、`↑`/`↓` 移动选择、`Esc` 清空查询、`⌘C` 复制用法。

## Build and verification

- `build.sh`：`swiftc -swift-version 5 -O -target arm64-apple-macosx13.0 Sources/*.swift -o dist/CmdBook.app/Contents/MacOS/CmdBook`，复制 `Info.plist` 与 `examples.json`，`codesign -s -`。
- `main.swift` 在启动 `NSApplication` 前识别 `--scan`（无界面扫描并打印统计）与 `--verify`（用无害命令验证 Runner、示例库与读写快照），供构建后自动验证。
- 验证标准：编译零错误；`--scan` 产出的快照中 `ffmpeg`/`photorec` 被标为 `user` 且有用法文本；`--verify` 全部通过；`open dist/CmdBook.app` 无崩溃。
- 局限：无完整 Xcode，无法使用 Interface Builder 与 SwiftUI 预览；UI 正确性通过运行观察与截图确认，像素级细节可能需要后续微调。

## Risks and mitigations

| 风险 | 缓解 |
|------|------|
| GUI 进程 PATH 缺失导致命令找不到 | 使用绝对路径 + 显式注入 login PATH |
| 探测时某个工具挂起拖垮扫描 | 每进程 1.5s SIGKILL、并发 12、全局软超时 |
| 交互式 TUI 内嵌执行挂起 | 交互清单硬编码，统一转交 Terminal.app |
| 用户参数触发覆盖/删除 | 白名单 argv、字段化编辑、二次确认、危险工具拒绝 |
| 无 Developer ID 导致 Gatekeeper 拦截 | 临时签名 + 本地构建；首次打开用右键「打开」或 `xattr -d com.apple.quarantine` |
| 扫描写入中断损坏快照 | 临时文件 + 原子替换 |
| **`--help` 探测产生文件副作用** | **实测发现**：首版扫描在工作区写出了 `.mib2c-updaterc`、`orb.db/`、`realdoc/`、`rsa_priv.txt` 等文件，并删除了原有 `index.html`。修复：每个探测进程使用独立的临时工作目录（结束后递归清理），且对 `.app/Contents/` 等 `runtime` 来源的二进制一律不执行 `--help`，仅用 `man` / `whatis` 这类已知只读命令。`--verify` 含回归用例，用 `touch` 确认工作区不会被污染。 |
