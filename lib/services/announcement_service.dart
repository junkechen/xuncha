// lib/services/announcement_service.dart
// 公告服务层 - 云端读取 + 本地缓存 + 已读上报（幂等）+ 断网重试队列
//
// 设计约束：
//  1. 不改动云同步核心文件（cloudbase_service.dart 等），统一通过
//     CloudBaseService.instance.callApi 访问云端，与工程既有调用方式一致。
//  2. 网络检测复用既有 OfflineQueueService.instance.isNetworkAvailable()，
//     不重复实现同类能力。
//  3. 已读上报采用「先查后插」：云端已有该 (公告,用户) 的 read 文档则直接跳过，
//     因此重复提交不会产生重复记录 —— 这是断网重试不重复写入的关键。
//  4. 本地缓存用 SharedPreferences（工程既有本地存储方案）。

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../config/constants.dart';
import '../models/announcement.dart';
import 'cloudbase_service.dart';
import 'offline_queue_service.dart';

class AnnouncementService {
  AnnouncementService._();

  static AnnouncementService? _instance;
  static AnnouncementService get instance {
    _instance ??= AnnouncementService._();
    return _instance!;
  }

  // ---- 本地存储 key ----
  // 公告内容对全员一致（仅展示已发布公告），缓存按全局共享即可
  static const String _cacheKey = 'gz_ann_cache_v1';
  // 已读集合必须按用户隔离，避免切换账号后串号（与催办 _localReadIds 同样的处理）
  static const String _readIdsKeyPrefix = 'gz_ann_read_ids_';
  // 已读上报重试队列（每条自带 userId，全局存储）
  static const String _pendingKey = 'gz_ann_pending_reads_v1';

  /// 单条已读上报最大重试次数，超过则丢弃（本地已读状态仍保留，不会丢用户感知）
  static const int maxRetry = 5;

  /// 缓存体积上限（字节）。公告正文可能较长，超过则放弃缓存，
  /// 避免 SharedPreferences 膨胀影响其它模块读写性能。
  static const int _cacheSizeLimit = 1024 * 1024; // 1MB

  // ================= 云端读取 =================

  /// 拉取公告列表（docType=announcement）
  /// 与电脑端一致：按 docType 过滤，避免把基数更大的 read/audit 文档一起拉回来。
  /// 返回 null 表示请求失败（调用方应保留缓存）；返回空列表表示云端确无公告。
  Future<List<Announcement>?> fetchAnnouncements() async {
    try {
      final result = await CloudBaseService.instance.callApi(
        'query',
        collection: AppConstants.announcementCollection,
        query: {'docType': AnnDocType.announcement},
      );

      if (result['code'] == 0 && result['data'] != null) {
        final data = result['data'];
        if (data is List) {
          final list = data
              .whereType<Map>()
              .map((e) => Announcement.fromJson(Map<String, dynamic>.from(e)))
              .toList();
          print('📢 拉取到 ${list.length} 条公告文档');
          return list;
        }
      }
      print('⚠️ 拉取公告失败: code=${result['code']}, msg=${result['message']}');
      return null;
    } catch (e) {
      print('❌ 拉取公告异常: $e');
      return null;
    }
  }

  /// 批量统计阅读量：返回 { announcementId: 阅读人数 }
  /// 用 $in 精确拉取，避免把整个 read 集合拉回客户端。
  Future<Map<String, int>> fetchReadCounts(List<String> ids) async {
    if (ids.isEmpty) return {};
    try {
      final result = await CloudBaseService.instance.callApi(
        'query',
        collection: AppConstants.announcementCollection,
        query: {
          'docType': AnnDocType.read,
          'announcementId': {r'$in': ids},
        },
      );

      if (result['code'] == 0 && result['data'] != null) {
        final data = result['data'];
        if (data is List) {
          final counts = <String, int>{};
          for (final item in data) {
            if (item is! Map) continue;
            final aid = item['announcementId']?.toString();
            if (aid == null || aid.isEmpty) continue;
            counts[aid] = (counts[aid] ?? 0) + 1;
          }
          return counts;
        }
      }
      return {};
    } catch (e) {
      print('❌ 统计阅读量异常: $e');
      return {};
    }
  }

  /// 标记已读（先查后插，幂等）
  /// 返回 true 表示云端已存在或写入成功；false 表示需要重试。
  Future<bool> markReadRemote({
    required String announcementId,
    required String userId,
  }) async {
    try {
      // 1) 先查：已存在则直接视为成功（幂等，重复调用不会新增记录）
      final exist = await CloudBaseService.instance.callApi(
        'query',
        collection: AppConstants.announcementCollection,
        query: {
          'docType': AnnDocType.read,
          'announcementId': announcementId,
          'userId': userId,
        },
      );
      if (exist['code'] == 0 && exist['data'] != null) {
        final data = exist['data'];
        if (data is List && data.isNotEmpty) {
          print('📖 已读记录已存在，跳过写入（幂等）: $announcementId');
          return true;
        }
      }

      // 2) 后插
      final added = await CloudBaseService.instance.callApi(
        'add',
        collection: AppConstants.announcementCollection,
        data: {
          'docType': AnnDocType.read,
          'announcementId': announcementId,
          'userId': userId,
          'readAt': DateTime.now().toIso8601String(),
        },
      );
      if (added['code'] == 0) {
        print('✅ 已读状态已同步云端: $announcementId');
        return true;
      }
      print('⚠️ 已读同步失败: code=${added['code']}, msg=${added['message']}');
      return false;
    } catch (e) {
      print('❌ 已读同步异常: $e');
      return false;
    }
  }

