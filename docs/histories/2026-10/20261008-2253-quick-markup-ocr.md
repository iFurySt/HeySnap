## 2026-10-08 22:53 | Task: 框选工具条直接 OCR

### Execution Context

- Agent ID: `/root`
- Runtime: Codex desktop

### User Query

框选工具条 Editor 左侧增加 OCR 图标；识别成功复制文字后退出截图，失败保留截图界面。

### Changes Overview

- 复用 Core 本地 Vision，后台识别冻结选区，不重新截取屏幕；工具条加入共用 OCR 图标并保持既有按钮尺寸。
- 成功写入剪切板后通过 `textCopied` 完成会话；空结果/异常保留会话和原剪切板，复制失败也不关闭；阻止重复点击，取消后忽略迟到结果。
- 滚动模式完成长图后识别，失败保留长图与工具条，允许继续进 Editor。
- 新增 AppKit 回归脚本，使用独立剪切板验证真实 Vision、图标位置、复制退出、空结果/识别异常保持、取消及滚动 OCR 失败后的编辑路由。

### Design Intent

保持框选界面的快速操作路径，与 Editor 共用识别能力，失败时允许调整选区或继续使用原工具条。

### Files Modified

- `apps/macos/HeySnap/Sources/Features/Capture/AreaSelectionController.swift`
- `apps/macos/HeySnap/Sources/App/AppMain.swift`
- `apps/macos/HeySnap/Tests/QuickMarkupOCRTests.swift`
- `scripts/test-macos-quick-markup-ocr.sh`

### Validation

框选 OCR AppKit 回归与既有滚动工具条回归通过；Developer ID 构建通过，已更新正式安装并重启，签名与二进制一致性检查通过。


### OCR 提示与 Editor 操作组

用户反馈 OCR hover 冗余、Editor OCR 的独立工具栏项与复制/保存组样式不同。框选提示简化为 OCR；Editor 把 OCR 合并到已有 SwiftUI 胶囊操作组，共用间距、图标、悬停提示与按钮外观，后台识别期间只禁用 OCR 按钮，完成/取消后恢复。Editor 回归同步检查三按钮组与原有识别/剪切板路径，并生成整窗预览用于检查布局。

分组版本的 Editor OCR 与框选 OCR 回归通过；Developer ID 构建、正式安装替换及签名/二进制一致性验证通过，应用已重启。


### v0.2.0 发布准备

用户验收后要求提交、推送并发布 minor 版本。版本由 0.1.4 升为 0.2.0，本地 bundle build 升为 6（CI 仍由 run number 覆盖）；新增面向用户的 v0.2.0 发布说明，汇总滚动截图与 OCR。本地 release 核心测试 37 项与 DMG 校验通过；本机无 Sparkle 私钥，appcast 签名和校验交给现有 CI secrets 与发布步骤。随后提交，推送 main 与 v0.2.0 tag，由现有 Actions 执行签名、公证和发布。
