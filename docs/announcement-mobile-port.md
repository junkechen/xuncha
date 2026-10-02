# 公告模块移动端移植说明（v3.7.5）

电脑端公告功能（发布/编辑/删除/置顶/富文本/已读统计等）的移动端查看端移植。
技术栈沿用工程现状：Flutter + Provider + CloudBase 云函数 RPC，
**未引入任何新的第三方依赖**。

> 说明：`org.gradle.user.home` 被重定向到 `D:\.gradle-cache`，排查 Gradle 问题时
> 需检查该目录，而非默认的 `~/.gradle`。

## 一、功能范围

移动端定位为**查看端**（发布/编辑/删除/置顶操作仍在电脑端完成）：

| 能力 | 实现 |
|---|---|
| 公告列表 | 卡片流，置顶优先，未读红点+加粗，分类/作者/阅读量 |
| 公告详情 | 富文本正文、附件图片、置顶/过期标记、进入即标记已读 |
| 分页 | 本地分页（每页 15 条），滚动到底自动加载更多 |
| 下拉刷新 | `RefreshIndicator` 强制走云端 |
| 已读/未读 | 本地已读集合（按 userId 隔离）+ 云端同步 |
| 置顶 | 排序置顶优先，同置顶按 pinnedAt 倒序（与电脑端一致） |
| 过期 | 过期公告自动隐藏；详情页对已过期公告显示「已过期」标记 |
| 入口 | 首页 AppBar 公告图标 + 未读数量角标 |

数据模型与接口对齐电脑端 `announcement.js` / `api.js`：
单集合 `announcement`，用 `docType` 区分 `announcement` / `read` / `audit`；
删除一律软删除（云端无 remove）；批量操作逐条（云端无 updateMany）。

## 二、变更文件清单

### 新增（6 个）

| 文件 | 说明 |
|---|---|
| `lib/models/announcement.dart` | 公告模型，字段与电脑端一致；含 normalize 兜底、isExpired、排序、可见性过滤 |
| `lib/utils/announcement_html.dart` | 自研轻量富文本渲染器（零新增依赖），含 HTML 消毒 |
| `lib/services/announcement_service.dart` | 云端读取、本地缓存、已读上报（幂等）、断网重试队列 |
| `lib/providers/announcement_provider.dart` | 状态管理：缓存优先、静默刷新、分页、已读未读 |
| `lib/screens/announcement_list_screen.dart` | 公告列表页 |
| `lib/screens/announcement_detail_screen.dart` | 公告详情页 |

### 修改（5 个）

| 文件 | 改动 |
|---|---|
| `lib/config/constants.dart` | 新增 `announcementCollection` |
| `lib/main.dart` | 注册 `AnnouncementProvider`；启动性能优化（见第五节） |
| `lib/screens/home_screen.dart` | AppBar 公告入口 + 未读角标；进入首页预热公告 |
| `lib/screens/profile_screen.dart` | 版本号 v3.7.4 → v3.7.5，构建日期更新 |
| `pubspec.yaml` | version 3.7.4+5 → 3.7.5+6 |

### 未改动（回归保护）

`auth_provider.dart`、`issue_provider.dart`、`user.dart`、`cloudbase_service.dart`
属云同步核心文件，本次**完全未触碰**，公告模块统一通过
`CloudBaseService.instance.callApi` 访问云端。

## 三、缓存策略

- **存储**：`SharedPreferences`（工程既有本地存储方案），key 前缀 `gz_ann_`。
- **首屏**：先读缓存立即渲染（0 网络等待）→ 再静默请求云端刷新 → 刷新后落盘并刷新 UI。
  无缓存时才显示 Loading。
- **下拉刷新**：强制走云端。
- **静默刷新防抖**：距上次刷新 < 30 秒则跳过，避免反复进出页面造成无谓请求。
- **失败降级**：请求失败返回 null 时**保留缓存内容**（区分「请求失败」与「云端确无公告」，
  后者才显示空态），避免偶发网络抖动把已有内容刷没。
