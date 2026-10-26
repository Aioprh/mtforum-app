import 'dart:math' as math;

import 'package:html/dom.dart';
import 'package:html/parser.dart' as parser;

import '../core/app_config.dart';
import '../core/http_session.dart';
import '../core/waf_solver.dart';
import 'models.dart';

/// 论坛数据仓库：负责请求、解析与表单提交。
class ForumRepository {
  ForumRepository._();

  static final ForumRepository instance = ForumRepository._();

  final HttpSession _http = HttpSession.instance;

  static const String _loginPath = 'member.php?mod=logging&action=login&mobile=2';

  Future<void> init() => _http.init();

  // ---------------------------------------------------------------- 列表

  Future<List<ThreadSummary>> fetchGuide(String view, {int page = 1}) async {
    final result = await _http.get(
      'forum.php',
      query: {'mod': 'guide', 'view': view, 'mobile': '2', 'page': '$page'},
    );
    _ensureOk(result);
    return _parseThreadList(result.body);
  }

  Future<List<ThreadSummary>> fetchBoardThreads(int fid, {int page = 1}) async {
    final result = await _http.get(
      'forum.php',
      query: {'mod': 'forumdisplay', 'fid': '$fid', 'mobile': '2', 'page': '$page'},
    );
    _ensureOk(result);
    return _parseThreadList(result.body);
  }

  Future<List<ThreadSummary>> fetchAnnouncements() async {
    final all = await fetchBoardThreads(AppConfig.announcementFid);
    return all.take(4).toList();
  }

  /// 我的主题 / 我的回复 / 我的收藏等页面。
  Future<List<ThreadSummary>> fetchPersonalList(String path, {Map<String, String>? query}) async {
    final result = await _http.get(path, query: query);
    _ensureOk(result);
    final list = _parseThreadList(result.body);
    if (list.isNotEmpty) return list;
    return _parseLooseThreads(result.body);
  }

  Future<List<ForumCategory>> fetchBoards() async {
    final result = await _http.get('forum.php', query: {'forumlist': '1', 'mobile': '2'});
    _ensureOk(result);
    final doc = parser.parse(result.body);
    final categories = <ForumCategory>[];
    for (final group in doc.querySelectorAll('.comiis_forumlist')) {
      final title = _clean(group.querySelector('h2 a')?.text ?? group.querySelector('h2')?.text ?? '');
      final boards = <ForumBoard>[];
      for (final a in group.querySelectorAll('.comiis_forum_nbox li a')) {
        final href = a.attributes['href'] ?? '';
        final fid = _firstInt(RegExp(r'forum-(\d+)-1\.html').firstMatch(href)?.group(1));
        if (fid == null) continue;
        final img = a.querySelector('img');
        final badge = _clean(a.querySelector('em span')?.text ?? '');
        final name = _clean(a.querySelector('p')?.text ?? img?.attributes['alt'] ?? '');
        if (name.isEmpty) continue;
        boards.add(ForumBoard(
          fid: fid,
          name: name,
          icon: _absolute(img?.attributes['src']),
          todayPosts: int.tryParse(badge) ?? 0,
        ));
      }
      if (boards.isNotEmpty) {
        categories.add(ForumCategory(
          name: title.isEmpty ? '版块' : title,
          boards: boards,
        ));
      }
    }
    return categories;
  }

  // ---------------------------------------------------------------- 详情

  Future<ThreadDetail> fetchThread(
    int tid, {
    int page = 1,
    int? authorId,
    bool orderDesc = false,
  }) async {
    final query = <String, String>{
      'mod': 'viewthread',
      'tid': '$tid',
      'mobile': '2',
      'page': '$page',
    };
    if (authorId != null && authorId > 0) query['authorid'] = '$authorId';
    if (orderDesc) query['ordertype'] = '1';
    final result = await _http.get('forum.php', query: query);
    _ensureOk(result);
    final html = result.body;
    final doc = parser.parse(html);

    final title = _clean(
      (doc.querySelector('title')?.text ?? '').replaceAll(RegExp(r'\s*-\s*MT论坛\s*$'), ''),
    );

    var boardName = '';
    final keywords = doc.querySelector('meta[name=keywords]')?.attributes['content'] ?? '';
    final parts = keywords.split(',').map(_clean).where((e) => e.isNotEmpty).toList();
    if (parts.length >= 2 && parts[1] != AppConfig.siteName && !parts[1].startsWith('MT')) {
      boardName = parts[1];
    }

    var fid = 0;
    for (final form in doc.querySelectorAll('form')) {
      final action = form.attributes['action'] ?? '';
      final match = RegExp(r'[?&]fid=(\d+)').firstMatch(action);
      if (match != null) {
        fid = int.tryParse(match.group(1)!) ?? 0;
        break;
      }
    }
    if (fid == 0) {
      final link = doc.querySelector(r'a[href*="forum-"][href$="-1.html"]');
      final match = RegExp(r'forum-(\d+)-1\.html').firstMatch(link?.attributes['href'] ?? '');
      fid = int.tryParse(match?.group(1) ?? '') ?? 0;
      if (boardName.isEmpty) boardName = _clean(link?.text ?? '');
    }

    final posts = <ForumPost>[];
    for (final el in doc.querySelectorAll('.comiis_postli')) {
      final post = _parsePost(el, posts.length + 1);
      if (post != null) posts.add(post);
    }
    // 楼主楼层偶发取不到 uid，退回用楼顶作者区再补一次。
    if (posts.isNotEmpty && posts.first.uid == 0) {
      final href = doc.querySelector('.comiis_postli_top a[href*="uid="]')?.attributes['href'] ?? '';
      final uid = int.tryParse(RegExp(r'[?&]uid=(\d+)').firstMatch(href)?.group(1) ?? '') ?? 0;
      if (uid > 0) {
        final first = posts.first;
        posts[0] = first.copyWith(
          uid: uid,
          avatar: first.avatar.isEmpty ? _avatarForUid(uid) : null,
        );
      }
    }

    var total = posts.length;
    final commentNode = doc.querySelector('.comiis_pltit h2');
    if (commentNode != null) {
      final match = RegExp(r'(\d+)').firstMatch(commentNode.text.replaceAll(',', ''));
      if (match != null) total = (int.tryParse(match.group(1)!) ?? 0) + 1;
    }
    if (posts.length <= 1 && total <= 1) total = posts.length;

    final formhash = _findFormhash(html);
    final loggedIn = _http.hasLoginCookie || _isLoggedInHtml(html);
    final notice = posts.isEmpty ? _pageMessage(doc) ?? '' : '';

    return ThreadDetail(
      tid: tid,
      title: title,
      fid: fid,
      boardName: boardName,
      author: posts.isNotEmpty ? posts.first.author : '',
      time: posts.isNotEmpty ? posts.first.time : '',
      views: 0,
      replies: math.max(0, total - 1),
      posts: posts,
      formhash: formhash,
      hasMore: page * AppConfig.postsPerPage < total,
      isLoggedIn: loggedIn,
      likes: _intOf(doc.querySelector('.comiis_recommend_num')?.text ?? doc.querySelector('#recommendv_add')?.text),
      dislikes: _intOf(doc.querySelector('#recommendv_subtract')?.text),
      uploadHash: _findUploadHash(html),
      uid: _findUid(html),
      poll: _parsePoll(doc),
      notice: notice,
    );
  }

