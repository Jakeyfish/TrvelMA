# 后台 0.1 交付状态（2026-11-11）

## 已提交方案、已部署静态前端

- 方案提交：9fc5010，codex/billing-1.1。
- 独立 Cloudflare 项目：yunsheng-admin，网址 https://yunsheng-admin.pages.dev/。
- 部署：a6006810-27d6-4a78-ac96-0eb33d19b1f6；固定地址 https://a6006810.yunsheng-admin.pages.dev/。
- 5 个文件上传成功，线上登录页加载、控制台无错误。发布包 SHA 校验和主要资源源码一致性检查通过。
- 管理数据库迁移已按用户本次最终确认执行成功；5 张表启用 RLS、6 个接口存在，未创建管理员、未授予任何账号后台权限。后台完整管理功能仍待账号设置与集成验收。

## 本地实现与验证

- 用户分页/搜索、用途标签、有效状态与到期提示、设备/已验签交易、设备释放、授权调整、成功变更审计、管理员 MFA 与范围校验。
- 数据库 PGlite 测试 16/16（含父测试）：执行现有授权/设备/Apple 台账真实迁移和新增管理迁移，覆盖无认证/普通账号/旧 MFA/撤销管理员、应用范围/空应用/别名拒绝、版本冲突、重复请求、审计失败原子回滚、延迟购买保留手工授权、紧急禁用不丢审计。
- 前端核心测试 5/5，JS 语法检查通过。
- 隔离浏览器使用实际渲染器完成用户详情、页面内确认、设备释放、审计显示和授权额度 4→5 流程；只改内存合成资料。
- 线上数据库只读前置核验：auth.sessions 必需字段齐全、授权函数/设备/交易台账存在、admin_private 尚不存在。
- 没有把 PGlite、合成界面测试当作生产 PostgREST/MFA/管理写入集成验收。
- Web 业务界面与 iOS 代码未修改，未重复执行无变化的 177 项业务 Web 测试或 iOS 构建。

## 待完成与边界

1. 用户指定独立管理员邮箱；本人注册/验证与设置 TOTP。不可使用审核/业务账号进行开发管理测试。
2. 按当次确认部署管理迁移；核验新增对象权限和未登录/普通账号拒绝。仅在独立确认后为指定 UUID 建立应用范围管理绑定并记 bootstrap 审计。
3. 真实 MFA、受控只读与合成目标写入测试完成后，才能宣布后台可用。
4. 二期：新增应用连接器、企业组织与员工、定制功能权限和额度。当前不支持任意新增应用后自动访问其后端。
5. 统一失败审计、全部读取访问审计尚未实现；失败走数据库/接口诊断，当前后台审计只覆盖详情读取和成功变更。
6. Auth 强制退出、账号删除、密码重置、生产收费与退款不在 0.1 内。设备释放不等于强制登出。

## 迁移与禁用

迁移 202611110001_admin_backoffice.sql 新增 5 张私有表、1 个私有鉴权函数、6 个管理 RPC；仅初始化展示标签，不调整业务授权、设备或交易。

verification/20261111_admin_disable.sql 禁用全部管理员及管理 RPC 执行权限，保留审计与变更历史。已发生授权变更需要按审计和预期版本有条件补偿，不以删除管理表回滚业务数据。

证据目录：协作工作区 deliverables/2026-11-11-admin/。前端 ZIP 与迁移 SQL 分开；数据库脚本不进入静态包。

## 正式迁移启用核验

- 用户已指定独立管理员邮箱 18857179866@139.com，并明确确认启用后台迁移。
- SQL Editor 执行完整迁移，返回 Success. No rows returned；核验 private_tables=5、tables_with_rls=5、management_functions=6、administrators=0。
- anon 对 admin_context 的执行权限为 false；authenticated 对 admin_private 的 USAGE 为 false。
- 以事务内 authenticated 角色和空 JWT 调用真实 admin_context，捕获预期 ADMIN_MFA_REQUIRED；最终返回 MFA_DENIAL_CONFIRMED，随后 rollback，无业务数据变更。
- 指定邮箱在 auth.users 尚无记录（requested_account=null）。已打开真实注册页，预填邮箱和“后台管理员”称呼，密码/提交/邮箱验证交由用户本人完成；没有代设密码或代建用户。
- 尚未绑定管理员，尚未进行真实 MFA、管理员读取或受控写入验收。下一步须先完成注册，再核验 UUID 与邮箱验证状态，并取得具体应用读写授权确认。
- 本次只新增管理结构与展示标签，不调整现有业务授权、设备或交易，不启用收费。
- 证据：production-permissions.jpg、production-denial.jpg。未在聊天记录或交付文件保存密码/会话凭据。

## 首次管理员授权（已确认并执行）

- 用户最终确认邮箱 18857179866@139.com 的生产应用管理读写范围。
- 注册已核验：UUID 4eabaadd-e345-4c83-bf92-8463b753a58a，email_verified=true。
- 开通结果：enabled=true、app_id=trvelma-production、permission=write；bootstrap 审计恰好 1 条。没有全局/其他应用授权，没有变更业务账号或其授权。
- 初始授权通过受监督 SQL 控制台执行；审计 actor 使用全零系统 UUID 哨兵，action=bootstrap_admin_by_owner_console，request_body 记录操作方式和数据库操作者。该记录不表示新管理员本人登录执行了自授权。
- 开通前以合成邮箱在 PGlite 验证待执行脚本：未验证拒绝、成功限定范围开通及审计、重复开通拒绝、定向禁用通过。未把本地定向禁用操作用于生产。
- 后台登录页已预填邮箱，验证器密钥设置、密码和验证码输入交由用户本人完成。真实 MFA、管理读取与受控写入集成验收仍待完成。
- 本次无产品源码修改。证据：admin-email-verified.jpg、admin-scope-enabled.jpg、bootstrap-admin-pending.sql（已按确认执行，文件原名保留）、bootstrap-admin-disable.sql。

