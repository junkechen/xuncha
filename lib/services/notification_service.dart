// lib/services/notification_service.dart
// 系统通知服务：发送后台/锁屏通知，管理通知权限

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._();
  static NotificationService get instance => _instance;
  NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  /// 通知渠道配置（Android 8+ 必须声明渠道）
  static const String _channelId = 'gz_inspection_channel';
  static const String _channelName = 'GZ环保巡查通知';
  static const String _channelDesc = '环保隐患问题催办、新增、状态变更等通知';

  /// 初始化（在 main.dart 启动时调用一次）
  Future<void> initialize() async {
    if (_initialized) return;

    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const InitializationSettings settings =
        InitializationSettings(android: androidSettings);

    await _plugin.initialize(
      settings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        debugPrint('🔔 用户点击通知: ${response.payload}');
        // TODO: 可根据 payload 跳转到对应问题详情
      },
    );

    // 创建通知渠道（Android 8+）
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: _channelDesc,
      importance: Importance.high,
      enableVibration: true,
      playSound: true,
      showBadge: true,
    );

    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    _initialized = true;
    debugPrint('✅ NotificationService 初始化完成');
  }

  /// 申请通知权限（Android 13+ 需要运行时申请）
  /// 返回 true 表示已获得权限
  Future<bool> requestPermission() async {
    // 先检查已有权限
    final status = await Permission.notification.status;
    if (status.isGranted) return true;

    // 申请权限
    final result = await Permission.notification.request();
    debugPrint('🔔 通知权限申请结果: $result');
    return result.isGranted;
  }

  /// 检查是否有通知权限
  Future<bool> hasPermission() async {
    final status = await Permission.notification.status;
    return status.isGranted;
  }

  /// 发送系统通知（后台/锁屏可见）
  ///
  /// [id]    通知唯一ID（相同ID会更新已有通知）
  /// [title] 通知标题
  /// [body]  通知内容
  /// [payload] 额外数据（如问题ID），用于点击通知后跳转
  Future<void> showNotification({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    if (!_initialized) await initialize();

    // 没权限时静默失败（不报错）
    final hasPerms = await hasPermission();
    if (!hasPerms) {
      debugPrint('⚠️ 无通知权限，跳过系统通知: $title');
      return;
    }

    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDesc,
      importance: Importance.high,
      priority: Priority.high,
      enableVibration: true,
      playSound: true,
      icon: '@mipmap/ic_launcher',
      // 大图标显示
      largeIcon: DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
      styleInformation: BigTextStyleInformation(''),
    );

    const NotificationDetails details =
        NotificationDetails(android: androidDetails);

    await _plugin.show(
      id,
      title,
      body,
      details,
      payload: payload,
    );

    debugPrint('🔔 发送系统通知 [$id]: $title | $body');
  }

  /// 发送催办通知（固定格式）
  Future<void> showUrgeNotification({
    required String issueTitle,
    required String fromUser,
    String? issueId,
  }) async {
    await showNotification(
      id: issueTitle.hashCode.abs() % 10000,
      title: '🔔 催办提醒',
      body: '$fromUser 催促您处理：$issueTitle',
      payload: issueId,
    );
  }

  /// 发送新问题通知
  Future<void> showNewIssueNotification({
    required String issueTitle,
    required String department,
    required String assigneeName,
    String? issueId,
  }) async {
    await showNotification(
      id: issueTitle.hashCode.abs() % 10000 + 1000,
      title: '📋 新问题待整改',
      body: '[$department] $issueTitle → 整改人：$assigneeName',
      payload: issueId,
    );
  }

  /// 发送验收/审核结果通知
  Future<void> showReviewNotification({
    required String issueTitle,
    required bool approved,
    String? reviewNote,
    String? issueId,
  }) async {
    await showNotification(
      id: issueTitle.hashCode.abs() % 10000 + 2000,
      title: approved ? '✅ 整改已验收通过' : '❌ 整改被驳回',
      body: approved
          ? '$issueTitle 已通过验收'
          : '$issueTitle 被驳回${reviewNote != null ? "：$reviewNote" : ""}',
      payload: issueId,
    );
  }
}
