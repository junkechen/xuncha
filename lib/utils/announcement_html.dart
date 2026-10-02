// lib/utils/announcement_html.dart
// 公告富文本渲染 - 自研轻量实现，零新增依赖
//
// 背景：公告正文由电脑端富文本编辑器产出（HTML）。本工程未引入任何 HTML 渲染库，
// 按「不引入未经确认的新技术栈」约束，这里用 flutter/material 自带组件实现。
//
// 支持：h1-h6 / p / br / div / strong,b / em,i / u / s,del / a / img /
//       ul,ol,li / blockquote / code,pre / hr
// 安全：先消毒再解析 —— 整块移除 script/style/iframe 等危险标签（含内容），
//       剔除 on* 事件属性，过滤 javascript:/vbscript:/data:text/html 协议。

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/cloudbase_service.dart';

/// 需要整块移除（连同内容）的危险标签
const String _blockTags =
    r'script|style|iframe|object|embed|link|meta|base|form|input|button|textarea|select|svg|math|template';

class AnnouncementHtml {
  AnnouncementHtml._();

  /// 消毒：把任意富文本清洗为可安全解析的片段
  static String sanitize(String? html) {
    var s = html ?? '';
    if (s.isEmpty) return '';
    // HTML 注释
    s = s.replaceAll(RegExp(r'<!--[\s\S]*?-->'), '');
    // 危险块（含内容）
    s = s.replaceAll(
      RegExp(r'<\s*(' + _blockTags + r')\b[\s\S]*?<\s*/\s*\1\s*>',
          caseSensitive: false),
      '',
    );
    // 残留危险标签
    s = s.replaceAll(
      RegExp(r'<\s*/?\s*(' + _blockTags + r')\b[^>]*>', caseSensitive: false),
      '',
    );
    // 事件属性 on*（大小写不敏感）
    s = s.replaceAllMapped(
      RegExp(r"""\son[a-zA-Z]+\s*=\s*(?:"[^"]*"|'[^']*'|[^\s>]+)""",
          caseSensitive: false),
      (_) => '',
    );
    // 危险协议
    s = s.replaceAllMapped(
      RegExp(r"""(href|src)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))""",
          caseSensitive: false),
      (m) {
        final name = m.group(1);
        final raw = m.group(2) ?? m.group(3) ?? m.group(4) ?? '';
        final safe = _sanitizeUrl(raw);
        return safe.isEmpty ? '' : '$name="$safe"';
      },
    );
    return s;
  }

  /// URL 协议白名单：http(s) / mailto / tel / data:image base64 / 相对路径
  static String _sanitizeUrl(String u) {
    final s = u.trim();
    if (s.isEmpty) return '';
    if (RegExp(r'^\s*(javascript|vbscript)\s*:', caseSensitive: false)
        .hasMatch(s)) {
      return '';
    }
    if (RegExp(r'^\s*data\s*:\s*text/html', caseSensitive: false)
        .hasMatch(s)) {
      return '';
    }
    if (RegExp(r'^data:image/(png|jpe?g|gif|webp);base64,', caseSensitive: false)
        .hasMatch(s)) {
      return s;
    }
    if (RegExp(r'^(https?:|mailto:|tel:|cloud:)', caseSensitive: false)
        .hasMatch(s)) {
      return s;
    }
    // 相对路径 / 锚点 / 同域路径
    if (RegExp(r'^[./#]').hasMatch(s) || RegExp(r'^[\w-]+([/?#]|$)').hasMatch(s)) {
      return s;
    }
    return '';
  }

