# 年付Sandbox入账与跨端恢复（2026-11-18）

## 已验证

- 用户本人完成02沙盒账号的云端年付US$99.99/年确认，Apple系统显示“操作完成／你已成功完成购买／Environment: Sandbox”。没有真实付款或重复月付购买。
- 返回App后，背景自动从到期资料只读路由恢复首页；购买弹窗保持。重新读取交易诊断：历史3/已验证3/Sandbox3/本账号3/可申请3。
- Supabase SQL Editor以begin read only事务仅查询02 owner，逐产品汇总：monthly/Sandbox/2笔/有效0/撤销0，原latest_expiry=2026-11-12 05:49:35+00；yearly/Sandbox/1笔/有效1/撤销0，latest_expiry=2026-11-18 09:53:56+00。没有Production行。
- 授权自动恢复active/cloud/max_devices=4/expires_at=2026-11-18 09:53:56+00，与年付交易一致。没有手工改授权、期限、台账或设备。
- Web原02只读归档点“重新检查授权”后实际恢复正常总览，原1条合成客户保留，显示到期2026/11/18 01:53（洛杉矶）。这是真实App购买后另一Web会话权益恢复证据，不当成跨设备退款失效。
- App Store Connect后台已实际恢复可登录；只读核对02测试员美国/每5分钟按月续期/中断购买false。未修改测试员；已删除临时apple-connect监测。后台可访问不等于官方状态公告已全部恢复。

## 年付恢复与续期复核

- 本人完成恢复购买的02沙盒密码验证后，实际真机底部显示“已恢复可用的购买权益。”，背景仍为可用首页。证据：deliverables/2026-11-18-yearly-sandbox/restored-ipad.png。
- 随后只读复核：monthly/Sandbox仍2笔、有效0；yearly/Sandbox为7笔、有效1。授权active/max_devices=4，到期2026-11-18 15:53:56+00，与年付最新期限一致；没有Production行。
- 进一步只读核对年付时间序列：首次purchased_at为2026-11-18 08:53:56+00，随后09:53:56至14:53:56逐小时接续，共7条，每条expires_at等于下一条purchased_at；全部revoked_at=NULL。这证明本次沙盒年付连续续期及最新授权对齐。没有手动再次购买，不能把续期条数当成恢复产生的重复购买。
- 页面旧“交易诊断3”是先前扫描缓存，未重新点击，不当作最新台账数量。恢复完成本身以实际成功提示确认。
- 本轮没有改代码、生产数据、授权或设备登记，也未重新购买、清历史或提交退款。

## 未完成和边界

未读取本次具体Apple通知类型或接口调用日志，不将台账入账单独归因于通知。没有完成年度退款/撤销、退款后跨设备即时失效、真实本地买断、生产老用户凭据升级重装。沙盒加速有效期不当成正式年付真实一年。普通生产收费仍关闭。

本轮无购买代码修改，不重复运行未变化的隔离测试。以上为Apple Sandbox真机、服务端只读及Web实际观察；不存在手写交易模拟。证据目录：协作工作区deliverables/2026-11-18-yearly-sandbox/，未保存密码框截图或交易签名。

## 提交后继续验收

- 真机重新读取交易诊断：历史9/已验证9/Sandbox9/本账号9/可申请9，与后台2笔月付+7笔年付一致。
- 打开沙盒退款测试后，Apple系统页实际仍显示“无法连接／重试”。未提交退款、未重复购买，保留证据refund-unavailable.png；已关闭错误页，不重复重试。退款撤销及跨端失效仍为阻碍项，不判通过。
- 本轮仅文档更新，无产品代码或发布包变化，因此无需重新部署App/Web。

## 退款再次复核

- 2026-11-18真机07:25再次打开退款入口，Apple系统页仍为“无法连接”，未进入原因表单、未提交退款；已关闭，不循环重试。
- 代码复核StorePurchaseManager.requestSandboxRefund：遍历已验证交易，通过SandboxRefundPolicy按环境、账号所有权、云端商品、撤销与升级状态过滤，再选择purchaseDate最新的一笔；不存在固定选择旧月付交易的实现。
- Apple开发者论坛 https://developer.apple.com/forums/thread/846103 有其他开发者报告相同系统退款页故障，包括自动续订商品、iOS27.2和替代API路径。帖子是开发者报告，不是Apple工程师的官方根因确认。仅可作为外部故障线索，不能据此证明本项目无问题或退款通过。
- 后续仍需真实原因表单提交、REFUND签名通知、台账revoked_at及App/Web授权失效闭环。不得把系统回调success单独作为退款完成依据。

## 真机退款失败日志定位（07:34 PST）

使用macOS控制台选择02测试iPad，先筛选refund，开始短时流式日志并在Apple错误页点击一次重试，随后暂停采集；没有保存完整设备日志、凭据、交易ID或设备标识。

确认的错误链：
- Apple进程AMSEngagementViewService请求Apple Sandbox主机mzstorekit-sb.itunes.apple.com的/inApps/v1/refund/info/<redacted>。
- 系统amsaccountsd生成请求签名头；这不等于认证最终成功。
- 同一请求链返回AMSErrorDomain Code=306：Reached max retry count / Task reached max retry count (3 / 3)。
- AMSUIWebView报告Action failed，错误元数据AMSStatusCode=200，随后实际UI显示“无法连接”。HTTP200不代表表单业务初始化成功。

已定位失败在Apple系统退款表单读取退款信息的阶段，尚未进入原因表单和提交阶段，不是本App向Supabase提交退款失败。不能凭此排除所有账号/网络因素，或断言Apple内部服务端唯一根因；需Apple依据系统诊断继续判定。该错误链与论坛thread/846103其他开发者报告相符，但论坛不是官方故障确认。此证据优先于此前仅凭截图的推断。

官方测试文档：https://developer.apple.com/documentation/storekit/testing-refund-requests 支持Sandbox退款，需要原因表单提交后再核验revocationDate及REFUND签名通知。当前均未完成。建议向Apple Feedback报告此可复现错误；未经用户明确授权不对外发送诊断。

## 年付自然到期验收基线

2026-11-18 15:49:47 UTC只读查询：年付7笔、有效1、授权active，交易与授权到期均15:53:56 UTC。等待自然到期，不改数据库期限或取消购买。

本地买断准备复核：LegacyLocalAccessPolicy.allowsLocalPurchase在cutoverConfigured=false且尚无本地购买时允许既有专用Sandbox验收；因此无需配置firstPaidLocalBuild即可测试。此前口头称“受收费分界阻止”不准确，已更正。生产收费与本地门禁仍关闭。

15:54:14 UTC到原期限后只读复核：年付自动续期至第8笔、有效1，交易及授权到期均16:53:56 UTC，status=active。Web重新加载显示洛杉矶08:53，客户1条保留。故没有发生自然到期，不能判定到期只读已通过。已请求仅关闭02沙盒年付自动续订的确认，尚未执行，不改服务端期限。

## 关闭02沙盒年付自动续订

经用户明确确认，仅操作iPad设置→开发者→02沙盒Apple账户→管理→订阅→云端版年付。本人完成系统密码验证后，代理点取消订阅并确认，Apple详情实际显示“已取消订阅／订阅将于11月18日到期”，按钮变为续订。未点击续订、未退款、未清历史、未修改服务端授权。当前最近后台到期为16:53:56 UTC（洛杉矶08:53:56），到期后仍需真实App/Web只读与导出核验；取消续订本身不等于到期失效。证据yearly-renewal-cancelled.png。
