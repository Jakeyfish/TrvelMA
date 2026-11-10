# Billing 1.1 Apple 操作历史

当前状态以 [1.1发布状态](billing-1.1-current-status.md) 为准。以下保留按时间累积的历史记录；旧段落的待办、测试数量和部署状态不是当前结论。

## 早期商品准备记录

Production billing remains disabled. No backend deployment. Stable 1.0(11) review unchanged.

Business: owner submitted bank and tax. UI: bank available, W-9 in use, Paid Apps Agreement processing.

Local lifetime: 6830699358, com.yunshengtech.travelmanager.local.lifetime. USD29.99 saved. Simplified Chinese description saved; excludes cloud sync and online flight lookup.

Subscription group: 22545785, TrvelMA Cloud.
Monthly: 6830703150, com.yunshengtech.travelmanager.cloud.monthly, 1 month.
Yearly: 6830703130, com.yunshengtech.travelmanager.cloud.yearly, 1 year.
Both service level 1 saved and verified. Simplified Chinese names/descriptions saved and verified: auto renewal, sync, online flight lookup, up to 4 devices.

Monthly USD9.99 and yearly USD99.99 prices now saved and verified in Apple current subscriber pricing, filtered to United States and Canada. Previous monthly spinner was delayed Apple processing. No repeat monthly price schedule was created.

Remaining: additional localizations, availability, review screenshots/notes, real Sandbox lifecycle tests. No products submitted for review.

Existing isolated verification: 361 regression tests, 5 local StoreKit tests, 32 server tests. These do not validate real Apple payment processing.

Purchase options audit: monthly and yearly changed from default multi-seat/business/school channels to single-seat App Store only; verified UI saved. This does not change four-device account allowance. Family sharing remains off. Annual installment commitment option not enabled.

Monthly product metadata: added en-US, zh-Hant, ja, ko, es-ES alongside existing zh-Hans. Verified each save via returned UI. Yearly and local lifetime additional locales still pending.
Sandbox release gates recorded in billing-1.1-sandbox-checklist.md.

## Server hardening follow-up
- Deleted owners: signed delayed events return recorded=false / ACCOUNT_DELETED without rebuilding accounts or grants. Apple notification handler can acknowledge; purchase client rejects recorded=false and must not report successful delivery.
- Auth user row is locked for key share during ledger writes to serialize against account deletion.
- Refund fallback restores original local device allowance; later manual permanent grants remain preserved.
- Missing environments and future revocation dates rejected.
- Apple library pinned 3.1.0, Supabase library pinned 2.118.0; Deno dependency lock stored in supabase/billing-tests/deno.lock.
- Purchase privacy link now points to privacy.html.
- Final verification: server isolated suite 41/41 passing; Swift regression 362/362 passing; Release simulator build 1.1(12) succeeded; Deno type check passed.
- Backend remains undeployed; production billing flags remain false.

Manual-grant race fixed: preserve and compare the last written entitlement snapshot in addition to timestamps. An explicit same-timestamp test verifies manual permanent grants survive later subscription refunds. Additional cases cover upgraded periods and newer verified refund reversals.
Diff whitespace check reports an existing trailing blank line in WishlistView.swift, outside this follow-up edit. No unrelated cleanup performed.

## Client recovery follow-up
- Cloud payment requires an injected preflight before opening StoreKit purchase. Production preflight revalidates authenticated owner and server grant, rejects revoked/missing grants, permits expired grants to renew, and fails closed on lookup errors.
- Rechecks account binding after asynchronous preflight and server delivery.
- Loading the purchase manager retries matching unfinished transactions; verification failure leaves the transaction unfinished. Foreign-account transactions are never delivered or finished by this recovery path.
- Restore skips foreign cloud subscriptions so they cannot block local lifetime restoration.
- Final client recovery verification: 12/12 local StoreKit integration cases passed, 362/362 general regressions passed, Release simulator 1.1(12) build succeeded. These use Xcode StoreKit testing, not real Apple Sandbox payments.

## Purchase screen state follow-up
- Account/product preparation disables purchase and restore until ready.
- Authentication preparation failure or empty product list provides a retry action.
- Preparation follows account scope; request IDs and cancellation checks prevent stale account loads overwriting current UI state.
- Busy duplicate purchase calls no longer replace the in-progress status with an unavailable message.
- Reload resets stale delivery errors; recovery failure sets a fresh error instead.
- Transaction updates for other cloud accounts are ignored, not finished.
- Purchase loading text added in all six application languages. Catalog check against stable snapshot found no changes to pre-existing translation entries.
- Local StoreKit suite 13/13 passed (including repeated-click and stale-error recovery assertions); no real charges or production changes. Release simulator 1.1(12) build passed. Apple business session was expired on read-only follow-up, so agreement activation has not been reverified in this batch.

