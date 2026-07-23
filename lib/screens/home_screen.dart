// lib/screens/home_screen.dart
// 首页 - 催办通知入口

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/issue_provider.dart';
import '../providers/chat_provider.dart';
import '../services/notification_service.dart';
import 'add_issue_screen.dart';
import 'stats_screen.dart';
import 'issue_list_screen.dart';
import 'profile_screen.dart';
import 'chat_list_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        // 进入首页时清除所有残留的 SnackBar
        ScaffoldMessenger.of(context).clearSnackBars();
        
        // 设置当前用户以便进行权限过滤（整改人只能看到自己的问题）
        final auth = context.read<AuthProvider>();
        final issueProvider = context.read<IssueProvider>();
        issueProvider.setCurrentUser(auth.currentUser);
        
        // 加载问题并在新问题出现时播放提示音
        context.read<IssueProvider>().loadIssues(playSound: true);
        // 初始化催办通知轮询
        _initChat();
        // 关键修复：进入首页时，把所有催办/隐患通知强制标记为已读（云端+本地）
        // 解决"重复登录后，以前查看办理结束的催办信息又提示一次"的问题
        Future.microtask(() async {
          await context.read<ChatProvider>().markAllRemindersAsRead();
        });
        // 申请系统通知权限（第一次进入首页时）
        _requestNotificationPermission();
      }
    });
  }

  /// 申请通知权限（Android 13+）
  Future<void> _requestNotificationPermission() async {
    await Future.delayed(const Duration(seconds: 2)); // 进入首页2秒后再弹
    if (!mounted) return;
    final granted = await NotificationService.instance.requestPermission();
    if (granted) {
      debugPrint('✅ 通知权限已获取');
    } else {
      debugPrint('⚠️ 用户未授予通知权限，后台通知将不可用');
    }
  }

  void _initChat() {
    final chatProvider = context.read<ChatProvider>();
    final authProvider = context.read<AuthProvider>();
    
    // 设置当前用户
    if (authProvider.currentUser != null) {
      chatProvider.setCurrentUser(
        authProvider.currentUser!.id,
        authProvider.currentUser!.name,
      );
    }
    
    // 注册新消息弹窗回调：收到催办/隐患通知时显示横幅 + 系统通知
    chatProvider.onNewNotification = (msg) {
      if (!mounted) return;
      final isAlert = msg.type.toString().contains('issueNotify') ||
                      msg.type.toString().contains('reminder');

      // ✅ 同步发送系统通知（后台/锁屏均可接收）
      NotificationService.instance.showNotification(
        id: msg.content.hashCode.abs() % 99999,
        title: isAlert ? '🔔 催办提醒 - GZ巡查' : '📋 新消息 - GZ巡查',
        body: msg.content,
        payload: msg.issueId,
      );

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(
                isAlert ? Icons.notifications_active : Icons.message,
                color: Colors.white,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      isAlert ? '📣 新催办通知' : '新消息',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    Text(
                      msg.content,
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          backgroundColor: isAlert ? Colors.orange[800] : Colors.blueGrey[700],
          duration: const Duration(seconds: 5),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          action: SnackBarAction(
            label: '查看',
            textColor: Colors.yellow,
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const ChatListScreen(),
                ),
              );
            },
          ),
        ),
      );
    };
    
    // 启动轮询，实时接收催办通知
    chatProvider.startPolling();
    print('✅ 已启动消息轮询，将实时接收隐患通知');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _currentIndex == 0
          ? AppBar(
              title: const Text('隐患列表'),
              centerTitle: true,
              actions: [
                // 催办通知入口 - 始终显示
                Consumer<ChatProvider>(
                  builder: (context, chatProvider, child) {
                    final unreadCount = chatProvider.getUnreadCount();
                    return Stack(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.notifications),
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const ChatListScreen(),
                              ),
                            );
                          },
                        ),
                        if (unreadCount > 0)
                          Positioned(
                            right: 8,
                            top: 8,
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: const BoxDecoration(
                                color: Colors.red,
                                shape: BoxShape.circle,
                              ),
                              constraints: const BoxConstraints(
                                minWidth: 16,
                                minHeight: 16,
                              ),
                              child: Text(
                                '$unreadCount',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ],
            )
          : null,
      body: IndexedStack(
        index: _currentIndex,
        children: const [
          IssueListScreen(),
          AddIssueScreen(),
          StatsScreen(),
          ProfileScreen(),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (index) {
            setState(() {
              _currentIndex = index;
            });
          },
          type: BottomNavigationBarType.fixed,
          selectedItemColor: const Color(0xFF10B981),
          unselectedItemColor: Colors.grey,
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.assignment),
              label: '问题',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.add_circle),
              label: '上报',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.bar_chart),
              label: '统计',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.person),
              label: '我的',
            ),
          ],
        ),
      ),
    );
  }
}
