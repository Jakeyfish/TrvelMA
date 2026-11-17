# 行程详情联系方式去重

- 原因：原有 LabeledContent 显示订单联系方式，后来另加 TripPhoneActions，导致同一电话占两条记录；本地、云端和 Web 均有此路径。
- 修复：App 使用共用 TripDetailContactRow，在同一记录中展示标签、号码和短信/拨号操作；按规范化电话号码去除原始联系方式与电话操作之间的重复。Web 对应使用 tripDetailContactHTML。
- 保留微信等非电话联系方式、不同的订单联系方式、客户多电话，以及原有账号归属和电话类型筛选；不改订单数据或保存逻辑。首页电话展开维持现有行为。
- 复用现有六语言键，无新增文案。此次仅修改 1.1 分支，未更新已安装 App 或线上 Web。
- 已执行 Web integration.test.mjs：128 项通过，其中新增重复号码、短信/电话链接、非电话资料保留和空联系方式回归；git diff --check 通过。App Release 编译结果见后续记录；未进行真机或视觉验收。
- App `xcodebuild -project WithoutPersistence/Wishlist.xcodeproj -scheme Wishlist -configuration Release -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/trvelma-legacy-policy-build CODE_SIGNING_ALLOWED=NO build`：BUILD SUCCEEDED。日志 `/tmp/trvelma-contact-build.log`；Web 日志 `/tmp/trvelma-contact-web.log`。编译通过不等于真机验收。
