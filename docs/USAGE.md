# 进度往返（.apkg）

1. 桌面 Anki：导出 Pronounce / Compose 牌组为 `.apkg`（勾选包含调度信息）。
2. 通过 AirDrop / 文件 App 拷到 iPad，在 SpeakingAnki 点「导入」。
3. 在 App 内复习；每次 Again/Hard/Good/Easy 写入 `cards` + `revlog`。
4. 点「导出」，将 `.apkg` 传回 Mac。
5. **先备份**桌面集合，再导入该包合并进度。

注意：这是文件往返，不是 AnkiWeb。若桌面与 App 同时改同一张卡，以导入时 Anki 的合并规则为准。

# Air 1 / iOS 12

- 部署目标 12.0；UIKit only
- Azure / DashScope 走 REST，避免新 SDK 抬高最低系统版本
- 弱网：评分失败会显示错误，可重试；不会自动改调度
- 大媒体：仅通过 `baseURL = collection.media` 加载当前卡引用的文件