  /// 剥离标签为纯文本（消毒后），用于摘要/搜索预览
  static String toPlainText(String? html) {
    final s = sanitize(html);
    if (s.isEmpty) return '';
    var t = s
        .replaceAllMapped(
            RegExp(r'<\s*(br|hr)\s*/?\s*>', caseSensitive: false), (_) => ' ')
        .replaceAllMapped(
            RegExp(r'<\s*/\s*(p|div|li|h[1-6]|tr|blockquote|pre)\s*>',
                caseSensitive: false),
            (_) => ' ')
        .replaceAll(RegExp(r'<[^>]*>'), '');
    t = _decodeEntities(t);
    return t.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// 实体解码（&amp; 必须最后处理，避免双重解码绕过）
  static String _decodeEntities(String s) => s
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&apos;', "'")
      .replaceAll('&amp;', '&');

  /// 构建渲染 Widget 列表
  /// [sink] 用于收集链接手势识别器，由调用方在 dispose 时统一释放
  static List<Widget> build({
    required BuildContext context,
    required String? html,
    required List<TapGestureRecognizer> sink,
    double? baseFontSize,
    Color? textColor,
  }) {
    final src = sanitize(html);
    if (src.trim().isEmpty) return const [];

    final base = baseFontSize ?? 15.0;
    final color = textColor ?? Theme.of(context).textTheme.bodyMedium?.color ?? Colors.black87;

    final spans = <InlineSpan>[];
    final widgets = <Widget>[];
    final stack = <_InlineStyle>[];
    final listStack = <String>[];
    var style = const _InlineStyle();
    var listIndex = 0;

    void addText(String raw) {
      if (raw.isEmpty) return;
      final text = _decodeEntities(raw);
      if (text.isEmpty) return;
      if (style.href != null && style.href!.isNotEmpty) {
        final recognizer = TapGestureRecognizer()
          ..onTap = () => _openLink(style.href!);
        sink.add(recognizer);
        spans.add(TextSpan(
          text: text,
          style: _textStyleOf(style, base, color),
          recognizer: recognizer,
        ));
      } else {
        spans.add(TextSpan(text: text, style: _textStyleOf(style, base, color)));
      }
    }

    void flush() {
      if (spans.isEmpty) return;
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: SelectableText.rich(
            TextSpan(children: List<InlineSpan>.of(spans)),
            textAlign: TextAlign.start,
          ),
        ),
      );
      spans.clear();
    }

    void push(_InlineStyle next) {
      stack.add(style);
      style = next;
    }

    void pop() {
      if (stack.isNotEmpty) style = stack.removeLast();
    }

    final tagRe = RegExp(r'<\s*(/?)\s*([a-zA-Z][a-zA-Z0-9-]*)\b([^>]*)>');
    var last = 0;
    for (final m in tagRe.allMatches(src)) {
      if (m.start > last) addText(src.substring(last, m.start));
      last = m.end;

      final closing = (m.group(1) ?? '').isNotEmpty;
      final tag = (m.group(2) ?? '').toLowerCase();
      final attrs = m.group(3) ?? '';

      switch (tag) {
        case 'br':
          flush();
          break;
        case 'p':
        case 'div':
        case 'tr':
        case 'pre':
          flush();
          break;
        case 'hr':
          flush();
          widgets.add(const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Divider(height: 1),
          ));
          break;
        case 'h1':
        case 'h2':
        case 'h3':
        case 'h4':
        case 'h5':
        case 'h6':
          flush();
          if (closing) {
            pop();
          } else {
            push(style.copyWith(
              headingLevel: int.tryParse(tag.substring(1)) ?? 3,
            ));
          }
          break;
        case 'ul':
        case 'ol':
          flush();
          if (closing) {
            if (listStack.isNotEmpty) listStack.removeLast();
            listIndex = 0;
          } else {
            listStack.add(tag);
            listIndex = 0;
          }
          break;
        case 'li':
          flush();
          if (!closing) {
            if (listStack.isNotEmpty && listStack.last == 'ol') {
              listIndex++;
              addText('$listIndex. ');
            } else {
              addText('• ');
            }
          }
          break;
        case 'blockquote':
          flush();
          if (closing) {
            pop();
          } else {
            push(style.copyWith(quote: true));
          }
          break;
        case 'img':
          flush();
          if (!closing) {
            final srcAttr = _attr(attrs, 'src');
            if (srcAttr != null && srcAttr.isNotEmpty) {
              widgets.add(AnnouncementImage(src: srcAttr, base: base));
            }
          }
          break;
        case 'strong':
        case 'b':
          closing ? pop() : push(style.copyWith(bold: true));
          break;
        case 'em':
        case 'i':
          closing ? pop() : push(style.copyWith(italic: true));
          break;
        case 'u':
          closing ? pop() : push(style.copyWith(underline: true));
          break;
        case 's':
        case 'del':
        case 'strike':
          closing ? pop() : push(style.copyWith(strike: true));
          break;
        case 'code':
          closing ? pop() : push(style.copyWith(mono: true));
          break;
        case 'a':
          if (closing) {
            pop();
          } else {
            push(style.copyWith(href: _attr(attrs, 'href'), clearHref: false));
          }
          break;
        default:
          break; // span/font 等忽略样式，仅保留文本
      }
    }
    if (last < src.length) addText(src.substring(last));
    flush();
    return widgets;
  }

  static String? _attr(String attrs, String name) {
    final m = RegExp('$name\\s*=\\s*"([^"]*)"', caseSensitive: false)
            .firstMatch(attrs) ??
        RegExp("$name\\s*=\\s*'([^']*)'", caseSensitive: false)
            .firstMatch(attrs);
    return m?.group(1);
  }

  static TextStyle _textStyleOf(_InlineStyle s, double base, Color color) {
    final level = s.headingLevel;
    final size = level > 0 ? base + (level <= 1 ? 8 : (level == 2 ? 5 : 2)) : base;
    final isLink = s.href != null && s.href!.isNotEmpty;
    return TextStyle(
      fontSize: size,
      height: 1.6,
      // 链接用主题主色 + 下划线，便于识别可点击
      color: isLink ? const Color(0xFF10B981) : (s.quote ? Colors.grey[700] : color),
      fontWeight: (s.bold || level > 0) ? FontWeight.bold : FontWeight.normal,
      fontStyle: s.italic ? FontStyle.italic : FontStyle.normal,
      fontFamily: s.mono ? 'monospace' : null,
      decoration: isLink
          ? TextDecoration.underline
          : (s.underline
              ? TextDecoration.underline
              : (s.strike ? TextDecoration.lineThrough : TextDecoration.none)),
    );
  }

  static Future<void> _openLink(String url) async {
    try {
      final uri = Uri.tryParse(url);
      if (uri == null) return;
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('⚠️ 打开链接失败: $e');
    }
  }
}

