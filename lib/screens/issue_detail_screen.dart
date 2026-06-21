// lib/screens/issue_detail_screen.dart
// 问题详情页面

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';
import '../models/issue.dart';
import '../models/user.dart';
import '../models/chat_message.dart';
import '../providers/issue_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/chat_provider.dart';
import '../services/cloudbase_service.dart';
import '../utils/phone_service.dart';
import 'chat_list_screen.dart';

class IssueDetailScreen extends StatefulWidget {
  final Issue issue;

  const IssueDetailScreen({super.key, required this.issue});

  @override
  State<IssueDetailScreen> createState() => _IssueDetailScreenState();
}

class _IssueDetailScreenState extends State<IssueDetailScreen> {
  late Issue _issue;

  @override
  void initState() {
    super.initState();
    _issue = widget.issue;
    // 从 Provider 获取最新数据（可能包含新上传的照片）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshIssueFromProvider();
    });
  }

  void _refreshIssueFromProvider() {
    final provider = context.read<IssueProvider>();
    final freshIssue = provider.getIssueById(widget.issue.id);
    if (freshIssue != null && mounted) {
      setState(() {
        _issue = freshIssue;
      });
    }
  }

  final Map<String, String> _refreshedPhotoUrls = {}; // 缓存已刷新的照片URL（key为原始URL）
  final Set<String> _refreshingPhotos = {}; // 正在刷新中的照片URL集合

  /// 刷新过期照片URL（支持主照片和整改照片，key为原始URL）
  Future<void> _refreshPhotoUrl(String originalUrl) async {
    if (_refreshingPhotos.contains(originalUrl)) return; // 防止重复刷新
    _refreshingPhotos.add(originalUrl);
    
    try {
      final cloudService = CloudBaseService.instance;
      
      // cloud:// 格式的 fileID：直接传给云函数刷新
      // 普通网络URL：提取文件路径后再刷新
      final String refreshTarget;
      if (originalUrl.startsWith('cloud://')) {
        refreshTarget = originalUrl;
        print('🔄 刷新照片 (cloud:// fileID): ${originalUrl.substring(0, 80)}...');
      } else {
        final filePath = cloudService.extractFilePathFromUrl(originalUrl);
        if (filePath == null) {
          print('⚠️ 无法提取文件路径: $originalUrl');
          _refreshingPhotos.remove(originalUrl);
          return;
        }
        refreshTarget = filePath;
        print('🔄 刷新照片: $filePath');
      }
      
      final freshUrl = await cloudService.getFreshPhotoUrl(refreshTarget);
      if (freshUrl != null && mounted) {
        setState(() {
          _refreshedPhotoUrls[originalUrl] = freshUrl;
        });
        print('✅ 照片URL刷新成功');
      }
    } catch (e) {
      print('❌ 刷新照片失败: $e');
    }
    
    if (mounted) {
      setState(() {
        _refreshingPhotos.remove(originalUrl);
      });
    }
  }

  /// 自动修复本地路径照片（旧版本存储的本地路径）
  Future<void> _autoRepairPhoto(String localPath) async {
    if (_refreshingPhotos.contains(localPath)) return;
    _refreshingPhotos.add(localPath);
    
    try {
      // 检查文件是否存在
      final file = File(localPath);
      if (!await file.exists()) {
        print('⚠️ 本地照片不存在: $localPath');
        if (mounted) setState(() { _refreshingPhotos.remove(localPath); });
        return;
      }
      
      // 上传到云端
      final cloudService = CloudBaseService.instance;
      final fileName = 'repaired_${_issue.id}_${DateTime.now().millisecondsSinceEpoch}_${localPath.hashCode}.jpg';
      final url = await cloudService.uploadImage(localPath, fileName);
      if (url != null && mounted) {
        setState(() {
          _refreshedPhotoUrls[localPath] = url;
        });
        print('✅ 本地照片已修复并上传到云端: $url');
      }
    } catch (e) {
      print('❌ 修复本地照片失败: $e');
    }
    
    if (mounted) {
      setState(() {
        _refreshingPhotos.remove(localPath);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // 使用 Consumer 监听数据变化，自动刷新界面
    return Consumer<IssueProvider>(
      builder: (context, provider, child) {
        // 当 Provider 数据更新时，重新从 Provider 获取
        final freshIssue = provider.getIssueById(widget.issue.id);
        if (freshIssue != null) {
          _issue = freshIssue;
        }

        Color statusColor;
        String statusText;

        // 根据新的业务逻辑显示状态
        if (_issue.status == IssueStatus.closed) {
          statusColor = Colors.green;
          statusText = '已完成';
        } else if (_issue.isOverdue && _issue.status == IssueStatus.pending) {
          statusColor = Colors.red;
          statusText = '待催办';
        } else if (_issue.status == IssueStatus.reviewing) {
          statusColor = Colors.purple;
          statusText = '待验收';
        } else if (_issue.status == IssueStatus.processing) {
          statusColor = Colors.blue;
          statusText = '待验收'; // processing 也在"待验收"统计中
        } else {
          // pending 状态
          statusColor = Colors.orange;
          statusText = '待反馈';
        }

        // 返回构建好的界面
        return _buildContent(context, statusColor, statusText);
      },
    );
  }

  Widget _buildContent(BuildContext context, Color statusColor, String statusText) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('问题详情'),
        backgroundColor: const Color(0xFF10B981),
        foregroundColor: Colors.white,
        actions: [
          Consumer<AuthProvider>(
            builder: (context, auth, _) {
              final currentUser = auth.currentUser;
              final isAdmin = auth.isAdmin;
              final isReporter = currentUser != null && (
                  currentUser.id == _issue.reporterId ||
                  currentUser.username == _issue.reporterId ||
                  currentUser.name == _issue.reporterName);
              // 管理员可以修改任何状态的问题，普通用户只能修改 pending 和 processing
              final canModify = (isAdmin || isReporter) &&
                  (isAdmin || _issue.status == IssueStatus.pending ||
                   _issue.status == IssueStatus.processing);
              // 管理员可以操作任何状态的问题，普通用户只能操作特定状态
              final canManage = currentUser != null && (isAdmin || isReporter);
              final canManageAnyStatus = isAdmin; // 管理员可操作任何状态

              if (!canModify) return const SizedBox.shrink();

              return PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert),
                onSelected: (value) {
                  if (value == 'recall') {
                    _showRecallDialog(context);
                  } else if (value == 'modify') {
                    _showModifyDialog(context, _issue);
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'modify',
                    child: Row(
                      children: [
                        Icon(Icons.edit, color: Colors.blue, size: 20),
                        SizedBox(width: 8),
                        Text('修改问题'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'recall',
                    child: Row(
                      children: [
                        Icon(Icons.delete_outline, color: Colors.red, size: 20),
                        SizedBox(width: 8),
                        Text('撤回问题'),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 头部状态
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              color: const Color(0xFF10B981),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          statusText,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      if (_issue.isOverdue) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.red,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            '超期${-_issue.daysRemaining}天',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _issue.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),

            // 基本信息
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 信息卡片
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.grey.withOpacity(0.1),
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        _buildInfoRow('问题类型', _issue.categoryName),
                        _buildInfoRow('严重程度', _issue.severityName),
                        _buildInfoRow('发现时间', _formatDate(_issue.createdAt)),
                        _buildInfoRow('整改期限', _formatDate(_issue.deadline)),
                        _buildInfoRow('检查人', _issue.reporterName),
                        _buildInfoRow('整改负责人', _issue.assigneeName),
                        _buildInfoRow('问题位置', _issue.location),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 问题描述
                  const Text(
                    '问题描述',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _issue.description,
                      style: const TextStyle(
                        color: Colors.grey,
                        height: 1.5,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 现场照片
                  Text(
                    '现场照片 (${_issue.photos.length}张)',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (_issue.photos.isEmpty)
                    Container(
                      height: 120,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.photo_library, size: 40, color: Colors.grey),
                            SizedBox(height: 8),
                            Text(
                              '暂无照片',
                              style: TextStyle(color: Colors.grey),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    SizedBox(
                      height: 120,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: _issue.photos.length,
                        itemBuilder: (context, index) {
                          final originalUrl = _issue.photos[index];
                          // 如果该照片的URL已被刷新过，使用新URL
                          final displayUrl = _refreshedPhotoUrls[originalUrl] ?? originalUrl;
                          // 判断类型：支持网络URL(http/https)、协议相对URL(//)、云端fileID(cloud://)
                          final isNetwork = displayUrl.startsWith('http://') || displayUrl.startsWith('https://') || displayUrl.startsWith('//');
                          final isCloudFile = displayUrl.startsWith('cloud://');
                          final isRefreshing = _refreshingPhotos.contains(originalUrl);
                          
                          // 如果是 cloud:// fileID 格式，自动触发刷新获取临时URL
                          if (isCloudFile && !_refreshedPhotoUrls.containsKey(originalUrl) && !_refreshingPhotos.contains(originalUrl)) {
                            _refreshPhotoUrl(originalUrl);
                          }
                          
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: GestureDetector(
                              onTap: () => _showFullScreenImage(context, displayUrl),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: isNetwork
                                    ? Image.network(
                                        displayUrl.startsWith('//') ? 'https:$displayUrl' : displayUrl,
                                        width: 120,
                                        height: 120,
                                        fit: BoxFit.cover,
                                        loadingBuilder: (context, child, loadingProgress) {
                                          if (loadingProgress == null) return child;
                                          return Container(
                                            width: 120,
                                            height: 120,
                                            color: Colors.grey[200],
                                            child: Center(
                                              child: isRefreshing
                                                  ? const SizedBox(
                                                      width: 20,
                                                      height: 20,
                                                      child: CircularProgressIndicator(strokeWidth: 2),
                                                    )
                                                  : const CircularProgressIndicator(strokeWidth: 2),
                                            ),
                                          );
                                        },
                                        errorBuilder: (context, error, stackTrace) {
                                          // 网络加载失败：可能是URL过期，尝试刷新
                                          if (!_refreshedPhotoUrls.containsKey(originalUrl)) {
                                            _refreshPhotoUrl(originalUrl);
                                          }
                                          return Container(
                                            width: 120,
                                            height: 120,
                                            color: Colors.grey[200],
                                            child: Column(
                                              mainAxisAlignment: MainAxisAlignment.center,
                                              children: [
                                                if (isRefreshing)
                                                  const SizedBox(
                                                    width: 20,
                                                    height: 20,
                                                    child: CircularProgressIndicator(strokeWidth: 2),
                                                  )
                                                else
                                                  Icon(Icons.refresh, color: Colors.grey[400], size: 24),
                                                const SizedBox(height: 4),
                                                Text(
                                                  isRefreshing ? '刷新中' : '点击重试',
                                                  style: TextStyle(fontSize: 10, color: Colors.grey[500]),
                                                ),
                                              ],
                                            ),
                                          );
                                        },
                                      )
                                    : isCloudFile
                                        ? Container(
                                            width: 120,
                                            height: 120,
                                            color: Colors.grey[200],
                                            child: const Column(
                                              mainAxisAlignment: MainAxisAlignment.center,
                                              children: [
                                                SizedBox(
                                                  width: 20,
                                                  height: 20,
                                                  child: CircularProgressIndicator(strokeWidth: 2),
                                                ),
                                                SizedBox(height: 4),
                                                Text(
                                                  '加载中',
                                                  style: TextStyle(fontSize: 10, color: Colors.grey),
                                                ),
                                              ],
                                            ),
                                          )
                                    : Image.file(
                                        File(displayUrl),
                                        width: 120,
                                        height: 120,
                                        fit: BoxFit.cover,
                                        errorBuilder: (context, error, stackTrace) {
                                          // 本地文件不存在，尝试自动修复（重建上传到云端）
                                          _autoRepairPhoto(displayUrl);
                                          return Container(
                                            width: 120,
                                            height: 120,
                                            color: Colors.grey[200],
                                            child: Column(
                                              mainAxisAlignment: MainAxisAlignment.center,
                                              children: [
                                                Icon(Icons.broken_image, color: Colors.grey[400]),
                                                const SizedBox(height: 4),
                                                Text(
                                                  isRefreshing ? '修复中' : '旧照片',
                                                  style: TextStyle(fontSize: 10, color: Colors.grey[500]),
                                                ),
                                              ],
                                            ),
                                          );
                                        },
                                      ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  const SizedBox(height: 16),

                  // 整改进展
                  if (_issue.status != IssueStatus.pending) ...[
                    const Text(
                      '整改进展',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('整改进度'),
                              Text(
                                _issue.status == IssueStatus.closed
                                    ? '100%'
                                    : '${50 + _issue.daysRemaining * 5}%',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF10B981),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: _issue.status == IssueStatus.closed
                                  ? 1.0
                                  : 0.5 + _issue.daysRemaining * 0.01,
                              backgroundColor: Colors.grey[200],
                              valueColor: const AlwaysStoppedAnimation<Color>(
                                Color(0xFF10B981),
                              ),
                              minHeight: 8,
                            ),
                          ),
                          if (_issue.rectificationNote != null) ...[
                            const SizedBox(height: 12),
                            Text(
                              '整改说明：${_issue.rectificationNote}',
                              style: const TextStyle(
                                color: Colors.grey,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],


                  // 操作按钮区域
                  Builder(
                    builder: (context) {
                      final auth = context.read<AuthProvider>();
                      final currentUser = auth.currentUser;
                      
                      // 判断是否为整改人（与 Provider._isCurrentUserAssignee 保持一致）
                      final isAssignee = currentUser != null && (
                          currentUser.id == _issue.assigneeId ||
                          currentUser.username == _issue.assigneeId ||
                          currentUser.name == _issue.assigneeId ||
                          currentUser.id == _issue.assigneeName ||
                          currentUser.username == _issue.assigneeName ||
                          currentUser.name == _issue.assigneeName
                      );
                      
                      // 判断是否为发起人（与 Provider._isCurrentUserReporter 保持一致）
                      final isReporter = currentUser != null && (
                          currentUser.id == _issue.reporterId ||
                          currentUser.username == _issue.reporterId ||
                          currentUser.name == _issue.reporterId ||
                          currentUser.id == _issue.reporterName ||
                          currentUser.username == _issue.reporterName ||
                          currentUser.name == _issue.reporterName
                      );
                      
                      // 判断是否有管理权限（管理员或发起人）
                      final canManage = currentUser != null && (auth.isAdmin || isReporter);
                      final isAdmin = auth.isAdmin; // 管理员可操作任何状态的问题
                      
                      return Column(
                        children: [
                          // ====== 待处理/整改中 状态 ======
                          if (_issue.status == IssueStatus.pending ||
                              _issue.status == IssueStatus.processing) ...[
                            // 【双向可见改造】整改人和发起人视角都显示完整往来时间轴
                            if (isAssignee || isReporter) ...[
                              // 1. 如果有驳回历史（多次驳回），显示完整时间轴
                              if (_issue.rejectionHistory.isNotEmpty) ...[
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.red[50],
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: Colors.red.withOpacity(0.3)),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Icon(Icons.warning_amber, color: Colors.red, size: 18),
                                          const SizedBox(width: 4),
                                          Text(
                                            '您的整改已被驳回，请查看以下意见',
                                            style: TextStyle(
                                              color: Colors.red[700],
                                              fontWeight: FontWeight.w500,
                                              fontSize: 13,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      // 按时间顺序显示完整驳回历史
                                      ..._issue.rejectionHistory.asMap().entries.map((entry) {
                                        final index = entry.key;
                                        final rejection = entry.value;
                                        final isLatest = index == _issue.rejectionHistory.length - 1;
                                        return _buildNoteCard(
                                          '驳回 ${index + 1}${isLatest ? "（最新）" : ""}',
                                          '${rejection.note}\n驳回人: ${rejection.reviewerName}  ${_formatDate(rejection.timestamp)}',
                                          isLatest ? Colors.red : Colors.grey,
                                        );
                                      }),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 12),
                              ] else if (_issue.rejectionNote != null && _issue.rejectionNote!.isNotEmpty) ...[
                                // 兼容旧数据：只有一个驳回意见时
                                _buildNoteCard('驳回意见', _issue.rejectionNote!, Colors.orange),
                                const SizedBox(height: 12),
                              ],
                              // 2. 显示历次整改反馈记录（完整时间轴）
                              if (_issue.rectificationHistory.isNotEmpty) ...[
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.blue[50],
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: Colors.blue.withOpacity(0.3)),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Icon(Icons.history, color: Colors.blue, size: 18),
                                          const SizedBox(width: 4),
                                          Text(
                                            '历次整改记录（共${_issue.rectificationHistory.length}次）',
                                            style: TextStyle(
                                              color: Colors.blue[700],
                                              fontWeight: FontWeight.w500,
                                              fontSize: 13,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      ..._issue.rectificationHistory.asMap().entries.map((entry) {
                                        final index = entry.key;
                                        final record = entry.value;
                                        final isLatest = index == _issue.rectificationHistory.length - 1;
                                        return Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            _buildNoteCard(
                                              '整改 ${index + 1}${isLatest ? "（最新）" : ""}',
                                              '${record.description}\n整改人: ${record.submitterName}  ${_formatDate(record.timestamp)}',
                                              isLatest ? Colors.blue : Colors.grey,
                                            ),
                                            // 显示该次整改的照片
                                            if (record.photos.isNotEmpty)
                                              _buildRectificationPhotoGrid(record.photos, isLatest ? Colors.blue : Colors.grey),
                                          ],
                                        );
                                      }),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 12),
                              ] else if (_issue.rectificationNote != null && _issue.rectificationNote!.isNotEmpty) ...[
                                // 兼容旧数据：只有一条整改反馈时
                                _buildNoteCard('之前的整改反馈', _issue.rectificationNote!, Colors.blue),
                                if (_issue.rectificationPhotos.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  _buildRectificationPhotoGrid(_issue.rectificationPhotos, Colors.blue),
                                ],
                                const SizedBox(height: 12),
                              ],
                              // 3. 提示：首次整改请查看问题详情
                              if (_issue.rectificationHistory.isEmpty && _issue.rectificationNote == null) ...[
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.green[50],
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: Colors.green.withOpacity(0.3)),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(Icons.info_outline, color: Colors.green[700], size: 18),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          '请查看上方「问题描述」和「现场照片」，了解需要整改的内容',
                                          style: TextStyle(
                                            color: Colors.green[700],
                                            fontSize: 13,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 12),
                              ],
                            ],
                            // 整改人显示"提交整改反馈"按钮
                            if (isAssignee)
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton(
                                  onPressed: () {
                                    _showRectificationDialog(context, _issue);
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF10B981),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(vertical: 14),
                                    textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.check_circle, size: 18),
                                      const SizedBox(width: 4),
                                      Text(_issue.status == IssueStatus.processing 
                                          ? '重新提交整改反馈' 
                                          : '我已完成整改'),
                                    ],
                                  ),
                                ),
                              ),
                            if (isAssignee) const SizedBox(height: 12),
                            // 联系/催办按钮行（管理员和发起人可见，管理员任何状态都可见）
                            Row(
                              children: [
                                Expanded(
                                  child: ElevatedButton(
                                    onPressed: () {
                                      _showContactOptions(context, _issue);
                                    },
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.white,
                                      foregroundColor: const Color(0xFF10B981),
                                      padding: const EdgeInsets.symmetric(vertical: 14),
                                      textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        side: const BorderSide(
                                          color: Color(0xFF10B981),
                                        ),
                                      ),
                                    ),
                                    child: const Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.phone, size: 18),
                                        SizedBox(width: 4),
                                        Text('联系'),
                                      ],
                                    ),
                                  ),
                                ),
                                // 管理员任何状态都可催办和修改整改人，发起人仅在 pending/processing 状态可见
                                if (canManage && (isAdmin || _issue.status == IssueStatus.pending || _issue.status == IssueStatus.processing)) ...[
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: ElevatedButton(
                                      onPressed: () => _sendReminder(context, _issue),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(0xFF10B981),
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(vertical: 14),
                                        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                      ),
                                      child: const Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(Icons.notifications_active, size: 18),
                                          SizedBox(width: 4),
                                          Text('催办'),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  IconButton(
                                    onPressed: () => _showChangeAssigneeDialog(context),
                                    icon: const Icon(Icons.swap_horiz),
                                    color: const Color(0xFF10B981),
                                    tooltip: '修改整改人',
                                  ),
                                ],
                              ],
                            ),
                            // 管理员在 pending/processing 状态也可直接验收
                            if (isAdmin && !canManage && (_issue.status == IssueStatus.pending || _issue.status == IssueStatus.processing))
                              Padding(
                                padding: const EdgeInsets.only(top: 12),
                                child: Column(
                                  children: [
                                    const Text(
                                      '管理员可直接验收该问题',
                                      style: TextStyle(color: Colors.grey, fontSize: 13),
                                    ),
                                    const SizedBox(height: 12),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: ElevatedButton(
                                            onPressed: () {
                                              _showReviewDialog(context, true);
                                            },
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: Colors.green,
                                              foregroundColor: Colors.white,
                                              padding: const EdgeInsets.symmetric(vertical: 14),
                                              textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                                              shape: RoundedRectangleBorder(
                                                borderRadius: BorderRadius.circular(12),
                                              ),
                                            ),
                                            child: const Text('验收通过'),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: ElevatedButton(
                                            onPressed: () {
                                              _showReviewDialog(context, false);
                                            },
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: Colors.red,
                                              foregroundColor: Colors.white,
                                              padding: const EdgeInsets.symmetric(vertical: 14),
                                              textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                                              shape: RoundedRectangleBorder(
                                                borderRadius: BorderRadius.circular(12),
                                              ),
                                            ),
                                            child: const Text('驳回'),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                          ],
                          
                          // ====== 待验收 状态 ======
                          if (_issue.status == IssueStatus.reviewing) ...[
                            // 管理员/发起人显示验收按钮
                            if (canManage)
                              Column(
                                children: [
                                  const Text(
                                    '整改人已提交整改，等待验收',
                                    style: TextStyle(color: Colors.grey, fontSize: 13),
                                  ),
                                  // 显示整改反馈内容
                                  if (_issue.rectificationNote != null && _issue.rectificationNote!.isNotEmpty)
                                    _buildNoteCard('整改反馈', _issue.rectificationNote!, Colors.blue),
                                  // 显示整改照片
                                  if (_issue.rectificationPhotos.isNotEmpty)
                                    _buildRectificationPhotoGrid(_issue.rectificationPhotos, Colors.blue),
                                  // 显示驳回历史（如果有）
                                  if (_issue.rejectionHistory.isNotEmpty) ...[
                                    ..._issue.rejectionHistory.asMap().entries.map((entry) {
                                      final index = entry.key;
                                      final rejection = entry.value;
                                      return _buildNoteCard(
                                        '驳回 ${index + 1}',
                                        '${rejection.note}\n驳回人: ${rejection.reviewerName}  ${_formatDate(rejection.timestamp)}',
                                        Colors.red,
                                      );
                                    }),
                                  ] else if (_issue.rejectionNote != null && _issue.rejectionNote!.isNotEmpty) ...[
                                    _buildNoteCard('驳回意见', _issue.rejectionNote!, Colors.red),
                                  ],
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: ElevatedButton(
                                          onPressed: () {
                                            _showReviewDialog(context, true);
                                          },
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.green,
                                            foregroundColor: Colors.white,
                                            padding: const EdgeInsets.symmetric(vertical: 14),
                                            textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                                            shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(12),
                                            ),
                                          ),
                                          child: const Text('验收通过'),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: ElevatedButton(
                                          onPressed: () {
                                            _showReviewDialog(context, false);
                                          },
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.red,
                                            foregroundColor: Colors.white,
                                            padding: const EdgeInsets.symmetric(vertical: 14),
                                            textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                                            shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(12),
                                            ),
                                          ),
                                          child: const Text('驳回'),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            // 管理员可直接验收 pending/processing 状态的问题
                            if (isAdmin && !canManage)
                              Column(
                                children: [
                                  const Text(
                                    '管理员可直接验收该问题',
                                    style: TextStyle(color: Colors.grey, fontSize: 13),
                                  ),
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: ElevatedButton(
                                          onPressed: () {
                                            _showReviewDialog(context, true);
                                          },
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.green,
                                            foregroundColor: Colors.white,
                                            padding: const EdgeInsets.symmetric(vertical: 14),
                                            textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                                            shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(12),
                                            ),
                                          ),
                                          child: const Text('验收通过'),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: ElevatedButton(
                                          onPressed: () {
                                            _showReviewDialog(context, false);
                                          },
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.red,
                                            foregroundColor: Colors.white,
                                            padding: const EdgeInsets.symmetric(vertical: 14),
                                            textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                                            shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(12),
                                            ),
                                          ),
                                          child: const Text('驳回'),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            // 整改人显示等待验收提示
                            if (isAssignee && !canManage)
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Colors.blue[50],
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Column(
                                  children: [
                                    const Icon(Icons.hourglass_empty, color: Colors.blue, size: 32),
                                    const SizedBox(height: 8),
                                    Text(
                                      _issue.rejectionHistory.isNotEmpty
                                        ? '您的整改已被驳回，请重新整改'
                                        : '整改反馈已提交，等待发起人验收',
                                      style: TextStyle(
                                        color: _issue.rejectionHistory.isNotEmpty ? Colors.red : Colors.blue, 
                                        fontWeight: FontWeight.w500
                                      ),
                                    ),
                                    // 显示驳回历史（优先显示）
                                    if (_issue.rejectionHistory.isNotEmpty) ...[
                                      ..._issue.rejectionHistory.asMap().entries.map((entry) {
                                        final index = entry.key;
                                        final rejection = entry.value;
                                        final isLatest = index == _issue.rejectionHistory.length - 1;
                                        return _buildNoteCard(
                                          '驳回 ${index + 1}${isLatest ? "(最新)" : ""}',
                                          '${rejection.note}\n驳回人: ${rejection.reviewerName}  ${_formatDate(rejection.timestamp)}',
                                          isLatest ? Colors.red : Colors.grey,
                                        );
                                      }),
                                    ] else if (_issue.rejectionNote != null && _issue.rejectionNote!.isNotEmpty) ...[
                                      _buildNoteCard('驳回意见', _issue.rejectionNote!, Colors.red),
                                    ],
                                    // 显示之前的整改反馈
                                    if (_issue.rectificationNote != null && _issue.rectificationNote!.isNotEmpty)
                                      _buildNoteCard('整改反馈', _issue.rectificationNote!, Colors.blue),
                                    // 显示整改照片
                                    if (_issue.rectificationPhotos.isNotEmpty)
                                      _buildRectificationPhotoGrid(_issue.rectificationPhotos, Colors.blue),
                                  ],
                                ),
                              ),
                          ],
                          
                          // ====== 已关闭 状态 ======
                          if (_issue.status == IssueStatus.closed)
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.green[50],
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                children: [
                                  const Icon(Icons.check_circle, color: Colors.green, size: 32),
                                  const SizedBox(height: 8),
                                  const Text(
                                    '问题已验收通过，整改完成',
                                    style: TextStyle(color: Colors.green, fontWeight: FontWeight.w500),
                                  ),
                                  // 驳回历史（验收后仍可查看历史驳回记录）
                                  if (_issue.rejectionHistory.isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    ..._issue.rejectionHistory.asMap().entries.map((entry) {
                                      final index = entry.key;
                                      final rejection = entry.value;
                                      final isLatest = index == _issue.rejectionHistory.length - 1;
                                      return _buildNoteCard(
                                        '驳回 ${index + 1}${isLatest ? "（最新）" : ""}',
                                        '${rejection.note}\n驳回人: ${rejection.reviewerName}  ${_formatDate(rejection.timestamp)}',
                                        Colors.orange,
                                      );
                                    }),
                                  ] else if (_issue.rejectionNote != null && _issue.rejectionNote!.isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    _buildNoteCard('驳回意见', _issue.rejectionNote!, Colors.orange),
                                  ],
                                  // 整改反馈
                                  if (_issue.rectificationNote != null && _issue.rectificationNote!.isNotEmpty)
                                    _buildNoteCard('整改反馈', _issue.rectificationNote!, Colors.blue),
                                  // 整改照片
                                  if (_issue.rectificationPhotos.isNotEmpty)
                                    _buildRectificationPhotoGrid(_issue.rectificationPhotos, Colors.blue),
                                  // 验收意见
                                  if (_issue.acceptanceNote != null && _issue.acceptanceNote!.isNotEmpty)
                                    _buildNoteCard('验收意见', _issue.acceptanceNote!, Colors.green),
                                ],
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.grey,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 显示意见卡片的辅助方法
  Widget _buildNoteCard(String title, String content, Color color) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.comment, color: color, size: 14),
              const SizedBox(width: 4),
              Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            content,
            style: TextStyle(color: Colors.grey[700], fontSize: 13),
          ),
        ],
      ),
    );
  }

  /// 构建缩略图（支持网络URL、cloud:// fileID 和本地文件）
  Widget _buildThumbnailImage(String path, bool isNetworkImage) {
    // 对 cloud:// 格式的 fileID，显示加载中（需先通过 getFreshPhotoUrl 获取临时URL）
    if (path.startsWith('cloud://')) {
      return Container(
        width: 80, height: 80, color: Colors.grey[200],
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
            SizedBox(height: 4),
            Text('加载中', style: TextStyle(fontSize: 8, color: Colors.grey)),
          ],
        ),
      );
    }
    
    if (isNetworkImage) {
      return Image.network(
        path.startsWith('//') ? 'https:$path' : path,
        width: 80, height: 80, fit: BoxFit.cover,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return Container(
            width: 80, height: 80, color: Colors.grey[200],
            child: const Center(
              child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
            ),
          );
        },
        errorBuilder: (context, error, stackTrace) {
          return Container(
            width: 80, height: 80, color: Colors.grey[200],
            child: const Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.broken_image, color: Colors.grey, size: 20),
                SizedBox(height: 2),
                Text('点击重试', style: TextStyle(fontSize: 8, color: Colors.grey)),
              ],
            ),
          );
        },
      );
    } else {
      // 本地路径：检查文件是否存在
      try {
        final file = File(path);
        if (file.existsSync()) {
          return Image.file(file, width: 80, height: 80, fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
          );
        }
      } catch (_) {}
      // 本地文件不存在
      return Container(
        width: 80, height: 80, color: Colors.grey[200],
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.broken_image, color: Colors.grey[300], size: 24),
            Text('旧照片', style: TextStyle(fontSize: 8, color: Colors.grey[400])),
          ],
        ),
      );
    }
  }

  /// 显示整改照片网格（支持本地文件和网络URL）
  Widget _buildRectificationPhotoGrid(List<String> photoPaths, Color color) {
    if (photoPaths.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.photo, color: color, size: 14),
              const SizedBox(width: 4),
              Text(
                '整改照片 (${photoPaths.length}张)',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: photoPaths.map((path) {
              final isNetworkImage = path.startsWith('http://') || path.startsWith('https://') || path.startsWith('//');
              // 对 cloud:// 格式的 fileID，自动在显示时刷新
              final isCloudFileId = path.startsWith('cloud://');
              // 如果已刷新，用刷新后的URL
              final displayPath = _refreshedPhotoUrls[path] ?? path;
              final refreshedIsNetwork = displayPath.startsWith('http://') || displayPath.startsWith('https://');
              // 自动触发 cloud:// 格式的刷新
              if (isCloudFileId && !_refreshedPhotoUrls.containsKey(path) && !_refreshingPhotos.contains(path)) {
                _refreshPhotoUrl(path);
              }
              return GestureDetector(
                onTap: () => _showPhotoViewer(context, displayPath),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: _buildThumbnailImage(displayPath, refreshedIsNetwork || isNetworkImage),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  /// 显示照片查看器（大图）- 支持本地文件和网络URL，网络URL过期时自动刷新
  void _showPhotoViewer(BuildContext context, String path) {
    final isNetworkImage = path.startsWith('http://') || path.startsWith('https://') || path.startsWith('//');
    final isCloudUrl = path.startsWith('cloud://');
    // 对于本地文件，检查是否存在
    bool localFileExists = false;
    if (!isNetworkImage && !isCloudUrl) {
      try {
        localFileExists = File(path).existsSync();
      } catch (_) {}
    }
    
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Stack(
          children: [
            Center(
              child: InteractiveViewer(
                child: isCloudUrl
                    ? Container(
                        color: Colors.black87,
                        child: const Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              CircularProgressIndicator(color: Colors.white),
                              SizedBox(height: 12),
                              Text('正在加载照片...', style: TextStyle(color: Colors.white70)),
                            ],
                          ),
                        ),
                      )
                    : isNetworkImage
                    ? Image.network(
                        path.startsWith('//') ? 'https:$path' : path,
                        fit: BoxFit.contain,
                        loadingBuilder: (context, child, loadingProgress) {
                          if (loadingProgress == null) return child;
                          return Container(
                            padding: const EdgeInsets.all(40),
                            color: Colors.grey[800],
                            child: const Center(
                              child: CircularProgressIndicator(
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            ),
                          );
                        },
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            padding: const EdgeInsets.all(40),
                            color: Colors.grey[800],
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.broken_image, color: Colors.grey[400], size: 60),
                                const SizedBox(height: 10),
                                Text('照片不可用（可能已过期）', style: TextStyle(color: Colors.grey[400])),
                              ],
                            ),
                          );
                        },
                      )
                    : localFileExists
                        ? Image.file(
                            File(path),
                            fit: BoxFit.contain,
                            errorBuilder: (context, error, stackTrace) {
                              return Container(
                                padding: const EdgeInsets.all(40),
                                color: Colors.grey[800],
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.broken_image, color: Colors.grey[400], size: 60),
                                    const SizedBox(height: 10),
                                    Text('照片不可用', style: TextStyle(color: Colors.grey[400])),
                                  ],
                                ),
                              );
                            },
                          )
                        : Container(
                            padding: const EdgeInsets.all(40),
                            color: Colors.grey[800],
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.broken_image, color: Colors.grey[400], size: 60),
                                const SizedBox(height: 10),
                                Text('照片已过期或已被清理', style: TextStyle(color: Colors.grey[400])),
                              ],
                            ),
                          ),
              ),
            ),
            // 关闭按钮
            Positioned(
              top: 10,
              right: 10,
              child: IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close, color: Colors.white, size: 30),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  // 显示联系方式选项
  void _showContactOptions(BuildContext context, Issue issue) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              '联系 ${issue.assigneeName}',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 20),
            // 一键拨打电话
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: Color(0xFF10B981),
                child: Icon(Icons.phone, color: Colors.white),
              ),
              title: const Text('📞 一键拨打电话'),
              subtitle: const Text('直接拨打整改人电话'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                Navigator.pop(context);
                // 从问题中获取整改人ID，然后查询其电话
                final phone = await _getAssigneePhone(issue.assigneeId, context);
                if (phone != null && phone.isNotEmpty) {
                  await PhoneService.makePhoneCall(phone);
                }
              },
            ),
            const Divider(),
            // 发送短信
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: Colors.blue,
                child: Icon(Icons.message, color: Colors.white),
              ),
              title: const Text('💬 发送短信'),
              subtitle: const Text('发送短信通知整改人'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                Navigator.pop(context);
                final phone = await _getAssigneePhone(issue.assigneeId, context);
                if (phone != null && phone.isNotEmpty) {
                  await PhoneService.sendSMS(
                    phone,
                    body: '【GZ巡查】您好，您有一条隐患问题需要处理：${issue.title}，请及时处理。',
                  );
                }
              },
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  // 获取整改人电话
  Future<String?> _getAssigneePhone(String assigneeId, BuildContext context) async {
    try {
      // 从AuthProvider获取用户列表
      final authProvider = context.read<AuthProvider>();
      
      // 尝试从当前用户列表中查找
      final allUsers = authProvider.getAllUsers();
      
      // 查找匹配的整改人
      for (var user in allUsers) {
        if (user.id == assigneeId || user.username == assigneeId) {
          if (user.phone.isNotEmpty) {
            return user.phone;
          }
        }
      }
      
      // 如果本地没找到，尝试从云端获取
      final cloudUsers = await authProvider.fetchAllUsersFromCloud();
      for (var user in cloudUsers) {
        if (user.id == assigneeId || user.username == assigneeId) {
          if (user.phone.isNotEmpty) {
            return user.phone;
          }
        }
      }
      
      // 没找到手机号
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('该用户未设置联系电话'),
            backgroundColor: Colors.orange,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
          ),
        );
      }
      return null;
    } catch (e) {
      print('获取整改人电话失败: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('获取联系电话失败'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
          ),
        );
      }
      return null;
    }
  }

  // 压缩图片 - 目标50KB以下（与问题发起时的压缩标准一致）
  Future<File?> _compressImage(File file) async {
    try {
      final fileSize = await file.length();
      print('📷 整改照片原始大小: ${(fileSize / 1024).toStringAsFixed(1)} KB');

      // 目标大小：50KB以下
      const targetSize = 50 * 1024;

      // 如果已经小于50KB，直接返回
      if (fileSize <= targetSize) {
        print('📷 照片已符合要求，无需压缩');
        return file;
      }

      // 分辨率等级：逐步降低
      const resolutions = [
        [1920, 1080],  // 保持1080p
        [1280, 720],   // 720p
        [1024, 576],   // 480p
        [800, 450],    // 低分辨率
        [640, 360],    // 极低分辨率
      ];

      // 使用应用文档目录
      final appDir = await getApplicationDocumentsDirectory();
      final compressDir = Directory('${appDir.path}/compressed_photos');
      if (!await compressDir.exists()) {
        await compressDir.create(recursive: true);
      }

      // 返回压缩结果文件
      File? lastResult;

      for (var resolution in resolutions) {
        int quality = 80;  // 初始质量

        for (int q = quality; q >= 20; q -= 10) {
          final timestamp = DateTime.now().millisecondsSinceEpoch;
          final uniqueId = '${timestamp}_${resolution[0]}x${resolution[1]}_q$q';
          final targetPath = '${compressDir.path}/compressed_$uniqueId.jpg';

          print('📷 尝试压缩: ${resolution[0]}x${resolution[1]}, 质量$q%');

          final result = await FlutterImageCompress.compressAndGetFile(
            file.absolute.path,
            targetPath,
            quality: q,
            minWidth: resolution[0],
            minHeight: resolution[1],
          );

          if (result != null) {
            // XFile 转换为 File
            final compressedFile = File(result.path);
            final compressedSize = await compressedFile.length();
            print('📷 分辨率${resolution[0]}x${resolution[1]}，质量$q%，大小: ${(compressedSize / 1024).toStringAsFixed(1)} KB');

            // 如果压缩后大小满足要求，返回
            if (compressedSize <= targetSize) {
              print('📷 压缩成功，满足50KB以下要求');
              return compressedFile;
            }

            // 保存当前最接近的结果
            if (lastResult == null || compressedSize < (lastResult.lengthSync())) {
              lastResult = compressedFile;
            }
          }
        }
      }

      // 返回最佳结果
      if (lastResult != null) {
        print('📷 返回压缩结果: ${(lastResult.lengthSync() / 1024).toStringAsFixed(1)} KB');
        return lastResult;
      }

      return file;
    } catch (e) {
      print('❌ 照片压缩失败: $e');
      return file; // 压缩失败返回原图
    }
  }

  // 拍照（拍照后立即压缩）
  Future<File?> _takeRectificationPhoto() async {
    try {
      final XFile? photo = await ImagePicker().pickImage(
        source: ImageSource.camera,
        maxWidth: 1920,
        maxHeight: 1080,
        imageQuality: 85,
      );

      if (photo == null) return null;

      // 压缩图片
      final originalFile = File(photo.path);
      final compressedFile = await _compressImage(originalFile);

      if (compressedFile != null) {
        final size = await compressedFile.length();
        print('📷 整改拍照压缩完成: ${(size / 1024).toStringAsFixed(1)} KB');
        return compressedFile;
      }
      return originalFile;
    } catch (e) {
      print('❌ 拍照失败: $e');
      return null;
    }
  }

  // 从相册选择照片
  Future<File?> _pickRectificationPhoto() async {
    try {
      final XFile? photo = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1920,
        maxHeight: 1080,
        imageQuality: 85,
      );

      if (photo == null) return null;

      // 压缩图片
      final originalFile = File(photo.path);
      final compressedFile = await _compressImage(originalFile);

      if (compressedFile != null) {
        final size = await compressedFile.length();
        print('📷 整改相册照片压缩完成: ${(size / 1024).toStringAsFixed(1)} KB');
        return compressedFile;
      }
      return originalFile;
    } catch (e) {
      print('❌ 选择照片失败: $e');
      return null;
    }
  }

  // 提交整改反馈对话框（支持文字+照片）
  void _showRectificationDialog(BuildContext context, Issue issue) {
    final noteController = TextEditingController();
    final List<File> _photoFiles = []; // 照片文件列表
    bool _isSubmitting = false; // 防止重复提交

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.check_circle, color: Color(0xFF10B981)),
                SizedBox(width: 8),
                Text('提交整改反馈'),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 问题信息卡片
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue[50],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '问题：${issue.title}',
                          style: const TextStyle(fontWeight: FontWeight.w500),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '位置：${issue.location}',
                          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 文字反馈
                  const Text(
                    '请描述您的整改措施和完成情况：',
                    style: TextStyle(fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: noteController,
                    maxLines: 3,
                    decoration: InputDecoration(
                      hintText: '例如：已完成设备维修，更换滤芯...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 照片反馈
                  Row(
                    children: [
                      const Text(
                        '整改照片：',
                        style: TextStyle(fontWeight: FontWeight.w500),
                      ),
                      Text(
                        '(${_photoFiles.length}/6)',
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // 照片网格
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      // 添加照片按钮
                      if (_photoFiles.length < 6) ...[
                        // 拍照按钮
                        _buildAddPhotoButton(
                          icon: Icons.camera_alt,
                          label: '拍照',
                          onTap: () async {
                            final file = await _takeRectificationPhoto();
                            if (file != null) {
                              setDialogState(() {
                                _photoFiles.add(file);
                              });
                            }
                          },
                        ),
                        // 相册按钮
                        _buildAddPhotoButton(
                          icon: Icons.photo_library,
                          label: '相册',
                          onTap: () async {
                            final file = await _pickRectificationPhoto();
                            if (file != null) {
                              setDialogState(() {
                                _photoFiles.add(file);
                              });
                            }
                          },
                        ),
                      ],
                      // 已选择的照片预览
                      ..._photoFiles.asMap().entries.map((entry) {
                        final index = entry.key;
                        final file = entry.value;
                        return _buildPhotoPreview(
                          file: file,
                          onRemove: () {
                            setDialogState(() {
                              _photoFiles.removeAt(index);
                            });
                          },
                        );
                      }),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '支持拍照或从相册选择，最多6张（自动压缩到50KB以下）',
                    style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: _isSubmitting ? null : () => Navigator.pop(dialogContext),
                child: const Text('取消'),
              ),
              ElevatedButton(
                onPressed: _isSubmitting
                    ? null
                    : () async {
                        final note = noteController.text.trim();
                        if (note.isEmpty && _photoFiles.isEmpty) {
                          ScaffoldMessenger.of(dialogContext).showSnackBar(
                            SnackBar(
                              content: const Text('请填写整改说明或添加照片'),
                              backgroundColor: Colors.orange,
                              behavior: SnackBarBehavior.floating,
                              duration: const Duration(seconds: 2),
                            ),
                          );
                          return;
                        }

                        setDialogState(() => _isSubmitting = true);

                        final auth = context.read<AuthProvider>();
                        final provider = context.read<IssueProvider>();
                        final chatProvider = dialogContext.read<ChatProvider>();

                        // 提交整改
                        final success = await provider.submitRectification(
                          issueId: issue.id,
                          description: note,
                          photos: _photoFiles,
                          submitterId: auth.currentUser?.id ?? '',
                          submitterName: auth.currentUser?.name ?? '',
                        );

                        // 提交成功后发送消息通知发起人和管理员
                        if (success) {
                          try {
                            // 通知发起人（整改人不是发起人时才发）
                            final isReporterSelf =
                                auth.currentUser?.id == issue.reporterId &&
                                auth.currentUser?.name == issue.reporterName;
                            if (!isReporterSelf) {
                              await chatProvider.sendMessage(
                                toUserId: issue.reporterId,
                                toUserName: issue.reporterName,
                                content:
                                    '【整改完成】${issue.description}\n\n请及时验收',
                                type: MessageType.text,
                                issueId: issue.id,
                                issueTitle: issue.title,
                              );
                            }
                            // 通知管理员
                            await chatProvider.sendMessage(
                              toUserId: 'admin',
                              toUserName: '管理员',
                              content:
                                  '【整改完成】${issue.description}\n\n整改人: ${auth.currentUser?.name ?? "未知"}\n请及时验收',
                              type: MessageType.text,
                              issueId: issue.id,
                              issueTitle: issue.title,
                            );
                          } catch (e) {
                            print('⚠️ 发送通知失败: ');
                          }
                        }

                        Navigator.pop(dialogContext);
                        Navigator.pop(context);

                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(success
                                ? '✅ 整改反馈已提交，等待验收'
                                : '❌ 提交失败，请重试'),
                            backgroundColor: success ? Colors.green : Colors.red,
                            behavior: SnackBarBehavior.floating,
                            duration: const Duration(seconds: 3),
                          ),
                        );
                      },
                style: ElevatedButton.styleFrom(
                  foregroundColor: Colors.white,
                  backgroundColor: const Color(0xFF10B981),
                ),
                child: _isSubmitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('提交'),
              ),
            ],
          );
        },
      ),
    );
  }

  // 添加照片按钮
  Widget _buildAddPhotoButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 70,
        height: 70,
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey[300]!),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.grey[600], size: 24),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(fontSize: 11, color: Colors.grey[600]),
            ),
          ],
        ),
      ),
    );
  }

  // 照片预览卡片
  Widget _buildPhotoPreview({required File file, required VoidCallback onRemove}) {
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.file(
            file,
            width: 70,
            height: 70,
            fit: BoxFit.cover,
          ),
        ),
        Positioned(
          top: -5,
          right: -5,
          child: InkWell(
            onTap: onRemove,
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: const BoxDecoration(
                color: Colors.red,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.close,
                color: Colors.white,
                size: 14,
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _showReviewDialog(BuildContext context, bool isApprove) {
    final noteController = TextEditingController();
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isApprove ? '验收通过' : '验收驳回意见'),
        content: TextField(
          controller: noteController,
          maxLines: 3,
          decoration: InputDecoration(
            hintText: isApprove ? '验收意见（选填）' : '驳回原因',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (!isApprove && noteController.text.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text('请填写驳回原因'),
                    backgroundColor: Colors.red,
                    behavior: SnackBarBehavior.floating,
                    duration: const Duration(seconds: 2),
                  ),
                );
                return;
              }
              
              final note = noteController.text.trim();
              final provider = context.read<IssueProvider>();
              
              // 验收通过时：更新状态并保存验收意见
              if (isApprove) {
                await provider.updateIssueStatus(
                  _issue!.id,
                  IssueStatus.closed,
                  acceptanceNote: note.isEmpty ? '验收通过' : note,
                );
              } else {
                // 驳回时：调用专门的驳回方法，一次性同步状态和驳回意见
                // 传入评审人信息以便记录到历史
                final auth = context.read<AuthProvider>();
                await provider.rejectIssue(
                  _issue!.id,
                  rejectionNote: note,
                  reviewerId: auth.currentUser?.id,
                  reviewerName: auth.currentUser?.name,
                );
              }
              
              // ====== 发送消息通知整改人 ======
              final auth = context.read<AuthProvider>();
              final chatProvider = context.read<ChatProvider>();
              final reviewerName = auth.currentUser?.name ?? '管理员';
              final assigneeId = _issue!.assigneeId;
              final assigneeName = _issue!.assigneeName;
              final reviewResult = isApprove ? '✅ 验收通过' : '❌ 驳回整改';
              final reviewComment = note.isNotEmpty ? '\n\n验收意见：$note' : '';
              
              await chatProvider.sendMessage(
                toUserId: assigneeId,
                toUserName: assigneeName,
                content: '【$reviewResult】${_issue!.title}$reviewComment\n\n验收人：$reviewerName',
                type: MessageType.issueNotify,
                issueId: _issue!.id,
                issueTitle: _issue!.title,
              );
              print('✅ 已通知整改人 $assigneeName ($assigneeId) 验收结果');
              
              Navigator.pop(context);
              Navigator.pop(context);
              
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(isApprove ? '验收通过，问题已关闭' : '已驳回，请整改人重新整改'),
                  backgroundColor: isApprove ? Colors.green : Colors.orange,
                  behavior: SnackBarBehavior.floating,
                  duration: const Duration(seconds: 3),
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              foregroundColor: Colors.white,
              backgroundColor: isApprove ? Colors.green : Colors.red,
            ),
            child: const Text('确认'),
          ),
        ],
      ),
    );
  }

  // 修改整改责任人
  Future<void> _showChangeAssigneeDialog(BuildContext parentContext) async {
    // 先获取 Provider，避免在 Dialog 内部获取不到
    final auth = parentContext.read<AuthProvider>();
    final issueProvider = parentContext.read<IssueProvider>();
    
    var users = auth.getAllUsers();
    
    if (users.isEmpty) {
      users = await auth.fetchAllUsersFromCloud();
    }
    
    showDialog(
      context: parentContext,
      builder: (dialogContext) => AlertDialog(
        title: const Text('修改整改责任人'),
        content: SizedBox(
          width: double.maxFinite,
          height: 400,
          child: ListView.builder(
            itemCount: users.length,
            itemBuilder: (context, index) {
              final user = users[index];
              final isSelected = user.id == _issue!.assigneeId || user.name == _issue!.assigneeName;
              
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: isSelected ? const Color(0xFF10B981) : Colors.grey,
                  child: Text(
                    user.name.isNotEmpty ? user.name[0] : '?',
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
                title: Text(user.name),
                subtitle: Text('${user.roleName} - ${user.department}'),
                trailing: isSelected ? const Icon(Icons.check, color: Color(0xFF10B981)) : null,
                onTap: isSelected ? null : () async {
                  Navigator.pop(dialogContext);
                  
                  // 确认对话框
                  final confirmed = await showDialog<bool>(
                    context: parentContext,
                    builder: (ctx) => AlertDialog(
                      title: const Text('确认修改'),
                      content: Text('确定将整改责任人从 "${_issue!.assigneeName}" 改为 "${user.name}" 吗？'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('取消'),
                        ),
                        ElevatedButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('确认'),
                        ),
                      ],
                    ),
                  );
                  
                  if (confirmed != true) return;
                  
                  // 使用预先获取的 Provider 更新整改人
                  final success = await issueProvider.updateAssignee(
                    _issue!.id,
                    user.id,
                    user.name,
                  );
                  

                  // 修改成功后发送消息通知新的整改人
                  if (success) {
                    try {
                      final chatProvider = parentContext.read<ChatProvider>();
                      final oldAssigneeName = _issue!.assigneeName;
                      final operatorName = auth.currentUser?.name ?? '未知用户';
                      
                      // 通知新的整改人
                      await chatProvider.sendMessage(
                        toUserId: user.id,
                        toUserName: user.name,
                        content: '【问题分配】您被指定为隐患问题的整改责任人\n\n问题: ${_issue!.title}\n\n请及时处理',
                        type: MessageType.text,
                        issueId: _issue!.id,
                        issueTitle: _issue!.title,
                      );
                      
                      // 同时通知原整改人（如有）
                      if (oldAssigneeName != user.name && _issue!.assigneeId.isNotEmpty) {
                        await chatProvider.sendMessage(
                          toUserId: _issue!.assigneeId,
                          toUserName: oldAssigneeName,
                          content: '【问题转移】隐患「${_issue!.title}」的整改责任人已更换为 ${user.name}\n\n操作人: $operatorName',
                          type: MessageType.text,
                          issueId: _issue!.id,
                          issueTitle: _issue!.title,
                        );
                      }
                      print('✅ 已发送通知给新整改人: ${user.name}');
                    } catch (e) {
                      print('⚠️ 发送通知失败: $e');
                    }
                  }
                  if (success && mounted) {
                    ScaffoldMessenger.of(parentContext).showSnackBar(
                      SnackBar(
                        content: Text('整改责任人已修改为 ${user.name}'),
                        backgroundColor: Colors.green,
                        behavior: SnackBarBehavior.floating,
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  }
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
        ],
      ),
    );
  }

  // 全屏查看图片（支持本地文件、网络URL和云端fileID）
  void _showFullScreenImage(BuildContext context, String imageUrl) {
    final isNetwork = imageUrl.startsWith('http://') || imageUrl.startsWith('https://') || imageUrl.startsWith('//');
    final isCloudUrl = imageUrl.startsWith('cloud://');
    // 检查本地文件是否存在
    bool localFileExists = false;
    if (!isNetwork && !isCloudUrl) {
      try { localFileExists = File(imageUrl).existsSync(); } catch (_) {}
    }
    
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            iconTheme: const IconThemeData(color: Colors.white),
            title: const Text('查看照片', style: TextStyle(color: Colors.white)),
          ),
          body: Center(
            child: InteractiveViewer(
              panEnabled: true,
              minScale: 0.5,
              maxScale: 4.0,
              child: isCloudUrl
                  ? const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircularProgressIndicator(color: Colors.white70),
                          SizedBox(height: 16),
                          Text('正在加载照片...', style: TextStyle(color: Colors.white54)),
                        ],
                      ),
                    )
                  : isNetwork
                  ? Image.network(
                      imageUrl.startsWith('//') ? 'https:$imageUrl' : imageUrl,
                      loadingBuilder: (context, child, loadingProgress) {
                        if (loadingProgress == null) return child;
                        return Center(
                          child: CircularProgressIndicator(
                            value: loadingProgress.expectedTotalBytes != null
                                ? loadingProgress.cumulativeBytesLoaded /
                                    loadingProgress.expectedTotalBytes!
                                : null,
                          ),
                        );
                      },
                      errorBuilder: (context, error, stackTrace) {
                        return const Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.broken_image, size: 64, color: Colors.white54),
                              SizedBox(height: 16),
                              Text(
                                '照片不可用（可能已过期）',
                                style: TextStyle(color: Colors.white54),
                              ),
                            ],
                          ),
                        );
                      },
                    )
                  : localFileExists
                      ? Image.file(
                          File(imageUrl),
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) {
                            return const Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.broken_image, size: 64, color: Colors.white54),
                                  SizedBox(height: 16),
                                  Text('照片不可用', style: TextStyle(color: Colors.white54)),
                                ],
                              ),
                            );
                          },
                        )
                      : const Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.broken_image, size: 64, color: Colors.white54),
                              SizedBox(height: 16),
                              Text('照片已过期', style: TextStyle(color: Colors.white54)),
                            ],
                          ),
                        ),
            ),
          ),
        ),
      ),
    );
  }

  // 发送催办通知
  Future<void> _sendReminder(BuildContext context, Issue issue) async {
    final authProvider = context.read<AuthProvider>();
    final chatProvider = context.read<ChatProvider>();
    
    // 获取当前用户信息
    final currentUser = authProvider.currentUser;
    if (currentUser == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('请先登录'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 1),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    // 获取整改人信息
    final allUsers = authProvider.getAllUsers();
    User? assignee;
    
    // 打印调试信息
    print('🔍 催办查找: assigneeId=${issue.assigneeId}, assigneeName=${issue.assigneeName}');
    print('🔍 当前用户列表:');
    for (var user in allUsers) {
      print('   - id=${user.id}, username=${user.username}, name=${user.name}');
      // 增加按姓名匹配
      if (user.id == issue.assigneeId || 
          user.username == issue.assigneeId ||
          user.name == issue.assigneeId ||
          user.name == issue.assigneeName) {
        assignee = user;
        print('   ✅ 匹配成功: ${user.name}');
      }
    }
    
    // 如果没找到，尝试从云端获取
    if (assignee == null) {
      try {
        final cloudUsers = await authProvider.fetchAllUsersFromCloud();
        for (var user in cloudUsers) {
          if (user.id == issue.assigneeId || 
              user.username == issue.assigneeId ||
              user.name == issue.assigneeId ||
              user.name == issue.assigneeName) {
            assignee = user;
            print('   ✅ 从云端匹配成功: ${user.name}');
            break;
          }
        }
      } catch (e) {
        print('从云端获取用户失败: $e');
      }
    }

    if (assignee == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('未找到整改负责人'),
            backgroundColor: Colors.orange,
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 2),
          ),
        );
      }
      return;
    }

    // 检查是否已经催办过（1小时内不重复催办）
    final now = DateTime.now();
    final lastHour = now.subtract(const Duration(hours: 1));
    bool canRemind = true;
    
    // 构建催办消息
    final reminderMessage = '【催办提醒】${currentUser.name} 催促您尽快处理隐患问题：\n'
        '「${issue.title}」\n'
        '问题位置：${issue.location}\n'
        '截止日期：${_formatDate(issue.deadline)}\n'
        '当前状态：${issue.statusName}'
        '${issue.isOverdue ? '\n⚠️ 已超期 ${-issue.daysRemaining} 天！' : ''}';

    try {
      // 通过聊天发送催办消息给整改人
      final success = await chatProvider.sendMessage(
        toUserId: assignee.id, // 使用id作为聊天目标ID，确保能正确查询
        toUserName: assignee.name,
        content: reminderMessage,
        type: MessageType.reminder, // 标记为催办类型
        issueId: issue.id,         // 关联隐患ID，用于点击跳转
        issueTitle: issue.title,   // 隐患标题
      );

      if (success) {
        if (context.mounted) {
          final messenger = ScaffoldMessenger.of(context);
          // 清除所有旧 SnackBar
          messenger.clearSnackBars();
          // 显示新的 SnackBar - 2秒自动消失，点击即消失
          messenger.showSnackBar(
            SnackBar(
              content: GestureDetector(
                onTap: () => messenger.hideCurrentSnackBar(),
                child: Text('✅ 已向 ${assignee?.name ?? '整改人'} 发送催办通知'),
              ),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
              margin: const EdgeInsets.all(16),
              action: SnackBarAction(
                label: '查看',
                textColor: Colors.white,
                onPressed: () {
                  messenger.hideCurrentSnackBar();
                  // 跳转到催办通知列表
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const ChatListScreen(),
                    ),
                  );
                },
              ),
            ),
          );
        }
      } else {
        if (context.mounted) {
          final messenger = ScaffoldMessenger.of(context);
          messenger.clearSnackBars();
          messenger.showSnackBar(
            const SnackBar(
              content: Text('发送催办通知失败，请稍后重试'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
              margin: EdgeInsets.all(16),
            ),
          );
        }
      }
    } catch (e) {
      print('发送催办失败: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('发送催办通知失败'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
            margin: EdgeInsets.all(16),
          ),
        );
      }
    }
  }

  // 撤回问题确认对话框
  void _showRecallDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber, color: Colors.red, size: 28),
            SizedBox(width: 8),
            Text('撤回问题'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('确定要撤回此问题吗？'),
            const SizedBox(height: 8),
            const Text('撤回后将无法恢复，问题将从列表中移除。', style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '「${_issue.title}」',
                style: TextStyle(color: Colors.orange[800], fontWeight: FontWeight.w500),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              foregroundColor: Colors.white,
              backgroundColor: Colors.red,
            ),
            onPressed: () async {
              Navigator.pop(ctx); // 关闭对话框
              final success = await context.read<IssueProvider>().recallIssue(_issue.id);
              if (context.mounted) {
                if (success) {
                  Navigator.pop(context); // 返回列表
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('问题已撤回'),
                      backgroundColor: Colors.green,
                      behavior: SnackBarBehavior.floating,
                      margin: EdgeInsets.all(16),
                    ),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('撤回失败，请稍后重试'),
                      backgroundColor: Colors.red,
                      behavior: SnackBarBehavior.floating,
                      margin: EdgeInsets.all(16),
                    ),
                  );
                }
              }
            },
            child: const Text('确认撤回', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // 修改问题对话框
  void _showModifyDialog(BuildContext context, Issue issue) {
    final titleController = TextEditingController(text: issue.title);
    final descController = TextEditingController(text: issue.description);
    final locationController = TextEditingController(text: issue.location);
    DateTime selectedDeadline = issue.deadline;
    IssueCategory selectedCategory = issue.category;
    SeverityLevel selectedSeverity = issue.severity;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('修改问题'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: titleController,
                  decoration: const InputDecoration(
                    labelText: '问题标题',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: '问题描述',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: locationController,
                  decoration: const InputDecoration(
                    labelText: '问题位置',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<IssueCategory>(
                  value: selectedCategory,
                  decoration: const InputDecoration(
                    labelText: '问题类别',
                    border: OutlineInputBorder(),
                  ),
                  items: IssueCategory.values.map((cat) {
                    String name;
                    switch (cat) {
                      case IssueCategory.wastewater: name = '废水排放';
                      case IssueCategory.wastegas: name = '废气排放';
                      case IssueCategory.solidWaste: name = '固废管理';
                      case IssueCategory.noise: name = '噪音污染';
                      case IssueCategory.other: name = '其他';
                    }
                    return DropdownMenuItem(value: cat, child: Text(name));
                  }).toList(),
                  onChanged: (v) => setState(() => selectedCategory = v!),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<SeverityLevel>(
                  value: selectedSeverity,
                  decoration: const InputDecoration(
                    labelText: '严重程度',
                    border: OutlineInputBorder(),
                  ),
                  items: SeverityLevel.values.map((sev) {
                    String name;
                    switch (sev) {
                      case SeverityLevel.general: name = '一般';
                      case SeverityLevel.serious: name = '较重';
                      case SeverityLevel.critical: name = '严重';
                    }
                    return DropdownMenuItem(value: sev, child: Text(name));
                  }).toList(),
                  onChanged: (v) => setState(() => selectedSeverity = v!),
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('截止日期'),
                  subtitle: Text(_formatDate(selectedDeadline)),
                  trailing: IconButton(
                    icon: const Icon(Icons.calendar_today),
                    onPressed: () async {
                      final date = await showDatePicker(
                        context: ctx,
                        initialDate: selectedDeadline,
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                      );
                      if (date != null) {
                        setState(() => selectedDeadline = date);
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (titleController.text.trim().isEmpty) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(
                      content: Text('标题不能为空'),
                      backgroundColor: Colors.red,
                      duration: Duration(seconds: 2),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                  return;
                }
                Navigator.pop(ctx);
                final success = await context.read<IssueProvider>().updateIssueDetail(
                  issue.id,
                  title: titleController.text.trim(),
                  description: descController.text.trim(),
                  category: selectedCategory.name,
                  severity: selectedSeverity.name,
                  deadline: selectedDeadline.toIso8601String().split('T')[0],
                  location: locationController.text.trim(),
                );
                if (context.mounted) {
                  if (success) {
                    // 重新加载问题详情
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('问题已修改'),
                        backgroundColor: Colors.green,
                        behavior: SnackBarBehavior.floating,
                        margin: EdgeInsets.all(16),
                      ),
                    );
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('修改失败，请稍后重试'),
                        backgroundColor: Colors.red,
                        behavior: SnackBarBehavior.floating,
                        margin: EdgeInsets.all(16),
                      ),
                    );
                  }
                }
              },
              child: const Text('保存修改'),
            ),
          ],
        ),
      ),
    );
  }
}