  /// 解析投票区块：兼容存在可投票表单与仅展示结果两种页面。
  Poll? _parsePoll(Document doc) {
    final container = doc.querySelector(
      '.comiis_poll, #poll, .poll, .comiis_pollbox, .pollpanel, form[action*="votepoll"]',
    );
    if (container == null) return null;

    final options = <PollOption>[];
    var multiple = false;
    for (final input in container.querySelectorAll('input')) {
      final type = (input.attributes['type'] ?? '').toLowerCase();
      if (type != 'radio' && type != 'checkbox') continue;
      final name = input.attributes['name'] ?? '';
      if (!name.contains('pollanswer') && !name.contains('polloption')) continue;
      final id = int.tryParse(input.attributes['value'] ?? '') ?? 0;
      if (id <= 0) continue;
      if (type == 'checkbox') multiple = true;
      final raw = _clean(input.parent?.text ?? '');
      final votes = RegExp(r'(\d+)\s*票').firstMatch(raw)?.group(1);
      final text = raw
          .replaceAll(RegExp(r'[（(]?\s*\d+\s*票[）)]?'), '')
          .replaceAll(RegExp(r'\d+(\.\d+)?%'), '')
          .trim();
      if (text.isEmpty) continue;
      options.add(PollOption(id: id, text: text, votes: int.tryParse(votes ?? '') ?? 0));
    }

    if (options.isEmpty) {
      for (final label in container.querySelectorAll('label, li, .polloption')) {
        final text = _clean(label.text);
        if (text.isEmpty || text.length > 80) continue;
        final votes = RegExp(r'(\d+)\s*票').firstMatch(text);
        options.add(PollOption(
          id: 0,
          text: text.replaceAll(RegExp(r'[（(]?\s*\d+\s*票[）)]?'), '').trim(),
          votes: int.tryParse(votes?.group(1) ?? '') ?? 0,
        ));
      }
    }
    if (options.isEmpty) return null;

    final text = _clean(container.text);
    final total = int.tryParse(RegExp(r'共\s*(\d+)\s*人参与').firstMatch(text)?.group(1) ?? '') ??
        options.fold<int>(0, (sum, option) => sum + option.votes);
    final hasForm = container.querySelector('input[type=radio], input[type=checkbox]') != null;
    return Poll(
      options: options,
      multiple: multiple || text.contains('多选'),
      total: total,
      voted: !hasForm && options.any((option) => option.votes > 0),
      expired: text.contains('投票已结束') || text.contains('已结束'),
    );
  }

  ForumPost? _parsePost(Element el, int floor) {
    final pidMatch = RegExp(r'pid(\d+)').firstMatch(el.attributes['id'] ?? '');
    if (pidMatch == null) return null;
    final pid = int.tryParse(pidMatch.group(1)!) ?? 0;

    final author = _clean(el.querySelector('.top_user')?.text ?? '');
    final uid = _postUid(el);
    var avatar = _postAvatar(el);
    if (avatar.isEmpty && uid > 0) avatar = _avatarForUid(uid);
    final level = _clean(el.querySelector('.top_lev')?.text ?? '');
    final timeNode = el.querySelector('.comiis_postli_time') ?? el.querySelector('.comiis_postli_times');
    var time = _clean(timeNode?.text ?? '');
    final location = _clean(el.querySelector('.comiis_iplocality')?.text ?? '').replaceAll(RegExp(r'^来自\s*'), '');
    if (location.isNotEmpty) time = time.replaceAll(location, '').trim();
    time = time.replaceAll(RegExp(r'来自\s*\S+$'), '').trim();

    final contentEl = el.querySelector('.comiis_messages') ??
        el.querySelector('.comiis_message_table') ??
        el.querySelector('.message');
    if (contentEl == null) return null;

    final images = <String>[];
    for (final img in contentEl.querySelectorAll('img')) {
      final src = _pickImage(img);
      if (src.isNotEmpty && !images.contains(src)) images.add(src);
    }

    return ForumPost(
      pid: pid,
      author: author,
      avatar: avatar,
      time: time,
      html: _sanitize(contentEl.innerHtml),
      floor: floor,
      uid: uid,
      level: level,
      location: location,
      isOp: floor == 1,
      likes: _intOf(el.querySelector('.comiis_recommend_num')?.text),
      images: images,
      comments: _parseComments(el),
    );
  }

  /// 楼中楼点评：兼容 Discuz 手机模板与桌面模板的几种容器。
  List<ForumComment> _parseComments(Element el) {
    final comments = <ForumComment>[];
    for (final container in el.querySelectorAll('.cm, .comiis_comment, .comment')) {
      var items = container.querySelectorAll('.cm_item');
      if (items.isEmpty) {
        items = container.children.where((child) => _clean(child.text).isNotEmpty).toList();
      }
      for (final item in items) {
        final text = _clean(item.querySelector('.cm_text')?.text ?? item.text);
        if (text.isEmpty || text.length > 600) continue;
        final authorLink = item.querySelector('.cm_name, a[href*="uid="]');
        final author = _clean(authorLink?.text ?? '');
        final uid = _firstInt(RegExp(r'[?&]uid=(\d+)').firstMatch(authorLink?.attributes['href'] ?? '')?.group(1)) ?? 0;
        final time = _clean(item.querySelector('.cm_time')?.text ?? '');
        comments.add(ForumComment(author: author, text: text, uid: uid, time: time));
        if (comments.length >= 30) return comments;
      }
    }
    return comments;
  }

  // ---------------------------------------------------------------- 账号

