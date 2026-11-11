# 1.1 商店截图：中文设计样稿

三张主图：接送机安排、航班信息、收支与对账。深色底、紫青点缀；HTML/CSS 排版嵌入真实截图，不使用生成式图片重绘 App 内容。

## 查看与导出

在 WithoutPersistence 目录执行：

`python3 -m http.server 4284 --bind 127.0.0.1 --directory marketing/app-store-1.1`

打开 `http://127.0.0.1:4284/?card=trips`，另两张为 `card=flight`、`card=finance`。
浏览器视口 1320×2868，等待 networkidle 且图片 complete/naturalWidth>0 后，以 fullPage 截图导出 JPEG。仅 viewport 截图在当前浏览器可能被裁成1280px高；必须检查最终像素尺寸。JPEG 不含透明通道。

总览 overview.html 使用 renders/ 中三张导出图并排显示；renders/ 是生成预览，不进入源码提交。将交付目录的 01-trips.jpg、02-flight.jpg、03-finance.jpg 复制进去即可查看。不得把原始空白加载态截图当成最终图。

## 素材来源与限制

- assets/trips.png、finance.png：2026-11-02 商店发布资料中的真实 App 演示截图，无真实客户电话或业务账号邮箱。保留原图，不对账面金额、状态等做像素修改；最终1.1提审前需复拍最新版本。
- assets/flight.png：当前生产 FlightInformationPanel 在临时 XCTest host 中的真实渲染；通过 scripts/tests/MarketingFlightPreview.swift 创建合成 JX2 数据，仅用于组件样式展示。容器导航属于隔离预览，不是完整的正式航班详情页，也没有执行真实航班查询。航司图标按组件现有路径加载。
- Swift fixture 只替换临时验收工程中的测试文件，没有修改生产 App 源码、数据或账号。捕获屏幕后中断预览；不将该预览报告为通过的自动化回归。
- 每张底部保留“设计样稿”及演示数据说明；航班页明确云端版要求。没有宣传航班实时推送、排名、无限查询或保证收入。
- 当前为简体中文方向稿。其他五语言与 iPad、最终1.1实屏、完整旅行社对账页面，均待后续制作/核对；不直接上传本轮稿件。

## 验证记录

三张实际 JPEG 均为 1320×2868；已逐张视觉检查，修正第一次导出的底部导航裁切和财务图片未加载问题。首图已完整保留原始底部导航。浏览器视口临时设置已复原。git diff --check 通过。

无生产代码或接口变更，不重复运行不相关业务测试。输出和来源 SHA-256 记录在交付目录 manifest.json。

交付：协作工作区 deliverables/2026-11-11-store-artwork/，包含三张JPEG、overview.jpg、manifest.json和ZIP。

[Apple截图规格](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/)列出1320×2868为大屏iPhone接受的竖向尺寸；尺寸合格不等于已通过Apple素材审核。
