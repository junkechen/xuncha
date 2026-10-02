// lib/services/ai_hazard_service.dart
// AI 隐患识别服务
//
// 设计要点（务必理解后再改）：
//
// 1. 密钥不下发
//    APK 不持有任何 AI 密钥，只调用自家云函数的 aiHazard action，
//    由云函数从环境变量 SILICONFLOW_API_KEY 读取密钥后代理调用硅基流动。
//    APK 里搜不到任何 sk- 开头的字符串。
//
// 2. 独立压缩轨（关键）
//    现有上报流程把图片极限压缩到 50KB（分辨率可能低至 640x360），
//    该规格无法满足视觉模型识别细节的需要（管道锈蚀、阀门状态、标识牌文字全糊）。
//    因此本服务独立压缩一份 1024px/质量80 的图片专供识别，
//    只在临时目录存活，不落业务存储、不上传云端、用完即删。
//
// 3. 不复用 CloudBaseService.callApi
//    callApi 硬编码 60 秒超时（cloudbase_service.dart:81），
//    而模型默认开启思考模式，推理可能超过 60 秒会被误判超时。
//    故此处自行发起请求并放宽超时，同时避免改动历史代码。

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

import '../config/constants.dart';
import '../models/hazard_analysis.dart';

/// AI 识别失败原因分类（便于 UI 给出针对性提示）
enum AiHazardErrorKind {
  none,
  notConfigured,
  noImage,
  tooManyImages,
  imageTooLarge,
  network,
  timeout,
  parse,
  unknown,
}

/// AI 识别结果
class AiHazardResult {
  final bool success;
  final HazardAnalysis? analysis;
  final String? message;
  final AiHazardErrorKind kind;

  const AiHazardResult._({
    required this.success,
    this.analysis,
    this.message,
    this.kind = AiHazardErrorKind.none,
  });

  factory AiHazardResult.ok(HazardAnalysis analysis) =>
      AiHazardResult._(success: true, analysis: analysis);

  factory AiHazardResult.fail(AiHazardErrorKind kind, String message) =>
      AiHazardResult._(success: false, kind: kind, message: message);
}

class AiHazardService {
  AiHazardService._({
    http.Client? client,
    Duration? timeout,
    Future<List<String>> Function(List<File>)? imageEncoder,
  })  : _client = client ?? http.Client(),
        _timeout = timeout ?? const Duration(seconds: 120),
        _imageEncoder = imageEncoder ?? _defaultEncode;

  static final AiHazardService instance = AiHazardService._();

  /// 测试入口：注入 mock 客户端 / 超时 / 图片编码器，使网络分支可测
  static AiHazardService withMocks({
    http.Client? client,
    Duration? timeout,
    Future<List<String>> Function(List<File>)? imageEncoder,
  }) =>
      AiHazardService._(
          client: client, timeout: timeout, imageEncoder: imageEncoder);

  final http.Client _client;
  final Duration _timeout;
  final Future<List<String>> Function(List<File>) _imageEncoder;

  /// 单次最多分析张数。
  ///
  /// ⚠️ 网关实测：CloudBase HTTP 触发对请求体大小限制约 100KB，
  /// 超过即返回 413 Payload Too Large（与图片内容无关，纯看 body 字节数）。
  /// base64 膨胀约 4/3，单张 JPEG 必须 ≤ ~55KB（base64 ≤ ~75KB），
  /// 整包 body 才稳定落在 100KB 以内。为避免多张叠加必超，这里强制 1 张。
  static const int maxImages = 1;

  /// AI 轨压缩阶梯 [长边像素, 质量]，目标压到 _targetBytes 以内。
  ///
  /// 注意：flutter_image_compress 的 minWidth/minHeight 是「最小边」语义，
  /// 若把 minWidth=minHeight=1024 传给 16:9 照片，实际长边会变成 1820px，
  /// 文件体积远超预期，导致 HTTP 413 Payload Too Large。
  /// 因此代码里会根据原图宽高比，把「长边像素」换算成正确的 minWidth/minHeight。
  ///
  /// 因网关 100KB body 硬限制，单张 JPEG 必须压到 55KB 以内，阶梯整体很激进。
  static const List<List<int>> _ladder = [
    [640, 60],
    [512, 55],
    [448, 50],
    [384, 45],
    [320, 40],
  ];

  /// 单张 JPEG 目标字节数（≤40KB，base64 约 53KB）
  static const int _targetBytes = 40 * 1024;

  /// 单张 JPEG 硬上限，超过则判定为无法处理
  static const int _hardLimitBytes = 55 * 1024;

  /// base64 输出硬上限（字符数），超过直接拒绝发送，避免触发网关 413。
  /// 75KB base64 → body 约 75KB+包装 < 85KB，稳定低于网关 100KB 上限。
  static const int _maxBase64Chars = 75 * 1024;

