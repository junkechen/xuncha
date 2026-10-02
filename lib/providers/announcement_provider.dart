// lib/providers/announcement_provider.dart
// 公告状态管理 - 缓存优先 + 静默刷新 + 本地分页 + 已读/未读
//
// 首屏策略：先读本地缓存立即渲染（0 网络等待），再静默请求云端刷新；
// 缓存为空时才显示 Loading。下拉刷新则强制走云端。
//
// 已读策略（复用催办已读的三层防护思路，避免重蹈「重复提示」类缺陷）：
//  1. 已读集合本地持久化（按 userId 隔离），UI 立即反馈，不依赖云端返回；
//  2. 云端上报失败即入队，网络恢复后自动重试；
//  3. 上报采用「先查后插」幂等写入，重复提交不会产生重复已读记录。

import 'package:flutter/foundation.dart';

import '../config/dept.dart';
import '../models/announcement.dart';
import '../services/announcement_service.dart';

class AnnouncementProvider extends ChangeNotifier {
  final AnnouncementService _service = AnnouncementService.instance;

  List<Announcement> _visible = [];
  bool _isLoading = false;
  bool _isRefreshing = false;
  String? _error;
  final Set<String> _readIds = {};
  final Map<String, int> _readCounts = {};
  String _currentUserId = '';
  // 【D-6 修复】当前科室，用于公告定向过滤（空 targetDept 仍全员可见）。
  String _deptCode = AppDept.defaultCode;

  int _pageSize = 15;
  int _displayCount = 15;
  DateTime? _lastRefreshAt;
  bool _fromCache = false;
  bool _disposed = false;

  /// 静默刷新的最小间隔：避免反复进出页面造成无谓请求
  static const Duration _minRefreshInterval = Duration(seconds: 30);

  // ================= getters =================

  bool get isLoading => _isLoading;
  bool get isRefreshing => _isRefreshing;
  String? get error => _error;
  bool get fromCache => _fromCache;
  DateTime? get lastRefreshAt => _lastRefreshAt;

  /// 当前分页应展示的公告（置顶在前，已过滤草稿/过期/已删除）
  List<Announcement> get announcements {
    if (_displayCount >= _visible.length) return _visible;
    return _visible.sublist(0, _displayCount);
  }

  bool get hasMore => _displayCount < _visible.length;
  bool get isEmpty => _visible.isEmpty && !_isLoading;

  /// 未读数量（用于首页角标）
  int get unreadCount =>
      _visible.where((a) => !_readIds.contains(a.id)).length;

  bool isRead(String id) => _readIds.contains(id);
  int readCount(String id) => _readCounts[id] ?? 0;

