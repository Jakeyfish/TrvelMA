# Billing 1.1 Sandbox release gate

Current status: [1.1 release status](billing-1.1-current-status.md). The items below are release requirements, not a list of completed tests. Production remains disabled until all gates pass. Preserve the published 1.0 and submitted 1.0.1(13).

- Apple agreement active (bank available and tax in use are already verified).
- Three product IDs match StoreProductCatalog; monthly/yearly same service level.
- Local lifetime excludes online flight lookup and cloud sync.
- Subscription single-seat App Store only; family sharing off.
- Availability must match approved App storefronts; no annual installment contract option.
- All six app languages have accurate product metadata; prices loaded from StoreKit.
- Sandbox backend only allowlists dedicated QA owners; Production transactions rejected there.
- Purchase: authenticated appAccountToken owner matches verified Apple JWS.
- Restore after reinstall; account switching never grants another owner.
- Pending, cancellation, duplicate, expiry, grace, refund, revocation, delayed notifications verified.
- Notifications after account deletion must not recreate or grant deleted account.
- Paid subscription on one device updates entitlement on another without duplicate charge.
- Existing-user local migration policy resolved before opening paywall.
- Real Sandbox evidence required; local StoreKit and SQL tests alone do not satisfy release gate.
- Upload new 1.1 build, attach first IAP and subscriptions for review only after readiness.

## 2026-11-10: Hotfix 1.0.1 merged into 1.1

The formally submitted 1.0.1(13) fixes are now ported: customer editor sheet, detailed notification migration, net-income snapshots, telephone/SMS actions, and matching Web changes. Billing changes were preserved. The test-file end differed between branches; existing reminder test updates and new telephone tests were applied separately without overwriting billing tests.

After merge: App376, Web175, backend76, local StoreKit13 tests passed; six-language audit290 keys passed. Production billing and ordinary paywall remain disabled. No production database mutation or new purchase.

Physical devices are unavailable; user will connect iPad later. Retry the original unfinished transaction on the development account, then verify Apple signature/OCSP, ledger, entitlement and real notifications. Local StoreKit/isolated PKI results are not real Sandbox evidence. Release1.1(14) simulator build passed; compiled six-language resources also passed (290 keys).
