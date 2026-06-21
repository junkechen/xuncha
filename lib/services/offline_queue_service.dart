// lib/services/offline_queue_service.dart
// 离线上传队列服务 - 无网络时本地缓存，有网络自动续传

import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;

class OfflineQueueService {
  static OfflineQueueService? _instance;
  static OfflineQueueService get instance {
    _instance ??= OfflineQueueService._();
    return _instance!;
  }

  OfflineQueueService._();

  // 待上传队列文件路径
  static const String _queueFileName = 'pending_uploads.json';
  String? _queueFilePath;

  // 队列项结构
  // {
  //   "queueId": "uuid",
  //   "issueId": "issue_123",
  //   "photos": [
  //     {"localPath": "/data/.../photo1.jpg", "cloudUrl": ""}
  //   ],
  //   "createdAt": "2026-04-20T10:00:00",
  //   "retryCount": 0,
  //   "lastError": ""
  // }

  List<Map<String, dynamic>> _queue = [];

  /// 初始化：加载本地队列
  Future<void> init() async {
    final dir = await getApplicationDocumentsDirectory();
    _queueFilePath = '${dir.path}/$_queueFileName';
    await _loadQueue();
    print('📦 离线队列服务初始化，待上传记录: ${_queue.length} 条');
  }

  /// 检查网络是否可用
  Future<bool> isNetworkAvailable() async {
    try {
      final result = await http.head(
        Uri.parse('https://www.baidu.com'),
      ).timeout(const Duration(seconds: 5));
      return result.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// 添加到待上传队列
  Future<void> addToQueue({
    required String issueId,
    required List<String> localPhotoPaths,
    String? cloudIssueId,
  }) async {
    final queueItem = {
      'queueId': 'q_${DateTime.now().millisecondsSinceEpoch}',
      'issueId': issueId,
      'cloudIssueId': cloudIssueId ?? issueId,
      'photos': localPhotoPaths.map((path) => {
        'localPath': path,
        'cloudUrl': '',
        'uploaded': false,
      }).toList(),
      'createdAt': DateTime.now().toIso8601String(),
      'retryCount': 0,
      'lastError': '',
    };

    _queue.add(queueItem);
    await _saveQueue();
    print('📦 已加入离线队列: issueId=$issueId, 照片${localPhotoPaths.length}张');
  }

  /// 处理整个队列（有网络时自动调用）
  Future<void> processQueue({
    required Future<String?> Function(String filePath, String fileName) uploadCallback,
  }) async {
    if (_queue.isEmpty) return;

    final networkOk = await isNetworkAvailable();
    if (!networkOk) {
      print('📡 网络不可用，跳过队列处理');
      return;
    }

    print('📡 检测到网络，尝试处理离线队列（${_queue.length}条）...');

    // 逐项处理
    final stillPending = <Map<String, dynamic>>[];

    for (final item in _queue) {
      final photos = List<Map<String, dynamic>>.from(item['photos'] as List);
      int uploadedCount = 0;

      for (int i = 0; i < photos.length; i++) {
        final photo = photos[i];
        if (photo['uploaded'] == true) continue;

        final localPath = photo['localPath'] as String;
        final file = File(localPath);

        if (!await file.exists()) {
          print('⚠️ 本地文件不存在，跳过: $localPath');
          photo['uploaded'] = true; // 标记跳过
          continue;
        }

        try {
          final cloudUrl = await uploadCallback(
            localPath,
            'hazard_${item['queueId']}_$i.jpg',
          );

          if (cloudUrl != null && cloudUrl.isNotEmpty) {
            photo['cloudUrl'] = cloudUrl;
            photo['uploaded'] = true;
            uploadedCount++;
            print('✅ 离线队列照片上传成功: $cloudUrl');
          } else {
            photo['uploaded'] = false;
            print('⚠️ 离线队列照片上传失败（空URL）');
          }
        } catch (e) {
          photo['uploaded'] = false;
          item['lastError'] = e.toString();
          print('❌ 离线队列照片上传异常: $e');
        }
      }

      // 更新重试计数
      item['retryCount'] = (item['retryCount'] as int) + 1;

      // 如果所有照片都上传成功，从队列移除；否则保留
      final allUploaded = photos.every((p) => p['uploaded'] == true);
      if (allUploaded) {
        print('✅ 队列项全部上传完成，移除: ${item['issueId']}');
      } else {
        stillPending.add(item);
      }
    }

    _queue = stillPending;
    await _saveQueue();
    print('📦 队列处理完成，剩余待上传: ${_queue.length} 条');
  }

  /// 获取待上传数量
  int get pendingCount => _queue.length;

  /// 获取待上传照片总数
  int get pendingPhotoCount {
    int count = 0;
    for (var item in _queue) {
      final photos = item['photos'] as List;
      count += photos.where((p) => p['uploaded'] != true).length;
    }
    return count;
  }

  /// 获取队列摘要
  List<Map<String, dynamic>> getQueueSummary() {
    return _queue.map((item) => {
      'issueId': item['issueId'],
      'photoCount': (item['photos'] as List).length,
      'createdAt': item['createdAt'],
      'retryCount': item['retryCount'],
    }).toList();
  }

  /// 手动触发一次队列处理（由外部如 home_screen 在网络恢复时调用）
  Future<int> triggerProcess({
    required Future<String?> Function(String filePath, String fileName) uploadCallback,
  }) async {
    final before = pendingPhotoCount;
    await processQueue(uploadCallback: uploadCallback);
    final after = pendingPhotoCount;
    return before - after; // 返回本次成功上传的数量
  }

  // ---- 私有方法 ----

  Future<void> _loadQueue() async {
    try {
      if (_queueFilePath == null) return;
      final file = File(_queueFilePath!);
      if (await file.exists()) {
        final content = await file.readAsString();
        final data = jsonDecode(content);
        _queue = List<Map<String, dynamic>>.from(data as List);
        print('📦 从本地加载离线队列: ${_queue.length} 条');
      }
    } catch (e) {
      print('❌ 加载离线队列失败: $e');
      _queue = [];
    }
  }

  Future<void> _saveQueue() async {
    try {
      if (_queueFilePath == null) return;
      final file = File(_queueFilePath!);
      await file.writeAsString(jsonEncode(_queue));
      print('💾 离线队列已保存: ${_queue.length} 条');
    } catch (e) {
      print('❌ 保存离线队列失败: $e');
    }
  }
}
