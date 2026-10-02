// lib/models/announcement.dart
// 公告数据模型 - 字段与电脑端 env_inspection_desktop/app/js/announcement.js 对齐
//
// 云端约束（与电脑端一致，勿改）：
//  1. 云端只有一个 announcement 集合，用 docType 区分 announcement / read / audit
//     （云函数无 createCollection，建集合只能人工在控制台做）
//  2. 云端无 remove 动作 → 删除一律软删除 isDeleted:true
//  3. 云端无 updateMany → 批量操作只能逐条
//
// 移动端定位：查看端。仅展示「已发布 + 未过期 + 未删除」的公告，
// 发布/编辑/删除/置顶操作仍在电脑端完成。

/// 文档类型（单集合内区分用途）
class AnnDocType {
  static const String announcement = 'announcement';
  static const String read = 'read';
  static const String audit = 'audit';
}

/// 公告状态
class AnnStatus {
  static const String draft = 'draft';
  static const String published = 'published';
  static const String archived = 'archived';
}

/// 公告分类（预留字段，key 与电脑端 CATEGORY_MAP 完全一致）
const Map<String, String> announcementCategories = {
  'notice': '通知公告',
  'regulation': '制度规范',
  'safety': '安全警示',
  'training': '培训活动',
  'holiday': '节假日安排',
  'other': '其他',
};

/// 置顶数量上限（与电脑端 MAX_PINNED 一致，移动端仅用于展示提示）
const int maxPinnedAnnouncements = 3;

class Announcement {
  final String id;
  final String docType;
  final String title;
  /// 正文，富文本 HTML（渲染前必须经 announcement_html.dart 消毒）
  final String content;
  final String category;
  final String status;
  final bool pinned;
  /// 过期时间，为空表示长期有效
  final DateTime? expireAt;
  final List<String> attachments;
  final bool isDeleted;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? publishedAt;
  final DateTime? pinnedAt;
  final String authorName;
  // 【D-6 修复】公告定向：为空表示全员可见；非空时仅列表内科室可见。
  final List<String> targetDept;

  const Announcement({
    required this.id,
    required this.docType,
    required this.title,
    required this.content,
    required this.category,
    required this.status,
    required this.pinned,
    required this.expireAt,
    required this.attachments,
    required this.isDeleted,
    required this.createdAt,
    required this.updatedAt,
    required this.publishedAt,
    required this.pinnedAt,
    required this.authorName,
    this.targetDept = const [],
  });

  // ---------- 时间解析 ----------
  // 云端字段可能是 ISO 字符串，也可能是毫秒时间戳（数字或纯数字字符串），统一兼容
  static DateTime? _parseTime(dynamic v) {
    if (v == null) return null;
    if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
    if (v is num) return DateTime.fromMillisecondsSinceEpoch(v.toInt());
    final s = v.toString().trim();
    if (s.isEmpty) return null;
    if (RegExp(r'^\d+$').hasMatch(s)) {
      return DateTime.fromMillisecondsSinceEpoch(int.parse(s));
    }
    return DateTime.tryParse(s);
  }

  static String _str(dynamic v) => v == null ? '' : v.toString();

  static bool _bool(dynamic v) => v == true || v == 'true';

  /// 附件兼容两种写法：['url1','url2'] 或 [{'url':..,'name':..}]
  static List<String> _parseAttachments(dynamic v) {
    if (v is! List) return const [];
    final out = <String>[];
    for (final item in v) {
      if (item is String) {
        if (item.trim().isNotEmpty) out.add(item.trim());
      } else if (item is Map) {
        final url = _str(item['url'] ?? item['src'] ?? item['fileId']);
        if (url.isNotEmpty) out.add(url);
      }
    }
    return out;
  }

  /// 公告定向科室：空/缺失表示全员可见
  static List<String> _parseTargetDept(dynamic v) {
    if (v is! List) return const [];
    return v.whereType<String>().where((s) => s.isNotEmpty).toList();
  }

  /// 字段兜底：云端脏数据/历史文档缺字段时统一补齐，避免渲染层到处判空
  factory Announcement.fromJson(Map<String, dynamic> json) {
    final j = json;
    final created = _parseTime(j['createdAt']);
    final published = _parseTime(j['publishedAt']);
    return Announcement(
      id: _str(j['_id'] ?? j['id']),
      docType: _str(j['docType']).isEmpty ? AnnDocType.announcement : _str(j['docType']),
      title: _str(j['title']),
      content: _str(j['content']),
      category: _str(j['category']).isEmpty ? 'other' : _str(j['category']),
      status: _str(j['status']).isEmpty ? AnnStatus.draft : _str(j['status']),
      pinned: _bool(j['pinned']),
      expireAt: _parseTime(j['expireAt']),
      attachments: _parseAttachments(j['attachments']),
      isDeleted: _bool(j['isDeleted']) || _str(j['status']) == 'deleted',
      createdAt: created,
      updatedAt: _parseTime(j['updatedAt']) ?? created,
      publishedAt: published,
      pinnedAt: _parseTime(j['pinnedAt']),
      authorName: _str(j['authorName']),
      targetDept: _parseTargetDept(j['targetDept']),
    );
  }