  /// 安全通知：避免异步回调在 dispose 之后触发
  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }

  /// 供 UI 主动触发刷新（如从详情页返回时同步未读状态）
  void notifyChange() => _notify();

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  // ================= 用户切换 =================

  /// 设置当前用户：切换账号时清空旧数据，防止串号
  Future<void> setCurrentUser(String userId) async {
    if (_currentUserId == userId && _visible.isNotEmpty) return;
    _currentUserId = userId;
    _deptCode = await AppDept.current();
    _visible = [];
    _readIds.clear();
    _readCounts.clear();
    _displayCount = _pageSize;
    _error = null;
    _lastRefreshAt = null;

    if (userId.isEmpty) {
      _notify();
      return;
    }
    // 先恢复本地已读集合，保证首屏未读状态正确
    final ids = await _service.loadReadIds(userId);
    _readIds
      ..clear()
      ..addAll(ids);
    print('📖 已加载 ${_readIds.length} 条本地已读公告 (user=$userId)');
    _notify();
  }

  // ================= 加载 =================

  /// 首屏加载：优先读缓存渲染，再静默刷新
  Future<void> loadFirstPage({bool force = false}) async {
    if (_currentUserId.isEmpty) return;
    _deptCode = await AppDept.current(); // 【D-6】切换科室后刷新定向基准

    // 1) 先读缓存，让首屏立刻有内容
    final cached = await _service.loadCache();
    if (cached != null && cached.isNotEmpty) {
      _applyList(cached);
      _fromCache = true;
      _error = null;
      _isLoading = false;
      _notify();
    } else {
      _isLoading = true;
      _fromCache = false;
      _notify();
    }

    // 2) 静默刷新（有缓存时不打断用户；无缓存时这次请求即为首屏数据）
    if (force || _shouldSilentRefresh()) {
      await _fetchAndApply(silent: cached != null && cached.isNotEmpty);
    }

    _isLoading = false;
    _notify();

    // 3) 顺带重试此前失败的已读上报
    await retryPendingReads();
  }

  /// 下拉刷新：强制走云端
  Future<void> refresh() async {
    if (_currentUserId.isEmpty) return;
    _isRefreshing = true;
    _error = null;
    _notify();
    await _fetchAndApply(silent: false);
    _isRefreshing = false;
    _notify();
  }

  bool _shouldSilentRefresh() {
    if (_lastRefreshAt == null) return true;
    return DateTime.now().difference(_lastRefreshAt!) > _minRefreshInterval;
  }

  Future<void> _fetchAndApply({required bool silent}) async {
    try {
      final list = await _service.fetchAnnouncements();
      if (list == null) {
        // 请求失败：保留缓存内容，仅在没有数据时提示
        if (_visible.isEmpty) {
          _error = '加载失败，请下拉重试';
        } else {
          print('⚠️ 公告刷新失败，保留缓存内容展示');
        }
        return;
      }

      _applyList(list);
      _fromCache = false;
      _error = null;
      _lastRefreshAt = DateTime.now();
      await _service.saveCache(list);
      await _loadReadCounts();
    } catch (e) {
      print('❌ 公告加载异常: $e');
      if (_visible.isEmpty) _error = '加载失败，请下拉重试';
    } finally {
      if (silent) _notify();
    }
  }

  /// 应用数据：过滤（已发布+未过期+未删除）→ 排序（置顶优先）→ 重置分页
  void _applyList(List<Announcement> raw) {
    // 【D-6 修复】按科室定向：targetDept 非空且不含当前科室的公告隐藏。
    final scoped = raw.where((a) {
      final td = a.targetDept;
      if (td == null || td.isEmpty) return true; // 历史公告全员可见
      return td.contains(_deptCode);
    }).toList();
    _visible = Announcement.sortedForDisplay(
      Announcement.visibleOnly(scoped),
    );
    if (_displayCount < _pageSize) _displayCount = _pageSize;
  }

  Future<void> _loadReadCounts() async {
    if (_visible.isEmpty) return;
    try {
      final ids = _visible.map((a) => a.id).toList();
      final counts = await _service.fetchReadCounts(ids);
      if (counts.isNotEmpty) {
        _readCounts
          ..clear()
          ..addAll(counts);
        _notify();
      }
    } catch (e) {
      print('⚠️ 加载阅读量失败: $e');
    }
  }

  // ================= 分页 =================

  /// 上拉加载更多（本地分页，云端一次取全量，与电脑端一致）
  void loadMore() {
    if (!hasMore) return;
    _displayCount = (_displayCount + _pageSize).clamp(0, _visible.length);
    _notify();
  }

  // ================= 已读 =================

  /// 标记已读：本地立即生效并持久化，再异步上报云端（失败入队重试）
  Future<void> markAsRead(String id) async {
    if (id.isEmpty || _currentUserId.isEmpty) return;
    if (_readIds.contains(id)) return;

    // 1) 本地立即标记并持久化 —— 即使此刻断网，用户看到的已读状态也不会丢
    _readIds.add(id);
    await _service.saveReadIds(_currentUserId, _readIds);
    _readCounts[id] = (_readCounts[id] ?? 0) + 1;
    _notify();

    // 2) 异步上报；失败则入队，等网络恢复后自动重试
    final ok = await _service.markReadRemote(
      announcementId: id,
      userId: _currentUserId,
    );
    if (!ok) {
      await _service.enqueuePendingRead(
        announcementId: id,
        userId: _currentUserId,
      );
    }
  }

  /// 重试此前失败的已读上报（进入公告页 / 网络恢复时调用）
  Future<int> retryPendingReads() async {
    if (_currentUserId.isEmpty) return 0;
    try {
      final success = await _service.processPendingReads();
      if (success > 0) {
        await _loadReadCounts();
        _notify();
      }
      return success;
    } catch (e) {
      print('⚠️ 重试已读上报失败: $e');
      return 0;
    }
  }
}
