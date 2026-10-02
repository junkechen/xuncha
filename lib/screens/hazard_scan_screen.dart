// lib/screens/hazard_scan_screen.dart
// AI 隐患识别页（首页独立入口）
//
// 定位：随手拍快速判断。拍照后由 AI 识别现场隐患。
//
// 关键改动：识别很慢，改为「后台异步」——
// 点「开始识别」后立即在后台跑，用户可马上返回做其他事；
// 完成后发系统通知，结果持久化，下次进本页可查看或一键转为正式上报。
//
// 注意：本页不持有任何 AI 密钥，识别请求统一走云函数代理。

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../config/constants.dart';
import '../models/hazard_analysis.dart';
import '../models/issue.dart' as models;
import '../providers/ai_analysis_provider.dart';
import '../services/ai_hazard_service.dart';
import '../utils/media_permission.dart';
import 'add_issue_screen.dart';

class HazardScanScreen extends StatefulWidget {
  const HazardScanScreen({super.key});

  @override
  State<HazardScanScreen> createState() => _HazardScanScreenState();
}

class _HazardScanScreenState extends State<HazardScanScreen> {
  final ImagePicker _picker = ImagePicker();
  final TextEditingController _locationController = TextEditingController();
  final TextEditingController _noteController = TextEditingController();

  List<File> _images = [];

  static const int _maxImages = AiHazardService.maxImages;

  @override
  void dispose() {
    _locationController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _takePhoto() async {
    if (_images.length >= _maxImages) {
      _showSnack('最多识别 $_maxImages 张照片');
      return;
    }
    if (!await MediaPermissionHelper.ensure(context, ImageSource.camera)) return;
    if (!mounted) return;
    try {
      final photo = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 92,
      );
      if (photo != null && mounted) {
        setState(() => _images.add(File(photo.path)));
      }
    } catch (e) {
      _showSnack('拍照失败：$e');
    }
  }

  Future<void> _pickFromGallery() async {
    if (_images.length >= _maxImages) {
      _showSnack('最多识别 $_maxImages 张照片');
      return;
    }
    if (!await MediaPermissionHelper.ensure(context, ImageSource.gallery)) return;
    if (!mounted) return;
    try {
      final photos = await _picker.pickMultiImage(imageQuality: 92);
      if (photos.isNotEmpty && mounted) {
        setState(() {
          for (final p in photos) {
            if (_images.length < _maxImages) _images.add(File(p.path));
          }
        });
      }
    } catch (e) {
      _showSnack('选择照片失败：$e');
    }
  }

  void _removeImage(int index) {
    setState(() => _images.removeAt(index));
  }

