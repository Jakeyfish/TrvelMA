# 1.1 老用户本地权限基础接入验收

分支 codex/billing-1.1，版本仍为 1.1(14)，未提交/部署本轮实现。保留原有未提交购买预览与回归脚本修改。

## 实现及边界

LegacyLocalAccessPolicy 处理数字构建号和明确的证据状态；LegacyLocalAccessReader 仅转换已验证 AppTransaction。load/restore 接入读取，重查前清除旧判断；配置分界后，未知证据及符合保留条件的老用户不允许发起本地买断，已买断者也不重复购买。

firstPaidLocalBuild=nil，Release 正式收费入口继续关闭。实际本地业务使用门禁/只读导出提示尚未接入；当前用户使用行为不改变。新文件不持久化 JWS、用户标记或跨账号缓存，不授予云端/Web/航班查询权限。无新增 UI 文案，无需新增六语言键。

## 实际执行

1. swiftc 编译生产 LegacyLocalAccessPolicy.swift 与专用 fixture executable：36项检查通过。涵盖数字比较、构建分界等值、溢出/非法构建、错误bundle、Sandbox/Xcode/未知环境、缺证据、未知及老用户禁止发起买断。该合成测试不验证 Apple 签名本身。
2. xcodebuild -project WithoutPersistence/Wishlist.xcodeproj -scheme Wishlist -configuration Release -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/trvelma-legacy-policy-build CODE_SIGNING_ALLOWED=NO build：BUILD SUCCEEDED。是无签名模拟器 Release 编译，不是归档、上传或真机验收。
3. python3 WithoutPersistence/scripts/verify-sync-regressions.py --storekit --destination 'platform=iOS Simulator,id=1D943880-76B5-422E-87E3-CEFF0F99A456'：16项通过，TEST SUCCEEDED。使用隔离临时工程与本地 StoreKit session，不购买真实商品。回归脚本原有未提交修改未覆盖或纳入本轮实现。
4. git diff --check 通过。纯策略后续入口 scripts/verify-legacy-local-access.py；本轮上述实际命令为等价直接 swiftc/executable，没有另跑重复测试。

编译存在 AppLocalization/主线程隔离等现有并发与系统 API 弃用警告，本轮无新模型编译错误；未处理无关模块。

## 未完成

- 不能用 1.1(14) 自动决定开始收费分界，须对应实际收费版本并确认。
- 生产历史 AppTransaction、1.0/1.0.1升级/重装及 Apple账号切换未验收。
- 未实现签名归属的离线缓存策略；当前无自行持久化的老用户凭据。
- 实际使用门禁及只读/导出和六语言状态提示待接入。
- Apple真实通知、退款/到期及跨设备授权仍未完成，不能据此启用生产收费或提审1.1。

证据目录：协作工作区 deliverables/2026-11-11-billing-1.1-legacy/，包含实际源码哈希、构建和16项测试日志。

参考：[originalAppVersion](https://developer.apple.com/documentation/storekit/apptransaction/originalappversion)、[商业模式迁移](https://developer.apple.com/documentation/storekit/supporting-business-model-changes-by-using-the-app-transaction)、[originalPurchaseDate](https://developer.apple.com/documentation/storekit/apptransaction/originalpurchasedate)。iOS按构建号比较，沙盒固定版本/日期不能作为正式旧用户证据。

## 后续权限状态回归（2026-11-11）

- 新增 workspaceAccess 状态矩阵；hasProductionLocalPurchase 仅统计有效 production 本地交易。测试权益与正式使用权分开；聚合保留任意有效交易。localAccessEnforcementEnabled=false，RootView 尚未使用该状态，不能称实际只读门禁已完成。
- `python3 WithoutPersistence/scripts/verify-legacy-local-access.py`：90 项通过，合成凭据。新增覆盖所有证据状态、有无正式买断、开关开启/关闭。
- `python3 WithoutPersistence/scripts/verify-sync-regressions.py --storekit --destination 'platform=iOS Simulator,id=1D943880-76B5-422E-87E3-CEFF0F99A456'`：16 项、0 失败，TEST SUCCEEDED。购买/恢复测试新增断言：Xcode 交易不形成 production 权益，关闭的门禁维持原使用行为。
- 本轮未修改 UI/六语言、云端权限、Web 或生产数据库；不执行真实购买，也不把本地 StoreKit 回归当 Apple Sandbox 验收。
- 本轮日志留存到协作工作区 deliverables/2026-11-11-billing-1.1-local-access-state/。
- 新增权限状态后再次执行上述 Release 模拟器构建命令：BUILD SUCCEEDED；`git diff --check` 通过。未执行真机、生产历史凭据或完整 App 回归，界面路由接入后仍需扩大验证范围。
