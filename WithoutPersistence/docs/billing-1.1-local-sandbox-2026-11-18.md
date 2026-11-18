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
