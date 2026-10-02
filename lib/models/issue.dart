// lib/models/issue.dart
// 问题数据模型

import 'business_type.dart';

enum IssueStatus { pending, processing, reviewing, closed }

// ⚠️ 类别枚举顺序【不可随意调整】：
// toJson 写的是 categoryName（中文），fromJson 也按中文回读，
// 历史数据零迁移；但本枚举值一旦被中文映射引用，删除/改名会编译报错并漏解析。
// 新类别体系（业务类别改造方案 §8.3）：
//   SAFE 安全业务 13 项、SAVING 节能业务 10 项、ENV 环保业务 5 项。
enum IssueCategory {
  // —— 安全业务 SAFE（13）——
  safeProcess,       // 工艺
  safeElectrical,    // 电气仪表
  safeFire,          // 消防应急
  safeEquipment,     // 设备隐患
  safeRules,         // 规章制度
  safeSpecial,       // 特种设备
  safeTraining,      // 培训教育
  safeInvest,        // 安全投入
  safeViolation,     // 违章操作
  safeHealth,        // 职业卫生
  safeConfined,      // 有限空间
  safeExternal,      // 外来施工
  safeOther,         // 其他（安全）
  // —— 节能业务 SAVING（10）——
  savingWater,       // 节水
  savingElectric,    // 节电
  savingAir,         // 压风
  savingHydrogen,    // 氢气
  savingNitrogen,    // 氮气
  savingGas,         // 燃气
  savingEnergyEquip, // 耗能设备
  savingProcess,     // 工艺节能
  savingWaste,       // 浪费损耗
  savingCarbon,      // 碳排管理
  // —— 环保业务 ENV（5）——
  envWastewater,     // 废水排放
  envWastegas,       // 废气排放
  envSolid,          // 固废管理
  envNoise,          // 噪音污染
  envOther,          // 其他（环保）
}

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

  /// 业务类型（SAFE / SAVING / ENV），由 category 反查或云端直读。
  /// 仅作标签与统计维度，不参与数据过滤。空串表示迁移兜底（按类别反查）。
  final String businessType;

  /// 科室编码（AQ / JN），由 businessType 反查（SAFE→AQ，SAVING/ENV→JN）。
  /// 仅作数据隔离维度与展示，不参与本端过滤逻辑。
  final String deptCode;

  /// 类别原始中文名。仅当云端类别无法用枚举精确表达时才非空
  /// （管理员在电脑端新增的类别、或历史遗留的未收录类别），
  /// 用于保证「提交 → 列表 → 详情 → 编辑」全程不丢名字。
  /// 空/null 时一切行为与改造前完全一致。
  final String? categoryLabel;

  Issue({
    required this.id,
    this.cloudId = '',
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
    this.businessType = '',
    this.deptCode = '',
    this.categoryLabel,
  });

  bool get isOverdue {
    if (status == IssueStatus.closed) return false;
    return DateTime.now().isAfter(deadline);
  }

  int get daysRemaining {
    return deadline.difference(DateTime.now()).inDays;
  }

  /// 云端存的就是中文名（与桌面端一致）。
  /// 有原始标签时用标签 —— 新增类别因此不会被折叠成「其他」。
  String get categoryName {
    final label = categoryLabel;
    if (label != null && label.isNotEmpty) return label;
    return categoryNameOf(category);
  }

  String get severityName => severityNameOf(severity);

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
      // 跨端类别统一为「中文全名」，与桌面端 business.js CATEGORY_BY_BUSINESS 对齐。
      'category': categoryName,
      // 业务类型与科室（由业务反查），与云端契约一致。
      'businessType': businessType,
      'deptCode': deptCode,
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

  /// 中文类别 → 枚举；businessType 仅用于消歧「其他」（安全其他 / 环保其他）。
  static IssueCategory fromChinese(String? s, [String businessType = '']) {
    final name = (s ?? '').trim();
    // 无歧义的字典（覆盖新类别 + 旧别名）
    const map = <String, IssueCategory>{
      // 安全业务
      '工艺': IssueCategory.safeProcess,
      '电气仪表': IssueCategory.safeElectrical,
      '消防应急': IssueCategory.safeFire,
      '设备隐患': IssueCategory.safeEquipment,
      '规章制度': IssueCategory.safeRules,
      '特种设备': IssueCategory.safeSpecial,
      '培训教育': IssueCategory.safeTraining,
      '安全投入': IssueCategory.safeInvest,
      '违章操作': IssueCategory.safeViolation,
      '职业卫生': IssueCategory.safeHealth,
      '有限空间': IssueCategory.safeConfined,
      '外来施工': IssueCategory.safeExternal,
      // 节能业务
      '节水': IssueCategory.savingWater,
      '节电': IssueCategory.savingElectric,
      '压风': IssueCategory.savingAir,
      '氢气': IssueCategory.savingHydrogen,
      '氮气': IssueCategory.savingNitrogen,
      '燃气': IssueCategory.savingGas,
      '耗能设备': IssueCategory.savingEnergyEquip,
      '工艺节能': IssueCategory.savingProcess,
      '浪费损耗': IssueCategory.savingWaste,
      '碳排管理': IssueCategory.savingCarbon,
      // 环保业务
      '废水排放': IssueCategory.envWastewater,
      '废水': IssueCategory.envWastewater,
      '废气排放': IssueCategory.envWastegas,
      '废气': IssueCategory.envWastegas,
      '固废管理': IssueCategory.envSolid,
      '固废': IssueCategory.envSolid,
      '噪音污染': IssueCategory.envNoise,
      '噪音': IssueCategory.envNoise,
      '噪声': IssueCategory.envNoise,
      // 旧安全科别名 → 最近邻新类别
      '消防安全': IssueCategory.safeFire,
      '设备与电气安全': IssueCategory.safeEquipment,
      '危化品管理': IssueCategory.safeOther,
      '作业安全': IssueCategory.safeViolation,
      '人员行为与防护': IssueCategory.safeOther,
      '安全标识与通道': IssueCategory.safeOther,
    };
    if (map.containsKey(name)) return map[name]!;
    // 「其他」歧义：按业务归属区分
    if (name == '其他') {
      return businessType == 'SAFE' ? IssueCategory.safeOther : IssueCategory.envOther;
    }
    return IssueCategory.envOther;
  }

  factory Issue.fromJson(Map<String, dynamic> json) {
    // —— 业务类型：优先直读，缺失则按中文类别反查（默认 ENV）——
    final rawBiz = json['businessType']?.toString() ?? '';
    final biz = (rawBiz.isNotEmpty && _validBiz(rawBiz)) ? rawBiz : _bizFromCategory(json['category']);

    // —— 类别：按中文回读，并用业务类型消歧「其他」——
    final catValue = json['category'];
    IssueCategory category;
    if (catValue is String) {
      category = Issue.fromChinese(catValue, biz);
    } else {
      // 旧数字下标兜底：直接映射（极端情况）
      category = (catValue is int && catValue >= 0 && catValue < IssueCategory.values.length)
          ? IssueCategory.values[catValue]
          : Issue.fromChinese(_oldCategoryFallback(json), biz);
    }

    // —— 科室：优先直读，缺失由业务反查 ——
    final rawDept = json['deptCode']?.toString() ?? '';
    final dept = rawDept.isNotEmpty ? rawDept : _deptFromBiz(biz);

    // 解析 severity - 支持字符串和数字
    SeverityLevel severity;
    final sevValue = json['severity'];
    if (sevValue is String) {
      switch (sevValue.trim().toLowerCase()) {
        case '一般':
        case 'general':
          severity = SeverityLevel.general;
          break;
        case '较重':
        case '较大':
        case 'serious':
          severity = SeverityLevel.serious;
          break;
        case '严重':
        case '重大':
        case 'critical':
          severity = SeverityLevel.critical;
          break;
        default:
          severity = SeverityLevel.general;
      }
    } else {
      severity = (sevValue is int && sevValue >= 0 && sevValue < SeverityLevel.values.length)
          ? SeverityLevel.values[sevValue]
          : SeverityLevel.general;
    }

    // 解析 status - 支持字符串和数字
    IssueStatus status;
    final statusValue = json['status'];
    if (statusValue is String) {
      switch (statusValue.trim().toLowerCase()) {
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
      status = (statusValue is int && statusValue >= 0 && statusValue < IssueStatus.values.length)
          ? IssueStatus.values[statusValue]
          : IssueStatus.pending;
    }

    // 解析 deadline
    DateTime deadline;
    try {
      final dl = json['deadline'] ?? json['dueDate'] ?? json['createdAt'];
      deadline = dl != null ? DateTime.parse(dl.toString()) : DateTime.now().add(const Duration(days: 3));
    } catch (_) {
      deadline = DateTime.now().add(const Duration(days: 3));
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
      rectificationNote: json['rectificationNote'] ?? json['rectification_note'],
      rejectionNote: json['rejectionNote'] ?? json['rejection_note'] ?? json['reviewNote'] ?? json['reviewerNote'],
      acceptanceNote: json['acceptanceNote'] ?? json['acceptance_comment'] ?? json['acceptanceComment'],
      rejectionHistory: (json['rejectionHistory'] as List<dynamic>?)
          ?.map((r) => RejectionRecord.fromJson(r as Map<String, dynamic>))
          .toList() ?? [],
      createdAt: createdAt,
      updatedAt: updatedAt,
      closedAt: closedAt,
      rectificationHistory: (json['rectificationHistory'] as List<dynamic>?)
          ?.map((r) => RectificationRecord.fromJson(r as Map<String, dynamic>))
          .toList() ?? [],
      businessType: biz,
      deptCode: dept,
    );
  }
}

