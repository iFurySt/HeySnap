# 滚动截图实现参考

2026-10-07 调研，公开项目浅 clone 到临时目录，阅读后按 HeySnap 边界自行实现，没有引入项目依赖或直接复制第三方源码。

- [Shottr 使用与问题说明](https://shottr.cc/kb/scrollingcapture/)：自动滚动依赖屏幕录制/辅助功能权限，滚动动画、固定元素和滚轮修改器影响采样；手动模式应允许用户控制节奏。
- [ShareX 官方说明](https://getsharex.com/docs/scrolling-screenshot)：区域采样、比较重叠、追加新增底部；固定侧栏/页脚适合从选区排除。
- [Lenscap](https://github.com/rutmehta/Lenscap)：MIT；阅读 `Capture/ScrollingCapture.swift`、`ScrollingCapturePanel.swift` 和 `ImageStitcher.swift`，参考非激活控制浮窗、公开 CGEvent 滚轮事件和滚动后等待渲染的流程。
- [ScrollSnap](https://github.com/Brkgng/ScrollSnap)：MIT；阅读 `Managers/StitchingManager.swift`，参考位移可信度验证、最近可靠帧及反向滚动的处理动机。它的 Vision 配准/分带共识未直接移植。

HeySnap 使用下移图像的像素重叠搜索，静止基线与相对误差验证拒绝假位移；像素比较横向降采样，纵向保留原像素行。只追加新内容条带，自动滚动保持较大重叠并等待渲染；无法匹配就暂停自动滚动，允许手动回退恢复。当前只保证纵向、足够重叠、静态滚动内容，不宣称动画或大块固定元素场景通用。

可重复浏览器测试页：`apps/macos/HeySnap/Tests/Fixtures/scrolling-capture.html`。在 Chrome 打开后从页面顶部框选整个可滚动视口，分别手动/自动采集，核对 START、Section 01–16 各出现一次及 END；不能用浏览器 full-page screenshot 替代 HeySnap 采集测试。

当前操作：点击滚动图标后默认手动，选区底部中央固定自动/停止按钮，中央短暂提示操作、右侧实时显示长图预览；自动到底只停止滚动。完成时使用原工具条的勾/保存/Pin/Editor，不再有独立 Finish 浮窗。