/// 行内样式状态（支持嵌套，通过栈 push/pop）
class _InlineStyle {
  final bool bold;
  final bool italic;
  final bool underline;
  final bool strike;
  final bool mono;
  final bool quote;
  final int headingLevel;
  final String? href;

  const _InlineStyle({
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.strike = false,
    this.mono = false,
    this.quote = false,
    this.headingLevel = 0,
    this.href,
  });

  _InlineStyle copyWith({
    bool? bold,
    bool? italic,
    bool? underline,
    bool? strike,
    bool? mono,
    bool? quote,
    int? headingLevel,
    String? href,
    bool clearHref = false,
  }) {
    return _InlineStyle(
      bold: bold ?? this.bold,
      italic: italic ?? this.italic,
      underline: underline ?? this.underline,
      strike: strike ?? this.strike,
      mono: mono ?? this.mono,
      quote: quote ?? this.quote,
      headingLevel: headingLevel ?? this.headingLevel,
      href: clearHref ? null : (href ?? this.href),
    );
  }
}

/// 正文内嵌图片：支持四种来源
///  - data:image/...;base64,  内联 base64（富文本粘贴/旧数据）→ Image.memory
///  - cloud:// fileID          云端文件 → 换取临时 URL
///  - http(s)/协议相对/相对路径 → 先尝试用云端刷新为有效临时 URL（修复「过期临时链接」
///    导致的「图片加载失败」），刷新失败则回退原链接交给 Image.network 暴露真实错误
class AnnouncementImage extends StatefulWidget {
  final String src;
  final double base;
  const AnnouncementImage({super.key, required this.src, required this.base});

  @override
  State<AnnouncementImage> createState() => AnnouncementImageState();
}

class AnnouncementImageState extends State<AnnouncementImage> {
  String? _resolved;
  bool _failed = false;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  /// 是否为内联 base64 data URI（data:image/...;base64,）
  bool get _isDataUri =>
      _resolved != null &&
      _resolved!.startsWith('data:image/') &&
      RegExp(r'^data:image/(png|jpe?g|gif|webp|bmp);base64,', caseSensitive: false)
          .hasMatch(_resolved!);

  static final RegExp _dataUriRe =
      RegExp(r'^data:image/(png|jpe?g|gif|webp|bmp);base64,', caseSensitive: false);

  Uint8List? _decodeDataUri(String s) {
    try {
      final comma = s.indexOf(',');
      if (comma < 0) return null;
      final meta = s.substring(0, comma).toLowerCase();
      if (!meta.contains(';base64')) return null;
      return base64Decode(s.substring(comma + 1));
    } catch (_) {
      return null;
    }
  }

  /// 尝试用云端换取新的临时 URL（处理已过期的 https 临时链接）。
  /// 返回刷新后的 URL；失败返回 null。
  Future<String?> _tryRefresh(String url) async {
    try {
      final path = CloudBaseService.instance.extractFilePathFromUrl(url);
      if (path == null || path.isEmpty) return null;
      final fresh = await CloudBaseService.instance.getFreshPhotoUrl(path);
      if (fresh != null && fresh.isNotEmpty) return fresh;
    } catch (_) {
      // 忽略，交由原链接兜底
    }
    return null;
  }

