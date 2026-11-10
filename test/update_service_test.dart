import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mt_forum/services/update_service.dart';

/// 更新检测：版本比较、Release 解析、按架构选包。
void main() {
  Map<String, dynamic> releaseJson({
    String tag = 'v2.9.1',
    List<Map<String, dynamic>>? assets,
  }) =>
      {
        'tag_name': tag,
        'body': '### 更新内容\n- 修了一个 bug\n- **新增** 屏蔽功能',
        'published_at': '2026-11-10T00:00:00Z',
        'assets': assets ??
            [
              {'name': 'app-arm64-v8a-release.apk', 'size': 23628018, 'browser_download_url': 'https://example.com/arm64.apk'},
              {'name': 'app-armeabi-v7a-release.apk', 'size': 21473358, 'browser_download_url': 'https://example.com/v7a.apk'},
              {'name': 'app-x86_64-release.apk', 'size': 25250550, 'browser_download_url': 'https://example.com/x86.apk'},
              {'name': 'app-release.apk', 'size': 65736032, 'browser_download_url': 'https://example.com/universal.apk'},
            ],
      };

  test('版本号按数字段比较，2.7.10 大于 2.7.9', () {
    expect(UpdateService.compareVersions('2.7.10', '2.7.9'), 1);
    expect(UpdateService.compareVersions('v2.7.9', '2.7.10'), -1);
    expect(UpdateService.compareVersions('2.8', '2.8.0'), 0);
    expect(UpdateService.compareVersions('2.10', '2.9.9'), 1);
    expect(UpdateService.compareVersions('3.0.0', '2.99.99'), 1);
  });

  test('带后缀的版本也能比，正式版排在预发布前面', () {
    expect(UpdateService.compareVersions('2.8.0', '2.8.0-beta'), 0);
    expect(UpdateService.compareVersions('2.8.1', '2.8.0-beta'), 1);
  });

  test('tag 去掉 v 前缀', () {
    expect(UpdateService.normalizeVersion('v2.7.6'), '2.7.6');
    expect(UpdateService.normalizeVersion('2.7.6'), '2.7.6');
    expect(UpdateService.normalizeVersion('  V2.7.6 '), '2.7.6');
  });

  test('解析 Release：四个包按体积排序，通用包垫底', () {
    final release = UpdateService.parseRelease(releaseJson())!;
    expect(release.version, '2.9.1');
    expect(release.apks.length, 4);
    expect(release.apks.first.name, 'app-armeabi-v7a-release.apk');
    expect(release.apks.last.name, 'app-release.apk');
    expect(release.apks.first.sizeText, '20.5 MB');
  });

  test('按架构挑包，认不出来退回通用包', () {
    final release = UpdateService.parseRelease(releaseJson())!;
    expect(release.assetFor('arm64-v8a')!.url, 'https://example.com/arm64.apk');
    expect(release.assetFor('x86_64')!.name, 'app-x86_64-release.apk');
    expect(release.assetFor('mips')!.name, 'app-release.apk');
  });

  test('没有通用包时挑第一个', () {
    final release = UpdateService.parseRelease(releaseJson(assets: [
      {'name': 'app-arm64-v8a-release.apk', 'size': 10, 'browser_download_url': 'https://example.com/a.apk'},
    ]))!;
    expect(release.assetFor('mips')!.name, 'app-arm64-v8a-release.apk');
  });

  test('缺 tag 或缺安装包时解析失败', () {
    expect(UpdateService.parseRelease({}), isNull);
    expect(UpdateService.parseRelease({'tag_name': 'v1.0.0', 'assets': []}), isNull);
    expect(
      UpdateService.parseRelease({
        'tag_name': 'v1.0.0',
        'assets': [
          {'name': 'notes.txt', 'browser_download_url': 'https://example.com/x.txt'},
        ],
      }),
      isNotNull,
    );
  });

  test('接口返回新版本时会给出更新', () async {
    final client = MockClient((request) async {
      expect(request.headers['User-Agent'], 'MTForum-App');
      return http.Response.bytes(
        utf8.encode(jsonEncode(releaseJson())),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    final check = await UpdateService.check(client: client);
    expect(check.hasUpdate, isTrue);
    expect(check.release!.version, '2.9.1');
    expect(check.release!.notes, contains('修了一个 bug'));
  });

  test('404 与 403 给出可读错误', () async {
    expect(
      (await UpdateService.check(client: MockClient((_) async => http.Response('', 404)))).error,
      contains('没有发布版本'),
    );
    expect(
      (await UpdateService.check(client: MockClient((_) async => http.Response('', 403)))).error,
      contains('太频繁'),
    );
    expect(
      (await UpdateService.check(client: MockClient((_) async => http.Response('', 500)))).error,
      contains('500'),
    );
  });

  test('网络异常不抛出，转成错误文案', () async {
    final check = await UpdateService.check(
      client: MockClient((_) async => throw http.ClientException('断了')),
    );
    expect(check.failed, isTrue);
    expect(check.hasUpdate, isFalse);
    expect(check.error, contains('检查更新失败'));
  });

  const atomXml = '''<?xml version="1.0" encoding="UTF-8"?>
<feed xmlns="http://www.w3.org/2005/Atom">
  <title>Release notes from mtforum-app</title>
  <entry>
    <id>tag:github.com,2008:Repository/1433555355/v2.7.6</id>
    <updated>2026-11-10T00:39:41Z</updated>
    <link rel="alternate" type="text/html" href="https://github.com/Aioprh/mtforum-app/releases/tag/v2.7.6"/>
    <title>v2.7.6</title>
    <content type="html">&lt;p&gt;修复居住地显示异常&lt;/p&gt;
&lt;ul&gt;&lt;li&gt;新增屏蔽功能&lt;/li&gt;&lt;/ul&gt;</content>
  </entry>
</feed>''';

  test('atom 降级：API 403 时仍能拿到版本和固定命名的安装包', () async {
    final client = MockClient((request) async {
      if (request.url.host == 'api.github.com') {
        return http.Response('', 403);
      }
      return http.Response.bytes(utf8.encode(atomXml), 200);
    });
    final check = await UpdateService.check(client: client);
    expect(check.hasUpdate, isTrue);
    expect(check.release!.version, '2.7.6');
    expect(check.release!.notes, contains('修复居住地显示异常'));
    expect(check.release!.apks.length, 4);
    expect(
      check.release!.assetFor('arm64-v8a')!.url,
      'https://github.com/Aioprh/mtforum-app/releases/download/v2.7.6/app-arm64-v8a-release.apk',
    );
  });

  test('atom 内容实体解码成纯文本', () {
    final release = UpdateService.parseAtom(atomXml)!;
    expect(release.notes, contains('新增屏蔽功能'));
    expect(release.notes, isNot(contains('<li>')));
  });

  test('atom 里没有 entry 时返回 null', () {
    expect(UpdateService.parseAtom('<feed></feed>'), isNull);
  });
}
