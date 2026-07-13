# Said iOS

独立口语练习 App（iOS 12+ / iPad Air 1），导入现有 Anki `.apkg`，用 **Anki SM-2 调度**复习，并提供两种练习模式：

| 模式 | 牌组 | 流程 |
|------|------|------|
| **A · Pronounce** | `Pronounce_Learning::*`、轻听生词/句库 | 录音 → Azure 发音评分 |
| **B · Compose** | `English_Speaking::Compose::*` | 录音 → Azure STT/评分 + Qwen `Fix`/`Better` |

进度通过 **导出 `.apkg`** 带回桌面 Anki（非 AnkiWeb）。导入桌面前请先备份集合。

## 要求

- Xcode 16+（可设部署目标 iOS 12）
- [xcodegen](https://github.com/yonaskolb/XcodeGen)
- 真机建议：iPad Air 1（iOS 12.5）或任意 iPad 模拟器做 UI 验证

## 生成工程（产品名 Said）

```bash
cd /Users/misaka10704/Documents/Workspace/SpeakingAnkiIOS
xcodegen generate
open Said.xcodeproj
```

在 Xcode 中选择 Team 签名后，部署到设备。

## 使用

1. **设置**：填写 Azure Speech Key / Region，以及 DashScope Key（Compose 需要）
2. **导入**：从 Files / AirDrop 导入 Pronounce 或 Compose 的 `.apkg`
3. **复习**：进入牌组 → 录音 → 评分 → 翻面 → Again/Hard/Good/Easy
4. **导出**：导出带进度的 `.apkg`，在桌面 Anki 导入合并

## 架构说明

- UI：UIKit（兼容 iOS 12，无 SwiftUI）
- 集合：SQLite `collection.anki2`（与 Anki `.apkg` 同构）
- 调度：`AnkiScheduler` 实现 Anki SM-2（v2）语义，行为对齐开源 Anki / AnkiDroid；模块边界预留日后替换为 `rslib` C FFI
- Azure / Qwen：HTTPS REST（不依赖新版 Speech SDK，利于 iOS 12）
- 许可：调度语义源自 Anki 开源算法；若日后链接官方 `rslib`，整体需按 **AGPL-3.0** 分发源码

## 内存（Air 1）

- 复习后立即删除临时 WAV
- 单 WKWebView 复用，按卡加载 HTML
- 不做牌组浏览器 / 统计 / 同步服务

## 相关桌面插件规格

见 `Engineer_Tex/AI文本/01_Anki制作与维护/pronounce_scorer` 与 `speaking_compose`。