  Future<UserProfile> login(String username, String password, {int questionId = 0, String answer = ''}) async {
    final page = await _http.get(_loginPath);
    _ensureOk(page);
    final formHash = _findFormhash(page.body);
    final action = RegExp(r'<form[^>]+action="([^"]*loginsubmit[^"]*)"', caseSensitive: false)
        .firstMatch(page.body)
        ?.group(1)
        ?.replaceAll('&amp;', '&');
    if (formHash.isEmpty || action == null) {
      throw SiteException(_pageMessage(parser.parse(page.body)) ?? '登录页加载失败，请稍后重试');
    }

    final response = await _http.post(
      action,
      referer: AppConfig.uri(_loginPath).toString(),
      form: {
        'formhash': formHash,
        'referer': AppConfig.base,
        'fastloginfield': 'username',
        'cookietime': '31104000',
        'username': username,
        'password': password,
        'questionid': '$questionId',
        'answer': answer,
      },
    );

    final ok = _http.hasLoginCookie ||
        response.body.contains('欢迎您回来') ||
        response.body.contains('登录成功') ||
        response.body.contains('您已登录');
    if (!ok) {
      final doc = parser.parse(response.body);
      final msg = _pageMessage(doc);
      if (msg != null && msg.isNotEmpty) throw SiteException(msg);
      throw SiteException('登录失败，请检查用户名或密码');
    }
    return fetchMyProfile(fallbackName: username);
  }

  Future<UserProfile> fetchMyProfile({String fallbackName = ''}) async {
    final result = await _http.get(
      'home.php',
      query: {'mod': 'space', 'do': 'profile', 'mobile': '2'},
    );
    _ensureOk(result);
    final doc = parser.parse(result.body);
    final html = result.body;

    final uid = _firstInt(
      RegExp(r"discuz_uid\s*=\s*'(\d+)'").firstMatch(html)?.group(1) ??
          RegExp(r'[?&]uid=(\d+)').firstMatch(html)?.group(1) ??
          '0',
    ) ??
        0;

    var name = _clean(
      doc.querySelector('.comiis_space_name')?.text ??
          doc.querySelector('.space_name')?.text ??
          doc.querySelector('.top_user')?.text ??
          RegExp(r"username\s*=\s*'([^']*)'").firstMatch(html)?.group(1) ??
          '',
    );
    if (name.isEmpty) name = fallbackName;

    var avatar = _absolute(
      doc.querySelector('.comiis_space_tximg img')?.attributes['src'] ??
          doc.querySelector('a.comiis_space_tximg img')?.attributes['src'] ??
          doc.querySelector('img[src*="/avatar/"]')?.attributes['src'],
    );
    if ((avatar.isEmpty || _isPlaceholderImage(avatar)) && uid > 0) avatar = _avatarForUid(uid);

    final bodyText = _clean(doc.body?.text ?? '');
    final level = RegExp(r'(Lv\.\s*\d+[^\s]{0,8})').firstMatch(bodyText)?.group(1) ?? '';
    String numberAfter(String label) {
      final match = RegExp('$label\\s*[:：]?\\s*(\\d+)').firstMatch(bodyText);
      return match?.group(1) ?? '';
    }

    return UserProfile(
      uid: uid,
      username: name,
      avatar: avatar,
      level: _clean(level),
      credits: numberAfter('金币'),
      posts: numberAfter('主题'),
      replies: numberAfter('帖子'),
      followers: numberAfter('粉丝'),
      regTime: RegExp(r'注册时间\s*[:：]?\s*([0-9\-\/年月日]+)').firstMatch(bodyText)?.group(1) ?? '',
      group: _clean(doc.querySelector('.comiis_space_group')?.text ?? ''),
    );
  }

  Future<void> logout() async {
    _http.clear();
  }

  Future<ComposeInfo> fetchComposeInfo(int fid) async {
    final page = await _http.get(
      'forum.php',
      query: {'mod': 'post', 'action': 'newthread', 'fid': '$fid', 'mobile': '2'},
    );
    _ensureOk(page);
    final formhash = _findFormhash(page.body);
    if (formhash.isEmpty) {
      throw SiteException(_pageMessage(parser.parse(page.body)) ?? '请先登录后再发帖');
    }
    return ComposeInfo(
      formhash: formhash,
      uploadHash: _findUploadHash(page.body),
      uid: _findUid(page.body),
    );
  }

  /// 上传图片 / 附件，返回服务器分配的 aid，用于 `[attachimg]aid[/attachimg]`。
  Future<int> uploadAttachment({
    required List<int> bytes,
    required String filename,
    required String uploadHash,
    required int uid,
    required String referer,
    bool image = true,
  }) async {
    if (uploadHash.isEmpty) throw SiteException('上传凭证已失效，请返回后重试');
    final result = await _http.postFile(
      'misc.php',
      query: {
        'mod': 'swfupload',
        'operation': 'upload',
        'type': image ? 'image' : 'attach',
        'inajax': 'yes',
        'infloat': 'yes',
        'simple': '2',
      },
      field: 'Filedata',
      filename: filename,
      bytes: bytes,
      fields: {'uid': '$uid', 'hash': uploadHash},
      referer: referer,
    );
    final match = RegExp(r'DISCUZUPLOAD\|(\d*)\|(-?\d+)\|(\d+)').firstMatch(result.body);
    if (match == null) {
      final msg = _pageMessage(parser.parse(result.body));
      throw SiteException(msg ?? '上传失败，请稍后重试');
    }
    final status = int.tryParse(match.group(2)!) ?? -1;
    final aid = int.tryParse(match.group(3)!) ?? 0;
    if (status != 0 || aid <= 0) throw SiteException(_uploadMessage(status));
    return aid;
  }

  /// 点赞 / 踩。Discuz 的 recommend 接口需要页面 formhash。
  Future<void> recommend({
    required int tid,
    required String formhash,
    required bool up,
  }) async {
    if (formhash.isEmpty) throw SiteException('操作凭证已失效，请下拉刷新后重试');
    final result = await _http.get(
      'forum.php',
      query: {
        'mod': 'misc',
        'action': 'recommend',
        'do': up ? 'add' : 'subtract',
        'tid': '$tid',
        'hash': formhash,
        'mobile': '2',
      },
    );
    _ensureOk(result);
    if (result.body.contains('成功') || result.body.contains('感谢')) return;
    final msg = _pageMessage(parser.parse(result.body));
    throw SiteException(msg ?? (up ? '点赞失败，请稍后重试' : '操作失败，请稍后重试'));
  }

  /// 参与投票。`ids` 为选项 id，多选时逐个提交。
  Future<String> votePoll({
    required int tid,
    required int fid,
    required String formhash,
    required List<int> ids,
  }) async {
    if (ids.isEmpty) throw SiteException('请选择投票选项');
    if (formhash.isEmpty) throw SiteException('投票凭证已失效，请下拉刷新后重试');
    final form = <String, String>{
      'formhash': formhash,
      'pollsubmit': 'yes',
      'quickforward': 'yes',
      'handlekey': 'poll',
    };
    for (var i = 0; i < ids.length; i++) {
      form['pollanswers[$i]'] = '${ids[i]}';
    }
    final response = await _http.post(
      'forum.php',
      query: {
        'mod': 'misc',
        'action': 'votepoll',
        'tid': '$tid',
        'fid': '$fid',
        'mobile': '2',
      },
      referer: _threadReferer(tid),
      form: form,
    );
    final msg = _pageMessage(parser.parse(response.body));
    if (msg != null && _looksLikeError(msg)) throw SiteException(msg);
    return msg ?? '投票成功';
  }

