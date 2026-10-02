// lib/screens/home_screen.dart
// 首页 - 催办通知入口

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/dept.dart';
import '../providers/auth_provider.dart';
import '../providers/issue_provider.dart';
import '../providers/chat_provider.dart';
import '../providers/announcement_provider.dart';
import '../services/notification_service.dart';
import '../services/update_service.dart';
import 'announcement_list_screen.dart';
import 'hazard_scan_screen.dart';
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

  // 【USE-03 / USE-08】当前激活科室与可切换的科室列表。
  // 科室是身份属性（服务端下发），只有归属多个科室的人才看得到切换入口。
  String _deptCode = AppDept.defaultCode;
  List<String> _availableDepts = const [AppDept.defaultCode];

  @override
  void initState() {
    super.initState();
    _loadDept();
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

        // 公告预热：进入首页即「先读缓存再静默刷新」，
        // 这样首页角标能立刻显示未读数，进入公告页时首屏也已有内容。
        final annProvider = context.read<AnnouncementProvider>();
        Future.microtask(() async {
          await annProvider.setCurrentUser(auth.currentUser?.id ?? '');
          await annProvider.loadFirstPage();
        });

        // 初始化催办通知轮询
        _initChat();
        // 关键修复：进入首页时，把所有催办/隐患通知强制标记为已读（云端+本地）
        // 解决"重复登录后，以前查看办理结束的催办信息又提示一次"的问题
        Future.microtask(() async {
          await context.read<ChatProvider>().markAllRemindersAsRead();
        });
        // 申请系统通知权限（第一次进入首页时）
        _requestNotificationPermission();

        // 登录后自动检查更新（手动登录 / 自动恢复登录均会进入首页触发）。
        // 无更新或网络异常时静默返回，不打扰用户。
        UpdateService.checkAndPrompt(context);
      }
    });
  }

  /// 读取当前科室与可访问科室列表（登录时已同步到本地）
  Future<void> _loadDept() async {
    final cur = await AppDept.current();
    final user = context.read<AuthProvider>().currentUser;
    final available = AppDept.availableFor(user?.deptCode, user?.deptCodes);
    if (mounted) {
      setState(() {
        _deptCode = available.contains(cur) ? cur : available.first;
        _availableDepts = available;
      });
    }
  }

  /// 【USE-08】切换科室：先二次确认未提交内容会丢失，再持久化并刷新列表。
  /// 不清缓存会读到另一个科室的旧数据 —— 这与电脑端切换必须清缓存是同一道理。
  Future<void> _switchDept() async {
    if (_availableDepts.length <= 1) return;
    final chosen = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('切换科室'),
        content: const Text('切换后当前未提交的草稿将丢失，确定切换吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          ..._availableDepts.map((code) => TextButton(
            onPressed: () => Navigator.pop(ctx, code),
            child: Text(AppDept.info(code).name),
          )),
        ],
      ),
    );
    if (chosen == null || chosen == _deptCode) return;

    await AppDept.setCurrent(chosen);
    if (mounted) {
      setState(() => _deptCode = chosen);
      // 重新拉取隐患与公告，避免残留对方科室数据
      context.read<IssueProvider>().loadIssues();
      final ann = context.read<AnnouncementProvider>();
      await ann.setCurrentUser(context.read<AuthProvider>().currentUser?.id ?? '');
      await ann.loadFirstPage();
      // 顶栏徽标刷新
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已切换到${AppDept.info(chosen).name}'), duration: const Duration(seconds: 2)),
      );
    }
  }

  /// 顶部科室徽标（环保绿🌿 / 安全橙⚠），常驻显示
  Widget _buildDeptBadge() {
    final info = AppDept.info(_deptCode);
    final canSwitch = _availableDepts.length > 1;
    return GestureDetector(
      onTap: canSwitch ? _switchDept : null,
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: Color(info.color),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(info.icon, style: const TextStyle(fontSize: 14)),
            const SizedBox(width: 4),
            Text(info.short,
                style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
            if (canSwitch) const Icon(Icons.arrow_drop_down, color: Colors.white, size: 16),
          ],
        ),
      ),
    );
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
              leading: _buildDeptBadge(),
              actions: [
                // AI 隐患识别入口（随手拍快速判断，可转为正式上报）
                IconButton(
                  icon: const Icon(Icons.auto_awesome_outlined),
                  tooltip: 'AI 隐患识别',
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const HazardScanScreen(),
                      ),
                    );
                  },
                ),
                // 公告入口 - 带未读角标
                Consumer<AnnouncementProvider>(
                  builder: (context, annProvider, child) {
                    final unread = annProvider.unreadCount;
                    return Stack(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.campaign_outlined),
                          tooltip: '公告',
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                    const AnnouncementListScreen(),
                              ),
                            );
                          },
                        ),
                        if (unread > 0)
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
                                unread > 99 ? '99+' : '$unread',
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