  Map<String, dynamic> toJson() => {
        '_id': id,
        'docType': docType,
        'title': title,
        'content': content,
        'category': category,
        'status': status,
        'pinned': pinned,
        'expireAt': expireAt?.toIso8601String(),
        'attachments': attachments,
        'isDeleted': isDeleted,
        'createdAt': createdAt?.toIso8601String(),
        'updatedAt': updatedAt?.toIso8601String(),
        'publishedAt': publishedAt?.toIso8601String(),
        'pinnedAt': pinnedAt?.toIso8601String(),
        'authorName': authorName,
        'targetDept': targetDept,
      };

  // ---------- 状态判定 ----------

  /// 是否已过期（无 expireAt 视为长期有效）
  bool isExpired({DateTime? now}) {
    if (expireAt == null) return false;
    return !expireAt!.isAfter(now ?? DateTime.now());
  }

  bool get isPinned => pinned;

  /// 移动端是否展示：已发布 + 未过期 + 未删除
  bool isVisible({DateTime? now}) {
    if (isDeleted) return false;
    if (status != AnnStatus.published) return false;
    return !isExpired(now: now);
  }

  /// 展示用状态文案（与电脑端 statusText 一致）
  String statusText({DateTime? now}) {
    if (isDeleted) return '已删除';
    if (status == AnnStatus.draft) return '草稿';
    if (status == AnnStatus.archived) return '已归档';
    return isExpired(now: now) ? '已过期' : '已发布';
  }

  String get categoryText => announcementCategories[category] ?? '其他';

  /// 列表展示时间：优先发布时间，无则创建时间
  DateTime? get displayTime => publishedAt ?? createdAt;

  /// 正文纯文本预览（列表副标题用，避免直接展示 HTML 源码）
  String get plainTextPreview {
    var s = content;
    // 块级标签转空格，避免段落首尾粘连
    s = s.replaceAllMapped(
      RegExp(r'<\s*(br|hr)\s*/?\s*>', caseSensitive: false),
      (_) => ' ',
    );
    s = s.replaceAllMapped(
      RegExp(r'<\s*/\s*(p|div|li|h[1-6]|tr|blockquote|pre)\s*>', caseSensitive: false),
      (_) => ' ',
    );
    s = s.replaceAll(RegExp(r'<[^>]*>'), '');
    s = s
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'");
    return s.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// 是否带图片（含正文内 img 或附件）
  bool get hasImage {
    if (attachments.isNotEmpty) return true;
    return RegExp(r'<img\b', caseSensitive: false).hasMatch(content);
  }

  Announcement copyWith({
    String? id,
    String? title,
    String? content,
    String? category,
    String? status,
    bool? pinned,
    DateTime? expireAt,
    List<String>? attachments,
    bool? isDeleted,
    String? authorName,
    List<String>? targetDept,
  }) {
    return Announcement(
      id: id ?? this.id,
      docType: docType,
      title: title ?? this.title,
      content: content ?? this.content,
      category: category ?? this.category,
      status: status ?? this.status,
      pinned: pinned ?? this.pinned,
      expireAt: expireAt ?? this.expireAt,
      attachments: attachments ?? this.attachments,
      isDeleted: isDeleted ?? this.isDeleted,
      createdAt: createdAt,
      updatedAt: updatedAt,
      publishedAt: publishedAt,
      pinnedAt: pinnedAt,
      authorName: authorName ?? this.authorName,
      targetDept: targetDept ?? this.targetDept,
    );
  }

  // ---------- 排序 ----------
  // 规则与电脑端 sortAnnouncements 一致：
  //   置顶优先（同置顶按 pinnedAt 倒序，后置顶的排前面）→ 按发布时间倒序（无则创建时间）
  static List<Announcement> sortedForDisplay(List<Announcement> list) {
    final arr = List<Announcement>.of(list);
    arr.sort((x, y) {
      final px = x.isPinned ? 1 : 0;
      final py = y.isPinned ? 1 : 0;
      if (px != py) return py - px; // 置顶在前
      if (px == 1) {
        final tx = x.pinnedAt?.millisecondsSinceEpoch ?? 0;
        final ty = y.pinnedAt?.millisecondsSinceEpoch ?? 0;
        if (tx != ty) return ty - tx; // 后置顶的排前面
      }
      final ax = x.publishedAt?.millisecondsSinceEpoch;
      final bx = y.publishedAt?.millisecondsSinceEpoch;
      final va = ax ?? x.createdAt?.millisecondsSinceEpoch ?? 0;
      final vb = bx ?? y.createdAt?.millisecondsSinceEpoch ?? 0;
      return vb - va; // 时间倒序
    });
    return arr;
  }

  /// 过滤出移动端可展示的公告（已发布 + 未过期 + 未删除）
  static List<Announcement> visibleOnly(
    List<Announcement> list, {
    DateTime? now,
  }) {
    final n = now ?? DateTime.now();
    return list.where((a) => a.isVisible(now: n)).toList();
  }
}
