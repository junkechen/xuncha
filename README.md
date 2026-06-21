# GZ 环保巡查管理系统

环保巡查问题管理移动端应用，支持问题上报、整改跟踪、催办提醒、统计分析等功能。

## 技术栈

- **前端**：Flutter 3.x
- **后端**：腾讯云 CloudBase（云函数 + 云数据库 + 云存储）
- **本地存储**：shared_preferences（已读消息持久化）
- **目标平台**：Android (arm64-v8a)

## 版本历史

| 版本 | 日期 | 说明 |
|------|------|------|
| v3.7.0 | 2026-04-20 | 初始完整版本 |
| v3.7.1 | 2026-06-17 | 修复催办重复提示 + 整改期限默认改为3日 |

## v3.7.1 修复说明

### 1. 催办信息每次登录后重复提示问题

**问题现象**：用户每次重新登录后，已经查看过的催办消息会再次响铃提示。

**根因**：原实现仅在内存中标记已读，退出登录或重启应用后内存丢失，再次登录时所有未读消息（含历史已读）会重新响铃。

**解决方案**：
- 引入 `shared_preferences` 持久化已读消息 ID 到本地存储
- 新增 `_localReadIds` 集合，轮询消息时过滤掉本地已读的消息
- `markAsRead()` 同步写入本地存储
- `getUnreadCount()` / `getReminderSessions()` 同时过滤本地已读

**改动文件**：`lib/providers/chat_provider.dart`

### 2. 整改期限默认值

**需求**：原默认 7 日过长，改为 3 日，并支持用户自主修改。

**改动内容**：
- `lib/screens/add_issue_screen.dart`：默认值改为 3 日，新增 1/3/7/15/30 日快捷选择按钮
- `lib/models/issue.dart`：JSON 解析 fallback 默认值同步改为 3 日

### 3. 其他改动

- `android/app/build.gradle`：`abiFilters` 从 `armeabi-v7a` 改为 `arm64-v8a`（减小 APK 体积约 50%）
- `lib/screens/profile_screen.dart`：版本号更新为 v3.7.1，构建日期更新为 2026-06-17
- `.gitignore`：完善 Gradle 缓存、分析日志、IDE 配置忽略规则

## 构建方法

```bash
flutter clean
flutter pub get
flutter build apk --release --target-platform android-arm64
```

构建产物：`build/app/outputs/flutter-apk/app-release.apk`

## 项目结构

```
lib/
├── main.dart                     # 应用入口
├── config/                       # 配置常量
├── models/                       # 数据模型
│   ├── issue.dart                # 问题模型
│   ├── user.dart                 # 用户模型
│   └── chat_message.dart         # 消息模型
├── providers/                    # 状态管理
│   ├── auth_provider.dart        # 认证
│   ├── issue_provider.dart       # 问题
│   └── chat_provider.dart        # 消息/催办
├── screens/                      # 页面
│   ├── login_screen.dart         # 登录
│   ├── issue_list_screen.dart    # 问题列表
│   ├── add_issue_screen.dart     # 上报问题
│   ├── issue_detail_screen.dart  # 问题详情
│   ├── rectification_feedback_screen.dart  # 整改反馈
│   ├── stats_screen.dart         # 统计
│   ├── profile_screen.dart       # 个人中心
│   └── user_selector_screen.dart # 用户选择
├── services/                     # 服务
│   ├── cloudbase_service.dart    # 腾讯云 CloudBase
│   ├── audio_service.dart        # 音频
│   ├── notification_service.dart # 通知
│   └── offline_queue_service.dart # 离线队列
└── utils/                        # 工具
    └── phone_service.dart        # 电话
```

## 注意事项

1. **构建架构**：默认仅构建 arm64-v8a，可在 `android/app/build.gradle` 中调整
2. **云端配置**：CloudBase 环境信息在 `lib/services/cloudbase_service.dart` 中
3. **后续开发原则**：从此仓库基础上修改，避免在无版本管理的副本上反复改动导致功能异常
