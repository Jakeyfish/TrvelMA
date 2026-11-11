# 统一应用管理后台 0.1

独立静态管理端，使用 Supabase Auth REST 与受保护管理 RPC。中文内部管理界面，不改变 App/Web 六语言业务文案。密码、验证码和会话仅在页面内存中；不共享业务 Web 的本地会话。

## 验证和打包

- `node --test admin/tests/*.test.mjs`（从 WithoutPersistence 目录）
- `cd supabase/admin-tests && npm ci --ignore-scripts && npm test`：PGlite 中执行当前授权、设备、Apple 台账及后台迁移，使用合成资料。不是线上 Postgres/PostgREST 或真实 MFA 集成验证。
- `python3 scripts/preview-admin.py --port 4280`：实际渲染器 + 合成资料 + 阻断外网，不包含真实会话。
- `python3 scripts/package-admin.py --archive /absolute/output.zip`：仅 5 个静态文件，独立 Cloudflare 项目；不得使用业务站点 trvelma 项目覆盖发布。

## 服务端部署前置

1. 复核实际 `auth.sessions` 的 id/user_id/not_after 字段、`auth.jwt()` 的 aal/session_id/amr，以及当前授权/设备/Apple 台账迁移已存在。
2. 审核 `202611110001_admin_backoffice.sql`。新增 admin_private 表及管理 RPC；不会创建管理员，不会改用户密码、授权、设备或交易。仅按已确认的三类账号写展示用途标签。
3. 新增管理入口及敏感访问需最终授权后才能执行。不要因为有静态页面就开放数据库表权限。
4. 用户本人选定独立管理邮箱、验证邮箱并设置 TOTP；不要在聊天中收取密码、密钥或验证码。注册因子只由用户本人操作。
5. 根据已核验的 auth.users UUID，受控建立 principal 与指定应用 binding，记录 bootstrap 审计；不按邮箱字符串动态放行。具体首次授予前再确认账号和读写范围。
6. 普通账号和 AAL1 请求必须被线上 RPC 拒绝；管理员完成 MFA 后验证只读路径。写操作仅以合成测试目标验收，不能用业务账号试改。
7. 可用 verification/20261111_admin_disable.sql 关闭管理入口并保留审计；数据修改采用审计记录和预期版本做有条件补偿，不做批量回写。

## 已实现边界

应用选择、用户分页搜索、显示用途标签、有效到期状态、设备及已验签交易查询、单设备释放、授权设置/延期/暂停/恢复、成功操作事务审计、旧版本和近期 MFA 校验、重复请求幂等。

仅首个本项目连接器可用。唯一约束禁止将第二应用指向同一 auth/授权表产生跨应用别名；其他应用配置为 unconfigured，拒绝访问，待真实独立连接器接入后启用。尚无“新增应用”管理界面、企业成员和功能额度接口。

当前成功变更与详情读取进入后台审计；失败请求通过数据库/接口错误诊断，尚未建成统一失败审计列表。不能将操作日志描述为覆盖全部安全事件。只读用户列表/日志查询本身尚未记录访问审计。

Auth 会话强制退出、账号删除、密码重置、生产收费、退款均不提供。释放设备不等于退出会话。授权来源分别展示，不推断为当前 Apple 购买：已验签历史并不意味着仍有效，试用历史也不代表当前仍在试用。

正式启用尚需：管理员身份与 TOTP、生产迁移最终授权、线上拒绝测试、真实 MFA 和受控写入验收。独立静态登录页面可先部署为未启用状态，但不得称为后台已可用。

认证设计参考官方文档：[Supabase MFA](https://supabase.com/docs/guides/auth/auth-mfa)、[TOTP](https://supabase.com/docs/guides/auth/auth-mfa/totp)。实际生产 MFA 链路仍待管理员本人设置后验证。
