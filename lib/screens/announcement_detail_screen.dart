// lib/screens/announcement_detail_screen.dart
// 公告详情 - 富文本正文（自研渲染器）+ 进入即标记已读 + 附件展示

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/announcement.dart';
import '../providers/announcement_provider.dart';
import '../utils/announcement_html.dart';

class AnnouncementDetailScreen extends StatefulWidget {
  final Announcement announcement;

  const AnnouncementDetailScreen({super.key, required this.announcement});

  @override
  State<AnnouncementDetailScreen> createState() =>
      _AnnouncementDetailScreenState();
}

class _AnnouncementDetailScreenState extends State<AnnouncementDetailScreen> {
  @override
  void initState() {
    super.initState();
    // 首帧后再标记已读，避免与页面构建竞争
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<AnnouncementProvider>().markAsRead(widget.announcement.id);
    });
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.announcement;
    final expired = a.isExpired();
    final baseFont = Theme.of(context).textTheme.bodyMedium?.fontSize ?? 15.0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('公告详情'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 置顶 / 过期提示
            if (a.isPinned || expired) ...[
              Row(
                children: [
                  if (a.isPinned) _badge('置顶', const Color(0xFFFF9800)),
                  if (a.isPinned && expired) const SizedBox(width: 8),
                  if (expired) _badge('已过期', Colors.grey),
                ],
              ),
              const SizedBox(height: 10),
            ],
            // 标题
            Text(
              a.title.isEmpty ? '(无标题)' : a.title,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 12),
            // 元信息：分类 / 作者 / 时间
            Wrap(
              spacing: 12,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _meta(Icons.folder_outlined, a.categoryText),
                _meta(
                  Icons.person_outline,
                  a.authorName.isEmpty ? '系统发布' : a.authorName,
                ),
                if (a.displayTime != null)
                  _meta(Icons.access_time, _fullTime(a.displayTime!)),
              ],
            ),
            const SizedBox(height: 12),
            Consumer<AnnouncementProvider>(
              builder: (context, provider, _) => _meta(
                Icons.visibility_outlined,
                '${provider.readCount(a.id)} 人已读',
              ),
            ),
            const Divider(height: 28),
            // 正文（富文本）
            AnnouncementHtmlView(html: a.content, baseFontSize: baseFont),
            // 附件
            if (a.attachments.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Divider(height: 24),
              Text(
                '附件（${a.attachments.length}）',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),
              ...a.attachments.map(
                (url) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: AnnouncementImage(src: url, base: baseFont),
                ),
              ),
            ],
            if (a.content.trim().isEmpty && a.attachments.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 24),
                child: Center(
                  child: Text(
                    '暂无内容',
                    style: TextStyle(color: Colors.grey[500], fontSize: 14),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _badge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.6)),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _meta(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: Colors.grey[500]),
        const SizedBox(width: 4),
        Text(
          text,
          style: TextStyle(fontSize: 13, color: Colors.grey[600]),
        ),
      ],
    );
  }

  String _fullTime(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
  }
}
