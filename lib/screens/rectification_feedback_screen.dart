// lib/screens/rectification_feedback_screen.dart
// 整改反馈页面 - 提交整改进展文字说明和照片

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';
import '../providers/issue_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/chat_provider.dart';
import '../models/issue.dart';
import '../models/chat_message.dart';

class RectificationFeedbackScreen extends StatefulWidget {
  final String issueId;
  final String issueTitle;
  
  const RectificationFeedbackScreen({
    Key? key,
    required this.issueId,
    required this.issueTitle,
  }) : super(key: key);

  @override
  State<RectificationFeedbackScreen> createState() => _RectificationFeedbackScreenState();
}

class _RectificationFeedbackScreenState extends State<RectificationFeedbackScreen> {
  final _descriptionController = TextEditingController();
  final _imagePicker = ImagePicker();
  final List<File> _selectedImages = []; // 改为 File 类型
  bool _isSubmitting = false;

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  /// 压缩图片 - 目标50KB以下
  Future<File?> _compressImage(File file) async {
    try {
      final fileSize = await file.length();
      print('📷 原始图片大小: ${(fileSize / 1024).toStringAsFixed(1)} KB');

      // 目标大小：50KB以下
      const targetSize = 50 * 1024;

      if (fileSize <= targetSize) {
        return file;
      }

      // 分辨率等级
      const resolutions = [
        [1920, 1080],
        [1280, 720],
        [1024, 576],
        [800, 450],
        [640, 360],
      ];

      final appDir = await getApplicationDocumentsDirectory();
      final compressDir = Directory('${appDir.path}/compressed_photos');
      if (!await compressDir.exists()) {
        await compressDir.create(recursive: true);
      }

      File? lastResult;

      for (var resolution in resolutions) {
        for (int q = 80; q >= 20; q -= 10) {
          final timestamp = DateTime.now().millisecondsSinceEpoch;
          final targetPath = '${compressDir.path}/compressed_${timestamp}_${resolution[0]}x${resolution[1]}_q$q.jpg';

          final result = await FlutterImageCompress.compressAndGetFile(
            file.absolute.path,
            targetPath,
            quality: q,
            minWidth: resolution[0],
            minHeight: resolution[1],
          );

          if (result != null) {
            final compressedFile = File(result.path);
            final compressedSize = await compressedFile.length();

            if (compressedSize <= targetSize) {
              print('📷 压缩成功: ${(compressedSize / 1024).toStringAsFixed(1)} KB');
              return compressedFile;
            }

            if (lastResult == null || compressedSize < lastResult.lengthSync()) {
              lastResult = compressedFile;
            }
          }
        }
      }

      return lastResult ?? file;
    } catch (e) {
      print('❌ 图片压缩失败: $e');
      return file;
    }
  }

  /// 拍照
  Future<void> _takePhoto() async {
    final XFile? image = await _imagePicker.pickImage(
      source: ImageSource.camera,
      imageQuality: 85,
      maxWidth: 1920,
      maxHeight: 1080,
    );
    if (image != null) {
      // 压缩图片
      final compressed = await _compressImage(File(image.path));
      if (compressed != null) {
        setState(() => _selectedImages.add(compressed));
      }
    }
  }

  /// 从相册选择
  Future<void> _pickFromGallery() async {
    final List<XFile> images = await _imagePicker.pickMultiImage(
      imageQuality: 85,
      maxWidth: 1920,
      maxHeight: 1080,
    );
    if (images.isNotEmpty) {
      // 压缩图片
      for (final image in images) {
        final compressed = await _compressImage(File(image.path));
        if (compressed != null) {
          setState(() => _selectedImages.add(compressed));
        }
      }
    }
  }

  /// 移除图片
  void _removeImage(int index) {
    setState(() => _selectedImages.removeAt(index));
  }
  