/// 类别枚举 → 中文名（与 Issue.categoryName 一致；供无 Issue 实例处调用）
String categoryNameOf(IssueCategory category) {
  switch (category) {
    case IssueCategory.safeProcess: return '工艺';
    case IssueCategory.safeElectrical: return '电气仪表';
    case IssueCategory.safeFire: return '消防应急';
    case IssueCategory.safeEquipment: return '设备隐患';
    case IssueCategory.safeRules: return '规章制度';
    case IssueCategory.safeSpecial: return '特种设备';
    case IssueCategory.safeTraining: return '培训教育';
    case IssueCategory.safeInvest: return '安全投入';
    case IssueCategory.safeViolation: return '违章操作';
    case IssueCategory.safeHealth: return '职业卫生';
    case IssueCategory.safeConfined: return '有限空间';
    case IssueCategory.safeExternal: return '外来施工';
    case IssueCategory.safeOther: return '其他';
    case IssueCategory.savingWater: return '节水';
    case IssueCategory.savingElectric: return '节电';
    case IssueCategory.savingAir: return '压风';
    case IssueCategory.savingHydrogen: return '氢气';
    case IssueCategory.savingNitrogen: return '氮气';
    case IssueCategory.savingGas: return '燃气';
    case IssueCategory.savingEnergyEquip: return '耗能设备';
    case IssueCategory.savingProcess: return '工艺节能';
    case IssueCategory.savingWaste: return '浪费损耗';
    case IssueCategory.savingCarbon: return '碳排管理';
    case IssueCategory.envWastewater: return '废水排放';
    case IssueCategory.envWastegas: return '废气排放';
    case IssueCategory.envSolid: return '固废管理';
    case IssueCategory.envNoise: return '噪音污染';
    case IssueCategory.envOther: return '其他';
  }
}

/// 严重度枚举 → 中文名（与 Issue.severityName 一致；供无 Issue 实例处调用）
String severityNameOf(SeverityLevel severity) {
  switch (severity) {
    case SeverityLevel.general: return '一般';
    case SeverityLevel.serious: return '较大';
    case SeverityLevel.critical: return '重大';
  }
}

/// 业务 code 合法性（避免把脏值写进模型）
bool _validBiz(String code) =>
    code == 'SAFE' || code == 'SAVING' || code == 'ENV';

/// 由中文类别反查业务（默认 ENV，与桌面端一致）
String _bizFromCategory(dynamic category) {
  if (category is! String) return 'ENV';
  // 延迟引用 business_type，避免循环 import 问题（本文件已 import business_type）
  return businessOfCategoryName(category);
}

/// 由业务反查科室
String _deptFromBiz(String biz) => deptOfBusiness(biz);

/// 旧数字类别字段兜底：把数字下标转成中文再交给 fromChinese
String _oldCategoryFallback(Map<String, dynamic> json) {
  final v = json['category'];
  if (v is int && v >= 0 && v < IssueCategory.values.length) {
    return categoryNameOf(IssueCategory.values[v]);
  }
  return '';
}
