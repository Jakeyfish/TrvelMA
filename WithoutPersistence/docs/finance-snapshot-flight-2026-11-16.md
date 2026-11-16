# 财务行程快照航班展示统一（1.1）

## 原因与修复

用户反馈“本周 → 详细信息 → 行程快照 → 展开行程”的航班区与其他位置不同。已确认本地 WalletView 和 CloudWalletView 把选中的航班快照拆成字段数组，再由 FinancialSnapshotRecordCard 用旧式逐行文字绘制。

改为在 FinancialTripSnapshotRow 保留完整 VariFlightLookupResult，由 FinancialSnapshotRecordCard 直接复用行程列表/详情使用的 FlightInformationPanel。航司、机场、航站楼、双列时间、飞机方向、六语言及真实状态都遵循共享组件；保留原有行李转盘。缺少快照时展示航班号及缺省字段，不触发网络查询。展示为只读，不改金额（仍为净收入）、订单状态或业务数据。

Web openFinanceSnapshots 本来就复用 renderTripCard(readOnly:true)，未修改业务实现；新增实际渲染回归覆盖同一航班卡片、短时间、状态及无编辑/删除/刷新入口。

## 文件

- Wishlist/Views/Wallet/WalletView.swift：完整快照载体、共享航班卡片。
- Wishlist/Views/Wallet/CloudWalletView.swift：云端快照传入相同载体。
- Wishlist/Views/WishlistView.swift：共享卡片机场名称完整换行，避免长英文名截掉机场代码。
- scripts/preview-settlement.py：新增 finance-flight 合成预览；仅临时副本默认展开，生产 DisclosureGroup 行为不变。
- web/tests/integration.test.mjs：财务快照共享航班卡片回归。

## 验证与限制

- Release iOS Simulator 构建成功（包含保留行李转盘后的最终代码）。
- Web integration.test.mjs：134 项全部通过。
- git diff --check、预览脚本 Python 编译检查通过。
- 隔离模拟器已观察到实际财务快照使用双列时间、航司图标及真实状态卡片；资料为合成数据。
- 未执行生产数据操作；没有数据库迁移。尚未提交、发布或安装真机。
- 其他未提交的 1.1 航班多语言、导航和计费改动保留；本次共享卡片复用了当前 1.1 分支实现。

## 后续真机验证

2026-11-16已完成三台更新，16 Plus相关财务显示及系统分享入口通过。没有实际发送到联系人。iPad与Max分享尚未逐一覆盖；详见[三台真机记录](device-finance-acceptance-2026-11-16.md)。上方“未安装”是较早本地验收阶段状态。
