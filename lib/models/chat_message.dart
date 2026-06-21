// lib/models/chat_message.dart
// 聊天消息数据模型

enum MessageType {
  text,           // 文本消息
  image,          // 图片消息
  issueNotify,     // 隐患通知
  system,         // 系统消息
  reminder,       // 催办提醒
}

class ChatMessage {
  final String id;
  final String fromUserId;
  final String fromUserName;
  final String toUserId;
  final String toUserName;
  final String content;
  final MessageType type;
  final DateTime createdAt;
  final bool isRead;
  final String? issueId;      // 关联的隐患ID
  final String? issueTitle;   // 关联的隐患标题
  final String? imageUrl;     // 图片URL

  ChatMessage({
    required this.id,
    required this.fromUserId,
    required this.fromUserName,
    required this.toUserId,
    required this.toUserName,
    required this.content,
    this.type = MessageType.text,
    required this.createdAt,
    this.isRead = false,
    this.issueId,
    this.issueTitle,
    this.imageUrl,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    MessageType msgType = MessageType.text;
    final typeStr = json['type']?.toString().toLowerCase() ?? 'text';
    switch (typeStr) {
      case 'image':
        msgType = MessageType.image;
        break;
      case 'issue_notification':
      case 'issue_notify':
      case 'hazard':  // 云端可能使用的格式
        msgType = MessageType.issueNotify;
        break;
      case 'system':
        msgType = MessageType.system;
        break;
      case 'reminder':
      case 'remind':       // 可能的变体
      case 'urge':         // 可能的变体
      case '催促':         // 中文格式
      case '催办':         // 中文格式
        msgType = MessageType.reminder;
        break;
      default:
        // 检查 content 或 title 是否包含催办关键词
        final content = json['content']?.toString().toLowerCase() ?? '';
        final title = json['title']?.toString().toLowerCase() ?? '';
        if (content.contains('催办') || content.contains('reminder') ||
            title.contains('催办') || title.contains('reminder') ||
            (json['issueId'] != null && json['issueId'].toString().isNotEmpty)) {
          msgType = MessageType.reminder;
        } else {
          msgType = MessageType.text;
        }
    }

    return ChatMessage(
      id: json['_id'] ?? json['id'] ?? '',
      fromUserId: json['fromUserId'] ?? '',
      fromUserName: json['fromUserName'] ?? '',
      toUserId: json['toUserId'] ?? '',
      toUserName: json['toUserName'] ?? '',
      content: json['content'] ?? '',
      type: msgType,
      createdAt: DateTime.tryParse(json['createdAt'] ?? '') ?? DateTime.now(),
      isRead: json['isRead'] ?? false,
      issueId: json['issueId'] ?? json['hazardId'] ?? json['problemId'],
      issueTitle: json['issueTitle'] ?? json['title'] ?? json['hazardTitle'],
      imageUrl: json['imageUrl'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'fromUserId': fromUserId,
      'fromUserName': fromUserName,
      'toUserId': toUserId,
      'toUserName': toUserName,
      'content': content,
      'type': type.name,
      'createdAt': createdAt.toIso8601String(),
      'isRead': isRead,
      'issueId': issueId,
      'issueTitle': issueTitle,
      'imageUrl': imageUrl,
    };
  }

  /// 创建发送的消息
  factory ChatMessage.create({
    required String fromUserId,
    required String fromUserName,
    required String toUserId,
    required String toUserName,
    required String content,
    MessageType type = MessageType.text,
    String? issueId,
    String? issueTitle,
    String? imageUrl,
  }) {
    return ChatMessage(
      id: 'temp_${DateTime.now().millisecondsSinceEpoch}',
      fromUserId: fromUserId,
      fromUserName: fromUserName,
      toUserId: toUserId,
      toUserName: toUserName,
      content: content,
      type: type,
      createdAt: DateTime.now(),
      isRead: false,
      issueId: issueId,
      issueTitle: issueTitle,
      imageUrl: imageUrl,
    );
  }

  /// 创建隐患通知消息
  factory ChatMessage.issueNotification({
    required String toUserId,
    required String toUserName,
    required String fromUserName,
    required String issueId,
    required String issueTitle,
    required String content,
  }) {
    return ChatMessage.create(
      fromUserId: 'system',
      fromUserName: '系统通知',
      toUserId: toUserId,
      toUserName: toUserName,
      content: content,
      type: MessageType.issueNotify,
      issueId: issueId,
      issueTitle: issueTitle,
    );
  }

  ChatMessage copyWith({
    String? id,
    String? fromUserId,
    String? fromUserName,
    String? toUserId,
    String? toUserName,
    String? content,
    MessageType? type,
    DateTime? createdAt,
    bool? isRead,
    String? issueId,
    String? issueTitle,
    String? imageUrl,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      fromUserId: fromUserId ?? this.fromUserId,
      fromUserName: fromUserName ?? this.fromUserName,
      toUserId: toUserId ?? this.toUserId,
      toUserName: toUserName ?? this.toUserName,
      content: content ?? this.content,
      type: type ?? this.type,
      createdAt: createdAt ?? this.createdAt,
      isRead: isRead ?? this.isRead,
      issueId: issueId ?? this.issueId,
      issueTitle: issueTitle ?? this.issueTitle,
      imageUrl: imageUrl ?? this.imageUrl,
    );
  }
}

/// 聊天会话（用于会话列表）
class ChatSession {
  final String odId;           // 对方的用户ID
  final String odUserName;      // 对方的用户名
  final String odDisplayName;   // 对方的显示名称
  final ChatMessage? lastMessage;  // 最后一条消息
  final int unreadCount;        // 未读消息数
  final DateTime updatedAt;     // 最后更新时间

  ChatSession({
    required this.odId,
    required this.odUserName,
    required this.odDisplayName,
    this.lastMessage,
    this.unreadCount = 0,
    required this.updatedAt,
  });

  factory ChatSession.fromMessages(String odId, String odUserName, String odDisplayName, List<ChatMessage> messages, {String? currentUserId}) {
    if (messages.isEmpty) {
      return ChatSession(
        odId: odId,
        odUserName: odUserName,
        odDisplayName: odDisplayName,
        updatedAt: DateTime.now(),
      );
    }
    
    // 按时间排序
    messages.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final lastMsg = messages.first;
    
    // 计算未读消息数：发给当前用户的未读消息
    final unreadCount = messages.where((m) => !m.isRead && m.toUserId == currentUserId).length;
    
    return ChatSession(
      odId: odId,
      odUserName: odUserName,
      odDisplayName: odDisplayName,
      lastMessage: lastMsg,
      unreadCount: unreadCount,
      updatedAt: lastMsg.createdAt,
    );
  }
}
