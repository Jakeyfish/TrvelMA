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