  /// 启动后台识别：不阻塞，立即返回上一页，完成后发通知
  void _startAnalysis() {
    if (_images.isEmpty) {
      _showSnack('请先拍摄或选择现场照片');
      return;
    }
    final provider = context.read<AiAnalysisProvider>();
    provider.startAnalysis(
      images: List<File>.from(_images),
      location: _locationController.text,
      note: _noteController.text,
    );
    _showSnack('AI 已在后台开始分析，您可返回做其他事，完成后会通知您');
    // 返回上一页，让用户去处理别的事
    Navigator.of(context).pop();
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final ai = context.watch<AiAnalysisProvider>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI 隐患识别'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildImageSection(),
              const SizedBox(height: 16),
              _buildInputSection(),
              const SizedBox(height: 16),
              _buildAnalyzeButton(),
              const SizedBox(height: 16),
              _buildTaskList(ai),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildImageSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              '现场照片',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
            ),
            const SizedBox(width: 8),
            Text(
              '${_images.length}/$_maxImages',
              style: const TextStyle(fontSize: 13, color: Colors.grey),
            ),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 100,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              ..._images.asMap().entries.map((e) => _buildThumb(e.value, e.key)),
              if (_images.length < _maxImages) _buildAddButtons(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildThumb(File file, int index) {
    return Container(
      width: 100,
      margin: const EdgeInsets.only(right: 10),
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.file(
              file,
              width: 100,
              height: 100,
              fit: BoxFit.cover,
            ),
          ),
          Positioned(
            right: 2,
            top: 2,
            child: GestureDetector(
              onTap: () => _removeImage(index),
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.black54,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close, size: 18, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAddButtons() {
    return Row(
      children: [
        _buildDashedButton(
          icon: Icons.photo_camera_outlined,
          label: '拍照',
          onTap: _takePhoto,
        ),
        const SizedBox(width: 10),
        _buildDashedButton(
          icon: Icons.photo_library_outlined,
          label: '相册',
          onTap: _pickFromGallery,
        ),
      ],
    );
  }

  Widget _buildDashedButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 100,
        height: 100,
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade400),
          borderRadius: BorderRadius.circular(8),
          color: Colors.grey.shade50,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.grey.shade600, size: 26),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputSection() {
    return Column(
      children: [
        TextField(
          controller: _locationController,
          decoration: const InputDecoration(
            labelText: '现场位置（选填，有助于 AI 判断）',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.location_on_outlined),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _noteController,
          maxLines: 2,
          decoration: const InputDecoration(
            labelText: '补充说明（选填）',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.notes_outlined),
          ),
        ),
      ],
    );
  }

  Widget _buildAnalyzeButton() {
    return SizedBox(
      height: 48,
      child: ElevatedButton.icon(
        onPressed: _images.isEmpty ? null : _startAnalysis,
        icon: const Icon(Icons.auto_awesome),
        label: const Text('开始识别（后台运行）'),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(AppColors.primaryGreen),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
    );
  }

  /// 历史/进行中的分析记录
  Widget _buildTaskList(AiAnalysisProvider ai) {
    if (ai.tasks.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 24),
        alignment: Alignment.center,
        child: Text(
          '暂无分析记录。拍完照点「开始识别」即可后台运行，完成后会通知您。',
          style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
          textAlign: TextAlign.center,
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '分析记录',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 10),
        ...ai.tasks.map((t) => _buildTaskCard(t)),
      ],
    );
  }

  Widget _buildTaskCard(AiAnalysisTask t) {
    final time = '${t.createdAt.month}/${t.createdAt.day} '
        '${t.createdAt.hour.toString().padLeft(2, '0')}:'
        '${t.createdAt.minute.toString().padLeft(2, '0')}';

    if (t.status == AiTaskStatus.running) {
      return _card(
        child: Row(
          children: [
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text('识别中…（后台运行，可返回做其他事）$time',
                  style: const TextStyle(fontSize: 13)),
            ),
          ],
        ),
      );
    }

    if (t.status == AiTaskStatus.error || t.success != true) {
      return _card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.error_outline, color: Colors.orange.shade700),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('识别未完成 · $time',
                      style: const TextStyle(fontSize: 13)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              t.errorMessage ?? '本次识别未成功，可重试',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
            ),
          ],
        ),
      );
    }

    // 成功
    final a = t.analysis!;
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.auto_awesome,
                  size: 20, color: Color(AppColors.primaryGreen)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  a.title.isNotEmpty ? a.title : '现场隐患',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w500),
                ),
              ),
              if (a.confidence > 0)
                Text('置信度 ${a.confidencePercent}',
                    style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            children: [
              _buildChip(_catName(a.category), Colors.blue),
              _buildChip(_sevName(a.severity), _severityColor(a.severity)),
            ],
          ),
          if (a.description.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(a.description, style: const TextStyle(fontSize: 13)),
          ],
          const SizedBox(height: 12),
          SizedBox(
            height: 40,
            child: ElevatedButton.icon(
              onPressed: () {
                final existing = t.imagePaths
                    .map((p) => File(p))
                    .where((f) => f.existsSync())
                    .toList();
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => AddIssueScreen(
                      initialAnalysis: a,
                      initialPhotos: existing,
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.assignment_outlined),
              label: const Text('转为隐患上报'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(AppColors.primaryGreen),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text('识别时间 $time · AI 判断仅供参考，字段均可修改',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
        ],
      ),
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _buildChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 12, color: color.withAlpha(230)),
      ),
    );
  }

  String _catName(models.IssueCategory cat) => models.categoryNameOf(cat);

  String _sevName(models.SeverityLevel level) => models.severityNameOf(level);

  Color _severityColor(models.SeverityLevel level) {
    switch (level) {
      case models.SeverityLevel.critical:
        return Colors.red;
      case models.SeverityLevel.serious:
        return Colors.orange;
      case models.SeverityLevel.general:
        return Colors.green;
    }
  }
}
