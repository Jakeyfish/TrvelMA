# 本地买断真实Sandbox验收（2026-11-18）

- iPad 1.1(14)专用验收构建，App与系统Sandbox均02；没有切换或修改业务账号。
- 商品本地版买断US$29.99一次性费用，系统确认页明确仅用于测试、不收取费用；本人完成购买。
- 实际观察Apple“操作完成／你已成功完成购买／Environment: Sandbox”，App本地商品变为“已购买”（禁用购买）、底部“购买已验证”。无重复购买。
- 调用链复核：local交易通过StoreKit .verified及Sandbox环境校验，refreshLocalEntitlement后finish；不送云端订阅台账，不授予生产本地购买标志或云端授权。本轮未改代码，未开启正式收费或本地门禁。
- 恢复购买已发起一次AppStore.sync，Apple要求本人02沙盒密码验证；本人验证后实际真机显示“已恢复可用的购买权益。”，回到本地商品仍为“已购买”且按钮禁用。恢复成功提示也可能包含当前有效云端年付，不能单凭此提示证明本地权益；本地商品状态提供单独观察。未重装，不能称重装恢复已通过。
- 当前App仍为有效云端账号，不能用此证明本地账号的航班入口已被拦截；后续需在保留02云端到期验收上下文前提下另选隔离路径。
- 待完成：恢复结果、本地使用隔离与禁在线航班、生产老用户升级/重装凭据、本地买断重装恢复。Sandbox买断不授予Production本地使用权。

证据：协作工作区deliverables/2026-11-18-yearly-sandbox/local-purchase-success.png（无密码）。

恢复证据：local-restore-success.png。没有再次购买或改账号。下一步需在独立本地账号路径检查无云端/在线航班权限，保留02云端账号用于08:53:56后的自然到期验收。

## 进程重新启动核验

08:17通过devicectl --terminate-existing重新启动同一App，不卸载、不清资料、不换账号。重新打开版本与购买并完成商品加载，本地版仍显示“已购买”且按钮禁用。这是进程重启后重新读取StoreKit权益证据，不等于卸载重装恢复。

静态调用链：AuthViewModel.canQueryFlights要求有效云端身份与授权；WishlistView列表及详情、NewTripFormModel和VariFlightSettingsView均引用该权限；VariFlightClient.lookupCandidates无令牌/空令牌在网络请求前拒绝。当前仍为02云端身份，未把静态核对冒充本地账号真机航班拦截验收。生产历史凭据仍未采集，firstPaidLocalBuild=nil保持不变。

## 买断与云端授权隔离只读核验

08:19 PST后限定02 owner逐产品查询：云端台账仅monthly/Sandbox 2笔、yearly/Sandbox 8笔，没有local或Production行。云端edition=cloud/max_devices=4/expires_at=2026-11-18 16:53:56 UTC，与买断前一致。证明此次买断未误延长云端期限或写入订阅台账；仍不能用此代替纯本地账号真机航班拦截或到期行为验收。无数据库修改。

## 模拟器输入阻碍排查

iPhone18Pro iOS27隔离模拟器中，密码显示按钮经AX点击可切换，账号分段控件点击未切换；单独重启App无效。随后仅shutdown/boot该模拟器（无erase、无卸载、无数据清理），重新启动App后同一控件点击成功，说明变为“本机资料只保存在此设备，不会自动上传”。不能据此前无响应断定LoginView业务逻辑存在Bug，未改登录源码。

本地模式打开注册页成功，显示本地称呼/邮箱/手机/密码及验证码控件；尚无本地已登录会话。密码创建需本人完成，用户暂离期间不自动设置新凭据、不混用审核账号，不把模式切换当作纯本地航班真机限制验收完成。

离线发布准备核对：TrvelMA.storekit的local.lifetime为NonConsumable/29.99，monthly为P1M/9.99，yearly为P1Y/99.99，与此前真机商品展示一致；商品资料JSON记录各六语言。此为本地配置与既有实测比对，不声称本轮已重新读取AppStoreConnect线上配置。

## 纯本地航班限制模拟器验收

用户完成空白本地账号注册登录。发现模拟器原装1.0旧App，因此未将旧版表现用于1.1判定。当前分支以xcodebuild Debug/iphonesimulator、指定iPhone18Pro设备、CODE_SIGNING_ALLOWED=NO构建，BUILD SUCCEEDED；构建目录/tmp/trvelma-local-acceptance-current，日志/tmp/trvelma-local-acceptance-current.log。simctl覆盖安装不卸载，原本地账号与空白资料保留，设置实际显示1.1(14)。该构建非Sandbox购买验收包，不用于真实交易。

实际模拟器观察：设置标识“我的账号、本地账号”；航班查询设置仅显示在线查询限云端及本地手动录入说明。新增行程航班区域可输入合成QA123，不显示在线查询按钮，显示本地手动说明。随后取消草稿返回首页行程0，没有保存订单。证据local-flight-restricted-simulator.png。

本次为当前1.1真实UI模拟器观察，不是纯代码推断，也不是物理设备验收；没有声称捕获网络请求为0。手动保存航班后详情读取、真机本地路径、卸载重装与生产老用户凭据仍待验收。无产品代码变更，未改任何云端账号或生产授权。

## 手填航班持久化与编辑模拟器验收

在用户创建的空白本地测试scope新增合成客户名QA、零金额行程，手填QA123并保存。当前本地行程由0变1，首页航班号QA123，刷新禁用；点击航班按钮实际提示“在线航班查询仅限云端版”。详情保留QA123，刷新禁用。编辑页保留原值且无在线查询按钮，改为QA124保存，详情读取QA124。随后terminate/launch同一App，首页仍1单且QA124、刷新禁用。没有点击完成、结算、发通知、导航或外部分享，没有云端业务记录修改。

本次合成资料保留供后续本地scope验收，未删除；创建时中文测试名称输入仅实际落为QA，按实际保存值记录，不用预期名称冒充已保存内容。该结果属于iPhone18Pro/iOS27模拟器1.1(14)，不是重装恢复、真机或生产老用户凭据验收。
