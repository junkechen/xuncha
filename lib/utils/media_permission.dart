// lib/utils/media_permission.dart
// 相机 / 相册 运行时权限助手。
//
// 背景：image_picker ^1.0.7 不会自动合并 CAMERA / READ_MEDIA_IMAGES /
// READ_EXTERNAL_STORAGE 权限，必须在 AndroidManifest.xml 中显式声明，
// 并在运行时申请（尤其 Android < 13 的相册读取依赖 READ_EXTERNAL_STORAGE）。
//
// 本助手统一处理「申请权限 → 被拒提示 → 永久拒绝引导去设置」，供所有
// 拍照 / 选图入口复用，避免每个页面重复实现权限逻辑。

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';

class MediaPermissionHelper {
  MediaPermissionHelper._();

  /// 根据来源申请对应权限。
  ///
  /// - [ImageSource.camera]  → [Permission.camera]
  /// - [ImageSource.gallery] → [Permission.photos]（Android 13+ 映射
  ///   READ_MEDIA_IMAGES，旧版映射 READ_EXTERNAL_STORAGE，自动适配）
  ///
  /// 返回 true 表示可以继续调用 image_picker；返回 false 表示被「永久拒绝」，
  /// 已弹窗引导去系统设置，调用方应中止。
  ///
  /// 设计要点（跨版本兼容）：
  /// - 「永久拒绝」才阻断：因为相机走系统相机 intent、Android 13+ 相册走系统
  ///   Photo Picker，二者都无需本应用持有对应权限也能工作；若临时拒绝就阻断，
  ///   反而会在 13+ 上误伤「本可正常打开」的 Photo Picker。
  /// - 临时拒绝时仍返回 true：相机 intent 照常工作；旧版 Android 相册若确需
  ///   权限，会由 image_picker 自然抛错，被各页面已有的 try/catch 兜底提示。
  /// - 提前申请的好处：在确实需要权限的旧版 Android 上，用户在首次选图前授权，
  ///   可修复原本「未声明/未申请 READ_EXTERNAL_STORAGE 导致相册打不开」的问题。
  static Future<bool> ensure(BuildContext context, ImageSource source) async {
    final Permission permission;
    final String label;
    if (source == ImageSource.camera) {
      permission = Permission.camera;
      label = '相机';
    } else {
      permission = Permission.photos;
      label = '相册';
    }

    final status = await permission.status;
    if (status.isGranted) return true;

    if (status.isPermanentlyDenied) {
      await _showSettingsDialog(context, label);
      return false;
    }

    final result = await permission.request();
    if (result.isPermanentlyDenied) {
      await _showSettingsDialog(context, label);
      return false;
    }
    // 已授权 / 临时拒绝 / 受限（restricted）：均继续，交由系统 intent / image_picker 处理
    return true;
  }

  static Future<void> _showSettingsDialog(BuildContext context, String label) async {
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('需要权限'),
        content: Text('$label权限已被永久拒绝，请到系统设置中手动开启后重试。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              openAppSettings();
            },
            child: const Text('去设置'),
          ),
        ],
      ),
    );
  }
}
