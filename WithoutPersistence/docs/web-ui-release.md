# Web UI v2 发布记录

## 发布结果

- 正式网址：https://trvelma.pages.dev/
- Web构建：20261110-ui-v2。
- 代码提交：184f679，分支codex/billing-1.1。本次没有Git推送或合并main。
- Cloudflare项目trvelma，Production/main直接上传发布。
- 部署ID：d89d1b98-a431-4fb1-8d98-c4b0dcb8a3e0。
- 固定部署网址：https://d89d1b98.trvelma.pages.dev/
- Cloudflare显示65/65文件上传完成，并显示站点构建部署成功。

## 发布验证

- 发布包为协作目录deliverables/2026-11-10-web-editors/trvelma-web-ui-v2.zip。
- 上传前逐项SHA-256核对65个发布文件，app.js、index.html、workspace.css与提交源文件相同。
- 线上登录页正常渲染，DOM链接的脚本和两份样式均为20261110-ui-v2；新紫色视觉已显示，控制台未发现错误。
- 线上检查没有登录审核账号、没有新增或修改真实客户/订单，没有变更数据库与收费开关；已登录业务页面的真实数据操作未在这次线上检查执行。
- 上线前Web177项测试通过，六语言292键无错误；隔离浏览器验证编辑保存、停靠点、联系方式、地址和仅保存结算状态，并检查桌面/手机/平板布局。
- 上述资源版本检查不等同于通过HTTP重新下载所有线上文件进行哈希核对；上传包哈希和Cloudflare部署状态另有凭证。

## 回滚与保留内容

上一生产部署ID：617f2650-13e5-4308-89a4-18a87fd51161，固定网址https://617f2650.trvelma.pages.dev/。若线上发现问题，在Cloudflare将生产回滚到该部署；本次没有执行回滚。

完整本地基线及本轮布局前快照保存在协作交付目录，保留其他未提交工作。购买页隔离预览工具、后台需求等不属于本次Web提交。

证据：同一交付目录的production-deployed.jpg、online-resource-version.json、release-manifest.json、web-177-tests.log、localizations.log。

## 顶栏图标更新（2026-11-11）

- 构建：20261111-ui-v3；代码提交 b92e198，测试空白修正 e0d1154；分支 codex/billing-1.1，仅本地提交，未推送 Git。
- 用户资料移至右上角，连接状态绿/黄/红灯；刷新与退出采用图标并保留本地化 title/aria-label。
- Cloudflare Production/main 部署：44a72a06-3a33-4a4d-81e0-4abb8a1ea70b；固定地址 https://44a72a06.trvelma.pages.dev/。
- 66/66 文件上传成功，发布包全部文件 SHA-256 校验通过，三项主要资源与源码逐字节一致。
- Web 177 项测试通过，六语言 292 键检查无错误；隔离 QA 检查桌面及 390px 手机宽度，无横向溢出。版本查询参数更新后未重复执行相同业务测试。
- 线上登录页资源均为 ui-v3，控制台无错误；未登录审核账号，未在真实业务数据上操作。登录后顶栏的视觉验证来自隔离 QA，不能视为线上真实数据操作验收。
- 回滚目标：上一部署 d89d1b98-a431-4fb1-8d98-c4b0dcb8a3e0；本次未执行回滚。
- 发布包、SHA 清单、测试日志及截图位于协作目录 deliverables/2026-11-11-web-topbar/。
