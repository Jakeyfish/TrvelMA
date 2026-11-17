# 1.1 iPad 恢复原沙盒购买复核

日期：2026-11-11（America/Los_Angeles），分支 codex/billing-1.1。

## 真机观察与只读查询

- iPad A16 已连接，已安装 1.1(14)。打开原“版本与购买”页面并点击恢复购买；Apple 沙盒密码由用户在设备验证，本轮没有新购。
- 密码弹窗关闭后购买页面保留；滚动底部，显示未找到可恢复购买，并带有“云端订阅恢复需完成账号和服务端验证配置”的旧提示。
- Supabase 对开发测试账号的只读查询：Sandbox 台账 12 条，当前有效交易 0 条，最新 expires_at 为 2026-11-05 17:41:17+00；group by environment 结果只有 Sandbox，无 Production 记录。
- 账号授权保持 cloud / active / expires_at=NULL / max_devices=4。该永久开发授权不能证明订阅到期降级正确，必须另用没有永久基线的专用测试账号验收。
- 本轮未修改数据库、授权或账号，没有把 12 条历史记录当成 12 次购买。无有效购买与空恢复结果一致，不等于本轮已完成服务端验签或退款通知闭环。

## 文案修复

- StorePurchaseManager.restore 仅在确有云端购买但缺账号或验证器配置时显示原配置提示；未发现有效购买则说明“未找到可恢复的有效购买。订阅可能已到期或退款。”。
- 不吞掉 AppStore.sync 或服务端验签错误，不更改任何权益或交易处理边界；新文案补齐六语言。
- 新增本地 StoreKit 空恢复回归，检查无新交易、不授予本地权益、不误报服务端缺配置。测试结果待追加。

实际执行：`verify-sync-regressions.py --storekit --destination 'platform=iOS Simulator,id=1D943880-76B5-422E-87E3-CEFF0F99A456'` 17 项、0 失败，TEST SUCCEEDED；`verify-localizations.py --shared-web` 六语言 298 键无错误，`git diff --check` 通过。该隔离回归不等于新代码真机恢复验收；新文案尚未安装。日志 `/tmp/trvelma-restore-message-tests.log`。

## 待配合事项

- 已询问是否另建订阅生命周期专用测试账号，现有业务/审核/永久开发账号保留。新增账号即使注册成功，也不能自动加入沙盒授权白名单，相关访问范围变更仍需准备后确认。
- App Store Connect 会话过期，重新登录页已显示并保留。登录恢复后核对 Apple 沙盒通知配置。
- iPad 当前安装包尚未包含本轮新文案与只读路由；不能把旧包界面观察当作新代码真机验证。正式收费保持关闭。

## 本轮随后更新 iPad

- 使用 Debug + STOREKIT_SANDBOX_ACCEPTANCE 构建最新 1.1(14)，签名验证通过后覆盖安装到 iPad A16，未卸载或清除资料。两台 iPhone 未安装沙盒版。
- `xcodebuild` 真机构建 BUILD SUCCEEDED；编译包六语言 298 键检查无错误。安装和启动命令均成功，真机首页显示原开发账号登录状态，0 条行程，与更新前一致。
- 新包进入“版本与购买”后正常载入本地/月付/年付商品。再次手动恢复时 Apple 要求密码验证，已请用户在设备操作；截至本条记录，新文案的真机完成结果尚未读取，不能记为已通过。
- 本轮只读门禁仍关闭，正常首页启动不代表该路由已做真机验收。尚未启用正式收费、改白名单或变更永久授权。
- 构建日志 `/tmp/trvelma-11-device-qa-build.log`，包 `/tmp/trvelma-11-device-qa/Build/Products/Debug-iphoneos/Wishlist.app`；证据目录 `deliverables/2026-11-11-billing-device-restore/`。

## 用户完成验证后的复核

- 用户在 iPad 新包再次完成 Apple 沙盒验证。实际滚动到弹窗底部，已显示“未找到可恢复的有效购买。订阅可能已到期或退款。”，旧的缺配置误导文案消失；新包该空恢复提示真机检查通过，没有发起新购买。
- 用户恢复 Apple 登录后，只读核对 App 信息：沙盒通知 URL 为项目的 `/functions/v1/storekit-notifications`，生产 URL 尚未设置。只确认配置，不代表收到真实 Apple 通知。
- 用户授权新增独立生命周期测试账号，并指定 ystechnology02@yahoo.com。注册表单已预填称呼和邮箱，等待本人设置密码及验证邮箱；尚未新增沙盒白名单或改变授权。
- 新账号的自动 14 天试用也会遮蔽订阅到期结果；后续需明确该账号的隔离测试基线，再准备定向配置、回退及授权确认。不能移除原开发账号永久授权来凑测试。Apple 沙盒原交易链绑定原业务账号，新业务测试账号还需独立的沙盒购买链，不能把旧链改绑。