  /// 编辑自己的帖子 / 回复。
  Future<String> editPost({
    required int fid,
    required int tid,
    required int pid,
    required String subject,
    required String message,
    required String formhash,
  }) async {
    final response = await _http.post(
      'forum.php',
      query: {
        'mod': 'post',
        'action': 'edit',
        'fid': '$fid',
        'tid': '$tid',
        'pid': '$pid',
        'editsubmit': 'yes',
        'mobile': '2',
      },
      referer: _threadReferer(tid),
      form: {
        'formhash': formhash,
        'subject': subject,
        'message': message,
        'posttime': '${DateTime.now().millisecondsSinceEpoch ~/ 1000}',
        'usesig': '1',
        'save': '',
      },
    );
    final msg = _pageMessage(parser.parse(response.body));
    if (msg != null && _looksLikeError(msg)) throw SiteException(msg);
    return '编辑成功';
  }

  /// 删除自己的帖子 / 回复（Discuz 用 `action=edit&delete=1`）。
  Future<String> deletePost({
    required int fid,
    required int tid,
    required int pid,
    required String formhash,
  }) async {
    final response = await _http.get(
      'forum.php',
      query: {
        'mod': 'post',
        'action': 'edit',
        'fid': '$fid',
        'tid': '$tid',
        'pid': '$pid',
        'delete': '1',
        'formhash': formhash,
        'mobile': '2',
      },
      referer: _threadReferer(tid),
    );
    final msg = _pageMessage(parser.parse(response.body));
    if (msg != null && _looksLikeError(msg)) throw SiteException(msg);
    return '已删除';
  }

  /// 举报主题或回复。
  Future<String> report({
    required int fid,
    required int tid,
    required int pid,
    required String formhash,
    required int reason,
    String message = '',
  }) async {
    final response = await _http.post(
      'forum.php',
      query: {
        'mod': 'misc',
        'action': 'report',
        'fid': '$fid',
        'tid': '$tid',
        'pid': '$pid',
        'reportsubmit': 'yes',
        'handlekey': 'report',
        'mobile': '2',
      },
      referer: _threadReferer(tid),
      form: {
        'formhash': formhash,
        'reason': '$reason',
        'message': message,
      },
    );
    final msg = _pageMessage(parser.parse(response.body));
    if (msg != null && _looksLikeError(msg)) throw SiteException(msg);
    return '举报已提交';
  }

  /// 给某个楼层评分（Discuz `misc&action=rate`）。
  Future<String> rate({
    required int tid,
    required int pid,
    required String formhash,
    required int score,
    String reason = '',
  }) async {
    final response = await _http.post(
      'forum.php',
      query: {
        'mod': 'misc',
        'action': 'rate',
        'tid': '$tid',
        'pid': '$pid',
        'ratesubmit': 'yes',
        'handlekey': 'rate',
        'inajax': '1',
        'mobile': '2',
      },
      referer: _threadReferer(tid),
      form: {
        'formhash': formhash,
        'score1': '$score',
        'reason': reason,
      },
    );
    final msg = _pageMessage(parser.parse(response.body));
    if (msg != null && _looksLikeError(msg)) throw SiteException(msg);
    return msg?.replaceAll(RegExp(r'<[^>]+>'), '') ?? '评分成功';
  }

  /// 版主管理：关闭 / 置顶 / 精华 / 警告 / 删除。
  Future<String> moderate({
    required int tid,
    required int fid,
    required String formhash,
    required String action,
  }) async {
    final response = await _http.post(
      'forum.php',
      query: {
        'mod': 'topicadmin',
        'action': action,
        'fid': '$fid',
        'tid': '$tid',
        'handlekey': 'topicadmin',
        'inajax': '1',
        'mobile': '2',
      },
      referer: _threadReferer(tid),
      form: {
        'formhash': formhash,
        'moderate[]': '$tid',
        if (action == 'digest') 'digest': '1',
      },
    );
    final msg = _pageMessage(parser.parse(response.body));
    if (msg != null && _looksLikeError(msg)) throw SiteException(msg);
    final labels = {
      'close': '主题已关闭',
      'stickreply': '已置顶',
      'digest': '已设为精华',
      'warn': '已警告',
      'delete': '已删除',
    };
    return labels[action] ?? '操作成功';
  }

  /// 站内私信。
  Future<String> sendPm({
    required int uid,
    required String formhash,
    required String message,
  }) async {
    final response = await _http.post(
      'home.php',
      query: {
        'mod': 'spacecp',
        'ac': 'pm',
        'op': 'send',
        'touid': '$uid',
        'pmsubmit': 'yes',
        'inajax': '1',
        'mobile': '2',
      },
      form: {
        'formhash': formhash,
        'touid': '$uid',
        'message': message,
      },
    );
    final msg = _pageMessage(parser.parse(response.body));
    if (msg != null && _looksLikeError(msg)) throw SiteException(msg);
    return '私信已发送';
  }

  /// 他人主页资料。`hash` 为关注操作所需的 formhash。
  Future<(UserProfile, String)> fetchUserProfile(int uid) async {
    final result = await _http.get(
      'home.php',
      query: {'mod': 'space', 'uid': '$uid', 'do': 'profile', 'mobile': '2'},
    );
    _ensureOk(result);
    final doc = parser.parse(result.body);
    final html = result.body;
    final bodyText = _clean(doc.body?.text ?? '');
    String numberAfter(String label) {
      final match = RegExp('$label\\s*[:：]?\\s*(\\d+)').firstMatch(bodyText);
      return match?.group(1) ?? '';
    }

    final name = _clean(
      doc.querySelector('.comiis_space_name')?.text ??
          doc.querySelector('.space_name')?.text ??
          doc.querySelector('.top_user')?.text ??
          RegExp(r"username\s*=\s*'([^']*)'").firstMatch(html)?.group(1) ??
          '',
    );
    var avatar = _absolute(
      doc.querySelector('.comiis_space_tximg img')?.attributes['src'] ??
          doc.querySelector('a.comiis_space_tximg img')?.attributes['src'] ??
          doc.querySelector('img[src*="/avatar/"]')?.attributes['src'],
    );
    if ((avatar.isEmpty || _isPlaceholderImage(avatar)) && uid > 0) avatar = _avatarForUid(uid);
    final level = RegExp(r'(Lv\.\s*\d+[^\s]{0,8})').firstMatch(bodyText)?.group(1) ?? '';

    return (
      UserProfile(
        uid: uid,
        username: name,
        avatar: avatar,
        level: _clean(level),
        credits: numberAfter('金币'),
        posts: numberAfter('主题'),
        replies: numberAfter('帖子'),
        followers: numberAfter('粉丝'),
        regTime: RegExp(r'注册时间\s*[:：]?\s*([0-9\-\/年月日]+)').firstMatch(bodyText)?.group(1) ?? '',
        group: _clean(doc.querySelector('.comiis_space_group')?.text ?? ''),
      ),
      _findFormhash(html),
    );
  }

