# 1.1 原交易Sandbox退款验收准备

## 已提交项

到期归档刷新修复已定向提交50b35a5，设备更新记录dc74db7。iPad与两台iPhone已更新原修复，独立快照App381项/Release构建通过。无Web变更，不重复发布；不含Git推送或1.1正式商店审核。

## 本次后续代码（尚未提交）

- StorePurchaseManager新增SandboxRefundPolicy及仅DEBUG && STOREKIT_SANDBOX_ACCEPTANCE编译的requestSandboxRefund。
- 入口仅02生命周期账号。只选择StoreKit已验证、appAccountToken匹配当前业务owner、Sandbox环境、云端产品、未撤销且未upgraded的原交易，按purchaseDate取最新；没有过期过滤，是否可以退由Apple决定。
- 请求前及系统申请页返回后校验当前云端账号；重用现有环境验证与preflight。只调用原Transaction.beginRefundRequest(in:)，不发起新购买、不直接写台账或权益、不finish交易。
- success消息仅表示申请已提交，必须继续等待Apple签名结果/通知，不能等同退款批准或权益撤销。
- 正式版和普通手机开发包无入口；业务与审核账号也不可使用。新增5条提示六语言齐全。
- PurchasePlansView新增开发验收按钮和原交易说明；生产销售仍关闭。

## 实际验证

- 完整工作区App394项通过（本轮新增4项选择策略：owner/token、Production/Xcode拒绝、普通build/产品隔离、已撤销或upgraded拒绝）。不把它当真实Apple退款。
- iPad Sandbox签名构建、签名验证、覆盖安装及启动成功；Release模拟器构建成功。
- 二进制nm验证requestSandboxRefund：Release 0个符号，Sandbox Debug 20个相关符号。
- 六语言及实际iPad编译资源检查315键，无错误；git diff --check通过。
- 服务端只读回查02：Sandbox2笔、revoked0、Production0、最后到期2026-11-12 05:49:35Z。没有手工写撤销或新购买。
- 镜像点击未能进入版本页，已请求用户真机打开“版本与购买→沙盒退款测试”，先停在Apple申请页不提交；目前未观察到系统退款页，不报告真实退款通过。

## 后续

先核对系统申请页是否明确为原沙盒交易；最终提交由本人操作。无可用交易/Apple拒绝/已申请时保留结果，不反复购买。申请后等待签名REFUND/REVOKE或交易撤销结果，回读台账、授权和跨设备状态。原交易已经到期，因此即使成功撤销，也不等于验证了有效付费期中退款后的权限即时回收。

参考：
- https://developer.apple.com/documentation/storekit/testing-refund-requests
- https://developer.apple.com/documentation/storekit/transaction/beginrefundrequest(in:)-9k0pj

日志、代码SHA和基线位于协作目录deliverables/2026-11-16-sandbox-refund/。本批后续代码尚未提交，不影响已发布Web。

## 无可用交易后的定向诊断

- 用户报告没有可用沙盒交易；尚未观察到Apple申请页，没有申请退款或再次购买。
- 不把该提示直接解释为“必须新购”。正在核对系统Sandbox Apple账号与业务02账号是否一致，未退出/切换Apple账户或清除购买历史。
- 增加仅沙盒验收构建可见的数量诊断：历史/验签通过/Sandbox/本业务账号/可申请笔数。不显示交易ID、appAccountToken或签名。筛选条件不放宽。
- 最新诊断包构建、签名、覆盖安装通过；编译六语言316键检查通过。本次纯诊断不更改购买或退款提交决策，未重复跑输入未变的策略回归；先前394项结果仍属相应版本。
- 当前待本人确认设置中沙盒邮箱，再在App读取诊断计数；没有这些证据前不假定是空历史或归属不匹配。若确为历史未同步，再考虑本人触发恢复原购买，不新增购买。

用户已确认系统Sandbox Apple账号为ystechnology02@yahoo.com。当前不再以账号选错解释无可用交易，仍需实际历史/验签/Sandbox/owner/eligible计数。镜像曾看到删除账号表单，已点击取消并确认返回归档；未输入密码/DELETE、未执行删除。已请求本人在更新后的退款测试入口读取计数或保留实际Apple申请页。没有新购、清除历史、手动改交易归属或提交退款。

## 17:47 只读诊断拆分

