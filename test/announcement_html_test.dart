// 公告富文本图片 URL 消毒逻辑回归测试
// 关联修复：公告图片「加载失败」——确保内联 base64 / cloud:// / https 图片能进入
// AnnouncementImage 渲染，同时恶意协议被剥离。
import 'package:flutter_test/flutter_test.dart';
import 'package:env_inspection_new/utils/announcement_html.dart';

void main() {
  group('AnnouncementHtml.sanitize 图片URL安全过滤', () {
    test('内联 base64 data:image 图片应被保留', () {
      final html = '<img src="data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+M8AAAMBAQDJ/pLvAAAAAElFTkSuQmCC">';
      final out = AnnouncementHtml.sanitize(html);
      expect(out, contains('data:image/png;base64,'));
    });

    test('cloud:// fileID 图片应被保留', () {
      final html = '<img src="cloud://anuanbu1-1-6gjqaydwd067dbb1.xxx/announcements/a.jpg">';
      final out = AnnouncementHtml.sanitize(html);
      expect(out, contains('cloud://'));
    });

    test('普通 https 图片应被保留', () {
      final html = '<img src="https://example.com/a.png">';
      final out = AnnouncementHtml.sanitize(html);
      expect(out, contains('https://example.com/a.png'));
    });

    test('javascript: 协议应被剥离（防 XSS）', () {
      final html = '<img src="javascript:alert(1)">';
      final out = AnnouncementHtml.sanitize(html);
      expect(out, isNot(contains('javascript:')));
    });

    test('script 块应整块移除', () {
      final html = '<p>hi</p><script>alert(1)</script>';
      final out = AnnouncementHtml.sanitize(html);
      expect(out, isNot(contains('alert(1)')));
    });

    test('onclick 事件属性应被移除但保留图片地址', () {
      final html = '<img src="https://x.com/a.png" onclick="alert(1)">';
      final out = AnnouncementHtml.sanitize(html);
      expect(out, contains('https://x.com/a.png'));
      expect(out, isNot(contains('onclick')));
    });
  });
}