  Future<List<ThreadSummary>> fetchUserThreads(int uid, {int page = 1}) => fetchPersonalList(
        'home.php',
        query: {
          'mod': 'space',
          'uid': '$uid',
          'do': 'thread',
          'view': 'me',
          'mobile': '2',
          'page': '$page',
        },
      );

  Future<List<ThreadSummary>> fetchUserReplies(int uid, {int page = 1}) => fetchPersonalList(
        'home.php',
        query: {
          'mod': 'space',
          'uid': '$uid',
          'do': 'reply',
          'view': 'me',
          'mobile': '2',
          'page': '$page',
        },
      );

  /// 关注 / 取消关注用户。
  Future<bool> followUser({required int uid, required bool follow, required String hash}) async {
    if (hash.isEmpty) throw SiteException('操作凭证已失效，请重新进入主页');
    final result = await _http.get(
      'home.php',
      query: {
        'mod': 'spacecp',
        'ac': 'follow',
        'op': follow ? 'add' : 'del',
        'hash': hash,
        'fuid': '$uid',
        'from': 'space',
        'mobile': '2',
      },
      referer: AppConfig.uri('home.php', {'mod': 'space', 'uid': '$uid'}).toString(),
    );
    _ensureOk(result);
    final msg = _pageMessage(parser.parse(result.body));
    if (msg != null && _looksLikeError(msg)) throw SiteException(msg);
    return follow;
  }

  /// 消息通知：回复提醒 / @提醒 / 系统通知。
  Future<List<NoticeItem>> fetchNotices({int page = 1}) async {
    final result = await _http.get(
      'home.php',
      query: {'mod': 'space', 'do': 'notice', 'mobile': '2', 'page': '$page'},
    );
    _ensureOk(result);
    final doc = parser.parse(result.body);
    final items = <NoticeItem>[];
    final containers = doc.querySelectorAll('.comiis_notice, .comiis_noticeli, .notice, .comiis_notice_list li');
    for (final el in containers) {
      final text = _clean(el.text);
      if (text.isEmpty || text.length > 400) continue;
      final link = el.querySelector('a[href]');
      items.add(NoticeItem(
        title: _clean(el.querySelector('h3, .comiis_notice_title, .title')?.text ?? text),
        text: text,
        time: _clean(el.querySelector('.time, .comiis_notice_time')?.text ?? ''),
        url: _absolute(link?.attributes['href']),
        kind: _clean(el.querySelector('.type')?.text ?? ''),
      ));
    }
    return items;
  }

  /// 排行榜：type ∈ member / thread / forum。
  Future<List<(String, String)>> fetchRanking(String type) async {
    final result = await _http.get(
      'misc.php',
      query: {'mod': 'ranklist', 'type': type, 'mobile': '2'},
    );
    _ensureOk(result);
    final doc = parser.parse(result.body);
    final items = <(String, String)>[];
    final rows = doc.querySelectorAll('.comiis_ranklist li, .ranklist li, ol li');
    for (final row in rows) {
      final name = _clean(row.querySelector('a')?.text ?? row.text);
      if (name.isEmpty) continue;
      final value = _clean(
        row.querySelector('.comiis_ranknum, .num, em, span')?.text ?? '',
      ).replaceAll(RegExp(r'^[^\d]*'), '');
      items.add((name, value));
    }
    if (items.isEmpty) {
      for (final a in doc.querySelectorAll('a[href*="uid="], a[href*="thread-"]')) {
        final name = _clean(a.text);
        if (name.isEmpty) continue;
        items.add((name, ''));
      }
    }
    return items;
  }

  /// 标签列表。
  Future<List<(String, int)>> fetchTags() async {
    final result = await _http.get('misc.php', query: {'mod': 'tag', 'mobile': '2'});
    _ensureOk(result);
    final doc = parser.parse(result.body);
    final tags = <(String, int)>[];
    final seen = <int>{};
    for (final a in doc.querySelectorAll('a[href*="mod=tag"]')) {
      final id = int.tryParse(
            RegExp(r'[?&]id=(\d+)').firstMatch(a.attributes['href'] ?? '')?.group(1) ?? '',
          ) ??
          0;
      final name = _clean(a.text);
      if (name.isEmpty || id <= 0 || !seen.add(id)) continue;
      tags.add((name, id));
    }
    return tags;
  }

  /// 标签下的主题列表。
  Future<List<ThreadSummary>> fetchTagThreads(int id, {int page = 1}) => fetchPersonalList(
        'misc.php',
        query: {'mod': 'tag', 'id': '$id', 'mobile': '2', 'page': '$page'},
      );

  /// 每日签到（k_misign 插件）。
  Future<String> signIn() async {
    final home = await _http.get('home.php', query: {'mobile': '2'});
    _ensureOk(home);
    final hash = _findFormhash(home.body);
    if (hash.isEmpty) throw SiteException('请先登录后再签到');
    final result = await _http.get(
      'plugin.php',
      query: {
        'id': 'k_misign:sign',
        'operation': 'qiandao',
        'format': 'button',
        'formhash': hash,
        'mobile': '2',
      },
      referer: AppConfig.uri('home.php', {'mobile': '2'}).toString(),
    );
    _ensureOk(result);
    final text = _clean(result.body);
    if (text.contains('已签到') || text.contains('签到成功') || text.contains('成功')) {
      return text.length <= 40 ? text : '签到成功';
    }
    final msg = _pageMessage(parser.parse(result.body));
    if (msg != null && _looksLikeError(msg)) throw SiteException(msg);
    return text.isEmpty ? '签到完成' : (text.length <= 40 ? text : '签到完成');
  }

  String _threadReferer(int tid) =>
      AppConfig.uri('forum.php', {'mod': 'viewthread', 'tid': '$tid', 'mobile': '2'}).toString();

