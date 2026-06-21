// lib/providers/chat_provider.dart
// 催办通知状态管理 - 实时轮询

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../models/chat_message.dart';
import '../services/audio_service.dart';

class ChatProvider extends ChangeNotifier {
  static const String _apiUrl = 'https://anuanbu1-1-6gjqaydwd067dbb1-1421679372.ap-shanghai.app.tcloudbase.com/api';
  
  final List<ChatMessage> _messages = [];
  final Map<String, List<ChatMessage>> _conversationMessages = {};
  Timer? _pollTimer;
  bool _isLoading = false;
  bool _isSending = false;
  String? _error;
  
  // 新消息通知回调（UI层注册，收到新催办/隐患通知时触发弹窗）
  Function(ChatMessage)? onNewNotification;
  
  // 当前登录用户（从AuthProvider获取）
  String _currentUserId = 'user_admin_001';
  String _currentUserName = '系统管理员';
  
  List<ChatMessage> get messages => _messages;
  bool get isLoading => _isLoading;
  bool get isSending => _isSending;
  String? get error => _error;
  
  /// 设置当前用户
  void setCurrentUser(String userId, String userName) {
    // 如果用户ID变化，清空旧消息，防止消息混淆
    if (_currentUserId != userId) {
      print('🔄 用户切换: $_currentUserId -> $userId，清空旧消息');
      _messages.clear();
      _conversationMessages.clear();
    }
    
    _currentUserId = userId;
    _currentUserName = userName;
    notifyListeners();
    
    // 用户切换时，立即拉取离线消息
    _loadOfflineMessages();
  }
  
  /// 加载离线消息（登录时或切换用户时调用）
  Future<void> _loadOfflineMessages() async {
    if (_currentUserId.isEmpty) return;
    
    try {
      print('📥 正在加载离线消息...');
      final result = await _queryMessages();
      if (result.isNotEmpty) {
        // 如果当前消息列表为空，直接使用查询结果
        if (_messages.isEmpty) {
          _messages.clear();
          _messages.addAll(result);
        } else {
          // 如果有现有消息，合并新消息（不覆盖）
          final existingIds = _messages.map((m) => m.id).toSet();
          for (var msg in result) {
            if (!existingIds.contains(msg.id) && !msg.id.startsWith('temp_')) {
              _messages.add(msg);
            }
          }
        }
        _sortMessages();
        final newCount = result.length;
        print('📥 加载了 $newCount 条离线消息，当前共有 ${_messages.length} 条');
        notifyListeners();
      } else {
        print('📥 没有新的离线消息');
      }
    } catch (e) {
      print('加载离线消息失败: $e');
    }
  }
  
  /// 手动刷新消息（用户下拉刷新时调用）
  Future<void> refreshMessages() async {
    await _loadOfflineMessages();
  }
  
