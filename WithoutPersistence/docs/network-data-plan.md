# 网络数据环境与本地数据迁移方案

## 决定

使用 Supabase（PostgreSQL、Auth、Storage）作为云端，保留 SwiftData 作为设备端数据库和离线缓存。客户端仅使用 Supabase publishable/anon key；数据库所有者操作必须通过登录 JWT 与 RLS 授权。`service_role`、Flight API 密钥等秘密不能放进 iOS 客户端或同步到普通用户设置。

数据库初始结构见 `supabase/migrations/202610180001_initial_network_schema.sql`。它按账户隔离旅行社、客户、联系方式、常用地址、行程、停靠点、费用和跨设备设置。各表都启用了 RLS，并按 `owner_id = auth.uid()` 限定用户数据；子表同时用复合外键保证不能关联到其他用户的父记录。

## 当前本地数据对应关系

| SwiftData / 本地字段 | 云端表 | 迁移说明 |
| --- | --- | --- |
| `LocalAccount` | `auth.users` + `profiles` | `LocalAccount.syncID` 不能直接当 Supabase 用户 ID；密码留在 Keychain，用户需完成云端注册或账号绑定。 |
| `TravelAgency` | `travel_agencies` | `uuid` 转 UUID，`agencyCode` 按用户唯一。 |
| `Custumer` | `customers` | `uuid` 转 UUID；行程保存可选的客户 ID，同时保留客户名称快照；旅行社订单信息继续保存为快照。 |
| `Connect` | `customer_contacts` | 目前模型没有稳定记录 ID，接入同步前需加 UUID。`connectlable` 对应 label，`connecttype` 对应类型/值需先统一语义。 |
| `Address` | `customer_addresses` | 目前模型没有稳定记录 ID，接入同步前需加 UUID。 |
| `TripBookingRecord` | `trips` | `id` 是稳定 UUID；`customerUUID` 对应可空的 `customer_id`；停靠点和费用 JSON 在云端拆成 `trip_stops`、`trip_expenses`。删除客户时云端将行程关联置空，保留行程快照。 |
| `UserDefaults` 中的语言、币种、导航和费用项目 | `user_settings` | 只同步非敏感偏好。设备权限状态、通知授权、航班服务密钥继续留在设备端。 |

## 迁移前必须处理的风险

1. 目前业务记录没有 `owner_id`，而且列表查询未按登录用户隔离。不能直接把现有记录全部上传给当前登录账号，否则可能把另一位本机用户的数据也上传。迁移界面应先让用户预览记录数量并确认归属，再写入绑定关系。
2. 注册密码当前只在本机 Keychain。不能读取后传到云端。账号迁移需通过 Supabase Auth 新注册、邮箱验证或密码重设完成。
3. 删除记录当前是硬删除。同步前需要本地删除队列/墓碑，避免离线设备把已删除记录重新上传。
4. 当前费用金额没有保存每笔记录的币种。首次同步时需从本位币设置写入 `currency_code`，之后按行程保留币种，不能只用用户当前设置解释历史金额。
5. 航班 API 密钥和其他凭据不能放入 `user_settings`，也不能提交到 Git。

## 实施顺序

1. 在 Supabase 创建开发项目并应用初始 SQL；先用两组测试账号验证 RLS 的读写隔离。
2. SwiftData 模型增加稳定 ID、`ownerID`、`updatedAt`、同步状态和删除墓碑，并给已有记录提供明确的本地归属迁移流程。
3. 把视图中的直接 `@Query`/`ModelContext` 写入逐步收进 repository；保留 SwiftData 的离线读取和本地保存。
4. 接入 Supabase Auth，完成邮箱验证、令牌刷新、退出和账号删除流程；之后先同步设置、客户、旅行社，再同步行程及子表。
5. 加入网络重试、增量同步、冲突策略和照片 Storage。初期以服务器 `updated_at` 与本地修改时间检测冲突，发生双端同时编辑时提示用户选择，避免静默覆盖。

## 当前接入状态

客户端已配置 Supabase URL 和 publishable key，并接入 Auth、业务数据同步，以及名片/收款方式 JSON 同步。数据库迁移文件位于 `supabase/migrations/`，但本地文件存在不等于远端数据库已执行迁移；若远端缺少列或策略，仍会出现同步失败。首次生产迁移前，应在 Supabase SQL Editor 或本地 Supabase CLI 项目中应用迁移并确认 RLS 策略。

当前同步仍使用一份 SwiftData 本机数据库，并将图片资产编码在 `user_settings` JSON 字段中。它还不是完全隔离的多模式架构；版本边界和后续拆分顺序见 [`product-editions-and-roadmap.md`](product-editions-and-roadmap.md)。
