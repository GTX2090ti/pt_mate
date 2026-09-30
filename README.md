# PT-Mate 鸿蒙版（个人自用）

基于 [JustLookAtNow/pt_mate](https://github.com/JustLookAtNow/pt_mate) 适配的 **HarmonyOS 鸿蒙原生版本**，Flutter 3.41.10-ohos 构建，仅供个人自用，在原版基础上添加了多项下载管理与使用体验增强功能。

📦 安装包（未签名 HAP）见本仓库 [Releases](https://github.com/GTX2090ti/pt_mate-harmonyos/releases)，当前版本 **ohos-v1.1.0**。

## 鸿蒙化适配

- 基于 Flutter 3.41.10-ohos-1.0.1 完成鸿蒙真机适配，支持深色模式
- WebView 组件替换为 br\_v6.1.5\_ohos 本地副本，解决第三方 WebView 兼容问题

## 在自用版中新增的功能

1. **Tracker 管理**：任务详情页新增 Tracker 列表，含状态徽章（已禁用 / 未联系 / 正常 / 更新中 / 红种）、tier 层级、节点 / 种子 / 下载者 / 已下载统计，红种消息突出显示
2. **连接节点**：新增节点页，展示 IP:端口、国家、连接类型、客户端、上下行速度、进度、flags，支持 5 秒自动刷新
3. **文件管理**：任务详情页新增"文件"Tab，显示种子内文件列表（大小、进度、下载 / 跳过状态），支持全屏勾选按需下载文件（通过文件优先级实现）
4. **分类管理**：支持分类新增 / 删除 / 重命名，任务卡片可修改分类，批量操作支持批量修改分类
5. **qB 风格设置页**：板块化设置（外观主题切换、自动刷新间隔、显示全部任务开关、分类管理），下载健康、限速调度、RSS 自动下载入口收拢到"任务工具"板块，设置按钮固定在下载页右下角
6. **下载管理页优化**：新增状态筛选 Tab（全部 / 下载中 / 做种中 / 已暂停 / 已完成），任务卡片状态徽章，空列表美化
7. **网络可靠性**：代理不可达时自动回退直连（TCP 探测 + 30 秒冷却）；连接超时放宽至 20 秒；网络失败显示中文可操作提示

## 已修复的问题

1. **Tracker 崩溃**：数值字段为空时 Null 强转 int 报错，改为类型安全解析
2. **数据流量下全部连接超时**：根因是启用了局域网代理，流量下不可达；已实现代理自动回退直连
3. **深色模式启动页白底**：启动窗口背景写死白色，新增 dark 资源目录，深色模式显示黑色
4. **站点刷新偶发 SecureStorageUnavailableException**：优化前台恢复时安全存储初始化逻辑，避免打断进行中的站点刷新；放宽安全存储平台调用超时，适配鸿蒙真机

## 快速开始（开发）

```bash
flutter pub get
flutter build hap --release
```

产物位于 `build/ohos/hap/`，未签名包 `entry-default-unsigned.hap` 可直接通过 hdc 安装调试。

## 文档

- [修改记录（2026-09）](./docs/pt_mate_修改记录_2026-09.md)
- [英文原版介绍（归档）](./docs/README-EN-archived.md)
- [旧中文介绍（归档）](./docs/README-zh-CN-archived.md)
- [使用指南](./docs/USER_GUIDE.md)
- [网站配置指南](./docs/SITE_CONFIGURATION_GUIDE.md)
- [支持网站清单](./docs/SUPPORTED_SITES.md)

## 许可

上游项目为 MIT License；本自用版沿用 [LICENSE](./LICENSE)。
