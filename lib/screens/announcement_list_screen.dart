// lib/screens/announcement_list_screen.dart
// 公告列表 - 下拉刷新 + 上拉分页 + 置顶优先 + 未读标记
//
// 移动端浏览习惯：卡片流、置顶公告置顶展示、未读用红点+加粗区分，
// 过期/草稿/已删除公告不展示（由 Provider 的 visibleOnly 统一过滤）。

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/announcement.dart';
import '../providers/announcement_provider.dart';
import '../providers/auth_provider.dart';
import 'announcement_detail_screen.dart';

class AnnouncementListScreen extends StatefulWidget {
  const AnnouncementListScreen({super.key});

  @override
  State<AnnouncementListScreen> createState() => _AnnouncementListScreenState();
}

class _AnnouncementListScreenState extends State<AnnouncementListScreen> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    // 首帧后再加载，避免阻塞页面打开（与首页既有做法一致）
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final auth = context.read<AuthProvider>();
      final provider = context.read<AnnouncementProvider>();
      await provider.setCurrentUser(auth.currentUser?.id ?? '');
      if (!mounted) return;
      await provider.loadFirstPage();
    });
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  /// 上拉接近底部时加载更多
  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 200) {
      context.read<AnnouncementProvider>().loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('公告'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '刷新',
            onPressed: () {
              context.read<AnnouncementProvider>().refresh();
            },
          ),
        ],
      ),
      body: Consumer<AnnouncementProvider>(
        builder: (context, provider, _) {
          // 首次加载且无缓存 → 转圈
          if (provider.isLoading && provider.announcements.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }

          // 有错误且无内容 → 错误态（可下拉/点击重试）
          if (provider.error != null && provider.announcements.isEmpty) {
            return _buildErrorState(provider);
          }

          // 空列表
          if (provider.isEmpty) {
            return _buildEmptyState();
          }

          final list = provider.announcements;
          final hasMore = provider.hasMore;

          return RefreshIndicator(
            onRefresh: () => provider.refresh(),
            child: ListView.builder(
              controller: _scrollController,
              // 内容不足一屏时也能下拉刷新
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              itemCount: list.length + (hasMore ? 1 : 0),
              itemBuilder: (context, index) {
                if (index >= list.length) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Center(
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  );
                }
                return _buildItem(provider, list[index]);
              },
            ),
          );
        },
      ),
    );
  }

  /// 单条公告卡片
  Widget _buildItem(AnnouncementProvider provider, Announcement a) {
    final isUnread = !provider.isRead(a.id);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => _openDetail(a),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 标签行：置顶 / 未读 / 分类 / 时间
              Row(
                children: [
                  if (a.isPinned) ...[
                    _tag('置顶', const Color(0xFFFF9800), Colors.white),
                    const SizedBox(width: 6),
                  ],
                  if (isUnread) ...[
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                  _tag(
                    a.categoryText,
                    const Color(0xFFE8F5E9),
                    const Color(0xFF10B981),
                  ),
                  const Spacer(),
                  Text(
                    _formatTime(a.displayTime),
                    style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // 标题：未读加粗
              Text(
                a.title.isEmpty ? '(无标题)' : a.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 16,
                  height: 1.3,
                  fontWeight: isUnread ? FontWeight.bold : FontWeight.w500,
                  color: isUnread ? Colors.black87 : Colors.black54,
                ),
              ),
              const SizedBox(height: 6),
              // 摘要
              Text(
                a.plainTextPreview.isEmpty ? '暂无内容' : a.plainTextPreview,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, height: 1.4, color: Colors.grey[600]),
              ),
              const SizedBox(height: 8),
              // 底部信息行
              Row(
                children: [
                  Icon(Icons.person_outline, size: 13, color: Colors.grey[500]),
                  const SizedBox(width: 3),
                  Expanded(
                    child: Text(
                      a.authorName.isEmpty ? '系统发布' : a.authorName,
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (a.hasImage) ...[
                    Icon(Icons.image_outlined, size: 13, color: Colors.grey[500]),
                    const SizedBox(width: 8),
                  ],
                  Icon(Icons.visibility_outlined, size: 13, color: Colors.grey[500]),
                  const SizedBox(width: 3),
                  Text(
                    '${provider.readCount(a.id)}',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tag(String text, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 11, color: fg, fontWeight: FontWeight.w500),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.campaign_outlined, size: 80, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            '暂无公告',
            style: TextStyle(fontSize: 18, color: Colors.grey[600]),
          ),
          const SizedBox(height: 8),
          Text(
            '有新公告时会在这里显示',
            style: TextStyle(fontSize: 14, color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(AnnouncementProvider provider) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.wifi_off_outlined, size: 80, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            provider.error ?? '加载失败',
            style: TextStyle(fontSize: 16, color: Colors.grey[600]),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: () => provider.refresh(),
            icon: const Icon(Icons.refresh),
            label: const Text('重试'),
          ),
        ],
      ),
    );
  }

  void _openDetail(Announcement a) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AnnouncementDetailScreen(announcement: a),
      ),
    ).then((_) {
      // 从详情返回时刷新列表，保证未读红点立即消失
      if (mounted) {
        context.read<AnnouncementProvider>().notifyChange();
      }
    });
  }

  /// 相对时间（与催办列表保持一致）
  String _formatTime(DateTime? time) {
    if (time == null) return '';
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes}分钟前';
    if (diff.inHours < 24) return '${diff.inHours}小时前';
    if (diff.inDays < 7) return '${diff.inDays}天前';
    return '${time.month}/${time.day}';
  }
}
