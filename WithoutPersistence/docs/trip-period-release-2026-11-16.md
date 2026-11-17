# 行程日期筛选提交与发布记录

- 功能提交 ae19973，codex/billing-1.1；不含Git推送、正式收费或App Store审核。
- 独立提交快照App388项、Web202项通过，Release模拟器构建成功，六语言实际编译资源308键通过。
- 主工作区真机包此前完整回归401项、Web203项；其他未提交功能保留，不能声称三台真机包与定向提交字节一致。
- 已安装并启动iPad A16、16 Plus、Max 1.1(14)；16 Plus两日期控件、默认全部、箭头及范围联动实测见trip-period-filter-2026-11-16.md。
- Web构建20261116-trip-period-v1；生产静态ZIP逐成员对比ae19973及SHA-256一致，未包含业务记录或会话。
- 初次Cloudflare登录过期；本人已在聊天旁浏览器恢复登录，后续生产发布结果如下。
- 回滚到现有生产bf1c2553-382d-4bb4-9970-21f9c9cbca77，不涉及数据库迁移。

发布包与独立日志保存在协作工作区deliverables/2026-11-16-trip-period/。版本与购买的沙盒退款入口等仍为未提交工作，不随本批Web发布。

## 生产已发布

- Cloudflare生产main部署7da0898c-772d-4877-b905-83a2a8b6c040，状态success；控制台显示2026-11-16 20:54（洛杉矶时间）。
- 固定地址https://7da0898c.trvelma.pages.dev/，正式https://trvelma.pages.dev/。67/67上传（66静态资产+_headers）。
- 正式站刷新后DOM脚本src为app.js?v=20261116-trip-period-v1；02账号仍进入只读归档并读回客户1条，console error为空。未更换账号，因此未在生产用有效账号操作行程筛选；该交互证据来自16 Plus真机和隔离Web测试。
- 发布ZIP静态成员已逐个与ae19973比对。另尝试终端公网逐文件校验被HTTP403阻断，未声称线上逐文件哈希通过；改用已登录浏览器确认新构建及运行状态。
- 发布截图cloudflare-deployed.jpg；回滚仍为bf1c2553-382d-4bb4-9970-21f9c9cbca77。无数据库写入或正式收费变更。
