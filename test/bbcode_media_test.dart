import 'package:flutter_test/flutter_test.dart';
import 'package:mt_forum/core/bbcode_media.dart';

void main() {
  group('parseBbcodeMedia', () {
    test('附件图片走站内地址', () {
      final items = parseBbcodeMedia('看这张\n[attachimg]321[/attachimg]\n好看吧');
      expect(items, hasLength(1));
      expect(items.single.aid, 321);
      expect(items.single.image, isTrue);
      expect(items.single.url, contains('mod=attachment'));
      expect(items.single.url, contains('aid=321'));
      expect(items.single.tag, '[attachimg]321[/attachimg]');
    });

    test('普通附件不当图片预览', () {
      final items = parseBbcodeMedia('[attach]88[/attach]');
      expect(items.single.aid, 88);
      expect(items.single.image, isFalse);
    });

    test('外链图片与带尺寸的图片都能认出来', () {
      final items = parseBbcodeMedia(
        '[img]https://a.example/1.png[/img]\n[img=600,480]https://a.example/2.png[/img]',
      );
      expect(items.map((e) => e.url), [
        'https://a.example/1.png',
        'https://a.example/2.png',
      ]);
      expect(items.every((e) => e.image), isTrue);
      expect(items.every((e) => e.aid == 0), isTrue);
    });

    test('同一段标记重复出现只算一次', () {
      final items = parseBbcodeMedia(
        '[attachimg]7[/attachimg]\n中间\n[attachimg]7[/attachimg]',
      );
      expect(items, hasLength(1));
    });

    test('混排时保持正文顺序', () {
      final items = parseBbcodeMedia(
        '[img]https://a.example/1.png[/img][attachimg]2[/attachimg][attach]3[/attach]',
      );
      expect(items.map((e) => e.aid), [0, 2, 3]);
    });

    test('没有媒体内容时返回空', () {
      expect(parseBbcodeMedia('只有文字'), isEmpty);
      expect(parseBbcodeMedia(''), isEmpty);
    });
  });

  group('attachmentIdsIn', () {
    test('图片和附件都算，重复只留一个', () {
      expect(
        attachmentIdsIn('[attachimg]11[/attachimg][attach]12[/attach][attachimg]11[/attachimg]'),
        [11, 12],
      );
    });

    test('外链图片不产生 aid', () {
      expect(attachmentIdsIn('[img]https://a.example/1.png[/img]'), isEmpty);
    });
  });
}
