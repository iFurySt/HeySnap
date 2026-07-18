# 安全默认约束

这份文档用于把安全默认值讲清楚，避免实现逐步演进时越走越散。

## 当前状态

HeySnap 当前还没有接入真实认证、外部 API、文件上传或专用安全联系人。公开漏洞反馈先按仓库根目录 `SECURITY.md` 的私下披露要求处理。

当前 macOS app 的截图、保存、权限状态和诊断日志都在本机完成，不上传屏幕内容。未来即使引入开源核心 + 商业付费版本，也应保持 capture、editor、OCR 等核心能力默认本地可用；任何网络、授权或商业功能开关必须明确放在 app/distribution 层，不应让核心截图路径依赖远端服务。

建议维护的内容：

- 认证与授权约束。
- 密钥和环境变量管理方式。
- Apple 发布证书、私钥和 notary API key 只能保存在本机 ignored `.apple/` 或系统 Keychain，不得提交到 git 或写进可追踪文档。
- 依赖治理与供应链安全要求。
- 数据分级、脱敏与保留策略。
- 对外 API、Webhook、文件上传和沙箱执行的规则。

依赖、SBOM 和 provenance 的后续接入建议，统一写在 `docs/SUPPLY_CHAIN_SECURITY.md`。
