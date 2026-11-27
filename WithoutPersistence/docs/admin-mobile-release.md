# 云盛应用管理 iOS

- 独立项目 `AdminMobile.xcodeproj`，Bundle ID `com.yunshengtech.appmanagement`，iPhone / iPad，版本 1.0 (1)。
- 复用现有管理后台的 Auth 和 RPC。登录后先完成 TOTP，再读取应用权限。管理员在现有 Web 后台完成初始 TOTP 配置。密码、验证码和 Auth 会话只在内存中。
- 写操作复用服务端近期 MFA、应用权限、预期版本、幂等请求号和审计。设备释放不强制退出 Auth 会话。
- 发布使用独立 App Store Connect 记录，TestFlight 仅限内部测试。指定现有管理员在测试设备验收。写入验收仅使用获授权的测试账号和设备。

## 本地验收

```sh
swiftc AdminMobile/AdminAPI.swift admin/tests/native/AdminAPICheck.swift -o /tmp/yunsheng-admin-api-check
/tmp/yunsheng-admin-api-check
xcodebuild -project AdminMobile.xcodeproj -scheme AdminMobile -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

模拟接口测试覆盖密码登录至 TOTP、AAL1 拒绝、已验证会话的查询、授权校验及近期 MFA 拦截。真实管理员登录和后台写入需要另行在测试设备验证。
