# 1.1 商品审核资料准备

状态：本地草稿，未发送Apple，未提交商品审核。先完成[发布条件](billing-1.1-current-status.md)。

## 截图采集清单

每个商品使用实际App“版本与购买”页面，保留商品名称、StoreKit价格、周期和对应说明。使用专用合成资料，不出现客户联系方式、密码、Token或支付凭据。

| 商品 | 必须看清的内容 | 当前截图状态 |
| --- | --- | --- |
| 本地买断 | 买断名称、一次购买价格、不含云同步/在线航班查询、恢复购买入口 | 待采集 |
| 云端月付 | 月付名称、每月价格、自动续费、最多4台设备、管理订阅入口 | 待采集 |
| 云端年付 | 年付名称、每年价格、自动续费、最多4台设备、管理订阅入口 | 待采集 |

截图应使用对应审核构建。沙盒或本地StoreKit截图仅可作为内部布局检查证据，需标明环境；不得伪装生产交易已通过或已有成功扣款。真实沙盒验收后，再确认商品审核截图符合Apple当前页面要求并上传。

## 提审前的账号和构建核对

- 当前沙盒构建只允许开发测试账号；专用Apple审核账号不能按此配置购买。正式审核构建必须按最终方案开放审核可验证的入口，不能直接提交当前受限沙盒版本。
- 审核登录资料只在App Store Connect安全填写，不写入此文档；核对邮箱已验证、授权期覆盖审核、设备名额足够。
- 旧用户规则确定并实现前，本地收费门禁尚不完整，不提交本地买断审核。
- 1.1(14)目前仅本地构建。正式上传前重新确认构建号未占用、签名、商品关联、隐私/地区和商务状态。

## English review notes template

The following text is a template for the final review-enabled build. Do not submit it until the stated flows work in that build.

Yunsheng Trip Manager 1.1 adds optional purchases for local access and cloud subscriptions. Please use the dedicated credentials entered in App Review Information. The account contains synthetic demonstration records only.

Product IDs:
- com.yunshengtech.travelmanager.local.lifetime — non-consumable local access. It does not include cloud synchronization or online flight lookup. Restoring a purchase restores access, not business data stored on a device.
- com.yunshengtech.travelmanager.cloud.monthly — auto-renewable monthly cloud subscription, up to four registered devices.
- com.yunshengtech.travelmanager.cloud.yearly — auto-renewable annual cloud subscription, with the same service level as monthly.

Navigation: open the account menu and select Versions & Purchases. Prices and billing periods are shown using StoreKit product information. Restore Purchases, Manage Subscriptions, Privacy Policy and Apple's standard EULA are available on that screen.

Cloud transactions are verified by our server and bound to the signed-in account. Restoring a subscription on a different app account does not transfer ownership. Cancelling auto-renewal retains access through the paid period; expiration, refunds and revocations are processed from verified Apple transaction information.

The separate 14-day registration trial does not require a payment method and does not charge automatically. It is not an introductory App Store subscription offer.

Before using this template, replace or supplement it with the final approved existing-user migration behavior and the completed real Sandbox acceptance results. Do not claim those checks are complete while they remain pending.
