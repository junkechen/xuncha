// lib/services/update_service.dart
// 登录后自动检查更新（移动端）。
//
// 方案：直接查询 GitHub Releases API 拿到最新 Release 的 tag 与 apk 下载地址，
// 与 PackageInfo 读取到的当前版本号做语义化比较。发现新版本时弹窗引导用户去浏览器
// 下载（Android 点开 apk 链接后可触发系统安装流程），不在程序内静默下载/自替换，
// 既满足「登录后自动检查更新」，又避免被安全软件误判。
//
// 设计要点：
// - 任何异常（无网、限流、JSON 解析失败）都静默返回「无更新」，绝不影响正常登录使用。
// - 比较逻辑与桌面端 update.js 的 isNewer 保持一致（三位版本号逐段比较）。

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

class AppUpdateInfo {
  final bool hasUpdate;
  final String currentVersion;
  final String latestVersion;
  final String? downloadUrl;
  final String? releaseNotes;
  final String? releasePage;
  final String? error;

  const AppUpdateInfo({
    required this.hasUpdate,
    required this.currentVersion,
    required this.latestVersion,
    this.downloadUrl,
    this.releaseNotes,
    this.releasePage,
    this.error,
  });
}

class UpdateService {
  static const String _repo = 'junkechen/xuncha';
  static const String _apiUrl =
      'https://api.github.com/repos/$_repo/releases/latest';

  /// 查询 GitHub Release latest，与本地版本比较，返回是否有更新。
  static Future<AppUpdateInfo> check() async {
    PackageInfo pkg;
    try {
      pkg = await PackageInfo.fromPlatform();
    } catch (_) {
      // 读不到版本信息时退化为 0.0.0，仅用于比较，不会误报更新。
      pkg = PackageInfo(appName: '', packageName: '', version: '0.0.0', buildNumber: '0');
    }
    final current = pkg.version; // 形如 3.7.14

    http.Response res;
    try {
      res = await http
          .get(
            Uri.parse(_apiUrl),
            headers: {
              'Accept': 'application/vnd.github+json',
              'User-Agent': 'env-inspection-app',
            },
          )
          .timeout(const Duration(seconds: 8));
    } catch (_) {
      return AppUpdateInfo(
          hasUpdate: false, currentVersion: current, latestVersion: current, error: 'network');
    }

    if (res.statusCode != 200) {
      return AppUpdateInfo(
          hasUpdate: false,
          currentVersion: current,
          latestVersion: current,
          error: 'status-${res.statusCode}');
    }

    Map<String, dynamic> j;
    try {
      j = jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {
      return AppUpdateInfo(
          hasUpdate: false, currentVersion: current, latestVersion: current, error: 'bad-json');
    }

    final tag = (j['tag_name'] as String? ?? '').replaceAll(RegExp(r'^v'), '');
    String? apkUrl;
    final assets = j['assets'];
    if (assets is List) {
      for (final a in assets) {
        final name = (a['name'] as String? ?? '').toLowerCase();
        if (name.endsWith('.apk')) {
          apkUrl = a['browser_download_url'] as String?;
          break;
        }
      }
    }

    final newer = _compareVersion(tag, current) > 0;
    return AppUpdateInfo(
      hasUpdate: newer,
      currentVersion: current,
      latestVersion: tag,
      downloadUrl: apkUrl ?? (j['html_url'] as String?),
      releaseNotes: j['body'] as String?,
      releasePage: j['html_url'] as String?,
    );
  }

  /// 登录后（首页挂载）调用：自动检查更新并弹窗提示。
  /// 无更新或发生异常时静默返回，不阻塞、不打扰用户。
  static Future<void> checkAndPrompt(BuildContext context) async {
    final info = await check();
    if (!info.hasUpdate || !context.mounted) return;

    final page = info.downloadUrl ?? info.releasePage;
    final notes = (info.releaseNotes ?? '').trim();
    final String content;
    if (notes.isEmpty) {
      content =
          '发现新版本 v${info.latestVersion}（当前 v${info.currentVersion}），是否前往下载？';
    } else {
      final trimmed = notes.length > 600 ? '${notes.substring(0, 600)}…' : notes;
      content =
          '发现新版本 v${info.latestVersion}（当前 v${info.currentVersion}）。\n\n'
          '更新内容：\n$trimmed\n\n是否前往下载？';
    }

    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('发现新版本'),
        content: SingleChildScrollView(child: Text(content)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('稍后'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              if (page != null) await openDownload(page);
            },
            child: const Text('立即更新'),
          ),
        ],
      ),
    );
  }

  /// 用系统浏览器打开下载链接（apk 直链在 Android 上会触发安装流程）。
  static Future<void> openDownload(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  static int _compareVersion(String a, String b) {
    final pa = _parse(a), pb = _parse(b);
    for (var i = 0; i < 3; i++) {
      if (pa[i] != pb[i]) return pa[i].compareTo(pb[i]);
    }
    return 0;
  }

  static List<int> _parse(String v) {
    final m = RegExp(r'(\d+)\.(\d+)\.(\d+)').firstMatch(v ?? '');
    if (m == null) return [0, 0, 0];
    return [int.parse(m.group(1)!), int.parse(m.group(2)!), int.parse(m.group(3)!)];
  }
}