## HTTP boundary follow-up
- Extracted shared HTTP handlers used by the deployed-entrypoint source and isolated Request/Response tests; runtime still supplies official Apple verifier and authenticated Supabase clients.
- Streamed byte limits stop body consumption before allocating the entire request; UTF-8 bytes counted, not string characters. Declared oversized bodies rejected too.
- Purchase endpoint rejects missing/malformed Bearer headers before processing; authenticated owner takes precedence over caller-supplied fields.
- Malformed/non-object JSON, failed nested signatures and persistence failures cannot return successful delivery. Persistence failure remains HTTP503; invalid requests return 400/401/413 as appropriate.
- Deleted-owner notification acknowledgements do not imply paid purchase delivery. Errors do not echo raw tokens or transactions; responses retain no-store.
- Final isolated backend suite: 68/68 passing (27 HTTP cases plus 41 core/ledger cases). Node Request/Response and mocked verifier fixtures do not substitute for real Apple Sandbox validation.
- iOS code unchanged in this batch. Production billing remains disabled and backend remains undeployed.

## Expired renewal entry and metadata preparation
- Read-only expired-account screen and blocked entitlement route now include the purchase sheet behind plansVisible. No normal write/sync view is mounted merely to show renewal.
- Shared access predicate requires completed successful authorization lookup and usable cloud session, rejects revoked/unknown grants, legacy fallback, reauthentication and device-limit errors.
- Seven account/authorization fixtures passed: expired, revoked, unknown, unavailable, legacy, full-device and active states. Complete Swift regression suite 369/369 passed.
- Prepared billing-1.1-product-localizations.json: 18 product name/description pairs and six subscription group names. All Apple 35-character name / 55-character description limits checked. Remaining Apple entries have NOT been saved yet.
- App Store Connect session expired; owner asked to sign in while local work continues.
- Supabase authorization reference checked: https://supabase.com/docs/guides/functions/auth-headers and https://supabase.com/docs/guides/functions/auth-legacy-jwt . Existing gateway settings retained; purchase handler independently authenticates through getUser, Apple webhook independently verifies signed outer/nested payloads. No production security setting changed.

Prepared metadata product IDs were checked against both the Swift StoreProductCatalog and local StoreKit configuration; all three match. Sales and plans visibility flags confirmed false.

Expired renewal entry batch: Release simulator 1.1(12) build succeeded. Formal 1.0(11) archive/review unchanged; no deployment performed.

## Apple configuration completed after renewed sign-in
- Paid Apps Agreement now verified ACTIVE (previous processing state superseded).
- All three products now have all six saved localizations (18 total); subscription group has six saved names. Monthly English/Spanish descriptions updated to explicitly indicate renewal period.
- Exact names/descriptions read back against billing-1.1-product-localizations.json: all 18 match.
- Read existing App availability: 148 offered-at-release, 27 not offered. Product availability saved to same 148 storefronts for local lifetime, monthly and annual prepaid. No App availability changed.
- Annual 12-month installment option remains unconfigured. Local automatic future-territory availability unchecked.
- Save controls read back disabled; yearly/monthly show148; local radio confirms148/175.
- No product review submission, production billing enablement or backend deployment. Remaining: review screenshots/notes and real Sandbox end-to-end verification; local-user migration gate still requires final design before production sales.

## Sandbox acceptance preparation
- Dedicated DEBUG + STOREKIT_SANDBOX_ACCEPTANCE build enables test navigation, ordinary configurations remain disabled. Compile-mode probes verify both requirements.
- Test purchase manager requires verified AppTransaction Sandbox environment before purchase/restore, and rejects non-Sandbox transaction delivery. Local Xcode fixtures are not accepted as real Sandbox transactions.
- Auth preparation limits this build to verified development owner71b164e4-7dbf-4433-8503-84ed156171de; owner and review accounts cannot initialize the purchase manager there.
- Sandbox notices localized in six languages.
- 373/373 general regressions and13/13 ordinary local StoreKit tests passed; specialized Debug simulator build passed.
- Backend prep package includes migration, both edge functions/imports, dependency lock, safe disabled .env example, rollback and read-only preflight. No secrets included.
- Production readonly preflight verified original grant function exists, developer email/UUID match, no same-name billing tables. No mutation executed. Deployment approval still pending.
- Official Apple environment references: https://developer.apple.com/documentation/storekit/apptransaction/environment and https://developer.apple.com/documentation/storekit/apptransaction/shared .

Normal Release simulator build passed after sandbox-gate changes. Final sandbox deployment confirmation requested; no backend changes executed.

## Sandbox deployment 2026-11-05
User approved Sandbox-only deployment. Applied ledger migration in transaction and verified success. Deployed both Edge Functions from Deno-generated single-file bundles with official pinned npm imports externalized; original local modules remain the maintained source. JWT gateway retained for purchase verification, disabled for Apple notification endpoint as approved; signed outer/nested verification remains mandatory.
Saved and digest-verified enabled=true, environment=Sandbox, production_enabled=false, sole allowed owner=development account. Disabled notification probe503, enabled forged notification400, unauthenticated purchase401, anonymous table and grant RPC401. SQL audit: all three tables RLS enabled; anon/authenticated permissions denied; service-only RPC; ledger empty after invalid probes.
Apple session expired again; user asked to log in for Sandbox URL configuration. Callback URL NOT yet saved. Real Sandbox transactions and notification delivery NOT yet verified. Production billing remains closed. Full status and generated bundle hashes archived in sandbox preparation deliverable.