  Future<String> reply({
    required int tid,
    required int fid,
    required String formhash,
    required String message,
    int? replyToPid,
    bool quote = false,
    List<int> attachmentIds = const [],
    bool useSignature = true,
  }) async {
    final query = <String, String>{
      'mod': 'post',
      'action': 'reply',
      'fid': '$fid',
      'tid': '$tid',
      'replysubmit': 'yes',
      'mobile': '2',
    };
    if (replyToPid != null && replyToPid > 0) {
      query[quote ? 'repquote' : 'reppost'] = '$replyToPid';
    }
    final response = await _http.post(
      'forum.php',
      referer: AppConfig.uri('forum.php', {'mod': 'viewthread', 'tid': '$tid', 'mobile': '2'}).toString(),
      query: query,
      form: {
        'formhash': formhash,
        'message': message,
        'posttime': '${DateTime.now().millisecondsSinceEpoch ~/ 1000}',
        'usesig': useSignature ? '1' : '0',
        for (final aid in attachmentIds) 'attachnew[$aid][description]': '',
      },
    );
    final doc = parser.parse(response.body);
    final msg = _pageMessage(doc);
    if (msg != null && _looksLikeError(msg)) throw SiteException(msg);
    if (response.body.contains('需要审核') || response.body.contains('审核')) {
      return '回复已提交，等待审核通过';
    }
    return '回复成功';
  }

  /// 楼中楼点评：Discuz 的 `action=comment`，直接挂在指定楼层下。
  Future<String> addComment({
    required int tid,
    required int pid,
    required String message,
    required String formhash,
  }) async {
    if (formhash.isEmpty) throw SiteException('点评凭证已失效，请下拉刷新后重试');
    final response = await _http.post(
      'forum.php',
      referer: AppConfig.uri('forum.php', {'mod': 'viewthread', 'tid': '$tid', 'mobile': '2'}).toString(),
      query: {
        'mod': 'post',
        'action': 'comment',
        'tid': '$tid',
        'pid': '$pid',
        'commentsubmit': 'yes',
        'mobile': '2',
      },
      form: {
        'formhash': formhash,
        'message': message,
        'posttime': '${DateTime.now().millisecondsSinceEpoch ~/ 1000}',
      },
    );
    final msg = _pageMessage(parser.parse(response.body));
    if (msg != null && _looksLikeError(msg)) throw SiteException(msg);
    return '点评成功';
  }

  Future<String> createThread({
    required int fid,
    required String subject,
    required String message,
    String formhash = '',
    List<int> attachmentIds = const [],
    bool replyOnly = false,
    bool orderDesc = false,
    bool notify = false,
    bool useSignature = true,
    bool poll = false,
    List<String> pollOptions = const [],
    bool pollMultiple = false,
    String tags = '',
    String readPerm = '',
    String price = '',
  }) async {
    var hash = formhash;
    if (hash.isEmpty) {
      final page = await _http.get(
        'forum.php',
        query: {
          'mod': 'post',
          'action': 'newthread',
          'fid': '$fid',
          if (poll) 'special': '1',
          'mobile': '2',
        },
      );
      _ensureOk(page);
      hash = _findFormhash(page.body);
    }
    if (hash.isEmpty) {
      throw SiteException('无法进入发帖页面');
    }

    final response = await _http.post(
      'forum.php',
      referer: AppConfig.uri('forum.php', {
        'mod': 'post',
        'action': 'newthread',
        'fid': '$fid',
        if (poll) 'special': '1',
        'mobile': '2',
      }).toString(),
      query: {
        'mod': 'post',
        'action': 'newthread',
        'fid': '$fid',
        'topicsubmit': 'yes',
        if (poll) 'special': '1',
        'mobile': '2',
      },
      form: {
        'formhash': hash,
        'posttime': '${DateTime.now().millisecondsSinceEpoch ~/ 1000}',
        'wysiwyg': '1',
        'subject': subject,
        'message': message,
        'tags': tags,
        'usesig': useSignature ? '1' : '0',
        if (readPerm.isNotEmpty && readPerm != '0') 'readperm': readPerm,
        if (price.isNotEmpty && price != '0') 'price': price,
        if (replyOnly) 'replyonly': '1',
        if (orderDesc) 'ordertype': '1',
        if (notify) 'emailnotify': '1',
        if (poll) ...{
          'polloptions': pollOptions.join('\n'),
          'pollmultiple': pollMultiple ? '1' : '0',
          'maxselect': pollMultiple ? '${pollOptions.length}' : '1',
        },
        for (final aid in attachmentIds) 'attachnew[$aid][description]': '',
        'save': '',
      },
    );
    final doc = parser.parse(response.body);
    final msg = _pageMessage(doc);
    if (msg != null && _looksLikeError(msg)) throw SiteException(msg);
    if (response.body.contains('审核')) return '主题已提交，等待审核通过';
    final tid = RegExp(r'thread-(\d+)-1-1\.html').firstMatch(response.uri.toString())?.group(1);
    return tid == null ? '发布成功' : '发布成功，主题 ID $tid';
  }

  Future<String> addFavorite({required int tid, required String formhash}) async {
    final response = await _http.post(
      'home.php',
      referer: AppConfig.uri('forum.php', {'mod': 'viewthread', 'tid': '$tid', 'mobile': '2'}).toString(),
      query: {
        'mod': 'spacecp',
        'ac': 'favorite',
        'type': 'thread',
        'id': '$tid',
        'favoritesubmit': 'yes',
        'handlekey': 'favorite',
        'mobile': '2',
      },
      form: {'formhash': formhash, 'description': ''},
    );
    final doc = parser.parse(response.body);
    final msg = _pageMessage(doc);
    if (msg != null && _looksLikeError(msg)) throw SiteException(msg);
    return msg == null || msg.length > 40 ? '已加入收藏' : msg;
  }

  /// Discuz 原生搜索：formhash -> POST 关键词 -> searchid 翻页。
  Future<List<ThreadSummary>> search(String keyword, {int fid = 0, int maxPages = 3}) async {
    final page = await _http.get('search.php', query: {'mod': 'forum', 'mobile': '2'});
    _ensureOk(page);
    final formHash = _findFormhash(page.body);
    if (formHash.isEmpty) {
      throw SiteException(_pageMessage(parser.parse(page.body)) ?? '搜索需要登录，请先登录');
    }

    final response = await _http.post(
      'search.php',
      referer: AppConfig.uri('search.php', {'mod': 'forum', 'mobile': '2'}).toString(),
      query: {'mod': 'forum', 'mobile': '2'},
      form: {
        'formhash': formHash,
        'srchtxt': keyword,
        'searchsubmit': 'yes',
        if (fid > 0) 'srchfid[]': '$fid',
      },
    );
    final sid = RegExp(r'searchid=(\d+)').firstMatch(response.body)?.group(1);
    if (sid == null) {
      final items = _parseThreadList(response.body);
      if (items.isNotEmpty) return items;
      final loose = _parseLooseThreads(response.body);
      if (loose.isNotEmpty) return loose;
      throw SiteException(_pageMessage(parser.parse(response.body)) ?? '没有找到相关帖子');
    }

    final results = <ThreadSummary>[];
    final seen = <int>{};
    for (var pageNo = 1; pageNo <= maxPages; pageNo++) {
      final result = await _http.get(
        'search.php',
        query: {
          'mod': 'forum',
          'searchid': sid,
          'orderby': 'lastpost',
          'ascdesc': 'desc',
          'searchsubmit': 'yes',
          'kw': keyword,
          'mobile': '2',
          'page': '$pageNo',
        },
      );
      _ensureOk(result);
      final items = _parseThreadList(result.body);
      if (items.isEmpty) break;
      for (final item in items) {
        if (seen.add(item.tid)) results.add(item);
      }
      if (items.length < AppConfig.pageSize) break;
    }
    return results;
  }