## MFA 重复创建修复（待上传）

- 用户截图显示同名 factor 已存在；代码原先仅接受 verified TOTP，重登会忽略已有 unverified 因子，随后固定 friendly_name 再 enroll 触发冲突。
- 新增 mfa.mjs：从已认证 /auth/v1/user 获取因子，优先已验证 TOTP，否则恢复同名未验证管理 TOTP。enroll 前重查；并发名称冲突后重查恢复。没有删除、替换、重新生成现有用户因子或降低 MFA 要求。
- 登录/继续设置均复用该逻辑，恢复后直接进入六位验证码页面。密钥仍仅在首次设置页面临时显示，不写缓存或日志。
- 前端 12/12 测试通过，包含原始待验证因子恢复、并发重名、网络失败不创建替代因子、原验证因子优先。JS 语法检查通过；服务端授权无变化，未重复运行不变的数据库测试。
- 修复包 admin-mfa-resume.zip，6 个静态文件，独立后台项目 yunsheng-admin；尚未上传/部署，不是线上已修复。
- 浏览器 Playwright 绑定报告 browser.user unavailable；原生 Tab 能操作页面但无法操作文件选择器，聊天宿主应用被安全规则禁止控制。CLI 未发现已配置的 Cloudflare 登录。上传文件需用户本人接手，未绕过限制。
- 下一步：用户选择 ZIP，继续保存并部署，再由用户输入现有验证器生成的验证码完成真实 MFA 验收。
- 官方行为参考：https://supabase.com/docs/reference/javascript/auth-mfa-enroll （创建未验证因子），https://supabase.com/docs/guides/auth/debugging/error-codes （名称冲突）。

## MFA 修复前端已由用户部署

- 用户手动完成上传/部署后，Cloudflare 生产列表已核验最新部署 bbbce389-199c-4dbe-b449-da23e4d603bf，固定地址 https://bbbce389.yunsheng-admin.pages.dev/，替代 a6006810。
- 独立后台登录页正常加载，已预填管理员邮箱，密码与六位验证码仍由用户本人输入；未代设/替换 TOTP 因子。
- 修复代码提交 99e9ae4；对应前端 12 项测试已在上一轮通过，本轮未重复运行不变测试。
- 尝试独立下载 5 个线上静态资源做哈希比对被 HTTP 403 拒绝，未获得线上哈希；直接在浏览器打开 mfa.mjs 也被客户端阻止。未绕过限制，不能声称逐文件线上哈希验证通过。
- 本轮已验证 Cloudflare 生产部署与登录页加载；实际未验证因子恢复和真实 MFA 进入用户列表仍待用户操作确认。
- 证据：mfa-resume-production.jpg。

## 真实 MFA 与用户列表验收通过

- 用户本人反馈：重新登录并完成验证码验证后，已进入用户列表。该部分标记为用户手工确认，不表述为工具代操作通过。
- 独立服务端只读核验：verified_totp=1、administrator_enabled=true，bindings 仅 trvelma-production/write，bootstrap_audits=1。
- 原未完成验证的因子已成功完成验证，重复创建问题结项；未删除、替换或读取 TOTP 密钥，未代输验证码。
- 已登录页面的工具读取仍报 browser.user unavailable，因此本轮没有继续操作其详情、设备释放或授权表单。真实管理写入验收仍未执行，不把已有隔离测试计作生产写入通过。
- 本轮没有修改账号授权/设备/交易，无源码变更；不重复执行不变测试。

## 应用名称移入侧栏（已发布）

- 源码提交 8ed191c，分支 codex/billing-1.1；app.js/admin.css 调整应用选择位置，沿用权限与 MFA，不调整数据库。
- 管理端应用列表移到左侧，选中应用高亮；“用户与授权”“操作日志”保留为当前应用功能入口。应用切换只接受服务端返回的可用应用，切换时清空搜索并重置分页。
- 前端 12 项测试、JS 语法、diff 空白检查通过；隔离浏览器核对应用列表及用户/日志页面切换。无服务端变更，未重复运行数据库测试。
- 发布包 admin-application-sidebar.zip：6 个文件逐项 SHA-256 校验通过，包内容与当前源码一致。
- 自动上传连接恢复后由工具完成 6/6 上传和保存部署；生产部署 69c7583d-8bb4-4f40-8c57-f12beb98793f，已核对成为当前 Production/main。网址 https://yunsheng-admin.pages.dev/，固定网址 https://69c7583d.yunsheng-admin.pages.dev/。
- 线上登录页正常加载，控制台无错误；新布局的已登录视觉验证来自隔离 QA。本轮未刷新用户的已登录会话、未代填凭据，也未操作真实业务数据。
- 上一生产部署 bbbce389-199c-4dbe-b449-da23e4d603bf 为回滚目标，未执行回滚；未推送 Git。
- 用户“提交”默认包含对应发布及线上核验的约定已加入项目和协作工作区 AGENTS.md，保留敏感操作当次确认要求。
- 证据：application-sidebar.jpg、sidebar-production-deployed.jpg、release-manifest-sidebar.json。