用户确认 Apple 沙盒退款弹窗持续“无法连接”，一次重试仍失败。官方开发者状态页 17:04 显示 App Store Sandbox 可用，不能据此排除单设备或会话故障。未提交退款、未购买、未变更台账。

新增仅 Debug + STOREKIT_SANDBOX_ACCEPTANCE、生命周期账号可见的“读取沙盒交易诊断”，复用严格验签、环境、账号和产品筛选；scene 为 nil 时在调用 beginRefundRequest 前返回，不打开 Apple 退款 UI。

实际验证：iPad Debug 构建成功（/tmp/trvelma-refund-readonly-diagnostic-build.log）、codesign 严格校验通过、六语言已编译资源317键无错误。覆盖安装并启动 A16 iPad 成功，旧客户1条仍可见。既有394测试未重复执行；新只读入口实际点击及退款结果待真机确认。本次未提交代码或启用正式收费。

## 17:49 真机只读诊断通过

用户点击“读取沙盒交易诊断”后截图核实：历史2、已验证2、沙盒2、本账号2、可申请2。与此前服务端只读台账Sandbox2笔吻合；排除本次设备Transaction.all为空及appAccountToken不匹配。可申请只是本地严格筛选结果，不等于Apple批准退款。结果字号小且显示在说明下方，用户初看误以为无反应。Apple退款系统页仍无法连接，具体网络/会话/服务端内部原因未确证；不重新购买、不清历史、不改台账。真机截图：workspace deliverables/2026-11-16-sandbox-refund/readonly-diagnostic-two-transactions.jpg。

## 17:53 诊断可见性与正式版隔离

诊断结果移到读取按钮下方，使用body/primary等宽数字及accessibilityIdentifier，避免脚注灰字难辨。发布诊断前新增Task取消和当前owner再次校验。iPad Debug构建、codesign、六语言317键校验通过；覆盖安装后到期资料页正常启动且客户1条。最新字号布局未通过真机再次点击验收。Release模拟器构建通过（/tmp/trvelma-refund-readonly-release.log），nm检索退款请求、只读诊断方法/字段相关符号0；正式版仍不包含该测试入口。未重复运行未改的纯交易筛选策略测试；未提交代码或正式收费。

## 日期功能提交后继续购买验收

日期功能ae19973及发布准备a05bab3已提交，不含本文件与沙盒退款入口等未提交计费工作。继续跑verify-sync-regressions.py --storekit（隔离模拟器，不连接真实支付）；实际结果见trvelma-purchase-acceptance-20261116.log。iPad保持02到期账号/旧客户1条，镜像点击版本与购买未响应，已请求本人打开并读取只读诊断；没有再次购买、退款提交、切换账号或清除真实交易。Cloudflare仍登录页，Web尚未发布。

继续验收结果：StoreKit本地集成17项全部通过，包括买断恢复/退款、原交易重试、owner隔离、验签中切换账号、预检中重复购买仅一笔。仅隔离Xcode交易，不当真实Sandbox。用户已打开iPad购买页并点只读诊断，截图再次核实五项均2且清晰可见；请求本人恢复原交易，待系统提示，未新购买/提交退款。

## 已到期账号恢复购买提示：本人确认通过

用户在iPad完成Apple沙盒密码验证，随后本人确认最终提示为“未找到可恢复的有效购买。订阅可能已到期或退款”。与02账号此前两笔Sandbox交易已自然到期、无有效购买的基线一致：恢复未误报成功或提示缺少服务端配置。此为用户手工确认，镜像未读取到页面底部文字；不宣称新增台账查询或通知验收。不把通用提示里的“退款”当真实退款证据；没有新购买、退款申请或权限写入。只读交易诊断五项均2的真机截图已单独保存。真实退款/撤销、跨设备即时失效、年度/买断真实Sandbox和生产老用户凭据门槛仍未完成。

## 设置验收后继续购买验收

设置变更已定向提交62c78f9，三台真机已更新并由用户确认界面可用。重新启动iPad，仍为02到期资料只读页，原合成客户1条可见。镜像点击“版本与购买”未打开，已请用户在真机进入并重试原交易退款入口，先保留结果、不提交或新购。此前恢复结果仍为无有效购买；本轮未新增交易查询、退款成功或服务端变更证据。

另记录用户延后处理项：我的账号页“关闭”按钮字号偏小，下次界面修改时一起调整，本轮购买验收不改。