  // ---------------------------------------------------------------- 解析

  List<ThreadSummary> _parseThreadList(String html) {
    final doc = parser.parse(html);
    final items = <ThreadSummary>[];
    for (final li in doc.querySelectorAll('li.forumlist_li')) {
      final titleLink = li.querySelector('.mmlist_li_box h2 a[href*="thread-"]') ??
          li.querySelector('.mmlist_li_box a[href*="thread-"]');
      if (titleLink == null) continue;
      final href = titleLink.attributes['href'] ?? '';
      final tid = _firstInt(RegExp(r'thread-(\d+)').firstMatch(href)?.group(1));
      if (tid == null) continue;

      final images = <String>[];
      for (final img in li.querySelectorAll('img.comiis_loadimages, .comiis_pyqlist_imgs img')) {
        final src = _pickImage(img);
        if (src.isNotEmpty && !images.contains(src)) images.add(src);
      }

      final numbers = <int>[];
      for (final span in li.querySelectorAll('.comiis_xznalist_bottom span.comiis_tm')) {
        final value = int.tryParse(_clean(span.text));
        if (value != null) numbers.add(value);
      }

      items.add(ThreadSummary(
        tid: tid,
        title: _clean(titleLink.text),
        url: _absolute(href),
        excerpt: _clean(li.querySelector('.list_body')?.text ?? ''),
        author: _clean(li.querySelector('.top_user')?.text ?? ''),
        avatar: _postAvatar(li),
        uid: _postUid(li),
        time: _clean(li.querySelector('.forumlist_li_time')?.text ?? ''),
        boardName: _clean(li.querySelector('.comiis_xznalist_bk a')?.text ?? ''),
        images: images.take(3).toList(),
        replies: numbers.length >= 2 ? numbers[1] : 0,
        views: numbers.length >= 3 ? numbers[2] : 0,
      ));
    }
    return items;
  }

  /// 兜底：从任意页面提取主题链接（个人中心、收藏页等）。
  List<ThreadSummary> _parseLooseThreads(String html) {
    final doc = parser.parse(html);
    final items = <ThreadSummary>[];
    final seen = <int>{};
    for (final a in doc.querySelectorAll('a[href*="thread-"]')) {
      final text = _clean(a.text);
      if (text.length < 4) continue;
      final tid = _firstInt(RegExp(r'thread-(\d+)').firstMatch(a.attributes['href'] ?? '')?.group(1));
      if (tid == null || !seen.add(tid)) continue;
      final container = a.parent?.parent ?? a.parent;
      items.add(ThreadSummary(
        tid: tid,
        title: text,
        url: _absolute(a.attributes['href']),
        excerpt: _clean(container?.querySelector('.list_body')?.text ?? ''),
        author: _clean(container?.querySelector('.top_user')?.text ?? ''),
        avatar: container == null ? '' : _postAvatar(container),
        uid: container == null ? 0 : _postUid(container),
        time: _clean(container?.querySelector('.comiis_postli_times, .forumlist_li_time')?.text ?? ''),
        boardName: _clean(container?.querySelector('.comiis_xznalist_bk a')?.text ?? ''),
      ));
    }
    return items;
  }

  /// 楼层作者 uid：优先取作者名 / 头像链接，再退回到楼层内任意资料链接。
  int _postUid(Element el) {
    final hrefs = <String?>[
      el.querySelector('a.top_user')?.attributes['href'],
      el.querySelector('a.postli_top_tximg')?.attributes['href'],
      el.querySelector('img.top_tximg')?.attributes['src'],
      el.querySelector('a[href*="mod=space"][href*="uid="]')?.attributes['href'],
      el.querySelector('a[href*="uid="]')?.attributes['href'],
      el.querySelector('[data-uid]')?.attributes['data-uid'],
    ];
    for (final href in hrefs) {
      final raw = (href ?? '').trim();
      if (raw.isEmpty) continue;
      final match = RegExp(r'[?&]uid=(\d+)').firstMatch(raw);
      final uid = int.tryParse(match?.group(1) ?? raw) ?? 0;
      if (uid > 0) return uid;
      // 静态头像路径 .../data/avatar/000/02/55/71_avatar_middle.jpg 里也带着 uid。
      final path = RegExp(r'data/avatar/(\d{3})/(\d{2})/(\d{2})/(\d{2})_').firstMatch(raw);
      if (path != null) {
        final fromPath = int.tryParse(
          '${path.group(1)}${path.group(2)}${path.group(3)}${path.group(4)}',
        );
        if (fromPath != null && fromPath > 0) return fromPath;
      }
    }
    final match = RegExp(r'''authorid[=:"']\s*(\d+)''').firstMatch(el.innerHtml);
    return int.tryParse(match?.group(1) ?? '') ?? 0;
  }

  /// 楼层头像：兼容普通头像、懒加载属性与背景图三种写法。
  String _postAvatar(Element el) {
    final img = el.querySelector('img.top_tximg') ??
        el.querySelector('.postli_top_tximg img') ??
        el.querySelector('img[class*="tximg"]') ??
        el.querySelector('a[href*="uid="] img') ??
        el.querySelector('img[src*="/avatar/"]');
    for (final attr in const ['src', 'data-src', 'data-original', 'file']) {
      final value = (img?.attributes[attr] ?? '').trim();
      if (value.isEmpty || _isPlaceholderImage(value)) continue;
      return _absolute(value);
    }
    final link = el.querySelector('a.postli_top_tximg') ?? el.querySelector('.comiis_postli_top a');
    final style = link?.attributes['style'] ?? '';
    final background = RegExp(r'''url\(["']?([^)"']+)["']?\)''').firstMatch(style)?.group(1) ?? '';
    if (background.isNotEmpty && !_isPlaceholderImage(background)) return _absolute(background);
    return '';
  }

