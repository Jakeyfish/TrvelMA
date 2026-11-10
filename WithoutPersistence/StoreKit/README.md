# StoreKit 本地准备与验证

TrvelMA.storekit包含本地买断、同组月付/年付三个本地商品。它在App源码目录外，不随生产App打包，未改变用户的运行方案。

客户端基础已实现：StorePurchaseManager加载商品、处理购买状态、currentEntitlements、恢复及交易更新；PurchasePlansView为准备界面，未接正式导航。默认salesEnabled=false；云端验证闭包默认nil，没有可由用户设置打开生产销售的开关。

2026-11-02在独立StoreKitQA模拟器宿主通过5项Xcode本地交易测试：

1. 本地买断、恢复及退款后撤销。
2. 缺少服务端验证器时拒绝云端购买。
3. 客户端本地购买流程。
4. 待批准期间不发权益，批准后恢复。
5. 云端恢复检查账号与已验证交易ID，错误账号拒绝。

测试夹具每例resetToDefaultState，防止Ask to Buy状态跨例残留。Transaction.updates与显式恢复可能重复送达同一交易；断言交易身份和账号，不把回调必须只一次当作协议保证。未来服务端必须按transactionID幂等，不能重复发权益。

运行：`python3 WithoutPersistence/scripts/verify-sync-regressions.py --storekit`（仓库根目录，需模拟器及Xcode）。测试使用独立宿主及本地假交易，不改用户App内的真实购买。

尚未完成：App Store Connect正式商品与App Apple ID、真实Sandbox、服务器JWS验证/持久权益、服务器通知、真实退款续费宽限期/跨平台权益、正式销售入口及用户迁移授权门槛。通过上述本地测试不等于支付已经上线。正式销售保持关闭。