  /// 提交整改反馈
  Future<void> _submitFeedback() async {
    final description = _descriptionController.text.trim();
    
    if (description.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('请填写整改情况说明'),
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    
    setState(() => _isSubmitting = true);
    
    try {
      final issueProvider = context.read<IssueProvider>();
      final authProvider = context.read<AuthProvider>();
      final chatProvider = context.read<ChatProvider>();
      
      // 获取当前用户信息
      final currentUser = authProvider.currentUser;
      final submitterId = currentUser?.id ?? 'unknown';
      final submitterName = currentUser?.name ?? currentUser?.username ?? '未知用户';
      
      // 使用新的 submitRectification 方法保存整改反馈
      final success = await issueProvider.submitRectification(
        issueId: widget.issueId,
        description: description,
        photos: _selectedImages,
        submitterId: submitterId,
        submitterName: submitterName,
      );
      
      if (success) {
        // ====== 发送通知给问题的发起人 ======
        // 获取问题的发起人信息
        final issue = issueProvider.getIssueById(widget.issueId);
        if (issue != null) {
          // 发送给发起人（而不是固定的 'admin'）
          await chatProvider.sendMessage(
            toUserId: issue.reporterId,
            toUserName: issue.reporterName,
            content: '【整改完成，等待验收】${widget.issueTitle}\n\n$description\n\n附件: ${_selectedImages.length} 张照片\n\n请尽快验收！',
            type: MessageType.issueNotify,
            issueId: widget.issueId,
            issueTitle: widget.issueTitle,
          );
          print('✅ 已通知发起人 ${issue.reporterName} (${issue.reporterId}) 验收');
        } else {
          print('⚠️ 未找到问题详情，无法发送通知');
        }
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('整改反馈已提交，等待验收'),
              backgroundColor: Color(0xFF10B981),
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 3),
            ),
          );
          Navigator.pop(context);
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('提交失败，请重试'),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('提交失败: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('提交整改反馈'),
        backgroundColor: const Color(0xFF10B981),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 问题标题
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange[200]!),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.assignment, color: Colors.orange[700], size: 20),
                      const SizedBox(width: 8),
                      const Text(
                        '关联问题',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.orange,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.issueTitle,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 24),
            
            // 整改情况说明
            const Text(
              '整改情况说明 *',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _descriptionController,
              maxLines: 6,
              decoration: InputDecoration(
                hintText: '请详细描述整改措施和完成情况...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
                fillColor: Colors.grey[50],
              ),
            ),
            
            const SizedBox(height: 24),
            
            // 整改照片
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  '整改照片',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  '${_selectedImages.length} 张',
                  style: TextStyle(color: Colors.grey[600]),
                ),
              ],
            ),
            const SizedBox(height: 12),
            
            // 添加照片按钮和预览
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                // 添加照片按钮
                GestureDetector(
                  onTap: () => _showImageSourceDialog(),
                  child: Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.grey[300]!,
                        style: BorderStyle.solid,
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add_a_photo, size: 32, color: Colors.grey[400]),
                        const SizedBox(height: 4),
                        Text(
                          '添加照片',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[500],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // 已选照片预览
                ..._selectedImages.asMap().entries.map((entry) {
                  return Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.file(
                          entry.value, // 已经是 File 类型
                          width: 100,
                          height: 100,
                          fit: BoxFit.cover,
                        ),
                      ),
                      Positioned(
                        top: 4,
                        right: 4,
                        child: GestureDetector(
                          onTap: () => _removeImage(entry.key),
                          child: Container(
                            decoration: const BoxDecoration(
                              color: Colors.red,
                              shape: BoxShape.circle,
                            ),
                            padding: const EdgeInsets.all(4),
                            child: const Icon(
                              Icons.close,
                              size: 16,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                }),
              ],
            ),
            
            const SizedBox(height: 32),
            
            // 提交按钮
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _isSubmitting ? null : _submitFeedback,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF10B981),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isSubmitting
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation(Colors.white),
                        ),
                      )
                    : const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.check_circle),
                          SizedBox(width: 8),
                          Text(
                            '提交整改反馈',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
              ),
            ),
            
            const SizedBox(height: 16),
            
            // 提示
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.blue[700], size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '提交后问题状态将变为"待验收"，管理员审核后即可关闭。',
                      style: TextStyle(fontSize: 12, color: Colors.blue[700]),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  /// 显示图片来源选择对话框
  void _showImageSourceDialog() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                '选择图片来源',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.camera_alt, color: Color(0xFF10B981)),
              ),
              title: const Text('拍照'),
              subtitle: const Text('使用相机拍摄'),
              onTap: () {
                Navigator.pop(ctx);
                _takePhoto();
              },
            ),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.photo_library, color: Colors.blue),
              ),
              title: const Text('相册'),
              subtitle: const Text('从相册选择'),
              onTap: () {
                Navigator.pop(ctx);
                _pickFromGallery();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
