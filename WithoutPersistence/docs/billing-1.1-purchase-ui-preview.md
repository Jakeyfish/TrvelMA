# 1.1 购买页面隔离预览

目的：在实体设备离线时检查实际PurchasePlansView的布局和六语言内容，不验证真实付款，不生成Apple审核通过证据。

从仓库根目录运行：

```sh
python3 WithoutPersistence/scripts/preview-purchases.py --destination 'platform=iOS Simulator,id=模拟器UDID'
```

此模式使用现有隔离XCTest宿主，并在其窗口显示正式购买组件。登录状态为隔离副本，不读取业务App凭据；不连接云端授权函数，不打开业务数据库。三个商品来自本地StoreKit配置，六语言商品名称/描述来自现有商品文档；购买开关为关闭，按钮不能发起购买。

在界面顶部选择语言，分别检查标题、说明、买断/月付/年付、价格/周期、恢复购买、管理订阅和政策链接。顶部必须显示“LOCAL STOREKIT · QA ONLY · NO PURCHASES”。结束时点击“Finish QA preview”退出测试；超时会报告失败，不能把超时当作通过。

本地预览使用XCTest上下文；不要把StoreKitTest初始化直接放在普通App启动中。未使用XCTest上下文的早期独立预览曾启动退出，正式App不受影响。

原有命令保持不变：`verify-sync-regressions.py --storekit`运行支付行为回归；新增`--purchase-preview`只运行交互界面夹具，不属于原16项支付断言。

截图应放在内部QA交付目录，文件名注明语言与local-storekit。最终商品审核截图仍需使用对应审核构建核对。界面截图不能证明沙盒交易、服务端台账、跨设备授权或真实Apple通知成功。

## 2026-11-10 结果

iPhone18Pro模拟器已完成六语言三档商品与页面入口核对，保存每种语言的顶部、订阅区、政策区三张截图及AX记录，共18张。购买按钮禁用，没有发起购买。首轮发现西语商品回退英文，定位为预览locale的es与商品es_ES不匹配，修正为es_ES后使用相同构建缓存定向重验，商品名称/说明和逗号小数价格格式均正确。交互夹具正常结束；这不增加或替代原16项支付断言。

截图与验证记录位于协作工作区deliverables/2026-11-10-billing-1.1-followup/purchase-ui-local/。正式商品审核截图及真实沙盒端到端仍待真机与审核构建确认。
