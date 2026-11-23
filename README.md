# GZ 环保巡查管理系统（手机端）

环保巡查问题管理移动端应用：问题上报（含 AI 识别回填）、整改跟踪、属地审批链、作业票签批、安全教育培训（千题题库 + 随机组卷）、催办提醒、统计分析等。

- **当前版本**：v3.7.51（2026-11-22）
- **更新通道**：GitHub Releases 自动更新（APP 内「检查更新」，登录后自动提示）
- **配套端**：电脑端 v1.0.41（junkechen/env-inspection-desktop）、网页版管理后台、APK 下载页，四端共享同一腾讯云 CloudBase 数据

## 技术栈

- **前端**：Flutter 3.x（Android）
- **后端**：腾讯云 CloudBase（云函数 + 云数据库 + 云存储）
- **本地存储**：shared_preferences（已读消息、题库缓存等）
- **目标平台**：arm64-v8a / armeabi-v7a / x86_64（split-per-abi 三包）
- **版本信息**：package_info_plus（版本自检与更新比较）

## 版本历史

| 版本 | 日期 | 说明 |
|------|------|------|
| v3.7.0 | 2026-04-20 | 初始完整版本 |
| v3.7.1 | 2026-06-17 | 修复催办重复提示；整改期限默认 3 日 |
| v3.7.23 | 2026-10-02 | 此阶段最后一次 GitHub Release（后因通道未同步停更） |
| v3.7.2~43 | — | 持续迭代：作业票签批与属地审批链、安全教育培训、动态权限、图文操作、AI 识别回填等 |
| v3.7.44 | 2026-11 | 培训资源模块归属修复与启动自愈（copyWith 透传 module + _healModules） |
| v3.7.45 | 2026-11 | 培训题库建立：题库自动维护、随机抽题组卷（15 题/卷，合格线 80） |
| v3.7.46 | 2026-11 | 题库千题化：知识点卡确定性生成器（固定种子展开 7 类题型） |
| v3.7.47 | 2026-11 | 节能/环保/碳排三模块题库全达标（1079/1016/1023，共 3073 生成题） |
| v3.7.48 | 2026-11 | 排查 APP 内更新通道（GitHub latest 停在 v3.7.23）；考试页空态新增「当前版本 · 题库共 N 题」自检行 |
| v3.7.49 | 2026-11 | 题库显示层兜底：examPoolFor 全模块回退 seedItems（按 module 过滤防串味），考试不依赖同步链路 |
| v3.7.50 | 2026-11-21 | 题库四端同步：training_question_banks 分片上云（13 片 + gen_manifest 清单幂等）；电脑端 v1.0.40 合并题库包；内存实测（JSON 2.49MB / 对象化 5~7MB，占 2~4%，可接受）；恢复 GitHub 发布（Release v3.7.50） |
| v3.7.51 | 2026-11-22 | 题库答案修复：全量筛查 3073 题，否定式题干 878 题重排（439 答案标反 + 439 多解歧义 → 统一「1 错 + 3 对」），factPool/borrowFact 修复生成器，stamp 触发题库包重新上云，缓存 key 升 v2；电脑端 v1.0.41 同构修复 |

## 构建方法

```bash
flutter clean
flutter pub get
flutter analyze          # 须无 error
flutter test             # 回归测试
flutter build apk --split-per-abi --release
```

构建产物：`build/app/outputs/flutter-apk/app-{arm64-v8a,armeabi-v7a,x86_64}-release.apk`

- **versionCode 规则**：主版本号 ×1000 偏移——v7a = 1000+N、arm64 = 2000+N、x86_64 = 4000+N（如 3.7.51+51 → 1051/2051/4051）
- **发布**：GitHub Release（junkechen/xuncha）资产顺序必须 **arm64 排第一**（APP 内更新通道取第一个 .apk），v7a 第二供老旧机型手动下载

## 自动更新机制

`lib/services/update_service.dart` 在首页挂载时查询 GitHub Releases 最新版本，与本地 `PackageInfo` 语义化比较，发现新版本弹窗引导浏览器下载安装；无更新或网络异常静默返回。

## 项目结构

```
lib/
├── main.dart                     # 应用入口
├── config/                       # 配置常量
├── models/                       # 数据模型（issue/user/chat_message/training_resource/question_bank_gen 等）
├── providers/                    # 状态管理
│   ├── auth_provider.dart        # 认证
│   ├── issue_provider.dart       # 问题/整改/审批
│   ├── chat_provider.dart        # 消息/催办
│   └── training_provider.dart    # 培训资源 + 题库（生成、缓存、云端分片同步）
├── screens/                      # 页面（上报/详情/统计/培训/考试/作业票等）
├── services/
│   ├── cloudbase_service.dart    # 腾讯云 CloudBase（环境信息在此）
│   ├── update_service.dart       # GitHub 版本检查与更新提示
│   ├── audio_service.dart        # 音频
│   ├── notification_service.dart # 通知
│   └── offline_queue_service.dart# 离线队列
└── utils/
```

## 注意事项

1. **云端配置**：CloudBase 环境信息在 `lib/services/cloudbase_service.dart`
2. **题库生成器**：`lib/models/question_bank_gen.dart` 为双端同构实现（电脑端 js 版逐题一致），改动须双端同步并重跑全量质检（否定式题干 0 缺陷口径）
3. **题库缓存 key**：生成器答案语义变更时须升版 `training_questions_cache_vN`，并更新 `generate(stamp:)` 触发云端题库包重传
4. **后续开发原则**：从本仓库基础上修改，避免在无版本管理的副本上反复改动