  /// 识别现场照片
  Future<AiHazardResult> analyze({
    required List<File> images,
    String? location,
    String? note,
  }) async {
    if (images.isEmpty) {
      return AiHazardResult.fail(
          AiHazardErrorKind.noImage, '请先拍摄或选择现场照片');
    }

    List<String> base64Images;
    try {
      base64Images = await _imageEncoder(images);
    } on _EncodeException catch (e) {
      return AiHazardResult.fail(AiHazardErrorKind.imageTooLarge, e.message);
    }
    if (base64Images.isEmpty) {
      return AiHazardResult.fail(
          AiHazardErrorKind.imageTooLarge, '图片过大或处理失败，请重新拍摄');
    }

    final body = jsonEncode({
      'action': 'aiHazard',
      'data': {
        'images': base64Images,
        if (location != null && location.trim().isNotEmpty)
          'location': location.trim(),
        if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
      },
    });

    Map<String, dynamic> result;
    try {
      final response = await _client
          .post(
            Uri.parse(AppConstants.cloudBaseApiUrl),
            headers: AppConstants.cloudBaseHeaders,
            body: body,
          )
          .timeout(_timeout);

      if (response.statusCode != 200) {
        return AiHazardResult.fail(
            AiHazardErrorKind.network, '网络异常（${response.statusCode}）');
      }
      result = jsonDecode(response.body) as Map<String, dynamic>;
    } on TimeoutException {
      return AiHazardResult.fail(
          AiHazardErrorKind.timeout, 'AI 分析超时，请稍后重试');
    } catch (e) {
      return AiHazardResult.fail(AiHazardErrorKind.network, '网络异常：$e');
    }

    final code = result['code'];
    if (code != 0) {
      return AiHazardResult.fail(
        _mapError(code),
        result['message']?.toString() ?? 'AI 分析失败',
      );
    }

    final analysis = HazardAnalysis.fromCloudResult(result);
    if (analysis == null) {
      return AiHazardResult.fail(
          AiHazardErrorKind.parse, 'AI 返回结果无法解析');
    }
    return AiHazardResult.ok(analysis);
  }

  /// 云函数错误码映射
  static AiHazardErrorKind _mapError(dynamic code) {
    switch (code) {
      case -20:
        return AiHazardErrorKind.notConfigured;
      case -21:
        return AiHazardErrorKind.noImage;
      case -22:
        return AiHazardErrorKind.tooManyImages;
      case -23:
        return AiHazardErrorKind.imageTooLarge;
      case -24:
        return AiHazardErrorKind.network;
      case -25:
      case -26:
        return AiHazardErrorKind.parse;
      default:
        return AiHazardErrorKind.unknown;
    }
  }

  /// 默认图片编码器：走 AI 专用压缩轨，转 base64；编码失败时抛出 _EncodeException
  static Future<List<String>> _defaultEncode(List<File> images) async {
    final out = <String>[];
    for (final file in images.take(maxImages)) {
      final b64 = await _toBase64ForAi(file);
      if (b64 == null || b64.isEmpty) {
        throw _EncodeException('图片过大或处理失败，请重新拍摄');
      }
      if (b64.length > _maxBase64Chars) {
        throw _EncodeException('照片压缩后仍超过上限，请换一张或降低分辨率重拍');
      }
      out.add(b64);
    }
    return out;
  }

  /// 压缩并转 base64（AI 专用轨，与原上报压缩轨完全隔离）
  static Future<String?> _toBase64ForAi(File file) async {
    try {
      // 先读原图尺寸，按宽高比把「长边像素」换算成 minWidth/minHeight。
      // 不这样做的话，16:9 照片用 minWidth=minHeight=1024 会被撑到 1820x1024。
      final rawBytes = await file.readAsBytes();
      final decoded = img.decodeImage(rawBytes);
      if (decoded == null) return null;

      final double aspect = decoded.width / decoded.height;
      final dir = await getTemporaryDirectory();
      File? lastCompressed;
      int lastSize = 0;

      for (final step in _ladder) {
        final int longEdge = step[0];
        final int quality = step[1];
        // 保持原图宽高比，让长边等于 longEdge
        final int minW;
        final int minH;
        if (aspect >= 1) {
          minW = longEdge;
          minH = (longEdge / aspect).round().clamp(1, longEdge);
        } else {
          minH = longEdge;
          minW = (longEdge * aspect).round().clamp(1, longEdge);
        }

        final targetPath =
            '${dir.path}/ai_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(99999)}_$longEdge.jpg';
        File? f;
        try {
          final result = await FlutterImageCompress.compressAndGetFile(
            file.absolute.path,
            targetPath,
            quality: quality,
            minWidth: minW,
            minHeight: minH,
          );
          if (result == null) continue;
          f = File(result.path);
          final size = await f.length();

          if (size <= _targetBytes) {
            final bytes = await f.readAsBytes();
            await _safeDelete(f);
            final b64 = base64Encode(bytes);
            if (b64.length <= _maxBase64Chars) return b64;
            // base64 仍超长，继续压下一档
          }

          // 记录本档结果，作为后续兜底
          await _safeDelete(lastCompressed);
          lastCompressed = f;
          lastSize = size;
        } catch (_) {
          await _safeDelete(f);
          continue;
        }
      }

      // 阶梯全部未达标：只要不超过硬上限仍可用
      if (lastCompressed != null && lastSize <= _hardLimitBytes) {
        final bytes = await lastCompressed.readAsBytes();
        await _safeDelete(lastCompressed);
        final b64 = base64Encode(bytes);
        if (b64.length <= _maxBase64Chars) return b64;
      }
      await _safeDelete(lastCompressed);

      // 压缩彻底失败，退回原图（仅在不超过硬上限时）
      if (rawBytes.length <= _hardLimitBytes) {
        final b64 = base64Encode(rawBytes);
        if (b64.length <= _maxBase64Chars) return b64;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  static Future<void> _safeDelete(File? f) async {
    if (f == null) return;
    try {
      if (await f.exists()) await f.delete();
    } catch (_) {
      // 临时文件清理失败不影响主流程
    }
  }
}

/// 图片编码失败（压缩/转 base64 异常），由 analyze 转换为 imageTooLarge 失败结果
class _EncodeException implements Exception {
  final String message;
  _EncodeException(this.message);
}