- **容量保护**：缓存 JSON 超过 1MB 则放弃写入，避免 SharedPreferences 膨胀拖慢其它模块。

## 四、断网重试策略（避免重复提交与数据丢失）

1. **本地优先**：标记已读时**先写本地已读集合并持久化**，UI 立即反馈，
   再异步上报云端。即使此刻断网，用户看到的已读状态也不会丢失。
2. **幂等写入**：云端上报采用「先查后插」——查询该 (公告, 用户) 的 read 文档，
   已存在则直接跳过。因此重复提交**不会产生重复已读记录**，这是重试安全的前提。
3. **失败入队**：上报失败则写入持久化队列（每条含 announcementId/userId/retryCount），
   入队前按 (公告, 用户) 去重。
4. **自动重试**：进入公告列表页 / 首页预热时触发队列处理；处理前先用
   `OfflineQueueService.instance.isNetworkAvailable()` 检测网络（复用工程既有能力，
   不重复造轮子），无网则保留队列等待下次。
5. **重试上限**：单条最多重试 5 次，超过则丢弃该上报（本地已读状态仍保留，
   不影响用户感知），避免队列无限增长。
6. **用户隔离**：已读集合按 userId 分别存储，切换账号不串号。

## 五、启动性能优化

`main()` 原为 4 个串行 `await`（设置/音频/通知/云服务），现优化为：

- 仅保留**首屏必需**的 `SettingsProvider.init()`（决定深色模式/大字体主题）。
- 音频、通知、云服务均非首屏必需，改为**首帧渲染完成后**延迟初始化，
  其中音频与通知**并行**执行，减少主线程阻塞、加快冷启动。

## 六、富文本渲染（零新增依赖）

工程无 HTML 渲染库，按「不引入未经确认的新技术栈」约束自研
`lib/utils/announcement_html.dart`：

- 支持 h1-h6 / p / br / div / strong,b / em,i / u / s,del / a / img /
  ul,ol,li / blockquote / code / hr。
- **安全**：先消毒再解析——整块移除 script/style/iframe 等危险标签（含内容）、
  剔除 `on*` 事件属性、过滤 `javascript:` / `vbscript:` / `data:text/html` 协议。
- 链接用 `url_launcher`（已有依赖）打开；图片支持 `cloud://` fileID，
  自动经 `getFreshPhotoUrl` 换临时 URL，加载失败显示占位。
- 链接手势识别器由 `AnnouncementHtmlView` 统一注册并在 dispose 时释放，无泄漏。

## 七、回归检查（项目历史 Bug 防回归清单）

| 检查项 | 结论 |
|---|---|
| 催办重复提示三层防护（`_localReadIds` / `_markAllCloudMessagesAsReadOnLogin` / `markAllRemindersAsRead`，setCurrentUser 第 57 行调用，首页与催办页进入时调用） | ✅ 未破坏 |
| auth_provider role 写入用 `.role.name` 字符串 | ✅ 未破坏（未改动该文件） |
| APK 架构 `abiFilters 'arm64-v8a'` 单架构 | ✅ 未改动 |
| 版本号与构建日期同步更新 | ✅ 已更新为 v3.7.5 / 2026-08-30 |
| 云同步核心文件未动 | ✅ 未触碰 |

公告已读刻意复用了催办已读的三层防护思路（本地集合优先 + 持久化 + UI 层兜底），
避免重蹈「重复提示」类缺陷。

## 八、构建验证与测试结论