  Future<void> _resolve() async {
    if (!mounted) return;
    final src = widget.src.trim();
    if (src.isEmpty) {
      setState(() => _failed = true);
      return;
    }

    // 1) 内联 base64：直接解码，无需网络
    if (_dataUriRe.hasMatch(src)) {
      final bytes = _decodeDataUri(src);
      setState(() {
        _resolved = bytes != null ? src : null;
        _failed = bytes == null;
      });
      return;
    }

    // 2) cloud:// fileID：云端换取临时 URL
    if (src.startsWith('cloud://')) {
      await _resolveCloud(src);
      return;
    }

    // 3) 其余（http(s) / 协议相对 // / 相对路径 / 其它）：
    //    先尝试刷新为有效临时 URL，失败则回退原链接。
    final candidate = src.startsWith('//') ? 'https:$src' : src;
    final refreshed = await _tryRefresh(candidate);
    if (mounted) {
      setState(() {
        _resolved = refreshed ?? candidate;
        _failed = false;
      });
    }
  }

  Future<void> _resolveCloud(String fileId) async {
    if (mounted) setState(() => _loading = true);
    try {
      final url = await CloudBaseService.instance.getFreshPhotoUrl(fileId);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _resolved = (url != null && url.isNotEmpty) ? url : null;
        _failed = _resolved == null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  Future<void> _retry() async {
    if (!mounted) return;
    setState(() {
      _failed = false;
      _loading = true;
      _resolved = null;
    });
    await _resolve();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    if (_failed || _resolved == null) {
      return _errorTile(onRetry: _retry);
    }

    // 内联 base64：用 Image.memory 渲染（Flutter 的 Image.network 不支持 data: 协议）
    if (_isDataUri) {
      final bytes = _decodeDataUri(_resolved!);
      if (bytes == null) return _errorTile(onRetry: _retry);
      return _imageTile(
        child: Image.memory(
          bytes,
          width: double.infinity,
          fit: BoxFit.fitWidth,
          errorBuilder: (_, __, ___) => _errorTile(onRetry: _retry),
        ),
        onTap: () => _previewBytes(bytes),
      );
    }

    // 普通网络/临时 URL
    return _imageTile(
      child: Image.network(
        _resolved!,
        width: double.infinity,
        fit: BoxFit.fitWidth,
        errorBuilder: (_, __, ___) => _errorTile(onRetry: _retry),
      ),
      onTap: () => _preview(context, _resolved!),
    );
  }

  Widget _imageTile({required Widget child, required VoidCallback onTap}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: GestureDetector(
        onTap: onTap,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: child,
        ),
      ),
    );
  }

  Widget _errorTile({VoidCallback? onRetry}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.grey[200],
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.broken_image_outlined, color: Colors.grey[500], size: 20),
            const SizedBox(width: 8),
            Text('图片加载失败',
                style: TextStyle(color: Colors.grey[600], fontSize: widget.base - 2)),
            if (onRetry != null) ...[
              const SizedBox(width: 8),
              TextButton(
                onPressed: onRetry,
                child: Text('重试',
                    style: TextStyle(
                        color: const Color(0xFF10B981), fontSize: widget.base - 2)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _preview(BuildContext context, String url) {
    final showUrl = url.startsWith('//') ? 'https:$url' : url;
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.zero,
        child: Stack(
          children: [
            InteractiveViewer(
              child: Center(
                child: showUrl.startsWith('data:image/')
                    ? Image.memory(_decodeDataUri(showUrl) ?? Uint8List(0))
                    : Image.network(showUrl),
              ),
            ),
            Positioned(
              right: 16,
              top: 40,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 28),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _previewBytes(Uint8List bytes) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.zero,
        child: Stack(
          children: [
            InteractiveViewer(child: Center(child: Image.memory(bytes))),
            Positioned(
              right: 16,
              top: 40,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 28),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 对外使用的公告正文组件（负责释放链接手势识别器）
class AnnouncementHtmlView extends StatefulWidget {
  final String? html;
  final double? baseFontSize;

  const AnnouncementHtmlView({super.key, this.html, this.baseFontSize});

  @override
  State<AnnouncementHtmlView> createState() => _AnnouncementHtmlViewState();
}

class _AnnouncementHtmlViewState extends State<AnnouncementHtmlView> {
  final List<TapGestureRecognizer> _recognizers = [];

  void _clearRecognizers() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
  }

  @override
  void dispose() {
    _clearRecognizers();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 每次重建都先释放上一批识别器，避免累积泄漏
    _clearRecognizers();
    final widgets = AnnouncementHtml.build(
      context: context,
      html: widget.html,
      sink: _recognizers,
      baseFontSize: widget.baseFontSize,
    );
    if (widgets.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: widgets,
    );
  }
}