  bool _isPlaceholderImage(String url) {
    final value = url.toLowerCase();
    return value.contains('none.gif') ||
        value.contains('none.png') ||
        value.contains('imageloading') ||
        value.contains('avatar_bg') ||
        // uid=0 的头像地址会被服务端当成「当前登录用户」，必须丢弃后按 uid 重新拼接。
        RegExp(r'[?&]uid=0(?:&|$)').hasMatch(value);
  }

  String _pickImage(Element img) {
    const lazyAttrs = [
      'comiis_loadimages',
      'data-src',
      'data-original',
      'file',
      'zoomfile',
      'longdesc',
    ];
    String valueOf(String attr) => (img.attributes[attr] ?? '').trim();
    bool usable(String value) =>
        value.isNotEmpty &&
        !value.contains('none.png') &&
        !value.contains('none.gif') &&
        !value.contains('imageloading.gif') &&
        !value.contains('noavatar');

    for (final attr in lazyAttrs) {
      final value = valueOf(attr);
      if (usable(value)) return _absolute(value);
    }
    final src = valueOf('src');
    return usable(src) ? _absolute(src) : '';
  }

  String _sanitize(String html) {
    var output = html
        .replaceAll(RegExp(r'<script[\s\S]*?</script>', caseSensitive: false), '')
        .replaceAll(RegExp(r'<style[\s\S]*?</style>', caseSensitive: false), '')
        .replaceAll(RegExp(r'\son[a-z]+\s*=\s*"[^"]*"', caseSensitive: false), '')
        .replaceAll(RegExp(r"\son[a-z]+\s*=\s*'[^']*'", caseSensitive: false), '');

    final doc = parser.parseFragment(output);
    for (final img in doc.querySelectorAll('img')) {
      final src = _pickImage(img);
      img.attributes['src'] = src;
      if (src.isEmpty) {
        img.attributes['data-empty'] = '1';
      }
      final width = img.attributes['width'];
      final height = img.attributes['height'];
      if (width == '0' || width == '1') img.attributes.remove('width');
      if (height == '0' || height == '1') img.attributes.remove('height');
      img.attributes.remove('comiis_loadimages');
      img.attributes.remove('data-src');
      img.attributes.remove('data-original');
      img.attributes.remove('zoomfile');
      img.attributes.remove('longdesc');
    }
    for (final a in doc.querySelectorAll('a')) {
      final href = a.attributes['href'] ?? '';
      if (href.startsWith('javascript:')) {
        a.attributes['href'] = '#';
      } else if (href.isNotEmpty) {
        a.attributes['href'] = _absolute(href);
      }
    }
    return doc.outerHtml;
  }

  // ---------------------------------------------------------------- 工具

  String _findFormhash(String html) {
    final patterns = [
      RegExp(r'''name=["']formhash["'][^>]*?value=["']([0-9a-zA-Z]+)["']''', caseSensitive: false),
      RegExp(r'''value=["']([0-9a-zA-Z]+)["'][^>]*?name=["']formhash["']''', caseSensitive: false),
      RegExp(r'''formhash\s*[=:]\s*["']([0-9a-zA-Z]+)["']''', caseSensitive: false),
      RegExp(r'formhash=([0-9a-zA-Z]{8})', caseSensitive: false),
    ];
    for (final pattern in patterns) {
      final match = pattern.firstMatch(html);
      if (match != null) return match.group(1)!;
    }
    return '';
  }

  bool _isLoggedInHtml(String html) {
    final match = RegExp(r"discuz_uid\s*=\s*'(\d+)'").firstMatch(html);
    return match != null && match.group(1) != '0';
  }

  /// 手机模板的附件上传凭证：`uploadformdata:{uid:"0", hash:"..."}`。
  String _findUploadHash(String html) {
    final patterns = [
      RegExp(r'''hash\s*:\s*["']([0-9a-zA-Z]{16,40})["']'''),
      RegExp(r'''name=["']hash["'][^>]*?value=["']([0-9a-zA-Z]{16,40})["']''', caseSensitive: false),
    ];
    for (final pattern in patterns) {
      final match = pattern.firstMatch(html);
      if (match != null) return match.group(1)!;
    }
    return '';
  }

  int _findUid(String html) {
    final patterns = [
      RegExp(r"discuz_uid\s*=\s*'(\d+)'"),
      RegExp(r"\buid\s*=\s*'(\d+)'"),
    ];
    for (final pattern in patterns) {
      final match = pattern.firstMatch(html);
      final value = int.tryParse(match?.group(1) ?? '') ?? 0;
      if (value > 0) return value;
    }
    return 0;
  }

  int _intOf(String? text) =>
      int.tryParse(_clean(text ?? '').replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;

  String _uploadMessage(int status) => switch (status) {
        1 || 4 => '不支持此类扩展名的文件',
        2 || 3 || 5 => '文件超过服务器允许的大小',
        6 || 11 => '今日已无法上传更多附件',
        7 => '请选择图片文件',
        8 => '附件文件无法保存',
        9 => '没有合法的文件被上传',
        10 => '非法操作，请重新登录后再试',
        _ => '上传失败，请稍后重试',
      };

  String? _pageMessage(Document doc) {
    for (final selector in [
      '.comiis_message_table',
      '.alert_info',
      '.alert_error',
      '.showmessage',
      '#messagetext p',
      '.comiis_tip',
    ]) {
      final text = _clean(doc.querySelector(selector)?.text ?? '');
      if (text.isNotEmpty && text.length < 800) return text;
    }
    return null;
  }

  bool _looksLikeError(String text) =>
      RegExp(r'(抱歉|错误|失败|不能|无权|权限|非法|灌水|间隔|禁止|审核|登录)').hasMatch(text);

  void _ensureOk(HttpResult result) {
    if (result.statusCode >= 400) {
      final doc = parser.parse(result.body);
      final message = _pageMessage(doc);
      throw SiteException(message ?? '站点返回错误（${result.statusCode}）', code: result.statusCode);
    }
  }

  int? _firstInt(String? value) => value == null ? null : int.tryParse(value);

  String _clean(String text) => text
      .replaceAll('\u00a0', ' ')
      .replaceAll(RegExp(r'[\uE000-\uF8FF\uFFFD]'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  String _absolute(String? url) {
    final value = (url ?? '').trim();
    if (value.isEmpty) return '';
    if (value.startsWith('//')) return 'https:$value';
    if (value.startsWith('http://') || value.startsWith('https://')) return value;
    return AppConfig.uri(value).toString();
  }

  String _avatarForUid(int uid) {
    final padded = uid.toString().padLeft(9, '0');
    return 'https://cdn.binmt.cc/uc_server/data/avatar/'
        '${padded.substring(0, 3)}/${padded.substring(3, 5)}/${padded.substring(5, 7)}/${padded.substring(7, 9)}_avatar_middle.jpg';
  }

  String decode(List<int> bytes) => WafSolver.decodeUtf8(bytes);
}
