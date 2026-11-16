# 财务二维码分享及对账单默认 PDF（1.1）

## 行为

- App 本地/云端收款方式的二维码预览，左上增加系统分享按钮。复用现有名片二维码的 Image ShareLink / SharePreview 方式，右侧完成按钮保留；无图片时没有可分享内容。
- App 对账单顶部直接 ShareLink PDF 文件，不再先弹出 PDF/CSV 格式菜单。CSV 保留为独立底部导出按钮。既有 PDF 文件生成代码未更换。
- Web 收款方式列表增加图片存在时的分享二维码按钮；原预览中的分享继续可用。
- Web 对账单主分享直接生成一个多页 application/pdf 文件，不再生成多张 PNG。浏览器文件分享支持时打开系统分享，否则下载 PDF 并提示可在微信选文件发送；取消系统分享不额外下载。
- Web PDF 用当前 Canvas 绘制的 JPEG 页面封装，离线保存中文等字形，无外部 PDF 库或字体请求；属于图像型 PDF，不能当作可搜索文本 PDF。保留原有每15行分页、费用列、横向合计及各币种总计，表格计算和业务状态均未改。
- 新增纯字节 PDF 模块有页结构、二进制流长度、xref偏移及无效页回归；Web实际分享函数有文件类型、单文件、取消不下载与二维码按钮回归。

## 验证

- Node --test WithoutPersistence/web/tests/*.test.mjs：最终 197 项全部通过。早期六语言繁体文案不一致已按 App 现有资源统一后重跑。
- Release iOS Simulator 构建成功。
- verify-localizations.py --shared-web --app /tmp/trvelma-legacy-policy-build/Build/Products/Release-iphonesimulator/Wishlist.app：309 键六语言和实际编译资源无错误。
- 浏览器运行从实际 shareAgencyStatement 提取的生产函数，使用20条合成订单；夹具仅替换数据及系统分享能力，验证下载分支。生成912739字节、2页 PDF1.4，pdfinfo可解析，pdftoppm逐页渲染检查中文、20条记录、停车/打印费、单行合计$115及总计$2300完整，无裁切。未读取或发送真实订单。
- git diff --check：通过。
- 系统分享成功发送到微信/其他应用未在真机验证；没有自动选择收件人或对外发送。App分享面板交互待真机验收。

## 文件与状态

App：Views/Wallet/WalletView.swift、CloudWalletView.swift、AgencyStatementView.swift；六语言 Localizable.xcstrings。
Web：app.js、statement-pdf.mjs、localization.mjs；tests/integration.test.mjs、statement-pdf.test.mjs。

日志、合成PDF及两页渲染图保存在协作目录 deliverables/2026-11-16-finance-share/。仅本地完成，尚未提交或部署；没有数据库迁移、权限或结算状态变更。工作区其他未提交的1.1功能保持原样。

## 后续真机验证

2026-11-16已完成三台更新，16 Plus相关财务显示及系统分享入口通过。没有实际发送到联系人。iPad与Max分享尚未逐一覆盖；详见[三台真机记录](device-finance-acceptance-2026-11-16.md)。上方“未安装”是较早本地验收阶段状态。