  /// 启动实时消息轮询
  void startPolling() {
    _stopPolling();
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _pollMessages();
    });
    _pollMessages();
    print('开始聊天轮询');
  }
  
  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }
  
  Future<void> _pollMessages() async {
    if (_isLoading) return;
    try {
      final result = await _queryMessages();
      if (result.isNotEmpty) {
        final hasNew = _hasNewMessages(result);
        if (hasNew) {
          // 合并新消息，不清空现有消息
          final existingIds = _messages.map((m) => m.id).toSet();
          int newCount = 0;
          for (var msg in result) {
            if (!existingIds.contains(msg.id) && !msg.id.startsWith('temp_')) {
              // 【BUG修复】新消息需要继承本地已读状态
              // 如果本地有同会话的其他消息标记为已读，新消息也标记为已读
              // 关键修复：确保新消息的 isRead 状态与本地一致
              ChatMessage msgToAdd = msg;
              if (msg.toUserId == _currentUserId) {
                // 发给自己的消息，检查是否应该已读
                // 如果云端这条消息的发送时间早于当前时间（已发送一段时间了），
                // 或者本地有同会话已读消息，则标记为已读
                final sessionMessages = _messages.where((m) =>
                    (m.fromUserId == msg.fromUserId && m.toUserId == msg.toUserId) ||
                    (m.fromUserId == msg.toUserId && m.toUserId == msg.fromUserId)
                );
                final hasReadInSession = sessionMessages.any((m) => m.isRead && m.toUserId == _currentUserId);
                if (hasReadInSession) {
                  msgToAdd = msg.copyWith(isRead: true);
                }
              }
              _messages.add(msgToAdd);
              newCount++;
            } else {
              // 【关键修复】已存在的消息：只更新 isRead 状态，不覆盖其他本地更新的字段
              // 如果本地已标记为已读，但云端未同步（isRead=false），保持本地已读状态
              final localMsg = _messages.firstWhere((m) => m.id == msg.id);
              if (!localMsg.isRead && (msg.isRead || _currentUserId == msg.fromUserId)) {
                // 云端已读 或 是自己发的消息 -> 保持已读
                final idx = _messages.indexWhere((m) => m.id == msg.id);
                if (idx != -1) {
                  _messages[idx] = localMsg.copyWith(isRead: true);
                }
              }
            }
          }
          _sortMessages();
          notifyListeners();
          
          // 播放新消息提示音 - 每条消息都分别响一下
          if (newCount > 0) {
            print('🔔 收到 $newCount 条新消息，播放提示音');
            
            // 每条发给自己的新消息都单独播放提示音
            for (var msg in result) {
              if (!existingIds.contains(msg.id) && 
                  !msg.id.startsWith('temp_') &&
                  msg.toUserId == _currentUserId) {
                // 隐患/催办通知使用警告音，普通消息使用普通提示音
                if (msg.type == MessageType.issueNotify || 
                    msg.type == MessageType.reminder) {
                  print('🔔 收到隐患/催办通知: ${msg.content}');
                  AudioService.instance.playAlertSound();
                  // 触发弹窗回调（UI层显示横幅通知）
                  onNewNotification?.call(msg);
                } else {
                  AudioService.instance.playMessageSound();
                  onNewNotification?.call(msg);
                }
              }
            }
          }
        }
      }
    } catch (e) {
      print('轮询消息失败: $e');
    }
  }
  
  bool _hasNewMessages(List<ChatMessage> newMessages) {
    if (_messages.isEmpty) return true;
    final existingIds = _messages.map((m) => m.id).toSet();
    for (var msg in newMessages) {
      if (!existingIds.contains(msg.id) && !msg.id.startsWith('temp_')) {
        return true;
      }
    }
    return false;
  }
  
  void _sortMessages() {
    _messages.sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }
  
  Future<List<ChatMessage>> getConversationMessages(String odUserId) async {
    // 每次都从云端获取最新消息，确保显示所有历史记录
    try {
      final result = await _queryMessages(odUserId: odUserId);
      _conversationMessages[odUserId] = result;
      print('📥 从云端获取到 ${result.length} 条与 $odUserId 的消息');
      return result;
    } catch (e) {
      print('获取对话消息失败: $e');
      // 如果网络失败，尝试返回缓存
      if (_conversationMessages.containsKey(odUserId)) {
        print('⚠️ 网络失败，返回本地缓存');
        return _conversationMessages[odUserId]!;
      }
      return [];
    }
  }
  
  Future<List<ChatMessage>> _queryMessages({String? odUserId}) async {
    try {
      Map<String, dynamic> query = {};
      if (odUserId != null) {
        query = {
          '\$or': [
            {'fromUserId': _currentUserId, 'toUserId': odUserId},
            {'fromUserId': odUserId, 'toUserId': _currentUserId},
          ]
        };
      } else {
        query = {
          '\$or': [
            {'fromUserId': _currentUserId},
            {'toUserId': _currentUserId},
          ]
        };
      }
      
      final response = await http.post(
        Uri.parse(_apiUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'action': 'query',
          'collection': 'message',
          'query': query,
        }),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['code'] == 0 && data['data'] != null) {
          final List<dynamic> dataList = data['data'];
          return dataList
              .map((json) => ChatMessage.fromJson(json as Map<String, dynamic>))
              .toList();
        }
      }
    } catch (e) {
      print('查询消息失败: $e');
    }
    return [];
  }
  
  Future<bool> sendMessage({
    required String toUserId,
    required String toUserName,
    required String content,
    MessageType type = MessageType.text,
    String? issueId,
    String? issueTitle,
    String? imageUrl,
  }) async {
    if (content.trim().isEmpty) return false;
    
    _isSending = true;
    notifyListeners();
    
    final tempMessage = ChatMessage.create(
      fromUserId: _currentUserId,
      fromUserName: _currentUserName,
      toUserId: toUserId,
      toUserName: toUserName,
      content: content,
      type: type,
      issueId: issueId,
      issueTitle: issueTitle,
      imageUrl: imageUrl,
    );
    
    if (_conversationMessages.containsKey(toUserId)) {
      _conversationMessages[toUserId]!.add(tempMessage);
    } else {
      _conversationMessages[toUserId] = [tempMessage];
    }
    notifyListeners();
    
    try {
      final response = await http.post(
        Uri.parse(_apiUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'action': 'add',
          'collection': 'message',
          'data': tempMessage.toJson(),
        }),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['code'] == 0) {
          print('消息发送成功');
          _isSending = false;
          notifyListeners();
          return true;
        }
      }
    } catch (e) {
      print('发送消息异常: $e');
    }
    
    _isSending = false;
    notifyListeners();
    return false;
  }
  
  Future<void> markAsRead(String messageId) async {
    try {
      // 找到对应的消息
      ChatMessage? targetMsg;
      int? msgIndex;
      String? conversationKey;
      
      // 先在 _messages 中查找
      msgIndex = _messages.indexWhere((m) => m.id == messageId);
      if (msgIndex != -1) {
        targetMsg = _messages[msgIndex];
        _messages[msgIndex] = _messages[msgIndex].copyWith(isRead: true);
      }
      
      // 同步更新 _conversationMessages 缓存（关键修复！）
      for (var entry in _conversationMessages.entries) {
        final idx = entry.value.indexWhere((m) => m.id == messageId);
        if (idx != -1) {
          entry.value[idx] = entry.value[idx].copyWith(isRead: true);
          conversationKey = entry.key;
          break;
        }
      }
      
      notifyListeners();
      
      // 再调用API同步到云端（用 _id 查询云端记录）
      await http.post(
        Uri.parse(_apiUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'action': 'update',
          'collection': 'message',
          'query': {'_id': messageId},
          'data': {'isRead': true},
        }),
      ).timeout(const Duration(seconds: 10));
      
      print('✅ 标记已读成功: $messageId');
    } catch (e) {
      print('标记已读失败: $e');
      // 即使API失败，本地状态也已更新
    }
  }
  
  /// 标记所有消息已读
  Future<void> markAllAsRead() async {
    final unreadMessages = _messages.where((m) => !m.isRead && m.toUserId == _currentUserId).toList();
    for (var msg in unreadMessages) {
      await markAsRead(msg.id);
    }
  }
  
  int getUnreadCount() {
    return _messages.where((m) => !m.isRead && m.toUserId == _currentUserId).length;
  }

  /// 获取所有催办/隐患通知，每条单独一行（显示所有记录）
  List<ChatSession> getReminderSessions() {
    // 筛选出所有发给自己的催办/隐患通知，按时间倒序
    final reminders = _messages.where((m) =>
      m.toUserId == _currentUserId &&
      (m.type == MessageType.reminder || m.type == MessageType.issueNotify) &&
      m.issueId != null
    ).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    // 每条催办记录单独一个会话，不过滤不合并
    return reminders.map((msg) {
      return ChatSession(
        odId: msg.fromUserId,
        odUserName: msg.fromUserName,
        odDisplayName: msg.fromUserName,
        lastMessage: msg,
        unreadCount: msg.isRead ? 0 : 1,
        updatedAt: msg.createdAt,
      );
    }).toList();
  }

  List<ChatSession> getChatSessions() {
    final Map<String, List<ChatMessage>> conversations = {};
    
    for (var msg in _messages) {
      final odId = msg.fromUserId == _currentUserId ? msg.toUserId : msg.fromUserId;
      final odName = msg.fromUserId == _currentUserId ? msg.toUserName : msg.fromUserName;
      
      if (!conversations.containsKey(odId)) {
        conversations[odId] = [];
      }
      conversations[odId]!.add(msg);
    }
    
    final sessions = conversations.entries.map((entry) {
      return ChatSession.fromMessages(
        entry.key,
        entry.key,
        entry.value.first.fromUserId == _currentUserId 
            ? entry.value.first.toUserName 
            : entry.value.first.fromUserName,
        entry.value,
        currentUserId: _currentUserId,  // 传入当前用户ID用于计算未读数
      );
    }).toList();
    
    sessions.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return sessions;
  }
  
  Future<void> sendIssueNotification({
    required String assigneeId,
    required String assigneeName,
    required String issueId,
    required String issueTitle,
    required String action,
  }) async {
    String content;
    switch (action) {
      case 'create':
        content = '您有一个新的隐患需要处理：$issueTitle';
        break;
      case 'update':
        content = '隐患状态已更新：$issueTitle';
        break;
      case 'overdue':
        content = '隐患已逾期：$issueTitle';
        break;
      default:
        content = '隐患通知：$issueTitle';
    }
    
    await sendMessage(
      toUserId: assigneeId,
      toUserName: assigneeName,
      content: content,
      type: MessageType.issueNotify,
      issueId: issueId,
      issueTitle: issueTitle,
    );
  }
  
  @override
  void dispose() {
    _stopPolling();
    super.dispose();
  }
}