### 编译与构建验证
- `flutter analyze`：**0 error**（本次新增/改动的 11 个文件无任何 error/warning，仅历史 avoid_print 类 warning 来自既有文件）。
- 修复迁移阻塞：历史文件 `stats_screen.dart` 两处 `const pw.TextStyle(fontWeight: pw.FontWeight.bold)` 在 Dart 3.11.3 下不再是编译期常量（`const_eval_type_bool_num_string`），已去 `const`，**不影响运行行为**，仅解除编译阻塞。
- `flutter build apk --release --target-platform android-arm64`：**BUILD_EXIT=0**。
- 交付产物：`build/app/outputs/flutter-apk/gzxc-v3.7.5.apk`
  - 架构：**单 arm64-v8a**（`lib/arm64-v8a/libapp.so`）✅ 符合防回归单架构约定
  - 体积：**28.9 MB**（与历史 gzxc-v3.7.4.apk 的 30MB 一致）✅
  - 签名：`apksigner verify` 返回 **EXIT=0**，已正确签名，可直接安装 ✅

### 环境阻塞与解决（记录备查）
1. **flutter 缓存死锁**：多次强杀 flutter 进程后 `/d/Flutter/bin/cache/lockfile` 残留，导致后续所有 `flutter` 命令无限等待、无任何磁盘产出。删除该 lockfile 后工具立即恢复正常（Flutter 3.41.5 / Dart 3.11.3）。
2. **Gradle 配置在新插件下失效**：Flutter 3.41 的新 Gradle 插件（`dev.flutter.flutter-gradle-plugin`）会忽略 `defaultConfig.ndk.abiFilters`，默认构建全部 ABI；旧 `applicationVariants.all { outputFileName = ... }` 写法也不再生效。故改用命令行 `--target-platform android-arm64` 直接生成单架构包，不受 build.gradle 该配置影响。
3. **split-per-abi 冲突**：`--split-per-abi` 会与 `ndk.abiFilters` 互斥报错（`Conflicting configuration`），已避开。
4. **Gradle 缓存位置**：`org.gradle.user.home` 被重定向到 `D:\.gradle-cache`（非默认 `~/.gradle`），排查 Gradle 下载/缓存问题时需检查该目录。

### 冒烟测试清单（需在真机 / 模拟器执行）
> 本构建环境无 Android 设备或模拟器，UI 交互冒烟测试请在真机或模拟器按以下清单验证（安装 `gzxc-v3.7.5.apk`）：

1. 首页 AppBar 显示公告图标；有未读时其角标显示未读数量。
2. 进入公告列表：首屏秒开（缓存优先），下拉刷新强制走云端并更新。
3. 列表置顶公告位于顶部并带「置顶」标签；未读项加粗 + 红点；分类 / 作者 / 阅读量正常展示。
4. 滚动到底自动加载更多（分页，每页 15 条）。
5. 点击进入详情：富文本正文（加粗 / 标题 / 列表 / 图片 / 链接）正确渲染；附件图片正常加载；cloud:// 图片可经换链显示。
6. 进入详情后返回列表：该项未读红点消失、不再加粗（已读标记生效）。
7. 断网启动 App：仍可读到上次缓存的公告列表（离线可用，非空白）。
8. 断网进入未读公告再返回：本地已读状态不丢失；恢复网络后自动补报云端（不会重复提交）。
9. 过期公告不在列表出现；从详情进入已过期公告显示「已过期」标记。
10. 切换账号登录：公告已读状态按 userId 隔离，不串号。

### 回归复核结论
| 检查项 | 结论 |
|---|---|
| 催办三层防护（`_localReadIds` / `_markAllCloudMessagesAsReadOnLogin` / `markAllRemindersAsRead`） | ✅ 未破坏 |
| `auth_provider` role 写入用 `.role.name` 字符串 | ✅ 未改动该文件 |
| APK 单架构 arm64-v8a + 体积 28.9MB | ✅ 符合约定 |
| 版本号 v3.7.5 / 构建日期 2026-08-30 | ✅ 已更新 |
| 云同步核心文件（auth_provider/issue_provider/user.dart/cloudbase_service） | ✅ 未触碰 |
