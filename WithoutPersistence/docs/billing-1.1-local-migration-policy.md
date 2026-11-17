# 1.1 本地授权迁移决策

2026-11-10 用户确认：原1.0用户保留本地使用权限，仅新用户需购买。本文件记录已确认的产品规则与后续实现边界，不表示门禁已实现。

## 权限边界

- 老用户保留本地使用权限，不要求重新买断；不因此增加云端同步或在线航班查询权限。
- 新用户获得本地买断权益后可正常使用本地功能；云端权益仍按独立账号授权判断。
- 不删除已有资料，不改写现有云端授权，不将云端账号注册日期当成App首次获取日期。
- 正式收费开关继续关闭，完成迁移与购买验收后再按授权启用。

## 识别方案与待核实事项

优先使用StoreKit已验证的AppTransaction首次获取信息，避免仅靠可修改的UserDefaults标记或是否存在业务数据识别老用户。Apple提供originalAppVersion与originalPurchaseDate，用于判断最初获取版本/日期及业务模式迁移。重装场景也必须恢复识别，不能只检查本机升级残留。

接入前核实iOS返回的originalAppVersion与正式构建号的对应关系，以及1.0、1.0.1发布边界；不能未经核实直接按营销版本字符串比较，也不能仅根据当前1.1(14)测试构建号决定收费分界。正式收费若晚于1.1上线，分界须与实际开始收费版本/时点一致。

生产、TestFlight/Sandbox、本地StoreKit和开发签名分别处理；沙盒凭据不能作为生产老用户证明。无法获取或验证凭据时保留明确的待确认状态与重试入口，不直接认定为新用户并诱导重复付款。已验证权益的离线使用与缓存策略需要单独验证。

Web不具备本机Apple商店首次获取凭据，不能按Web首次登录日期推断iOS老用户；跨平台授权范围维持现状，不把iOS本地权益自动升级为Web/云端权益。

## 实现后的必要验收

1. 1.0/1.0.1用户升级及重装后保留本地权限，不重复购买。
2. 收费分界后的新用户、有效买断、退款撤销分别判断；老用户保留权益与购买权益分别存储和推导。
3. 凭据缺失、签名不通过、网络中断及重试不误判；切换Apple账户不沿用无归属的缓存。
4. 老用户本地权益不授予云端和在线航班查询；云端账号切换不破坏本地业务数据。
5. 新用户购买、恢复购买与只读/导出路径完成针对性回归；六语言提示一致。
6. 在真实商店/TestFlight可支持的边界内验证；隔离夹具不能代替生产历史凭据验收。

## 官方参考

- https://developer.apple.com/documentation/storekit/apptransaction
- https://developer.apple.com/documentation/storekit/apptransaction/originalappversion
- https://developer.apple.com/documentation/storekit/apptransaction/originalpurchasedate
- https://developer.apple.com/documentation/storekit/supporting-business-model-changes-by-using-the-app-transaction

## 2026-11-11 实现进度（未启用正式门禁）

- 已核对 Apple 文档：iOS originalAppVersion 对应 CFBundleVersion，沙盒固定 1.0；originalPurchaseDate 在重装后不变，沙盒固定为 2013-08-01。不能使用这些沙盒固定值判断正式老用户。
- 新增 LegacyLocalAccessPolicy：严格数字构建号比较，已验证生产证据且 bundle 匹配才可能判断 legacy；未知凭据、测试环境、错误应用、无效构建、分界未配置分别返回明确状态。
- 新增 LegacyLocalAccessReader：只转换 .verified AppTransaction，失败与未验签独立处理。不持久化 JWS、凭据或无归属的老用户标记，不显式调用 AppTransaction.refresh()。
- StorePurchaseManager 的 load/restore 已接入读取并在重查前清除旧判断。分界一旦配置，凭据不明或符合老用户保留条件时不能发起本地买断；有效买断仍禁止重复购买。
- firstPaidLocalBuild 保持 nil；当前正常 Release 收费入口仍关闭，现有本地业务使用行为不改变。此基础接入不等于“本地收费门禁已完成”，也不授予云端/航班查询权限。
- 纯判断模块有 36 项合成证据检查。重现命令：python3 scripts/verify-legacy-local-access.py。具体构建与 StoreKit 结果见本轮验收记录。
- 仍待：确认实际开始收费的构建分界、正式历史凭据核验、升级/重装及 Apple 账号切换、门禁/只读导出 UI 与六语言、签名凭据离线使用策略。本轮不把未归属缓存作为授权证据。

## 本地使用权限状态补充（2026-11-11）

- 新增纯策略 `workspaceAccess`：关闭门禁时维持当前行为；开启后仅正式生产买断或已验证老用户可编辑；确认分界后新用户进入需购买只读状态，其余证据不明进入需验证只读状态。两种只读状态均不允许编辑，未知证据不显示购买诱导。
- `StorePurchaseManager.hasProductionLocalPurchase` 仅接受已验证、有效、未撤销、未升级的 production 本地商品。它与供沙盒验收的 `hasLocalPurchase` 分开，Xcode/Sandbox 恢复不能授予生产本地使用权。聚合采用“任意有效权益即有效”，避免后续无效记录覆盖有效权益。
- `localWorkspaceAccess` 暴露统一策略结果，但尚未用于 RootView 路由；`localAccessEnforcementEnabled=false`。该状态准备不等于界面写入门禁完成。
- 下一步在本地数据归属准备成功后接独立只读/导出路由，不挂载正常编辑页面；异步结果必须绑定当前账号并丢弃过期请求。前台重新核验不得因临时加载销毁草稿或购买弹窗。导出仅包含当前本地 scope 的业务记录与允许的资料，不能包含登录密码、Token 或其他账号记录。
- 无新 UI 文案，无 Web 权限变化，无数据库迁移。实际新增界面时补六语言；Web 继续使用原云端授权。

## 后续路由实现

上述“尚未接入 RootView”描述为本阶段初始状态。随后已接入 LocalAccountWorkspace 和按账号隔离的 LocalAccountArchive；门禁仍关闭，未作真机验收。新增文案已补六语言。当前状态及验证限制见 [本地只读导出记录](billing-1.1-local-archive-2026-11-11.md)。