Live deployment follow-up: oversized notification initially timed out. Replaced awaiting request-stream cancellation with starting cancellation without blocking error response. Added two never-settling-cancellation tests. Backend suite70/70 passed, both functions rebuilt/redeployed with compared source. Live notification now returns413 in~0.71sec; forged signature400; unsupported method405. Production remains disabled; Apple Sandbox notification URL still pending sign-in.


## 2026-11-05 Apple 沙盒通知地址已保存

用户恢复 Apple 登录后，已在 App 信息保存 Sandbox Server Notifications URL：
`https://lbdfqzeiweqbsklklcqr.supabase.co/functions/v1/storekit-notifications`。
页面读回地址一致，生产环境仍显示“设置 URL”（未设置）。此页面无发送测试通知或版本选择控件；尚无 Apple 签名的真实通知或购买成功证据。
证据：`/tmp/trvelma-apple-sandbox-url-saved.png`。正式收费和现有 1.0(11) 审核保持原状。


## 2026-11-05 真机恢复弹窗生命周期修复

Apple 身份验证返回前台时，在线版权限复核暂时卸载 ContentView，原本挂在 WishlistView / ExpiredAccountArchiveView 的购买 sheet 被一起销毁。购买请求现统一交 RootView 持有 sheet，入口仍按版本及账号权限检查，前台权限复核仍 fail closed。iPad 已安装修复后的 Debug 1.1(12)，主屏→应用切换后 sheet 保留，373 项隔离回归通过。Apple 再次要求沙盒密码验证，等待本人输入；尚无恢复完成或真实交易通过结论。
另修复 requestPasswordRecovery 丢弃 HTTP 响应体的问题，限流响应现能显示既有六语“操作过于频繁”提示。


## 2026-11-05 Apple Sandbox 月付成功、服务端验签阻塞

iPad Apple 显示操作完成，明确 Environment: Sandbox。App 显示云端账号操作失败。storekit-verify 400，加入仅含错误枚举/状态码/缺失 API 名称的诊断（不记录 token/JWS/账号），确认官方 Node 库在 Edge runtime 的 X509Certificate.toString 不支持；临时 PEM fallback 随后遇到 raw 不支持，已撤回，保留官方验签及全部安全检查。测试账号的原交易保持 unfinished 等待重试，不应重新购买。

70 项后端隔离测试此前通过但不能覆盖 Edge X509 兼容问题，真实端到端未通过。后续需验证完整受支持的 X509 验证运行环境或严格等价适配（包括链签名、Apple OID、日期、OCSP），不能关闭在线撤销检查或跳过签名。通知函数同依赖该运行环境，亦需一起修复及真实通知验证。


## 2026-11-05 Edge X509 compatibility deployed; device retry pending

The adapter supplies raw/toString/verify/infoAccess only when native methods explicitly throw ERR_NOT_IMPLEMENTED. Certificate signatures use pinned jsrsasign 11.1.5 (already used by Apple). The official Apple verifier, online OCSP, trust anchors, Apple OIDs, validity checks, owner allowlist and Production-off gate remain active. Both function bundles were pasted, copied back and compared before deployment.

74 isolated backend tests passed, including Apple MIT test certificates, chain signatures, wrong issuer, tampering, missing Apple OIDs, expiry and error propagation. A forced-old-Edge probe verified real Apple intermediate OCSP successfully; reproduce using supabase/billing-tests/verify-edge-ocsp.ts.

Live negative probes: invalid notification 400; unauthenticated purchase 401. iPad disconnected before original unfinished transaction could be retried; user reconnection requested. No end-to-end success claim. Do not repurchase. Rollback: disable STOREKIT_ENABLED, then restore a complete previous bundle; never skip verification.


2026-11-05 additional acceptance: 76 backend tests passed. A fresh isolated PKI with Apple marker OIDs signs a complete ES256 JWS; the official verifier runs with forced Edge API fallbacks and only the valid matching transaction reaches persistence. Tampering, wrong bundle/environment and missing OCSP information are rejected. Test-only certificates are never added to production trust anchors; temporary signing keys are generated and removed within the test. Real Sandbox transaction retry is still pending physical iPad reconnection.


## 2026-11-10 TestFlight beta 1.0(11) approved

After user restored Apple sign-in, the external group build table visibly shows 1.0(11) Testing, 84 days remaining, 1 external tester, 85 sessions. Build 1.0(9) remains Rejected. No resubmission or duplicate reviewer message needed. This confirms Beta availability only, not App Store public release or 1.1 billing readiness. Evidence: /tmp/trvelma-beta-approved-20261110.png.
