// test/ai_hazard_service_test.dart
// AiHazardService 边界测试：通过依赖注入覆盖网络分支，无需真实云端与密钥。
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:env_inspection_new/models/issue.dart';
import 'package:env_inspection_new/services/ai_hazard_service.dart';

/// 内存假客户端：可模拟状态码、响应体、抛异常、延迟（触发超时）
class _FakeClient extends http.BaseClient {
  int callCount = 0;
  int statusCode = 200;
  String responseBody = '{}';
  Exception? thrown;
  Duration? delay;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    callCount++;
    if (thrown != null) throw thrown!;
    if (delay != null) await Future.delayed(delay!);
    final bytes = utf8.encode(responseBody);
    return http.StreamedResponse(
      Stream<Uint8List>.value(Uint8List.fromList(bytes)),
      statusCode,
      request: request,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  }
}

const _sampleB64 = 'data:image/jpeg;base64,/9jtest';

const _okBody = '''
{
  "code": 0,
  "analysis": {
    "hasHazard": true,
    "title": "管道锈蚀穿孔",
    "category": "废水排放",
    "severity": "critical",
    "riskPoints": ["管壁锈蚀减薄", "存在泄漏风险"],
    "suggestion": "立即停用并更换管段",
    "confidence": 0.88
  }
}
''';

AiHazardService _svc(_FakeClient c,
    {Duration? timeout, required List<String> base64}) {
  return AiHazardService.withMocks(
    client: c,
    timeout: timeout,
    imageEncoder: (_) async => base64,
  );
}

void main() {
  group('AiHazardService.analyze 边界', () {
    test('空图列表直接返回 noImage，不发起请求', () async {
      final c = _FakeClient();
      final r = await AiHazardService.withMocks(
        client: c,
        imageEncoder: (_) async => [],
      ).analyze(images: []);
      expect(r.success, isFalse);
      expect(r.kind, AiHazardErrorKind.noImage);
      expect(c.callCount, 0);
    });

    test('云函数返回 code:0 且含合法 analysis → 成功解析', () async {
      final c = _FakeClient()..responseBody = _okBody;
      final r = await _svc(c, base64: [_sampleB64]).analyze(images: [File('x.jpg')]);
      expect(r.success, isTrue);
      expect(r.analysis, isNotNull);
      expect(r.analysis!.title, '管道锈蚀穿孔');
      expect(r.analysis!.category, IssueCategory.envWastewater);
      expect(r.analysis!.severity, SeverityLevel.critical);
      expect(r.analysis!.confidence, closeTo(0.88, 1e-6));
      expect(c.callCount, 1);
    });

    test('HTTP 非 200 → network', () async {
      final c = _FakeClient()..statusCode = 500;
      final r = await _svc(c, base64: [_sampleB64]).analyze(images: [File('x.jpg')]);
      expect(r.success, isFalse);
      expect(r.kind, AiHazardErrorKind.network);
    });

    test('客户端抛异常 → network', () async {
      final c = _FakeClient()..thrown = Exception('socket closed');
      final r = await _svc(c, base64: [_sampleB64]).analyze(images: [File('x.jpg')]);
      expect(r.success, isFalse);
      expect(r.kind, AiHazardErrorKind.network);
    });

    test('code:-20 未配置密钥 → notConfigured', () async {
      final c = _FakeClient()
        ..responseBody = jsonEncode({'code': -20, 'message': '未配置'});
      final r = await _svc(c, base64: [_sampleB64]).analyze(images: [File('x.jpg')]);
      expect(r.kind, AiHazardErrorKind.notConfigured);
      expect(r.message, contains('未配置'));
    });

    test('code:-22 超张数 → tooManyImages', () async {
      final c = _FakeClient()
        ..responseBody = jsonEncode({'code': -22, 'message': '最多 3 张'});
      final r = await _svc(c, base64: [_sampleB64]).analyze(images: [File('x.jpg')]);
      expect(r.kind, AiHazardErrorKind.tooManyImages);
    });

    test('图片编码器返回空 → imageTooLarge（不发起请求）', () async {
      final c = _FakeClient();
      final r = await AiHazardService.withMocks(
        client: c,
        imageEncoder: (_) async => [],
      ).analyze(images: [File('x.jpg')]);
      expect(r.kind, AiHazardErrorKind.imageTooLarge);
      expect(c.callCount, 0);
    });

    test('注入短超时 + 长延迟 → timeout', () async {
      final c = _FakeClient()..delay = const Duration(seconds: 5);
      final r = await _svc(
        c,
        timeout: const Duration(milliseconds: 150),
        base64: [_sampleB64],
      ).analyze(images: [File('x.jpg')]);
      expect(r.kind, AiHazardErrorKind.timeout);
    });
  });
}
