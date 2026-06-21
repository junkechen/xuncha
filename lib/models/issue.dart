// lib/models/issue.dart
// 问题数据模型

enum IssueStatus { pending, processing, reviewing, closed }
enum IssueCategory { wastewater, wastegas, solidWaste, noise, other }
enum SeverityLevel { general, serious, critical }

/// 整改反馈记录
class RectificationRecord {
  final DateTime timestamp;
  final String description;
  final List<String> photos;
  final String submitterId;
  final String submitterName;

  RectificationRecord({
    required this.timestamp,
    required this.description,
    this.photos = const [],
    required this.submitterId,
    required this.submitterName,
  });

  Map<String, dynamic> toJson() {
    return {
      'timestamp': timestamp.toIso8601String(),
      'description': description,
      'photos': photos,
      'submitterId': submitterId,
      'submitterName': submitterName,
    };
  }

  factory RectificationRecord.fromJson(Map<String, dynamic> json) {
    return RectificationRecord(
      timestamp: DateTime.parse(json['timestamp']),
      description: json['description'] ?? '',
      photos: List<String>.from(json['photos'] ?? []),
      submitterId: json['submitterId'] ?? '',
      submitterName: json['submitterName'] ?? '',
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RectificationRecord &&
          timestamp == other.timestamp &&
          description == other.description &&
          submitterId == other.submitterId &&
          submitterName == other.submitterName;

  @override
  int get hashCode => Object.hash(timestamp, description, submitterId, submitterName);
}

/// 驳回记录（支持多次驳回）
class RejectionRecord {
  final DateTime timestamp;
  final String note;
  final String reviewerId;
  final String reviewerName;

  RejectionRecord({
    required this.timestamp,
    required this.note,
    required this.reviewerId,
    required this.reviewerName,
  });

  Map<String, dynamic> toJson() {
    return {
      'timestamp': timestamp.toIso8601String(),
      'note': note,
      'reviewerId': reviewerId,
      'reviewerName': reviewerName,
    };
  }

  factory RejectionRecord.fromJson(Map<String, dynamic> json) {
    return RejectionRecord(
      timestamp: DateTime.parse(json['timestamp']),
      note: json['note'] ?? '',
      reviewerId: json['reviewerId'] ?? '',
      reviewerName: json['reviewerName'] ?? '',
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RejectionRecord &&
          timestamp == other.timestamp &&
          note == other.note &&
          reviewerId == other.reviewerId &&
          reviewerName == other.reviewerName;

  @override
  int get hashCode => Object.hash(timestamp, note, reviewerId, reviewerName);
}

class Issue {
  final String id;
  final String cloudId; // 云端 _id（UUID），用于云端更新时的查询条件
  final String title;
  final String description;
  final IssueCategory category;
  final SeverityLevel severity;
  final List<String> photos;
  final String location;
  final String department;
  final double? latitude;
  final double? longitude;
  final String reporterId;
  final String reporterName;
  final String assigneeId;
  final String assigneeName;
  final DateTime deadline;
  final IssueStatus status;
  final List<String> rectificationPhotos;
  final String? rectificationNote;    // 整改反馈
  final String? rejectionNote;        // 驳回意见（兼容旧数据）
  final String? acceptanceNote;       // 验收意见
  final List<RejectionRecord> rejectionHistory; // 驳回历史（支持多次驳回）
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? closedAt;
  final List<RectificationRecord> rectificationHistory; // 整改历史记录

  Issue({
    required this.id,
    this.cloudId = '', // 云端_id，云同步更新时使用
    required this.title,
    required this.description,
    required this.category,
    required this.severity,
    this.photos = const [],
    required this.location,
    this.department = '',
    this.latitude,
    this.longitude,
    required this.reporterId,
    required this.reporterName,
    required this.assigneeId,
    required this.assigneeName,
    required this.deadline,
    required this.status,
    this.rectificationPhotos = const [],
    this.rectificationNote,
    this.rejectionNote,
    this.acceptanceNote,
    this.rejectionHistory = const [],
    required this.createdAt,
    required this.updatedAt,
    this.closedAt,
    this.rectificationHistory = const [],
  });

  bool get isOverdue {
    if (status == IssueStatus.closed) return false;
    return DateTime.now().isAfter(deadline);
  }

  int get daysRemaining {
    return deadline.difference(DateTime.now()).inDays;
  }

  String get categoryName {
    switch (category) {
      case IssueCategory.wastewater: return '废水排放';
      case IssueCategory.wastegas: return '废气排放';
      case IssueCategory.solidWaste: return '固废管理';
      case IssueCategory.noise: return '噪音污染';
      case IssueCategory.other: return '其他';
    }
  }

  String get severityName {
    switch (severity) {
      case SeverityLevel.general: return '一般';
      case SeverityLevel.serious: return '较重';
      case SeverityLevel.critical: return '严重';
    }
  }

  String get statusName {
    switch (status) {
      case IssueStatus.pending: return '待处理';
      case IssueStatus.processing: return '整改中';
      case IssueStatus.reviewing: return '待验收';
      case IssueStatus.closed: return '已关闭';
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'cloudId': cloudId,
      'title': title,
      'description': description,
      'category': category.index,
      'severity': severity.index,
      'photos': photos,
      'location': location,
      'department': department,
      'latitude': latitude,
      'longitude': longitude,
      'reporterId': reporterId,
      'reporterName': reporterName,
      'assigneeId': assigneeId,
      'assigneeName': assigneeName,
      'deadline': deadline.toIso8601String(),
      'status': status.index,
      'rectificationPhotos': rectificationPhotos,
      'rectificationNote': rectificationNote,
      'rejectionNote': rejectionNote,
      'acceptanceNote': acceptanceNote,
      'rejectionHistory': rejectionHistory.map((r) => r.toJson()).toList(),
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'closedAt': closedAt?.toIso8601String(),
      'rectificationHistory': rectificationHistory.map((r) => r.toJson()).toList(),
    };
  }

  factory Issue.fromJson(Map<String, dynamic> json) {
    // 解析 category - 支持字符串和数字
    IssueCategory category;
    final catValue = json['category'];
    if (catValue is String) {
      switch (catValue.toLowerCase()) {
        case '废水':
        case '废水排放':
        case 'wastewater':
          category = IssueCategory.wastewater;
          break;
        case '废气':
        case '废气排放':
        case 'wastegas':
          category = IssueCategory.wastegas;
          break;
        case '固废':
        case '固废管理':
        case 'solidwaste':
        case 'solid_waste':
          category = IssueCategory.solidWaste;
          break;
        case '噪音':
        case '噪音污染':
        case 'noise':
          category = IssueCategory.noise;
          break;
        default:
          category = IssueCategory.other;
      }
    } else {
      category = IssueCategory.values[catValue ?? 0];
    }

    // 解析 severity - 支持字符串和数字
    SeverityLevel severity;
    final sevValue = json['severity'];
    if (sevValue is String) {
      switch (sevValue.toLowerCase()) {
        case '一般':
        case 'general':
          severity = SeverityLevel.general;
          break;
        case '较重':
        case '严重':
        case 'serious':
          severity = SeverityLevel.serious;
          break;
        case 'critical':
          severity = SeverityLevel.critical;
          break;
        default:
          severity = SeverityLevel.general;
      }
    } else {
      severity = SeverityLevel.values[sevValue ?? 0];
    }

    // 解析 status - 支持字符串和数字
    IssueStatus status;
    final statusValue = json['status'];
    if (statusValue is String) {
      switch (statusValue.toLowerCase()) {
        case '待处理':
        case 'pending':
          status = IssueStatus.pending;
          break;
        case '整改中':
        case 'processing':
          status = IssueStatus.processing;
          break;
        case '待验收':
        case 'reviewing':
          status = IssueStatus.reviewing;
          break;
        case '已关闭':
        case 'closed':
          status = IssueStatus.closed;
          break;
        default:
          status = IssueStatus.pending;
      }
    } else {
      status = IssueStatus.values[statusValue ?? 0];
    }

    // 解析 deadline
    DateTime deadline;
    try {
      final dl = json['deadline'] ?? json['dueDate'] ?? json['createdAt'];
      deadline = dl != null ? DateTime.parse(dl.toString()) : DateTime.now().add(const Duration(days: 7));
    } catch (_) {
      deadline = DateTime.now().add(const Duration(days: 7));
    }

    // 解析 createdAt
    DateTime createdAt;
    try {
      createdAt = DateTime.parse(json['createdAt'] ?? json['created_at'] ?? DateTime.now().toIso8601String());
    } catch (_) {
      createdAt = DateTime.now();
    }

    // 解析 updatedAt
    DateTime updatedAt;
    try {
      updatedAt = DateTime.parse(json['updatedAt'] ?? json['updated_at'] ?? DateTime.now().toIso8601String());
    } catch (_) {
      updatedAt = DateTime.now();
    }

    // 解析 closedAt
    DateTime? closedAt;
    try {
      final ca = json['closedAt'] ?? json['closed_at'];
      if (ca != null && ca.toString().isNotEmpty) {
        closedAt = DateTime.parse(ca.toString());
      }
    } catch (_) {}

    return Issue(
      // id 字段优先（因为云端可能同时存在 _id 和 id，且含义不同）
      // _id 是云端自动生成的 UUID，id 是 App 端生成的业务 ID（如 issue_xxx）
      // cloudId 保存云端的 _id，用于后续云端更新操作
      id: json['id'] ?? json['_id'] ?? '',
      cloudId: json['_id']?.toString() ?? json['cloudId'] ?? '',
      title: json['title'] ?? '',
      description: json['description'] ?? '',
      category: category,
      severity: severity,
      photos: List<String>.from(json['photos'] ?? []),
      location: json['location'] ?? '',
      department: json['department'] ?? '',
      latitude: json['latitude']?.toDouble(),
      longitude: json['longitude']?.toDouble(),
      reporterId: json['reporterId'] ?? json['reporter_id'] ?? '',
      reporterName: json['reporterName'] ?? json['reporter_name'] ?? '',
      assigneeId: json['assigneeId'] ?? json['assignee_id'] ?? '',
      assigneeName: json['assigneeName'] ?? json['assignee_name'] ?? '',
      deadline: deadline,
      status: status,
      rectificationPhotos: List<String>.from(json['rectificationPhotos'] ?? json['rectification_photos'] ?? []),
      // 整改反馈（整改人提交）
      rectificationNote: json['rectificationNote'] ?? json['rectification_note'],
      // 驳回意见（发起人驳回）
      rejectionNote: json['rejectionNote'] ?? json['rejection_note'] ?? json['reviewNote'] ?? json['reviewerNote'],
      // 验收意见（发起人验收通过）
      acceptanceNote: json['acceptanceNote'] ?? json['acceptance_comment'] ?? json['acceptanceComment'],
      // 驳回历史（支持多次驳回）
      rejectionHistory: (json['rejectionHistory'] as List<dynamic>?)
          ?.map((r) => RejectionRecord.fromJson(r as Map<String, dynamic>))
          .toList() ?? [],
      createdAt: createdAt,
      updatedAt: updatedAt,
      closedAt: closedAt,
      rectificationHistory: (json['rectificationHistory'] as List<dynamic>?)
          ?.map((r) => RectificationRecord.fromJson(r as Map<String, dynamic>))
          .toList() ?? [],
    );
  }
}