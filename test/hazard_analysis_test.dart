// AI 隐患识别结果解析的回归测试
//
// Qwen3.5-4B 不支持原生结构化输出，返回内容形态不可控，
// 解析层一旦抛异常就会让上报流程崩溃。这里锁定容错行为。

import 'package:flutter_test/flutter_test.dart';
import 'package:env_inspection_new/models/hazard_analysis.dart';
import 'package:env_inspection_new/models/issue.dart';

void main() {
  group('枚举解析', () {
    test('标准英文枚举', () {
      final a = HazardAnalysis.fromJson({
        'hasHazard': true,
        'title': '地沟含油废水外溢',
        'category': '废水排放',
        'severity': 'critical',
        'description': '现场地沟有含油废水外溢',
        'suggestion': '立即封堵并清理',
        'confidence': 0.85,
      });
      expect(a.hasHazard, isTrue);
      expect(a.category, IssueCategory.envWastewater);
      expect(a.severity, SeverityLevel.critical);
      expect(a.isValid, isTrue);
    });

    test('中文枚举值（模型偶尔不按英文输出）', () {
      final a = HazardAnalysis.fromJson({
        'category': '固废管理',
        'severity': '较重',
      });
      expect(a.category, IssueCategory.envSolid);
      expect(a.severity, SeverityLevel.serious);
    });

    test('中文「严重」必须映射到 critical 而非 serious', () {
      final a = HazardAnalysis.fromJson({'severity': '严重'});
      expect(a.severity, SeverityLevel.critical);
    });

    test('数字下标枚举', () {
      expect(
        HazardAnalysis.fromJson({'category': IssueCategory.envSolid.index}).category,
        IssueCategory.envSolid,
      );
      expect(
        HazardAnalysis.fromJson({'severity': 2}).severity,
        SeverityLevel.critical,
      );
    });

    test('未知值安全落到默认项，不抛异常', () {
      expect(
        HazardAnalysis.fromJson({'category': '不存在的分类'}).category,
        IssueCategory.envOther,
      );
      expect(
        HazardAnalysis.fromJson({'severity': '离谱等级'}).severity,
        SeverityLevel.general,
      );
      // 越界下标也不能抛
      expect(
        HazardAnalysis.fromJson({'category': 999}).category,
        IssueCategory.envOther,
      );
      expect(
        HazardAnalysis.fromJson({'severity': -1}).severity,
        SeverityLevel.general,
      );
    });
  });

  group('字段容错', () {
    test('空 JSON 不抛异常', () {
      final a = HazardAnalysis.fromJson({});
      expect(a.title, '');
      // 模型漏返 hasHazard 时安全默认"无隐患"，避免误报（实现层有意设计）
      expect(a.hasHazard, isFalse);
      expect(a.confidence, 0);
      expect(a.riskPoints, isEmpty);
    });

    test('null 值不抛异常', () {
      final a = HazardAnalysis.fromJson({
        'title': null,
        'category': null,
        'severity': null,
        'confidence': null,
        'riskPoints': null,
      });
      expect(a.title, '');
      expect(a.category, IssueCategory.envOther);
      expect(a.confidence, 0);
    });

    test('confidence 为字符串或越界数值', () {
      expect(HazardAnalysis.fromJson({'confidence': '0.5'}).confidence, 0.5);
      expect(HazardAnalysis.fromJson({'confidence': 3.7}).confidence, 1.0);
      expect(HazardAnalysis.fromJson({'confidence': -2}).confidence, 0.0);
      expect(HazardAnalysis.fromJson({'confidence': 'abc'}).confidence, 0.0);
    });

    test('hasHazard 兼容字符串与数字', () {
      expect(HazardAnalysis.fromJson({'hasHazard': 'false'}).hasHazard, isFalse);
      expect(HazardAnalysis.fromJson({'hasHazard': 'true'}).hasHazard, isTrue);
      expect(HazardAnalysis.fromJson({'hasHazard': 0}).hasHazard, isFalse);
      expect(HazardAnalysis.fromJson({'hasHazard': 1}).hasHazard, isTrue);
      expect(HazardAnalysis.fromJson({'hasHazard': '否'}).hasHazard, isFalse);
    });

    test('riskPoints 非数组时降级为单项', () {
      expect(
        HazardAnalysis.fromJson({'riskPoints': '油污扩散'}).riskPoints,
        ['油污扩散'],
      );
    });
  });

  group('云函数返回解析', () {
    test('正常返回体', () {
      final a = HazardAnalysis.fromCloudResult({
        'code': 0,
        'analysis': {
          'hasHazard': true,
          'title': '消防通道被占用',
          'category': 'other',
          'severity': 'serious',
        },
      });
      expect(a, isNotNull);
      expect(a!.title, '消防通道被占用');
      expect(a.severity, SeverityLevel.serious);
    });

    test('未解析出 analysis 但有原文时降级，不返回 null', () {
      final a = HazardAnalysis.fromCloudResult({
        'code': -26,
        'raw': '模型返回的一段非结构化文本',
      });
      expect(a, isNotNull);
      expect(a!.isFallback, isTrue);
      expect(a.description, contains('非结构化'));
      expect(a.isValid, isFalse); // 降级结果不可用于回填
    });

    test('完全无有效数据返回 null', () {
      expect(HazardAnalysis.fromCloudResult(null), isNull);
      expect(HazardAnalysis.fromCloudResult({}), isNull);
      expect(HazardAnalysis.fromCloudResult({'code': -3}), isNull);
    });
  });

  group('回填文案', () {
    test('描述含风险点与整改建议', () {
      final a = HazardAnalysis.fromJson({
        'hasHazard': true,
        'title': '废气排放异常',
        'description': '排气筒有可见黄烟',
        'riskPoints': ['超标排放', '影响下风向'],
        'suggestion': '检修除尘设施',
      });
      final text = a.toFilledDescription();
      expect(text, contains('排气筒有可见黄烟'));
      expect(text, contains('超标排放'));
      expect(text, contains('影响下风向'));
      expect(text, contains('整改建议：检修除尘设施'));
    });

    test('内容全空时返回空串，不产生多余空行', () {
      expect(HazardAnalysis.fromJson({}).toFilledDescription(), '');
    });
  });
}