  // ================= 本地缓存 =================

  /// 读取缓存的公告列表；无缓存返回 null
  Future<List<Announcement>?> loadCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey);
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final list = decoded['list'];
      if (list is! List) return null;
      return list
          .whereType<Map>()
          .map((e) => Announcement.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (e) {
      print('⚠️ 读取公告缓存失败: $e');
      return null;
    }
  }

  /// 缓存写入时间戳（毫秒），无缓存返回 null
  Future<int?> cacheSavedAt() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey);
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is Map && decoded['savedAt'] is int) {
        return decoded['savedAt'] as int;
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// 写入缓存（超过体积上限则放弃，避免拖慢 SharedPreferences）
  Future<void> saveCache(List<Announcement> list) async {
    try {
      final payload = jsonEncode({
        'savedAt': DateTime.now().millisecondsSinceEpoch,
        'list': list.map((a) => a.toJson()).toList(),
      });
      if (payload.length > _cacheSizeLimit) {
        print('⚠️ 公告缓存体积 ${(payload.length / 1024).toInt()}KB 超限，跳过缓存');
        return;
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cacheKey, payload);
      print('💾 公告已缓存 ${list.length} 条（${(payload.length / 1024).toInt()}KB）');
    } catch (e) {
      print('❌ 写入公告缓存失败: $e');
    }
  }

  // ================= 本地已读集合 =================

  Future<Set<String>> loadReadIds(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ids = prefs.getStringList('$_readIdsKeyPrefix$userId') ?? [];
      return ids.toSet();
    } catch (e) {
      print('⚠️ 加载本地已读公告失败: $e');
      return {};
    }
  }

  Future<void> saveReadIds(String userId, Set<String> ids) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('$_readIdsKeyPrefix$userId', ids.toList());
    } catch (e) {
      print('❌ 保存本地已读公告失败: $e');
    }
  }

  // ================= 已读上报重试队列 =================

  Future<List<Map<String, dynamic>>> _loadPending() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_pendingKey);
      if (raw == null || raw.isEmpty) return [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    } catch (e) {
      print('⚠️ 加载已读重试队列失败: $e');
      return [];
    }
  }

  Future<void> _savePending(List<Map<String, dynamic>> queue) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_pendingKey, jsonEncode(queue));
    } catch (e) {
      print('❌ 保存已读重试队列失败: $e');
    }
  }

  /// 入队（同 (公告,用户) 去重，避免重复提交）
  Future<void> enqueuePendingRead({
    required String announcementId,
    required String userId,
  }) async {
    if (announcementId.isEmpty || userId.isEmpty) return;
    final queue = await _loadPending();
    final dup = queue.any((e) =>
        e['announcementId']?.toString() == announcementId &&
        e['userId']?.toString() == userId);
    if (dup) {
      print('📦 已读上报已排队，跳过重复入队: $announcementId');
      return;
    }
    queue.add({
      'announcementId': announcementId,
      'userId': userId,
      'createdAt': DateTime.now().toIso8601String(),
      'retryCount': 0,
    });
    await _savePending(queue);
    print('📦 已读上报已入队（网络恢复后自动重试）: $announcementId');
  }

  /// 处理队列；返回本次成功上报的条数
  /// 幂等由 markReadRemote 的「先查后插」保证，即使队列里存在重复项也不会写重。
  Future<int> processPendingReads() async {
    final queue = await _loadPending();
    if (queue.isEmpty) return 0;

    // 复用既有网络检测，不重复实现
    final online = await OfflineQueueService.instance.isNetworkAvailable();
    if (!online) {
      print('📡 网络不可用，已读上报队列保留（${queue.length} 条）');
      return 0;
    }

    print('📡 网络恢复，处理已读上报队列（${queue.length} 条）...');
    final remaining = <Map<String, dynamic>>[];
    var success = 0;

    for (final item in queue) {
      final aid = item['announcementId']?.toString() ?? '';
      final uid = item['userId']?.toString() ?? '';
      if (aid.isEmpty || uid.isEmpty) continue;

      final ok = await markReadRemote(announcementId: aid, userId: uid);
      if (ok) {
        success++;
      } else {
        final retry = (item['retryCount'] as int? ?? 0) + 1;
        if (retry < maxRetry) {
          item['retryCount'] = retry;
          remaining.add(item);
        } else {
          print('⚠️ 已读上报超过最大重试次数，丢弃: $aid（本地已读状态保留）');
        }
      }
    }

    await _savePending(remaining);
    print('✅ 已读上报队列处理完成，成功 $success 条，剩余 ${remaining.length} 条');
    return success;
  }

  Future<int> get pendingCount async => (await _loadPending()).length;
}
