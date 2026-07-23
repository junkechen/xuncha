// lib/screens/chat_list_screen.dart
// 催办通知列表 - 只保留催办通知，点击跳转到对应问题

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/chat_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/issue_provider.dart';
import '../models/chat_message.dart';
import 'issue_detail_screen.dart';

class ChatListScreen extends StatefulWidget {
  const ChatListScreen({Key? key}) : super(key: key);

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  @override
  void initState() {
    super.initState();
    _initChat();
  }

  void _initChat() {
    final chatProvider = context.read<ChatProvider>();
    final authProvider = context.read<AuthProvider>();
    
    if (authProvider.currentUser != null) {
      chatProvider.setCurrentUser(
        authProvider.currentUser!.id,
        authProvider.currentUser!.name,
      );
    }
    
    // 启动轮询，实时接收催办通知
    chatProvider.startPolling();

    // 进入通知列表时：
    // 1) 先把所有催办/隐患通知的本地状态修复成"已读"，避免登录后老催办显示为"新"
    // 2) 再调用原 markAllAsRead 处理其他消息（聊天消息等）
    Future.microtask(() async {
      await chatProvider.markAllRemindersAsRead();
      await chatProvider.markAllAsRead();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('催办通知'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              context.read<ChatProvider>().startPolling();
            },
          ),
        ],
      ),
      body: Consumer<ChatProvider>(
        builder: (context, chatProvider, child) {
          final reminders = chatProvider.getReminderSessions();
          
          if (chatProvider.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          
          if (reminders.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.notifications_off_outlined, size: 80, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text(
                    '暂无催办通知',
                    style: TextStyle(fontSize: 18, color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '有催办时会在这里显示',
                    style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                  ),
                ],
              ),
            );
          }
          
          return RefreshIndicator(
            onRefresh: () async {
              await chatProvider.refreshMessages();
            },
            child: ListView.builder(
              itemCount: reminders.length,
              itemBuilder: (context, index) {
                final session = reminders[index];
                final msg = session.lastMessage;
                return _buildReminderTile(session, msg);
              },
            ),
          );
        },
      ),
    );
  }

  /// 催办通知行
  Widget _buildReminderTile(ChatSession session, ChatMessage? msg) {
    if (msg == null) return const SizedBox.shrink();
    final isUnread = session.unreadCount > 0;
    
    // 根据消息类型选择图标颜色
    Color iconColor;
    IconData iconData;
    if (msg.type == MessageType.reminder) {
      iconColor = Colors.orange;
      iconData = Icons.alarm;
    } else {
      iconColor = Colors.blue;
      iconData = Icons.assignment;
    }
    
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: isUnread ? iconColor : Colors.grey[300],
        child: Icon(
          iconData,
          color: Colors.white,
          size: 20,
        ),
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              msg.issueTitle ?? msg.content,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: isUnread ? FontWeight.bold : FontWeight.normal,
                fontSize: 15,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _formatTime(session.updatedAt),
            style: TextStyle(fontSize: 12, color: Colors.grey[500]),
          ),
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 2),
          Row(
            children: [
              Icon(Icons.person_outline, size: 12, color: Colors.grey[500]),
              const SizedBox(width: 2),
              Text(
                msg.fromUserName,
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            msg.content,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: isUnread ? Colors.black87 : Colors.grey[500],
              fontSize: 13,
            ),
          ),
        ],
      ),
      trailing: isUnread
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.red,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text(
                '新',
                style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
              ),
            )
          : Icon(Icons.chevron_right, color: Colors.grey),
      onTap: () => _jumpToReminderIssue(session, msg),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    );
  }

  void _jumpToReminderIssue(ChatSession session, ChatMessage msg) async {
    // 标记已读（本地+云端同步）
    if (session.unreadCount > 0) {
      await context.read<ChatProvider>().markAsRead(msg.id);
    }
    _jumpToIssue(msg.issueId!);
  }

  void _jumpToIssue(String issueId) async {
    ScaffoldMessenger.of(context).clearSnackBars();
    
    final issueProvider = context.read<IssueProvider>();
    await issueProvider.loadIssues();
    
    final issue = issueProvider.allIssues
        .where((i) => i.id == issueId)
        .firstOrNull;
    
    if (issue != null && mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => IssueDetailScreen(issue: issue),
        ),
      ).then((_) {
        // 返回时刷新通知列表，确保已读状态已更新
        if (mounted) {
          context.read<ChatProvider>().startPolling();
        }
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('该隐患数据已不存在或已被删除'),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);
    
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes}分钟前';
    if (diff.inHours < 24) return '${diff.inHours}小时前';
    if (diff.inDays < 7) return '${diff.inDays}天前';
    
    return '${time.month}/${time.day}';
  }
}
