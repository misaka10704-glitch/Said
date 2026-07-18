# 进度往返（.apkg）

## 换机迁移（Said → Said）

1. 旧设备：**设置 → 本地数据维护 → 换机导出 APKG**（或牌组菜单 → 换机导出（无媒体））
2. 通过 AirDrop / 文件 App 传到新设备
3. 新设备：牌组列表 **导入 APKG**（合并导入）
4. 导入完成后按提示补全：
   - **批量翻译**（牌组菜单，处理 `trans` 标签）
   - **Edge TTS 批量生成**（设置，补参考音频）

换机包规范：**含学习调度与牌组配置，不含媒体文件**；笔记中的中文翻译与 `[sound:…]` 引用会在导出时剥离，并自动打上 `trans` 标签。

## 桌面 Anki 往返

1. 桌面 Anki：导出 Pronounce / Compose 牌组为 `.apkg`（勾选包含调度信息）。
2. 通过 AirDrop / 文件 App 拷到 iPad，在 Said 点「导入」。
3. 在 App 内复习；每次 Again/Hard/Good/Easy 写入 `cards` + `revlog`。
4. **本地数据维护 → 导出 APKG（含媒体，桌面同步）**，将 `.apkg` 传回 Mac。
5. **先备份**桌面集合，再导入该包合并进度。

注意：这是文件往返，不是 AnkiWeb。若桌面与 App 同时改同一张卡，以导入时 Anki 的合并规则为准。

# Air 1 / iOS 12

- 部署目标 12.0；UIKit only
- Azure / DashScope 走 REST，避免新 SDK 抬高最低系统版本
- 弱网：评分失败会显示错误，可重试；不会自动改调度
- 大媒体：仅通过 `baseURL = collection.media` 加载当前卡引用的文件
