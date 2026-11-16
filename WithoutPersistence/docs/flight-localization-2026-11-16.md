# 1.1 航班多语言及真实状态显示

2026-11-12 完成代码和测试；2026-11-16 核对结果、保存日志。分支 codex/billing-1.1，版本 1.1(14)。未提交或部署本批功能。

## 行为

- App 与 Web 的航班结果、候选航段使用相同六语言词表：简体、繁体、英文、西班牙文、日文、韩文。Web 结果卡字段标签补齐翻译。
- 首批名称映射覆盖 LAX/SFO/TPE/HKG/PVG/NRT/HND，以及 BR/CI/CX/JX/UA/MU 航司的精确别名。机场保留 IATA 代码。未知名称与有歧义城市保留原文，不猜机场；不是全世界机场的完整翻译库。
- 解析 FlightState/FlightStatus/status 等字符串状态及文本形式；可识别计划、延误、起飞、落地、取消、备降、返航的中英文别名。显示接口值，不根据当前时间推断状态。
- 缺失状态和未经证实的数字枚举显示“状态待确认”；未知文字保留原文。移除卡片固定“计划”。
- status 为可选字段，旧快照仍可解码；原始名称及状态随快照持久化，显示转换不重写业务数据。旧缓存需正常刷新查询才能取得新增状态。
- 两端词表一致性有自动化检查。无数据库迁移、无新语言接口参数、无更换供应商、无新增付费调用；正式收费开关不变。

## 验证

- python3 WithoutPersistence/scripts/verify-flight-core.py：53 项通过，包含生产解析器 JSON/文本状态、六语言、未知值、快照兼容。
- Node --test WithoutPersistence/web/tests/*.test.mjs：最终 192 项全部通过，含两端词表一致性、真实渲染器语言/状态检查。新增测试的早期夹具错误已修复后全量重跑；不以失败轮次作为通过证据。
- verify-sync-regressions.py --destination platform=iOS\ Simulator,id=1D943880-76B5-422E-87E3-CEFF0F99A456：385 项通过。
- xcodebuild Release / generic iOS Simulator / CODE_SIGNING_ALLOWED=NO：最终 BUILD SUCCEEDED。
- verify-localizations.py --shared-web --app /tmp/trvelma-legacy-policy-build/Build/Products/Release-iphonesimulator/Wishlist.app：305 键、六语言及编译资源无错误。
- git diff --check：通过。
- 隔离 Web 实际页面观察：无状态显示“状态待确认”；英文合成数据能显示 STARLUX Airlines、Delayed、Taiwan Taoyuan International Airport (TPE)、Los Angeles International Airport (LAX)。使用临时内存夹具，远端访问阻断；不代表真实供应商调用或真机验收。

日志及当前代码 SHA-256 位于协作目录 deliverables/2026-11-12-flight-languages/。

## 发布前遗留

- 用真实航班响应确认状态字段形态，尤其是否存在数字状态码；未验证的码不得自行映射。
- 真机六语言、窄屏及长名称显示检查；这轮 Release 是模拟器构建，未安装设备。
- 当前工作区另有计费、联系方式、导航未提交修改。提交/发布必须按获准范围拆分，不覆盖或混入其他工作。
- 可进入代码审阅；本批本地验证就绪，尚不能宣称真实航班与真机端到端验收或发布完成。
