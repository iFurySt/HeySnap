## [2026-10-07 22:20] | Task: 静默框选反馈

### 🤖 Execution Context

- **Agent ID**: `/root`
- **Base Model**: GPT-6
- **Runtime**: Codex desktop

### 📥 User Query

> 截图框选后底图有动画感，要求静默框选，不让人感觉下面的画面动了。

### 🛠 Changes Overview

- 移除框选过程中的淡蓝色选区填充，松手进入快速标注时不再移除色罩而造成底图颜色变化。
- 设置截图窗口 `animationBehavior = .none`，关闭系统出入动画。
- overlay 图层关闭 contents/bounds/position/opacity actions；刷新在禁止隐式动画的 Core Animation 事务中立即重绘。
- 保留定格底图、边框和选区外遮罩，更新架构、前端规范及发布记录。

### 🧠 Design Intent (Why)

截图画面应保持固定，交互只即时更新框选反馈。避免装饰性填充或系统图层过渡让用户误以为底图在变化。

### ✅ Validation

- 定格底图像素回归通过，覆盖不透明选区、稳定重绘与 1x/2x 多屏裁切。
- app 构建、Developer ID 签名及安装版重启通过（本机构建关闭在线时间戳）；真实桌面的主观过渡感由用户继续验证。

### 📁 Files Modified

- `apps/macos/HeySnap/Sources/Features/Capture/AreaSelectionController.swift`
- `docs/ARCHITECTURE.md`、`docs/FRONTEND.md`、`docs/releases/feature-release-notes.md`
