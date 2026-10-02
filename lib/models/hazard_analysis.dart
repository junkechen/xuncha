// lib/models/hazard_analysis.dart
// AI 隐患识别分析结果模型
//
// Qwen3.5-4B 不支持原生结构化输出，返回内容可能出现：
// 被 ```json 围栏包裹、前后夹杂解释文字、字段名大小写不一、
// 枚举值用中文而非英文、数值是字符串、甚至截断。
// 因此本文件的解析全部做容错处理，任何单点异常都不允许抛出，
// 解析不出来就降级为原始文本，绝不阻塞隐患上报。

import 'issue.dart';

/// AI 隐患识别结果
class HazardAnalysis {
  /// 是否识别到隐患
  final bool hasHazard;

  /// 隐患标题
  final String title;

  /// 隐患分类（可直接回填上报表单）
  final IssueCategory category;

  /// 业务类型（SAFE/SAVING/ENV，由云函数新 scheme 返回，可直接回填业务选择框）
  final String businessType;

  /// 严重程度（可直接回填上报表单）
  final SeverityLevel severity;

  /// 现场隐患客观描述
  final String description;

  /// 具体风险点
  final List<String> riskPoints;

  /// 整改建议
  final String suggestion;

  /// 置信度 0~1
  final double confidence;

  /// 解析失败时保留的原始文本，用于降级展示
  final String? rawText;

  const HazardAnalysis({
    required this.hasHazard,
    required this.title,
    required this.category,
    this.businessType = '',
    required this.severity,
    required this.description,
    this.riskPoints = const [],
    required this.suggestion,
    this.confidence = 0,
    this.rawText,
  });

  /// 是否可用于回填（识别到隐患且有实际内容）
  bool get isValid =>
      hasHazard && (title.trim().isNotEmpty || description.trim().isNotEmpty);

  /// 是否为降级结果（未能解析成结构化数据）
  bool get isFallback => rawText != null;

  /// 置信度百分比文案
  String get confidencePercent => '${(confidence * 100).round()}%';

  factory HazardAnalysis.fromJson(Map<String, dynamic> json) {
    final businessType = _parseString(json['businessType']);
    return HazardAnalysis(
      // 模型漏返 hasHazard 时，安全默认"无隐患"，避免误报（isFallback 会走降级展示）
      hasHazard: _parseBool(json['hasHazard'], defaultValue: false),
      title: _parseString(json['title']),
      category: _parseCategory(json['category'], businessType),
      businessType: businessType,
      severity: _parseSeverity(json['severity']),
      description: _parseString(json['description']),
      riskPoints: _parseStringList(json['riskPoints']),
      suggestion: _parseString(json['suggestion']),
      confidence: _parseConfidence(json['confidence']),
    );
  }

  /// 解析失败时的降级结果：保留原文，供 UI 展示，不阻塞流程
  factory HazardAnalysis.fallback(String rawText) {
    return HazardAnalysis(
      hasHazard: false,
      title: '',
      category: IssueCategory.envOther,
      severity: SeverityLevel.general,
      description: rawText,
      riskPoints: const [],
      suggestion: '',
      confidence: 0,
      rawText: rawText,
    );
  }

  /// 从云函数返回体解析
  /// 云函数成功时返回 { code: 0, analysis: {...}, raw: '...' }
  static HazardAnalysis? fromCloudResult(Map<String, dynamic>? result) {
    if (result == null) return null;

    final analysis = result['analysis'];
    if (analysis is Map<String, dynamic>) {
      return HazardAnalysis.fromJson(analysis);
    }
    if (analysis is Map) {
      return HazardAnalysis.fromJson(Map<String, dynamic>.from(analysis));
    }

    // 云函数也没解析出来，但有原始文本 → 降级展示
    final raw = result['raw']?.toString();
    if (raw != null && raw.trim().isNotEmpty) {
      return HazardAnalysis.fallback(raw);
    }
    return null;
  }

  /// 序列化为 JSON（供后台分析任务持久化）
  Map<String, dynamic> toJson() => {
        'hasHazard': hasHazard,
        'title': title,
        'category': categoryNameOf(category),
        'businessType': businessType,
        'severity': severity.name,
        'description': description,
        'riskPoints': riskPoints,
        'suggestion': suggestion,
        'confidence': confidence,
        'rawText': rawText,
      };

  // ==================== 容错解析工具 ====================

  static bool _parseBool(dynamic value, {required bool defaultValue}) {
    if (value == null) return defaultValue;
    if (value is bool) return value;
    if (value is num) return value != 0;
    final s = value.toString().trim().toLowerCase();
    if (const ['true', 'yes', '1', '是', '有'].contains(s)) return true;
    if (const ['false', 'no', '0', '否', '无'].contains(s)) return false;
    return defaultValue;
  }

  static String _parseString(dynamic value) {
    if (value == null) return '';
    return value.toString().trim();
  }

  static double _parseConfidence(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value.clamp(0.0, 1.0).toDouble();
    final parsed = double.tryParse(value.toString());
    if (parsed == null) return 0;
    return parsed.clamp(0.0, 1.0).toDouble();
  }

  static List<String> _parseStringList(dynamic value) {
    if (value == null) return const [];
    if (value is List) {
      return value
          .map((e) => e.toString().trim())
          .where((s) => s.isNotEmpty)
          .toList();
    }
    final s = value.toString().trim();
    return s.isEmpty ? const [] : [s];
  }

  static IssueCategory _parseCategory(dynamic value, [String businessType = '']) {
    // 兼容旧数字下标
    if (value is int && value >= 0 && value < IssueCategory.values.length) {
      return IssueCategory.values[value];
    }
    if (value == null) return IssueCategory.envOther;
    final s = value.toString().trim();
    if (s.isEmpty) return IssueCategory.envOther;
    // 统一走 issue.dart 的中文→枚举解析（覆盖新类别 + 旧别名 + 「其他」业务消歧）
    return Issue.fromChinese(s, businessType);
  }

  static SeverityLevel _parseSeverity(dynamic value) {
    // 兼容数字下标
    if (value is int && value >= 0 && value < SeverityLevel.values.length) {
      return SeverityLevel.values[value];
    }
    if (value == null) return SeverityLevel.general;

    final s = value.toString().trim().toLowerCase();

    switch (s) {
      case 'critical':
      case '严重':
        return SeverityLevel.critical;
      case 'serious':
      case '较重':
        return SeverityLevel.serious;
      case 'general':
      case '一般':
        return SeverityLevel.general;
      default:
        return SeverityLevel.general;
    }
  }

  /// 转成可回填描述文本（把风险点和整改建议拼进描述，便于用户直接提交）
  String toFilledDescription() {
    final buffer = StringBuffer();
    if (description.isNotEmpty) buffer.writeln(description);
    if (riskPoints.isNotEmpty) {
      buffer.writeln();
      buffer.writeln('风险点：');
      for (final p in riskPoints) {
        buffer.writeln('· $p');
      }
    }
    if (suggestion.isNotEmpty) {
      buffer.writeln();
      buffer.writeln('整改建议：$suggestion');
    }
    return buffer.toString().trim();
  }
}
