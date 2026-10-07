# 前端协作说明

HeySnap 当前的界面由 `apps/macos/HeySnap/` 下的原生 macOS SwiftUI Preference 窗口和 AppKit 截图编辑器组成。

## macOS Preference

- 左侧侧边栏固定为 `General`、`HotKeys`、`About`，使用 macOS 原生 sidebar `List` 选中态，不加入登录或账号入口。
- 右侧设置页复用 HeyYo macOS settings 的布局语言：浅灰页面背景、圆角卡片（10px）、section 标题带 SF Symbol、设置行左侧标题/副标题、右侧紧凑控件、行间 hairline 分隔线。
- 卡片不要嵌套卡片；设置项保持单层列表，复杂控件优先放在行右侧。
- `General > Storage` 包含 `After capture` 下拉、保存位置、保存格式和 `Resize retina screenshots` 开关；`After capture` 支持截图后自动保存到 Save location 或打开编辑器，Retina 开关只影响保存/导出写盘时的输出尺寸，不改变截图捕获或编辑器画布分辨率。
- `General > Window Screenshot Background` 使用类似 System Settings Appearance 的原生大图选择器，包含 `Transparent`、`Shadow`、`Solid Color`、`Wallpaper` 四个选项；预览图由 SwiftUI 绘制，不依赖外部图片资产，内部窗口固定居中且保持平面风格。
- 快捷键录入使用 `ShortcutRecorderField` 胶囊输入框：点击进入录制态（系统焦点色高亮 + `Press Shortcut` 占位），按下含 ⌘/⌥/⌃ 的组合键即提交，右侧 ⓧ 清除快捷键（禁用该热键），`Esc` 或点击其他位置取消录制；与另一个 action 冲突时接管（对方被清除）。
- 主要固定格式控件需要稳定宽度，避免路径、快捷键、状态文案改变时挤压布局。
- 当前 Preference 不使用外部图片资产；About 页使用 SF Symbol 组成的轻量 app mark。

## macOS Editor

- 截图完成后的行为由 `General > After capture` 决定：可自动保存到 Save location，也可打开独立编辑窗口；保存目录、格式和 Retina downscale 作用于自动保存和编辑器 `Save`。
- 编辑窗口保持紧凑的原生截图编辑器结构，但只作用于独立 Editor window，不影响 Preference 主窗口：window 使用 full-size content titlebar，自绘 48pt 单行顶部工具条承载品牌、工具选择、颜色、线宽、撤销/重做、图片尺寸、缩放、复制和保存；下方是棋盘格背景的可滚动图片画布。
- 顶部工具条应保持单行密度，以 48pt content toolbar / 24pt 主要子控件作为基准，避免 full-size titlebar 和工具栏上下留白叠加成厚 chrome；调整后必须用实际窗口截图检查高度、traffic lights、品牌和工具组是否对齐。
- Editor 左侧品牌后提供 `text.viewfinder` OCR 图标；识别当前截图底图或待确认的裁切范围，后台识别期间禁用重复点击，完成后自动复制并显示短暂状态。空结果或失败不覆盖剪切板，关闭窗口后不交付结果。
- 棋盘格只作为编辑视图背景，复制/保存时不得进入导出位图，透明截图也不能被棋盘格污染。
- 编辑器首次打开时图片要按当前窗口自动适配；后续缩放走 `NSScrollView` magnification，保持标注坐标和导出分辨率不受视图缩放影响。滚轮缩放必须有阈值累计和小步进，避免触控板过于敏感；`Command+=` / `Command+-` 控制缩放，`Command+0` 回到适配窗口。Select 工具未命中标注时，拖动画布空白区或图片本体都应平移画布；图片小于视口时应居中显示。
- 工具按钮使用 SF Symbol 图标和 tooltip，避免在工具栏里堆长文案；画布内只显示图片与用户编辑对象。
- 当前编辑器是 AppKit 自绘 canvas，支持选择/移动、带 start/control/end 三锚点的曲线箭头、文字、矩形、圆形、直线、高亮、马赛克遮挡、裁切、撤销/重做、复制和保存。
- 矩形、圆圈、直线、箭头和文字的几何、绘制及文本输入优先复用 `Features/Annotations/`；Editor 与 quick markup 只适配自己的窗口、模型和坐标。不要把标注对象状态塞进 capture backend。快速标注文字支持 Normal/Filled，预览、输入与导出共用 Editor 的默认字号、字体、自动尺寸和圆角背景规则。

## 快速截图

- 框选反馈保持即时、静默：选区不额外叠加蓝色底色，松手进入标注时不改变底图色彩；截图窗口禁用出入动画，overlay 重绘禁用图层隐式动画并即时显示。
- 采集时禁用系统鼠标指针，定格底图和导出图片都不得包含指针；交互中的正常 cursor 由系统继续显示。
- 进入快速标注之前捕获一次桌面，框选和标注界面使用这张静态图片作底图；选区不得通过清空视图像素透出实时窗口。复制、保存、Pin 和转 Editor 均使用同一快照。
- 多屏底图分别从联合快照裁切，窗口候选位置与截图会话一起固定。进入滚动截图时隐藏静态底图，恢复实时窗口与鼠标穿透；滚动失败返回标注时重新显示原快照。

- 圆圈八个缩放锚点全部位于椭圆轮廓，四个斜向锚点不放在外接矩形角上；绘制、hover、命中与拖动必须使用共享形状几何。快速标注已有文字单击可拖动、双击进入编辑，输入期间抓文本框边缘可移动。

## 本地验证

构建、签名并安装本地 `.app`：

```sh
make macos-app
```

开发阶段统一打开 `/Applications/HeySnap.app`，保持 Screen Recording 授权和手动 UI 验证路径稳定。UI 或 app 代码变更后，先运行 `make macos-app`，再运行 `make restart-macos-app` 重启安装版；不要只 `open` 激活旧进程，也不要用 `open -n` 强开多个实例。UI 变更至少需要确认该命令可构建，并尽量启动 app 检查 Preference 窗口。
