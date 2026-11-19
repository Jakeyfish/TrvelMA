# Release收费隔离检查（2026-11-18）

当前codex/billing-1.1，1.1(14)，无产品源码修改。

## 实际执行

1. 从StorePurchaseManager.swift提取原样BillingReleaseConfiguration，import Foundation/StoreKit，在临时Swift程序执行六项precondition：salesEnabled=false、plansVisible=false、sandboxAcceptanceBuild=false、sandboxOwnerIDs为空、localAccessEnforcementEnabled=false、firstPaidLocalBuild=nil。
2. swift /tmp/trvelma-release-gate-probe.swift：六项通过；swift -D STOREKIT_SANDBOX_ACCEPTANCE同文件：六项通过。第二种确认仅有沙盒标记而无DEBUG不会开放沙盒或生产购买。未把此探针当作完整App或真实StoreKit交易验收。
3. 当前源码xcodebuild Release/iphonesimulator指定iPhone18Pro、CODE_SIGNING_ALLOWED=NO，derivedDataPath=/tmp/trvelma-release-gate-acceptance，BUILD SUCCEEDED。日志/tmp/trvelma-release-gate-acceptance.log。此为未签名模拟器Release，不是分发归档、上传或提审。

构建存在既有弃用API警告（例如CLGeocoder/UIScreen.main）及无AppIntents依赖的元数据提示，未为无关警告进行架构重构。没有构建错误。

## 重装恢复边界

现有iPad已验证本地Sandbox买断、恢复与进程重启；其App仍保留02到期归档，不直接卸载。iPhone模拟器本地scope含一条合成QA/QA124行程，没有这笔真实AppleSandbox买断。不能通过卸载该模拟器就声称真实买断重装恢复通过；也不能把simctl覆盖安装（保留数据）当成卸载重装。

下一步真实买断重装需先保留本地资料与登录恢复能力，安排专用真机，明确重装只恢复权益、不会自动恢复本机业务资料。未删除账号、App或用户数据，未打开生产收费开关。
