// lib/providers/ai_analysis_provider.dart
// AI 隐患识别后台任务管理
//
// 设计目标：识别很慢（模型思考可达数十秒），不能阻塞用户。
// 用户点「开始识别」后，任务在后台异步跑，用户可立即返回做其他事；
// 完成后发一条系统通知，结果持久化（本地），下次进入本页可查看/转为上报。

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/issue.dart';
import '../models/hazard_analysis.dart';
import '../services/ai_hazard_service.dart';
import '../services/notification_service.dart';
import '../services/cloudbase_service.dart';

/// 单个后台分析任务的状态
enum AiTaskStatus {
  running,
  done,
  error,
}

/// 一次后台 AI 分析任务
class AiAnalysisTask {
  final String id;
  final DateTime createdAt;
  final String? location;
  final String? note;
  final List<String> imagePaths;

  AiTaskStatus status;
  HazardAnalysis? analysis;
  bool? success;
  String? errorMessage;

  AiAnalysisTask({
    required this.id,
    required this.createdAt,
    this.location,
    this.note,
    this.imagePaths = const [],
    this.status = AiTaskStatus.running,
    this.analysis,
    this.success,
    this.errorMessage,
  });

  factory AiAnalysisTask.fromJson(Map<String, dynamic> j) {
    AiTaskStatus status;
    try {
      status = AiTaskStatus.values[j['status'] as int? ?? 0];
    } catch (_) {
      status = AiTaskStatus.error;
    }
    return AiAnalysisTask(
      id: j['id'] ?? '',
      createdAt: DateTime.tryParse(j['createdAt'] ?? '') ?? DateTime.now(),
      location: j['location'],
      note: j['note'],
      imagePaths:
          (j['imagePaths'] as List? ?? []).map((e) => e.toString()).toList(),
      status: status,
      success: j['success'],
      errorMessage: j['errorMessage'],
      analysis: j['analysis'] != null
          ? HazardAnalysis.fromJson(Map<String, dynamic>.from(j['analysis']))
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'createdAt': createdAt.toIso8601String(),
        'location': location,
        'note': note,
        'imagePaths': imagePaths,
        'status': status.index,
        'success': success,
        'errorMessage': errorMessage,
        'analysis': analysis?.toJson(),
      };
}

class AiAnalysisProvider extends ChangeNotifier {
  static const String _spKey = 'ai_analysis_tasks_v1';

  List<AiAnalysisTask> _tasks = [];

  /// 任务列表（最新在前）。含进行中与历史记录。
  List<AiAnalysisTask> get tasks => List.unmodifiable(_tasks);

  AiAnalysisProvider() {
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_spKey);
      if (raw == null) return;
      final list = jsonDecode(raw) as List;
      _tasks = list.map((e) => AiAnalysisTask.fromJson(e)).toList();
      // 上次会话未跑完的任务标记为中断（进程已不在，无法续跑）
      for (final t in _tasks) {
        if (t.status == AiTaskStatus.running) {
          t.status = AiTaskStatus.error;
          t.success = false;
          t.errorMessage = '分析在上次会话中中断，请重新识别';
        }
      }
      _tasks.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      notifyListeners();
    } catch (_) {
      // 持久化数据损坏不影响主流程
    }
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _spKey,
        jsonEncode(_tasks.map((t) => t.toJson()).toList()),
      );
    } catch (_) {}
  }

  /// 启动一次后台分析。非阻塞：立即返回，结果通过通知 + 持久化呈现。
  void startAnalysis({
    required List<File> images,
    String? location,
    String? note,
  }) {
    final task = AiAnalysisTask(
      id: 'ai_${DateTime.now().millisecondsSinceEpoch}',
      createdAt: DateTime.now(),
      location: location,
      note: note,
      imagePaths: images.map((f) => f.path).toList(),
    );
    _tasks.insert(0, task);
    _persist();
    notifyListeners();
    // 后台执行，不 await，不打断用户操作
    _run(task, images, location, note);
  }

  Future<void> _run(
    AiAnalysisTask task,
    List<File> images,
    String? location,
    String? note,
  ) async {
    try {
      final r = await AiHazardService.instance.analyze(
        images: images,
        location: location,
        note: note,
      );
      if (r.success && r.analysis != null) {
        task.status = AiTaskStatus.done;
        task.success = true;
        task.analysis = r.analysis;
      } else {
        task.status = AiTaskStatus.error;
        task.success = false;
        task.errorMessage = r.message ?? '识别未完成，可重试';
      }
      // 尝试存档到云端（跨设备查看，失败不影响本地）
      _saveToCloud(task);
    } catch (e) {
      task.status = AiTaskStatus.error;
      task.success = false;
      task.errorMessage = '分析异常：$e';
    } finally {
      _persist();
      notifyListeners();
      _notify(task);
    }
  }

  /// 完成后发系统通知（即便用户已离开本页也能收到）
  Future<void> _notify(AiAnalysisTask task) async {
    final id = task.id.hashCode.abs() % 100000;
    if (task.success == true) {
      await NotificationService.instance.showNotification(
        id: id,
        title: '✅ AI 隐患识别完成',
        body: task.analysis?.title.isNotEmpty == true
            ? '${task.analysis!.title}（${_catName(task.analysis!.category)}）'
            : '已完成，点击查看详情',
        payload: task.id,
      );
    } else {
      await NotificationService.instance.showNotification(
        id: id,
        title: '⚠️ AI 隐患识别未完成',
        body: task.errorMessage ?? '本次识别未成功，可重试',
        payload: task.id,
      );
    }
  }

  Future<void> _saveToCloud(AiAnalysisTask task) async {
    try {
      await CloudBaseService.instance.callApi(
        'add',
        collection: 'ai_analysis',
        data: {
          'taskId': task.id,
          'createdAt': task.createdAt.toIso8601String(),
          'location': task.location,
          'note': task.note,
          'success': task.success,
          'title': task.analysis?.title,
          'category': task.analysis?.category.name,
          'severity': task.analysis?.severity.name,
          'description': task.analysis?.description,
          'suggestion': task.analysis?.suggestion,
          'riskPoints': task.analysis?.riskPoints ?? [],
        },
      );
    } catch (_) {
      // 云端存档失败不影响本地结果
    }
  }

  static String _catName(dynamic cat) {
    if (cat is IssueCategory) return categoryNameOf(cat);
    return '其他';
  }
}
