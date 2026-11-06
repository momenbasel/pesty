<div align="center">

<img src="/Users/henry_ji/Documents/pesty/docs/assets/icon.png" width="128" alt="Pesty icon" />

# Pesty

**为 macOS 设计的免费、开源的剪贴板管理器 - 受 [Paste](https://pasteapp.io) 启发**。

将你的剪贴板

[![Download](https://img.shields.io/github/v/release/momenbasel/pesty?label=download&style=flat-square)](https://github.com/momenbasel/pesty/releases/latest)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg?style=flat-square)](LICENSE)
![Platform](https://img.shields.io/badge/macOS-14%2B-black?style=flat-square&logo=apple)
![Universal](https://img.shields.io/badge/Universal-Apple%20Silicon%20%2B%20Intel-orange?style=flat-square)

[**官网**](https://www.moamenbasel.com/pesty/) · [下载](https://github.com/momenbasel/pesty/releases/latest) · [Homebrew](#install) · [Mac App Store](https://apps.apple.com/us/app/pesty-clipboard-manager/id6784511397)

<a href="https://apps.apple.com/us/app/pesty-clipboard-manager/id6784511397"><img src="https://tools.applemediaservices.com/api/badges/download-on-the-mac-app-store/black/en-us?size=250x83" alt="Download Pesty on the Mac App Store" height="56" /></a>

<sub>Pesty **免费开源**。在 Mac App Store 里付费帮我我们支付 Apple Developer Program 的费用以保证软件被 Apple 认证。无需支付即可通过 [Homebrew](#install) 或 [直接下载](https://github.com/momenbasel/pesty/releases/latest) 来完全免费地获得本软件。</sub>

<img src="/Users/henry_ji/Documents/pesty/docs/assets/demo.gif" width="820" alt="Pesty clipboard manager demo - color-coded clipboard strip with keyboard navigation on macOS" />

### ⭐ 如果 Pesty 帮助你省钱了，为本仓库点个星 —— 这真的很有用

</div>

## 什么是 Pesty?

你复制过的所有东西都被 Pesty 妥善记录并可以即刻找回。按下设定好的全局快捷键，窗口将从屏幕底部弹出，用方向键 (或  `⌘1`–`⌘9`)选择一块剪贴板，按下 `return` 即可粘贴到当前窗口。

它是 Paste 的完美平替 - 用 **Swift + SwiftUI** 构建，**零第三方依赖**，**由 Apple 认证**且**永久免费**。

## 功能

- **弹出窗口** - 从活动屏幕底部弹出完整宽度的半透明窗口
- **颜色编码的卡片** - 每张卡片的标题栏都用来源对应的高亮色标注，且显示 app 图标，类型标签，复制时间，预览，底部显示字数统计和快捷粘贴编号
- **全格式** - 纯文本、富文本、链接、图片、文件、颜色……
- **置顶板** - 将需要重复使用的剪贴板保存在自助命名，颜色标注且不会过期的置顶板中
- **iCloud 同步** - 可通过 iCloud Drive 在你的多台 Mac 间同步剪贴板历史
- **即时搜索** - 键入以搜索剪贴板历史
- **键盘交互** - 方向键移动， `return`  键确认， `⌘1`–`⌘9`  快捷粘贴， `⌫`  或  `⌘⌫` 删除, `esc` 关闭
- **直接粘贴** - 直接把剪贴板拖进当前窗口，无需手动按下 `⌘V` 
- **隐私保护** - 忽略密码管理器标记为隐藏的内容；使用`0600`权限存储历史记录
- **菜单栏应用** - 以菜单栏形式静默运行，可选在登录时启动
- **轻量原生** - 仅一个  `.app`, 无 Electron, 无后台网页

## 安装

### Homebrew（推荐）

```bash
brew install --cask momenbasel/pesty/pesty
```

### 直接下载

1. 从  [latest release](https://github.com/momenbasel/pesty/releases/latest)  下载  `Pesty-x.y.z.dmg` 
2. 打开 DMG 文件，将 **Pesty** 拖入 **Applications**
3. 运行 Pesty，它会出现在菜单栏中

构建由一个 Developer ID 签名并被 Apple 认证，所以不会出现 Gatekeeper 警告

## 首次运行

1. 按下  **`⌘⇧V`** (默认快捷键) 打开面板
2. 选择一张卡片，按下 `return`
   - **直接下载/Homebrew 构建：**首次粘贴时, macOS 会要求**辅助功能**权限，授权以便 pesty 可以直接向其它 App 中粘贴，你可以随时在**设置 → 权限**中更改此项设置
   - **Mac App Store 版本：**完全沙盒运行，**无需**权限，选中的剪贴板会复制，焦点会自动回到原来的 app 中，所以直接按下 **`⌘V`** 粘贴即可

## 快捷键

| Key                         | Action                                                       |
| --------------------------- | ------------------------------------------------------------ |
| `⌘⇧V`（可修改）             | 显示/隐藏面板                                                |
| `⌘⇧S`（面板打开时）         | 打开设置                                                     |
| `⌘⇧P`（面板打开时）         | 暂停/恢复剪贴板监视器                                        |
| `←` `→` `↑` `↓`             | 移动选择器                                                   |
| `return`                    | 粘贴所选内容                                                 |
| `⌘1`–`⌘9`（可修改）         | 快捷粘贴第 N 个剪贴板；按住纯文本修饰键（默认为 `⇧`）以纯文本粘贴 |
| `⌫` （搜索框为空时）或 `⌘⌫` | 删除选中的剪贴板                                             |
| 输入任意内容                | 搜索                                                         |
| `esc`                       | 清除搜索，关闭                                               |

## 从源码构建

需要 macOS 14+ 和 Xcode 16+ (Swift 6)

```bash
git clone https://github.com/momenbasel/pesty.git
cd pesty
swift run            # run in place
# or build a distributable .app:
VERSION=1.0.0 BUILD=1 ./scripts/build_app.sh
open packaging/Pesty.app
```

生成带签名和 Apple 认证的 DMG（需要 Developer ID 授权和 App Store Connect API 密钥）

```bash
SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
ASC_KEY="$HOME/.appstoreconnect/private_keys/AuthKey_XXXX.p8" \
ASC_KEY_ID="XXXX" ASC_ISSUER="<issuer-uuid>" \
./scripts/release_build.sh
```

## 项目结构

```
Sources/Pesty/
  Main.swift            entry point
  AppController.swift   app delegate, hotkey + menu-bar wiring, paste flow
  Models/               ClipItem, ClipType, Pinboard
  Store/                ClipboardStore (history, pinboards, persistence)
  Monitor/              ClipboardMonitor (pasteboard polling), PasteService (⌘V injection)
  Hotkey/               HotKeyCenter (Carbon global hotkey)
  UI/                   BarView, ClipCardView, PinboardTabs, the sliding panel
  Settings/             Settings store + preferences window + hotkey recorder
  Util/                 icons, color hex, visual-effect view, launch-at-login
scripts/                build, icon, sign + notarize
packaging/              Info.plist, entitlements, generated artifacts
```

## Pesty vs 其它 Mac 剪贴板管理器

|                     | Pesty                                     | Paste  | Maccy      |
| ------------------- | ----------------------------------------- | ------ | ---------- |
| 定价                | **免费**（可选通过 App store 一次性付款） | 订阅制 | 免费       |
| 开源                | **是 (MIT)**                              | 否     | 是         |
| 按颜色编码的 UI     | 是                                        | 是     | 否（列表） |
| 置顶板              | 是                                        | 是     | 否         |
| 源 app 颜色编码     | 是                                        | 是     | 否         |
| 原生（无 Electron） | 是                                        | 是     | 是         |
| 签名与认证          | 是                                        | 是     | 是         |

Pesty 重构了 Paste 中的常用模块 - 上滑面板，多色卡片，置顶板，搜索和键盘驱动的操作 - 免费、开源、原生。如果你喜欢 Paste，[购买它](https://pasteapp.io)；它很优秀。Pesty 专为需要 **Paste** 免费替代或者一个更漂亮的 **Maccy** 的用户。

## FAQ

**Pesty 是免费的吗** 是的 - 免费在 GitHub 上开源（MIT）或通过 Homebrew 下载。也可以通过 App Store 给我们一点点支持，帮助我们支付 Developer ID 和 Apple 签名的费用。各种渠道的 app 是一样的！

**Pesty 是一个优秀的 Mac 剪贴板管理工具吗？** 它为你的复制过的所有内容提供一个可索引的记录并可一键粘贴，同时提供置顶板和颜色标签。

**它能保证隐私吗？** 是的！所有内容都保存在你的 Mac 上，没有服务器，没有分析，没有网络请求，密码管理器的剪贴板会被忽略。

**它需要什么版本的 macOS？** 搭载 M 系列或 Intel 芯片的 macOS 14 (Sonoma) 或更新

> **关键词：** Mac 剪贴板管理器，macOS 剪贴板历史，Paste 平替，开源剪贴板管理器，Maccy 替代品，复制粘贴历史，剪贴板置顶

🔗 **官网：** [www.moamenbasel.com/pesty](https://www.moamenbasel.com/pesty/)

## 贡献

欢迎 PRs - 参见 [CONTRIBUTING.md](CONTRIBUTING.md)。好的 Issues：大号预览面板，拖动卡片，面板大小调整手柄，iOS/iPad 支持，更多格式的渲染器。

## 尝试一下

[JMacy](https://jmacy.xyz) - 专为 macOS 打造的最好最快的下载器，多连接分段，让您满速下载，同时支持浏览器捕获和流媒体下载。

## 协议

[MIT](LICENSE) © 2026 Moamen Basel.

## 免责声明

Pesty 是一个独立项目，**不隶属于且不被** Paste 及其商标所有者 (Wonder Warp / FIPLAB) **承认**，与之**没有任何关联**。"Paste" 仅用于描述灵感来源，所有商标均归属其原本所有者。