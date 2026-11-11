# Admin backoffice requirement

Status: recorded, not implemented.
Confirmed by owner: 2026-11-04, America/Los_Angeles.

## Purpose and delivery
Provide a separate browser-based administrator backoffice for user and entitlement management, replacing routine direct database operations. Schedule after current App Store release and billing verification; recording this request does not authorize immediate production access changes.

## First release scope
- Account list: email, registration date, account role (business / Apple review / development testing).
- Entitlement: edition, trial days remaining, expiry, active/expired/revoked state, device allowance. Derive validity from expiry as well as stored status.
- Devices: registered device list, last activity, release registration and sign out sessions. Distinguish last activity from live online status.
- Authorization actions: grant, extend, suspend; explicit scope and confirmation for consequential changes; record operator, target, time and before/after values.
- Apple subscriptions: verified subscription validity, expiry, refund/revocation state. Keep manual grants distinct from verified purchases.

## Access and data boundaries
- Administrator-only access, enforced server-side; never rely on hidden navigation alone.
- Ordinary users cannot access administrative APIs or other accounts.
- Never display passwords or ship service-role credentials to the browser.
- Do not display customer records or trip content by default.
- Log administrative actions without credentials or raw authentication tokens.

## Acceptance criteria
- Three designated accounts and roles match account-roles.md.
- Effective entitlement accurately reflects expiration and suspension.
- Device release affects only the selected account/device; business account unaffected by QA actions.
- Non-admin requests fail server-side, including direct API calls.
- Grant/extension/suspension can be traced to an administrator and before/after values.
- Subscription status comes from verified server records, not client claims.

## Open implementation decisions
Administrator identity/bootstrap, admin authentication controls, search/filter/pagination, audit retention, session revocation semantics and subscription webhook integration. Resolve before implementation; do not invent live online presence from historical timestamps.

## Multi-application expansion (owner confirmed 2026-11-04)
The backoffice is a shared application management platform, not a TrvelMA-only console. The initial managed application is the current trip management product (store name: cloud trip manager; bundle com.yunshengtech.travelmanager). Future independent applications must be addable without rebuilding a separate console for each one.

- Application registry: stable application ID, display name, bundle/package identifiers, platforms, environment and enabled/disabled state. Add future applications through controlled configuration.
- Application selector and overview: navigate to a selected application before managing its users, grants, devices or subscriptions. Show the application context clearly on action confirmations.
- Distinguish platform identity from application membership. A person may use multiple applications, but access, edition, trial, device allowance and subscription belong to a specific application and are not shared automatically.
- Scope all business management records and actions by application ID plus owner/account identity. Identical emails across separate authentication projects must not be assumed to be the same account.
- Map Apple product IDs and verified transaction bundle IDs to the correct application; do not apply one application's purchase to another.
- Support global administrators and application-scoped administrators with server-side authorization. A global overview must not grant cross-application write access implicitly.
- Each application can use different edition names, subscription products, device rules and backend integrations; do not hardcode current trip-management rules into the platform.
- Separate development/test/production environments and credentials; server-side connectors only. Secrets must not appear in browser configuration or audit logs.
- Audit records include application ID, environment, operator, target, action and before/after values.

Additional acceptance: register a second synthetic application; verify account lists, permissions, device actions and purchase mappings remain isolated, and an application-scoped administrator cannot access or change the other application through UI or direct API requests.

## Customer-specific authorization (owner confirmed 2026-11-04)
Support Application -> Customer organization -> Authorization plan, in addition to individual accounts. A customer organization is a purchasing/business tenant, not a traveler/contact in trip records.

### Scope
- Feature permissions per application and customer: enable selected modules such as online flight lookup, finance and export.
- Quotas: registered devices, employee accounts and query/API usage.
- Validity: trial, fixed-term and perpetual grants. A perpetual feature grant must not accidentally imply unlimited metered service usage.
- Customer-specific development: identify and enable exclusive features for selected customers only. Share the main codebase where practical instead of maintaining an independent application fork for every customer.
- Standard package plus explicit customer overrides: derive effective permissions from the package and scoped overrides, with a documented conflict/precedence rule and visible effective result.
- Enterprise/customer organization and member employee accounts are separate entities. Define organization membership, employee roles and individual vs organization quota consumption.
- All custom grants are application-scoped and customer-scoped. Matching email addresses or organization names do not grant access to another application's data or features.

### Management and enforcement
- Display the selected application, customer, base package, custom permissions, remaining quotas and expiry before changing authorization.
- Manage grants, extensions, suspension and exclusive-feature enablement through authorized administrators, with scoped confirmation and audit records.
- Enforce permissions, membership, quotas and expiry server-side. Hiding a client button is not sufficient authorization.
- Keep manually negotiated customer grants distinct from Apple-verified purchase entitlements; define precedence and payment-channel compliance before commercial rollout.
- Do not introduce charging, unlimited usage, cross-application grants or new public administrative endpoints merely by recording this requirement.

### Acceptance criteria
- Two customers in the same application can receive different module permissions, device limits, employee allowances, query quotas and expiry.
- One customer can use multiple applications, with independent authorization in each.
- Exclusive features are inaccessible to other customers through both UI and direct API requests.
- Expiry/suspension and member removal take effect server-side without affecting another customer's authorization.
- Quota consumption and membership cannot be manipulated by client-supplied owner/customer/application IDs.
- Administrators can see the effective grant and trace every customization to its operator and before/after values.

### Decisions to resolve before implementation
Package/override conflict rules; employee roles; organization vs individual quotas; membership revocation and session behavior; customer-specific feature lifecycle; handling existing individual accounts; purchase/manual-grant precedence and applicable distribution/payment requirements.
