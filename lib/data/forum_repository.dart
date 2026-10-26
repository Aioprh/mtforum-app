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

  /// 少数页面（如小黑屋）没有移动模板，需要桌面 UA。
  static const String _desktopUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';

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

    // 站点插件 bin_post_report 会在页面尾部注入「踢帖(n/5)」入口。
    final kickUrl = RegExp(
      r'plugin\.php\?id=bin_post_report&(?:amp;)?tid=(\d+)&(?:amp;)?m=([0-9A-Za-z]+)',
    ).firstMatch(html);
    final kickLabel = RegExp(r'踢帖\s*\(\s*(\d+)\s*/\s*(\d+)\s*\)').firstMatch(html);

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
      favorited: _isThreadFavorited(html),
      favoriteHref: _favoriteHref(html),
      kickToken: kickUrl?.group(2) ?? '',
      kickVotes: int.tryParse(kickLabel?.group(1) ?? '') ?? 0,
      kickLimit: int.tryParse(kickLabel?.group(2) ?? '') ?? 5,
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
      rates: _parseRates(el, pid),
      rateSummary: _clean(el.querySelector('.comiis_rate a[href*="viewratings"]')?.text ?? ''),
    );
  }

  /// 打赏记录：`#ratelog_<pid>` 内每条 `li#rate_<pid>_<uid>`。
  List<RateRecord> _parseRates(Element el, int pid) {
    final box = el.querySelector('#ratelog_$pid') ?? el.querySelector('.comiis_view_lcrate');
    if (box == null) return const <RateRecord>[];
    final records = <RateRecord>[];
    for (final li in box.querySelectorAll('li')) {
      final score = _clean(li.querySelector('.f_a')?.text ?? '');
      final link = li.querySelector('a.f_c') ?? li.querySelector('a[href*="uid="]');
      final name = _clean(link?.text ?? '');
      final reason = _clean(li.querySelector('p')?.text ?? '');
      if (name.isEmpty && score.isEmpty) continue;
      final uid = _firstInt(
            RegExp(r'[?&]uid=(\d+)').firstMatch(link?.attributes['href'] ?? '')?.group(1),
          ) ??
          0;
      records.add(RateRecord(username: name, uid: uid, score: score, reason: reason));
      if (records.length >= 20) break;
    }
    return records;
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
    return _parseSpaceProfile(parser.parse(result.body), result.body, fallbackName: fallbackName);
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

  /// 页面中收藏 / 取消收藏的原始链接（已收藏时 Discuz 会输出 op=delete&favid=xx）。
  String _favoriteHref(String html) {
    final matches = RegExp(
      'href=[\'"]([^\'"]*ac=favorite[^\'"]*)[\'"]',
      caseSensitive: false,
    ).allMatches(html);
    var first = '';
    for (final match in matches) {
      final href = match.group(1) ?? '';
      if (href.isEmpty) continue;
      if (first.isEmpty) first = href;
      if (href.contains('op=delete')) return _absolute(href);
    }
    return first.isEmpty ? '' : _absolute(first);
  }

  /// 是否已收藏：优先看 op=delete 链接，其次看收藏图标的 f_a 状态。
  bool _isThreadFavorited(String html) {
    if (_favoriteHref(html).contains('op=delete')) return true;
    return RegExp(r'comiis_favorite_a_color[^"]*\bf_a\b').hasMatch(html);
  }

  /// 点赞 / 踩。Discuz 的 recommend 接口要求 inajax=1，返回 CDATA 包裹的提示。
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
        'inajax': '1',
        'mobile': '2',
      },
      referer: _threadReferer(tid),
    );
    _ensureOk(result);
    final message = _inajaxMessage(result.body);
    if (message.contains('recommendv') ||
        message.contains('投票成功') ||
        message.contains('点赞成功') ||
        message.contains('感谢')) {
      return;
    }
    if (message.contains('已评价过本主题') || message.contains('已经评价')) {
      throw SiteException(up ? '你已经赞过这个帖子' : '你已经踩过这个帖子');
    }
    if (message.contains('不能评价自己的帖子')) throw SiteException('不能点赞自己的帖子');
    if (message.contains('关闭的主题')) throw SiteException('该主题已关闭，无法点赞');
    if (message.contains('今日评价机会已用完')) throw SiteException('今天的点赞次数已用完');
    throw SiteException(up ? '点赞失败，请稍后重试' : '操作失败，请稍后重试');
  }

  /// 读取 inajax 响应里的 CDATA 文本。
  String _inajaxMessage(String body) {
    final cdata = RegExp(r'<!\[CDATA\[(.*?)\]\]>', dotAll: true).firstMatch(body)?.group(1);
    return _clean((cdata ?? body).replaceAll(RegExp(r'<[^>]+>'), ' '));
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

  /// 读取当前用户组可用的打赏项（好评 / 金币等）、单次范围与今日剩余额度。
  ///
  /// 评分弹窗由站点按用户组动态生成，这里直接解析 `showratetip` 试读页；
  /// 站点下拉（`#scoreoption*`）已按 24 小时剩余额度裁剪，是最准确的来源。
  Future<RateOptions> fetchRateOptions({required int tid, required int pid}) async {
    try {
      final result = await _http.get(
        'forum.php',
        query: {
          'mod': 'misc',
          'action': 'rate',
          'tid': '$tid',
          'pid': '$pid',
          'showratetip': '1',
          'mobile': '2',
        },
        referer: _threadReferer(tid),
      );
      _ensureOk(result);
      final doc = parser.parse(result.body);
      final fields = <RateField>[];
      final seen = <int>{};
      for (final control in doc.querySelectorAll('input[name^="score"], select[name^="score"]')) {
        final name = control.attributes['name'] ?? '';
        final id = int.tryParse(name.replaceFirst('score', '')) ?? 0;
        if (id <= 0 || !seen.add(id)) continue;

        // 站点给出的可选分值，已按 24 小时剩余额度裁剪。
        final presets = <int>[];
        if (control.localName == 'select') {
          for (final option in control.querySelectorAll('option')) {
            final value = int.tryParse(
              _clean(option.attributes['value'] ?? option.text).replaceAll('+', ''),
            );
            if (value != null && !presets.contains(value)) presets.add(value);
          }
        } else {
          for (final item in doc.querySelectorAll('#scoreoption$id li')) {
            final value = int.tryParse(_clean(item.text).replaceAll('+', ''));
            if (value != null && !presets.contains(value)) presets.add(value);
          }
        }
        presets.sort();

        Element? row;
        for (final candidate in doc.querySelectorAll('tr')) {
          if (candidate.querySelector('[name="$name"]') != null) {
            row = candidate;
            break;
          }
        }

        final text = _clean(row?.text ?? control.parent?.text ?? '');
        final range = RegExp(r'(-?\d+)\s*~\s*(-?\d+)').firstMatch(text);
        var min = int.tryParse(range?.group(1) ?? '') ?? 0;
        var max = int.tryParse(range?.group(2) ?? '') ?? 1;
        if (presets.isNotEmpty) {
          min = presets.first;
          max = presets.last;
        }
        if (max < min) max = min;
        if (max > 100) max = 100;

        // 评分表第 4 列为「今日剩余」；部分模板只在文案里给出。
        final cells = row?.querySelectorAll('td') ?? const <Element>[];
        var left = max;
        final leftMatch = RegExp(r'剩余\s*[:：]?\s*(\d+)').firstMatch(text);
        if (leftMatch != null) {
          left = int.tryParse(leftMatch.group(1) ?? '') ?? max;
        } else if (cells.length >= 4) {
          left = int.tryParse(
                RegExp(r'\d+').firstMatch(_clean(cells[3].text))?.group(1) ?? '',
              ) ??
              max;
        }
        if (left < 0) left = 0;

        final labelSource = row != null && row.children.isNotEmpty
            ? row.children.first.text
            : (control.parent?.text ?? '');
        var label = _clean(labelSource).replaceAll(RegExp(r'[0-9\s]'), '');
        if (label.isEmpty || label.length > 8) label = '积分 $id';

        fields.add(RateField(
          id: id,
          label: label,
          min: min,
          max: max,
          left: left,
          presets: presets,
        ));
      }
      if (fields.isEmpty) {
        final notice = _rateNotice(result.body);
        if (notice.isNotEmpty) {
          return RateOptions(fields: RateOptions.fallback.fields, notice: notice);
        }
        return RateOptions.fallback;
      }
      return RateOptions(
        fields: fields,
        canNotify: doc.querySelector('input[name="sendreasonpm"]') != null,
      );
    } catch (_) {
      return RateOptions.fallback;
    }
  }

  /// 给某个楼层打赏（Discuz `misc&action=rate`）。
  Future<String> rate({
    required int tid,
    required int pid,
    required String formhash,
    required Map<int, int> scores,
    String reason = '',
    bool notify = false,
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
        'formhash': formhash,
        'inajax': '1',
        'mobile': '2',
      },
      referer: _threadReferer(tid),
      form: {
        'formhash': formhash,
        'tid': '$tid',
        'pid': '$pid',
        'reason': reason,
        for (final entry in scores.entries) 'score${entry.key}': '${entry.value}',
        if (notify) 'sendreasonpm': 'on',
      },
    );
    _ensureOk(response);
    final msg = _rateMessage(response.body);
    if (msg.isNotEmpty && _looksLikeRateError(msg)) {
      throw SiteException(_rateErrorText(msg));
    }
    return msg.isEmpty ? '打赏成功' : msg;
  }

  /// 提取站点评分页 / 评分提交响应里的提示文案。
  ///
  /// `inajax` 返回的通常是 `errorhandle_rate('提示')` 这类脚本，
  /// 必须只取引号内的提示，避免把整段 JS 弹给用户。
  String _rateMessage(String body) {
    final cdata = RegExp(r'<!\[CDATA\[(.*?)\]\]>', dotAll: true).firstMatch(body)?.group(1);
    final raw = cdata ?? body;
    final quoted = RegExp(
      r"(?:errorhandle_\w+|succeedhandle_\w+|showmessage|showDialog)\(\s*'([^']*)'",
    ).firstMatch(raw)?.group(1);
    if (quoted != null && _clean(quoted).isNotEmpty) return _clean(quoted);
    final page = _pageMessage(parser.parse(body)) ?? '';
    if (page.isNotEmpty) return page;
    final text = _clean(raw.replaceAll(RegExp(r'<[^>]+>'), ' '));
    if (_looksLikeRateError(text) && text.length < 80) return text;
    return '';
  }

  /// 评分页本身返回的错误提示（权限不足等）。
  String _rateNotice(String body) {
    final page = _pageMessage(parser.parse(body)) ?? '';
    return _looksLikeRateError(page) ? page : '';
  }

  String _rateErrorText(String message) {
    if (RegExp(r'24\s*小时评分数超过限制').hasMatch(message)) {
      return '24 小时内该积分项的评分额度已用完，请明天再试';
    }
    if (message.contains('不能给自己评分') || message.contains('不能评分自己')) {
      return '不能打赏自己的帖子';
    }
    if (message.contains('没有权限') || message.contains('无权')) {
      return '当前账号没有打赏权限';
    }
    return message;
  }

  bool _looksLikeRateError(String text) =>
      RegExp(r'(抱歉|错误|失败|不能|无权|权限|非法|禁止|请先登录|间隔|重复|超过限制)')
          .hasMatch(text);

  /// 踢帖：站点插件 `bin_post_report` 的确认页可能带有表单，按其字段原样提交。
  Future<String> kickThread({
    required int tid,
    required String token,
    required String formhash,
  }) async {
    final entry = await _http.get(
      'plugin.php',
      query: {
        'id': 'bin_post_report',
        'tid': '$tid',
        'm': token,
        'mobile': '2',
      },
      referer: _threadReferer(tid),
    );
    _ensureOk(entry);
    final doc = parser.parse(entry.body);
    final form = doc.querySelector('form');
    if (form == null) {
      final msg = _pageMessage(doc) ?? '';
      if (_looksLikeRateError(msg)) throw SiteException(msg);
      throw SiteException(msg.isEmpty ? '踢帖页面暂不可用，请在浏览器中操作' : msg);
    }

    final fields = <String, String>{};
    for (final input in form.querySelectorAll('input, textarea')) {
      final name = input.attributes['name'] ?? '';
      if (name.isEmpty) continue;
      final type = (input.attributes['type'] ?? 'text').toLowerCase();
      if (type == 'button' || type == 'image') continue;
      if (type == 'checkbox' || type == 'radio') {
        if (input.attributes.containsKey('checked')) {
          fields[name] = input.attributes['value'] ?? 'on';
        }
        continue;
      }
      fields[name] = input.localName == 'textarea'
          ? input.text
          : input.attributes['value'] ?? '';
    }
    for (final select in form.querySelectorAll('select')) {
      final name = select.attributes['name'] ?? '';
      if (name.isEmpty) continue;
      final selected = select.querySelector('option[selected]') ?? select.querySelector('option');
      fields[name] = selected?.attributes['value'] ?? '';
    }
    fields.putIfAbsent('formhash', () => formhash);

    final action = (form.attributes['action'] ?? '').trim().replaceFirst(RegExp(r'^\./'), '');
    final target = action.isEmpty
        ? AppConfig.uri('plugin.php', {'id': 'bin_post_report', 'tid': '$tid', 'm': token}).toString()
        : _absolute(action);
    final response = await _http.post(
      target,
      query: {'formhash': fields['formhash'] ?? formhash, 'mobile': '2'},
      referer: _threadReferer(tid),
      form: fields,
    );
    _ensureOk(response);
    final text = response.body.contains('<![CDATA[')
        ? _inajaxMessage(response.body)
        : (_pageMessage(parser.parse(response.body)) ?? '');
    if (_looksLikeRateError(text)) throw SiteException(text);
    return text.isEmpty ? '已提交踢帖' : text;
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
    return (
      _parseSpaceProfile(parser.parse(result.body), result.body, uid: uid),
      _findFormhash(result.body),
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

  /// 回复列表。Discuz 没有 `do=reply`，正确入口是
  /// `do=thread&view=me&type=reply`，且回复行只有 findpost 链接、没有 thread- 链接。
  Future<List<ThreadSummary>> fetchUserReplies(int uid, {int page = 1}) async {
    final query = <String, String>{
      'mod': 'space',
      'do': 'thread',
      'view': 'me',
      'type': 'reply',
      'from': 'space',
      'page': '$page',
      if (uid > 0) 'uid': '$uid',
    };
    // 桌面模板会额外输出每条回复的正文摘要，结构也更稳定，优先使用。
    final desktop = await _getDesktopPage('home.php', query);
    if (desktop.ok) {
      final parsed = _parseSpaceReplies(desktop.body);
      if (parsed.isNotEmpty) return parsed;
    }
    final mobile = await _http.get('home.php', query: {...query, 'mobile': '2'});
    _ensureOk(mobile);
    return _parseSpaceReplies(mobile.body);
  }

  /// 我的回复（不带 uid，服务端自动取当前登录用户）。
  Future<List<ThreadSummary>> fetchMyReplies({int page = 1}) => fetchUserReplies(0, page: page);

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

  /// 我的好友列表。
  Future<List<FriendItem>> fetchFriends({int page = 1}) async {
    final result = await _http.get(
      'home.php',
      query: {
        'mod': 'space',
        'do': 'friend',
        'view': 'me',
        'mobile': '2',
        'page': '$page',
      },
    );
    _ensureOk(result);
    final doc = parser.parse(result.body);
    final items = <FriendItem>[];
    final seen = <int>{};
    // 移动端 comiis 模板：div.comiis_userlist01 > li；桌面模板回落 ul.buddy / #friend_ul。
    for (final selector in ['.comiis_userlist01 li', '#friend_ul li', 'ul.buddy li']) {
      for (final element in doc.querySelectorAll(selector)) {
        // 无好友时页面会推荐好友 / 在线成员，带「加好友」按钮的不是已有好友。
        if (element.querySelector('a[href*="ac=friend&op=add"]') != null) continue;
        final nameLink = element.querySelector('p.tit a[href*="mod=space&uid="]') ??
            element.querySelector('p.tit a') ??
            element.querySelector('h4 a[href*="mod=space&uid="]') ??
            element.querySelector('h4 a') ??
            element.querySelector('.comiis_friend_name, .name');
        final name = _clean(nameLink?.text ?? '');
        if (name.isEmpty) continue;
        var uid = 0;
        for (final link in element.querySelectorAll('a[href]')) {
          uid = _uidFromHref(link.attributes['href'] ?? '');
          if (uid > 0) break;
        }
        if (uid <= 0 || !seen.add(uid)) continue;
        final avatarEl = element.querySelector('a.list01_limg img') ??
            element.querySelector('dd.avt img') ??
            element.querySelector('img');
        items.add(FriendItem(
          uid: uid,
          username: name,
          avatar: avatarEl == null ? '' : _pickImage(avatarEl),
          note: _clean(
            element.querySelector('p.txt, .note, .comiis_friend_note')?.text ?? '',
          ),
        ));
        if (items.length >= 80) break;
      }
      if (items.isNotEmpty) break;
    }
    return items;
  }

  /// 以桌面模板读取页面：结构稳定，读取后立即清掉服务端写入的 mobile=no Cookie，
  /// 避免后续请求也跟着切到桌面模板。
  Future<HttpResult> _getDesktopPage(String path, Map<String, String> query) async {
    final result = await _http.get(
      path,
      query: {...query, 'mobile': 'no'},
      userAgent: _desktopUserAgent,
    );
    _http.removeCookie('mobile');
    return result;
  }

  /// 私信会话列表。桌面模板结构固定，避免移动端模板差异导致昵称/头像解析失败。
  Future<List<PmConversation>> fetchPmConversations({int page = 1}) async {
    final result = await _getDesktopPage('home.php', {
      'mod': 'space',
      'do': 'pm',
      'filter': 'privatepm',
      'page': '$page',
    });
    _ensureOk(result);
    final doc = parser.parse(result.body);
    final items = <PmConversation>[];
    final seen = <int>{};
    for (final node in doc.querySelectorAll('dl[id^="pmlist_"]')) {
      final link = node.querySelector('a[href*="subop=view"][href*="touid="]');
      final uid = _firstInt(
        RegExp(r'[?&](?:amp;)?touid=(\d+)').firstMatch(link?.attributes['href'] ?? '')?.group(1),
      );
      if (uid == null || uid <= 0 || !seen.add(uid)) continue;
      final name = _clean(node.querySelector('dd.ptm a[href*="mod=space&uid="]')?.text ?? '');
      final avatarEl = node.querySelector('dd.avt img');
      final preview = _pmNodeText(node);
      if (name.isEmpty && preview.isEmpty) continue;
      items.add(PmConversation(
        uid: uid,
        name: name,
        avatar: avatarEl == null ? '' : _pickImage(avatarEl),
        preview: preview,
        time: _clean(node.querySelector('dd.ptm span.xg1')?.text ?? ''),
        // newpm_avt 在每条会话里都会输出，靠 CSS 控制显示，不能用它判断未读。
        unread: node.classes.contains('newpm'),
      ));
      if (items.length >= 40) break;
    }
    return items;
  }

  /// 与某个用户的私信记录，返回（消息、formhash、对方昵称）。
  Future<(List<PmMessage>, String, String)> fetchPmMessages(int uid, {int myUid = 0}) async {
    final result = await _getDesktopPage('home.php', {
      'mod': 'space',
      'do': 'pm',
      'subop': 'view',
      'touid': '$uid',
    });
    _ensureOk(result);
    final html = result.body;
    final doc = parser.parse(html);
    final messages = <PmMessage>[];
    var peer = '';
    for (final node in doc.querySelectorAll('dl[id^="pmlist_"]')) {
      final text = _pmNodeText(node);
      if (text.isEmpty) continue;
      final authorLink = node.querySelector('dd.ptm a[href*="mod=space&uid="]');
      final author = _clean(authorLink?.text ?? '');
      final authorUid = _uidFromHref(authorLink?.attributes['href'] ?? '');
      // 自己的消息在模板里只显示「您」，没有作者链接。
      final mine = authorLink == null || (myUid > 0 && authorUid == myUid);
      if (!mine && author.isNotEmpty && peer.isEmpty) peer = author;
      messages.add(PmMessage(
        text: text,
        author: author,
        uid: authorUid,
        time: _clean(node.querySelector('dd.ptm span.xg1')?.text ?? ''),
        mine: mine,
      ));
    }
    if (peer.isEmpty) {
      peer = _clean(
        RegExp(r'与\s*(\S+)\s*的短消息').firstMatch(doc.querySelector('title')?.text ?? '')?.group(1) ?? '',
      );
    }
    return (messages, _findFormhash(html), peer);
  }

  /// 从链接里取用户 uid：兼容 home.php?...&uid=1 与 space-uid-1.html 两种写法。
  int _uidFromHref(String href) {
    final match = RegExp(r'(?:[?&](?:amp;)?uid=|space-uid-)(\d+)').firstMatch(href);
    return _firstInt(match?.group(1)) ?? 0;
  }

  /// 私信节点正文：取第一个 <br> 之后的内容，跳过时间与操作菜单。
  String _pmNodeText(Element node) {
    final body = node.querySelector('dd.ptm') ?? node;
    final buffer = StringBuffer();
    var afterBreak = false;
    for (final child in body.nodes) {
      if (child is Element) {
        if (child.localName == 'br') {
          afterBreak = true;
          continue;
        }
        if (!afterBreak) continue;
        final classes = child.classes;
        if (classes.contains('xg1') || classes.contains('pm_o') || child.localName == 'script') {
          continue;
        }
        buffer.write(child.text);
      } else if (afterBreak) {
        buffer.write(child.text);
      }
    }
    return _clean(buffer.toString());
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
        'formhash': formhash,
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

  /// 收藏 / 取消收藏。
  ///
  /// Discuz 的取消收藏必须 POST 提交 deletesubmit；X3.4 支持直接按 tid 定位收藏，
  /// 老版本再退回收藏夹里的 favid。
  Future<String> toggleFavorite({
    required int tid,
    required String formhash,
    required bool favorited,
    String href = '',
  }) async {
    if (!favorited) {
      try {
        return await addFavorite(tid: tid, formhash: formhash);
      } catch (e) {
        final message = e is SiteException ? e.message : '';
        if (message.contains('重复收藏') || message.contains('已经收藏') || message.contains('收藏过')) {
          return '该主题已在收藏中';
        }
        rethrow;
      }
    }

    var message = await _deleteFavorite(tid: tid, formhash: formhash);
    if (!await _favoriteExists(tid)) return '已取消收藏';

    // 兼容旧版：从收藏夹里取真实 favid 后再删一次。
    var favid = await _findFavoriteFavid(tid);
    if (favid.isEmpty) favid = RegExp(r'favid=(\d+)').firstMatch(href)?.group(1) ?? '';
    if (favid.isNotEmpty) {
      message = await _deleteFavorite(tid: tid, formhash: formhash, favid: favid) ?? message;
    }
    if (await _favoriteExists(tid)) {
      throw SiteException(message ?? '取消收藏失败，请稍后重试');
    }
    return '已取消收藏';
  }

  /// 提交删除收藏；返回页面提示（失败时用于告知用户）。
  Future<String?> _deleteFavorite({
    required int tid,
    required String formhash,
    String favid = '',
  }) async {
    final target = <String, String>{};
    if (favid.isEmpty) {
      target['id'] = '$tid';
    } else {
      target['favid'] = favid;
    }
    final result = await _http.post(
      'home.php',
      query: {
        'mod': 'spacecp',
        'ac': 'favorite',
        'op': 'delete',
        'type': 'thread',
        ...target,
        'formhash': formhash,
        'deletesubmit': 'yes',
        'handlekey': 'favorite',
        'mobile': '2',
      },
      form: {'formhash': formhash, 'deletesubmit': 'yes', ...target},
      referer: AppConfig.uri('home.php', {'mod': 'space', 'do': 'favorite', 'view': 'me'}).toString(),
    );
    _ensureOk(result);
    final message = _pageMessage(parser.parse(result.body));
    if (message != null && _looksLikeError(message) && !message.contains('不存在')) {
      throw SiteException(message);
    }
    return message;
  }

  /// 打开删除确认页：仍能打开说明该主题还在收藏夹里。
  Future<bool> _favoriteExists(int tid) async {
    final result = await _http.get(
      'home.php',
      query: {
        'mod': 'spacecp',
        'ac': 'favorite',
        'op': 'delete',
        'type': 'thread',
        'id': '$tid',
        'handlekey': 'favorite',
        'mobile': '2',
      },
    );
    _ensureOk(result);
    final doc = parser.parse(result.body);
    return doc.querySelector('input[name="deletesubmit"]') != null ||
        doc.querySelector('form[id^="favoriteform_"]') != null ||
        result.body.contains('name="deletesubmit"');
  }

  /// 在收藏夹中按主题 tid 定位 favid；找不到返回空串。
  Future<String> _findFavoriteFavid(int tid) async {
    for (final userAgent in <String?>[_desktopUserAgent, null]) {
      for (var page = 1; page <= 3; page++) {
        final body = await _favoritePage(page, userAgent);
        if (!body.contains('favid=') && !body.contains('favorite[]')) break;
        final doc = parser.parse(body);
        for (final marker in _favoriteMarkers(doc)) {
          final favid = _favoriteMarkerFavid(marker);
          if (favid == null) continue;
          if (_favoriteRowHasThread(marker, tid)) return favid;
        }
      }
    }
    return '';
  }

  /// 收藏项里的 favid 标记：删除链接或批量删除复选框。
  Iterable<Element> _favoriteMarkers(Document doc) sync* {
    yield* doc.querySelectorAll('a[href*="favid="]');
    yield* doc.querySelectorAll('input[type="checkbox"][name*="favorite"]');
  }

  String? _favoriteMarkerFavid(Element marker) {
    final href = marker.attributes['href'] ?? '';
    final fromHref = RegExp(r'favid=(\d+)').firstMatch(href)?.group(1);
    if (fromHref != null) return fromHref;
    final value = marker.attributes['value'] ?? '';
    return RegExp(r'^\d+$').hasMatch(value) ? value : null;
  }

  Future<String> _favoritePage(int page, String? userAgent) async {
    final result = await _http.get(
      'home.php',
      query: {'mod': 'space', 'do': 'favorite', 'view': 'me', 'type': 'thread', 'page': '$page'},
      userAgent: userAgent,
    );
    _ensureOk(result);
    return result.body;
  }

  /// 从收藏项内的标记（删除链接 / 复选框）向上找到行容器，判断该行收藏的主题是否为 tid。
  bool _favoriteRowHasThread(Element marker, int tid) {
    Element? node = marker;
    for (var depth = 0; depth < 10 && node != null; depth++) {
      if (_containsThreadHref(node, tid)) return true;
      // 出现别的主题说明已经越过当前收藏项。
      if (_containsOtherThreadHref(node, tid)) return false;
      node = node.parent;
    }
    return false;
  }

  bool _containsThreadHref(Element node, int tid) {
    for (final a in node.querySelectorAll('a[href]')) {
      final match = RegExp(r'(?:tid=|thread-)(\d+)').firstMatch(a.attributes['href'] ?? '');
      if (match != null && int.tryParse(match.group(1)!) == tid) return true;
    }
    return false;
  }

  bool _containsOtherThreadHref(Element node, int tid) {
    for (final a in node.querySelectorAll('a[href]')) {
      final match = RegExp(r'(?:tid=|thread-)(\d+)').firstMatch(a.attributes['href'] ?? '');
      if (match != null && int.tryParse(match.group(1)!) != tid) return true;
    }
    return false;
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

  /// 个人空间回复列表（`type=reply`）：标题走 findpost 链接，
  /// 桌面模板另有一行 `<td class="xg1">` 存放回复正文摘要。
  List<ThreadSummary> _parseSpaceReplies(String html) {
    final doc = parser.parse(html);

    // pid -> 回复正文摘要。
    final excerpts = <int, String>{};
    for (final cell in doc.querySelectorAll('td.xg1')) {
      final link = cell.querySelector('a[href*="goto=findpost"]');
      if (link == null) continue;
      final pid = _firstInt(RegExp(r'pid=(\d+)').firstMatch(link.attributes['href'] ?? '')?.group(1));
      final text = _clean(link.text);
      if (pid == null || text.isEmpty || text == '......') continue;
      excerpts.putIfAbsent(pid, () => text);
    }

    final items = <ThreadSummary>[];
    final seen = <int>{};

    // 桌面模板：回复标题固定在 <th> 内，避免误取页面其它 findpost 跳转链接。
    final anchors = <Element>[];
    for (final row in doc.querySelectorAll('#delform tr')) {
      final link = row.querySelector('th a[href*="goto=findpost"]');
      if (link != null) anchors.add(link);
    }
    // 移动模板：<div class="bm_c"><a href="...goto=findpost...">标题</a></div>。
    if (anchors.isEmpty) {
      for (final anchor in doc.querySelectorAll('a[href*="goto=findpost"]')) {
        if (anchor.parent?.classes.contains('xg1') == true) continue;
        anchors.add(anchor);
      }
    }

    for (final anchor in anchors) {
      final href = anchor.attributes['href'] ?? '';
      final tid = _firstInt(RegExp(r'ptid=(\d+)').firstMatch(href)?.group(1)) ??
          _firstInt(RegExp(r'[?&]tid=(\d+)').firstMatch(href)?.group(1));
      if (tid == null || tid <= 0 || !seen.add(tid)) continue;
      final title = _clean(anchor.text);
      if (title.isEmpty) continue;
      final pid = _firstInt(RegExp(r'pid=(\d+)').firstMatch(href)?.group(1)) ?? 0;
      final row = anchor.parent?.parent;
      items.add(ThreadSummary(
        tid: tid,
        title: title,
        url: _absolute(href),
        excerpt: excerpts[pid] ?? '',
        boardName: _clean(row?.querySelector('td a[href*="mod=forumdisplay"]')?.text ?? ''),
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

  /// 解析个人空间页（`home.php?mod=space&do=profile` 的 comiis 移动模板）。
  UserProfile _parseSpaceProfile(Document doc, String html, {int uid = 0, String fallbackName = ''}) {
    final info = doc.querySelector('.comiis_space_info') ??
        doc.querySelector('.comiis_space_tx') ??
        doc.querySelector('.comiis_space_center');

    final resolvedUid = uid > 0
        ? uid
        : _firstInt(
              RegExp(r"discuz_uid\s*=\s*'(\d+)'").firstMatch(html)?.group(1) ??
                  RegExp(r'[?&]uid=(\d+)').firstMatch(html)?.group(1) ??
                  '0',
            ) ??
            0;

    var name = _clean(
      info?.querySelector('h2')?.text ??
          doc.querySelector('h2.fyy')?.text ??
          doc.querySelector('.comiis_space_name')?.text ??
          doc.querySelector('.top_user')?.text ??
          RegExp(r"username\s*=\s*'([^']*)'").firstMatch(html)?.group(1) ??
          '',
    );
    if (name.isEmpty) name = fallbackName;

    final rawAvatar = _absolute(
      info?.querySelector('.user_img img')?.attributes['src'] ??
          doc.querySelector('.comiis_space_tximg img')?.attributes['src'] ??
          doc.querySelector('.user_img img')?.attributes['src'],
    );
    // 页面顶部可能混入当前登录用户的头像，必须校验 uid 才能采用。
    var avatar = rawAvatar;
    if (resolvedUid > 0) {
      if (_avatarMatchesUid(rawAvatar, resolvedUid)) {
        avatar = rawAvatar;
      } else if (rawAvatar.toLowerCase().contains('noavatar')) {
        avatar = rawAvatar;
      } else {
        avatar = _avatarForUid(resolvedUid);
      }
    } else if (_isPlaceholderImage(avatar)) {
      avatar = '';
    }

    // 统计区：<span>帖子 45</span> / <span>回复 2988</span> / <span>粉丝 16</span>。
    final counts = <String, String>{};
    for (final span in doc.querySelectorAll('ul li span, .comiis_space_num span')) {
      final text = _clean(span.text);
      final match = RegExp(r'^(.{1,4}?)\s*(\d+)$').firstMatch(text);
      if (match == null) continue;
      counts.putIfAbsent(_clean(match.group(1)!), () => match.group(2)!);
    }
    // 积分区：<li><span>4083</span>金币</li>。
    for (final li in doc.querySelectorAll('ul li')) {
      final label = _clean(li.text).replaceAll(RegExp(r'[0-9\s]'), '');
      final number = _clean(li.querySelector('span')?.text ?? '').replaceAll(RegExp(r'[^0-9]'), '');
      if (label.isEmpty || label.length > 4 || number.isEmpty) continue;
      counts.putIfAbsent(label, () => number);
    }

    final bodyText = _clean(doc.body?.text ?? '');
    final level = _clean(
      info?.querySelector('.kmlevs')?.text ??
          RegExp(r'Lv\.\s*\d+').firstMatch(bodyText)?.group(0) ??
          '',
    );

    return UserProfile(
      uid: resolvedUid,
      username: name,
      avatar: avatar,
      level: level,
      credits: counts['金币'] ?? counts['积分'] ?? '',
      posts: counts['帖子'] ?? counts['主题'] ?? '',
      replies: counts['回复'] ?? '',
      followers: counts['粉丝'] ?? '',
      regTime: _parseRegTime(doc, bodyText),
      group: _clean(info?.querySelector('.kmlev:not(.kmlevs)')?.text ?? doc.querySelector('.comiis_space_group')?.text ?? ''),
    );
  }

  /// 注册时间。comiis 移动模板把值放在前面、标签放在后面：
  /// `<li><div class="profile_rs">2022-7-7 13:22</div><span>注册时间</span></li>`，
  /// 若按整页文本取「注册时间」后面的日期，会误取到下一条「最后访问」的时间。
  String _parseRegTime(Document doc, String bodyText) {
    final datePattern = RegExp(
      r'[0-9]{4}-[0-9]{1,2}-[0-9]{1,2}(?:\s+[0-9]{1,2}:[0-9]{2}(?::[0-9]{2})?)?',
    );
    String extract(String text) => datePattern.firstMatch(text)?.group(0) ?? '';
    bool isLabel(String text) {
      final normalized = _clean(text).replaceAll(RegExp(r'[:：\s]'), '');
      return normalized == '注册时间' || normalized == '注册于' || normalized == '注册日期';
    }

    // comiis 移动模板 / 桌面 #pbbs：值在前或在同一行。
    for (final li in doc.querySelectorAll('li')) {
      final labelEl = li.querySelector('span, em, dt, strong');
      if (labelEl == null || !isLabel(labelEl.text)) continue;
      final value = extract(li.text.replaceFirst(labelEl.text, ''));
      if (value.isNotEmpty) return value;
    }

    // 默认移动模板的表格：<tr><td>注册时间: </td><td>值</td></tr>。
    for (final tr in doc.querySelectorAll('tr')) {
      final cells = tr.querySelectorAll('td, th');
      if (cells.isEmpty || !isLabel(cells.first.text)) continue;
      final value = extract(cells.length > 1 ? cells[1].text : cells.first.text);
      if (value.isNotEmpty) return value;
    }

    // 兜底：标签前后的日期，优先「值 + 标签」的写法（comiis 的排列顺序）。
    for (final candidate in [
      '${datePattern.pattern}\\s*(?:注册时间|注册于|注册日期)',
      '(?:注册时间|注册于|注册日期)\\s*[:：]?\\s*${datePattern.pattern}',
    ]) {
      final match = RegExp(candidate).firstMatch(bodyText);
      if (match == null) continue;
      final value = datePattern.firstMatch(match.group(0) ?? '')?.group(0) ?? '';
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  /// 头像地址是否属于指定 uid（静态头像路径或 avatar.php?uid=）。
  bool _avatarMatchesUid(String url, int uid) {
    if (url.isEmpty || _isPlaceholderImage(url)) return false;
    final padded = uid.toString().padLeft(9, '0');
    final path = '${padded.substring(0, 3)}/${padded.substring(3, 5)}/${padded.substring(5, 7)}/${padded.substring(7, 9)}_avatar';
    return url.contains(path) || url.contains('uid=$uid');
  }

  /// 小黑屋（forum.php?mod=misc&action=showdarkroom，桌面模板表格）。
  /// 站点每页只给 11 条，底部「更多」按钮带 cid，需要顺着 cid 连续翻页才能取全。
  Future<List<DarkRoomEntry>> fetchDarkRoom() async {
    final entries = <DarkRoomEntry>[];
    final seen = <String>{};
    String? cid;
    for (var page = 0; page < 20; page++) {
      // 该页没有移动模板，移动 UA 会被引导页拦截，必须用桌面模板。
      final query = <String, String>{'mod': 'misc', 'action': 'showdarkroom'};
      if (cid != null) query['cid'] = cid;
      final result = await _getDesktopPage('forum.php', query);
      _ensureOk(result);
      final doc = parser.parse(result.body);
      final before = entries.length;
      for (final tr in doc.querySelectorAll('#darkroomtable tr')) {
        final cells = tr.querySelectorAll('td');
        if (cells.length < 4) continue;
        final link = cells[0].querySelector('a[href]');
        final href = link?.attributes['href'] ?? '';
        final uid = int.tryParse(
              RegExp(r'space-uid-(\d+)\.html').firstMatch(href)?.group(1) ??
                  RegExp(r'[?&]uid=(\d+)').firstMatch(href)?.group(1) ??
                  '',
            ) ??
            0;
        final name = _clean(link?.text ?? cells[0].text);
        if (name.isEmpty || !seen.add('$uid|$name')) continue;
        entries.add(DarkRoomEntry(
          uid: uid,
          name: name,
          action: _clean(cells[1].text),
          expiry: _clean(cells[2].text),
          time: _clean(cells[3].text),
        ));
      }
      final next = _clean(doc.querySelector('#darkroommore')?.attributes['cid'] ?? '');
      // 没有「更多」、cid 不再变化或本页没有新记录时结束。
      if (next.isEmpty || next == cid || entries.length == before) break;
      cid = next;
    }
    return entries;
  }

  /// 勋章中心：返回（勋章目录, 最近获得记录）。
  Future<(List<MedalItem>, List<MedalRecord>)> fetchMedals() async {
    final result = await _http.get('home.php', query: {'mod': 'medal', 'mobile': '2'});
    _ensureOk(result);
    final doc = parser.parse(result.body);

    final items = <MedalItem>[];
    final seen = <String>{};
    for (final block in doc.querySelectorAll('p.list02_limg')) {
      final img = block.querySelector('img');
      final name = _clean(img?.attributes['alt'] ?? '');
      if (name.isEmpty || !seen.add(name)) continue;
      final onclick = block.querySelector('a')?.attributes['onclick'] ?? '';
      final desc = _clean(
        RegExp(r"kmtxt[^>]*>(.*?)<").firstMatch(onclick)?.group(1) ?? '',
      );
      items.add(MedalItem(name: name, image: _absolute(img?.attributes['src']), desc: desc));
    }

    final records = <MedalRecord>[];
    for (final a in doc.querySelectorAll('.comiis_medal_box a.block')) {
      final href = a.attributes['href'] ?? '';
      final uid = int.tryParse(RegExp(r'uid=(\d+)').firstMatch(href)?.group(1) ?? '') ?? 0;
      if (uid <= 0) continue;
      final time = _clean(a.querySelector('p.tit font')?.text ?? '');
      final titleText = _clean(a.querySelector('p.tit')?.text ?? '');
      final name = _clean(titleText.replaceAll(time, ''));
      final medal = _clean(a.querySelector('p.txt')?.text ?? '').replaceFirst('获得', '');
      if (name.isEmpty) continue;
      records.add(MedalRecord(
        uid: uid,
        name: name,
        medal: medal,
        avatar: _absolute(a.querySelector('img')?.attributes['src']),
        time: time,
      ));
    }
    return (items, records);
  }

  /// 积分页：余额与总积分（桌面模板 `ul.creditl`）。
  Future<CreditSummary> fetchCredits() async {
    final result = await _getDesktopPage('home.php', {
      'mod': 'spacecp',
      'ac': 'credit',
    });
    _ensureOk(result);
    final doc = parser.parse(result.body);

    final items = <CreditItem>[];
    var total = '';
    var formula = '';
    for (final li in doc.querySelectorAll('ul.creditl li')) {
      final labelEl = li.querySelector('em');
      final label = _clean(labelEl?.text ?? '').replaceAll(RegExp(r'[:：]\s*$'), '');
      final formulaEl = li.querySelector('span.xg1');
      var value = _clean(li.text);
      if (labelEl != null) value = value.replaceFirst(_clean(labelEl.text), '');
      if (formulaEl != null) value = value.replaceFirst(_clean(formulaEl.text), '');
      value = _clean(value);
      if (label.isEmpty || value.isEmpty) continue;
      final classes = (li.attributes['class'] ?? '').split(RegExp(r'\s+'));
      // 总积分行是 `<li class="cl"><em>积分: </em>...`；若有转账积分则是 `class="xi1 cl"`。
      if (classes.contains('cl') && !classes.contains('xi1')) {
        total = value;
        formula = _clean(formulaEl?.text ?? '');
        continue;
      }
      items.add(CreditItem(
        name: label,
        value: value,
        highlight: classes.contains('xi1'),
      ));
    }
    return CreditSummary(items: items, total: total, formula: formula);
  }

  /// 积分交易记录（`ac=credit&op=log`，桌面模板 `table.dt` 四列）。
  Future<List<CreditLog>> fetchCreditLogs({int page = 1}) async {
    final result = await _getDesktopPage('home.php', {
      'mod': 'spacecp',
      'ac': 'credit',
      'op': 'log',
      'page': '$page',
    });
    _ensureOk(result);
    final doc = parser.parse(result.body);

    final items = <CreditLog>[];
    for (final tr in doc.querySelectorAll('table.dt tr')) {
      final cells = tr.querySelectorAll('td');
      if (cells.length < 4) continue;
      final values = cells.map((cell) => _clean(cell.text)).toList();
      if (values[0] == '操作' || values[0].isEmpty && values[1].isEmpty) continue;
      items.add(CreditLog(
        operation: values[0],
        change: values[1],
        detail: values[2],
        time: values[3],
      ));
    }
    return items;
  }

  /// 道具商店（`home.php?mod=magic&action=shop`）。
  Future<List<MagicItem>> fetchMagicShop({int page = 1, bool hot = false}) async {
    final result = await _getDesktopPage('home.php', {
      'mod': 'magic',
      'action': 'shop',
      if (hot) 'operation': 'hot',
      'page': '$page',
    });
    _ensureOk(result);
    final doc = parser.parse(result.body);

    final items = <MagicItem>[];
    for (final li in doc.querySelectorAll('ul.mgcl li')) {
      final imgEl = li.querySelector('.mg_img img') ?? li.querySelector('img');
      final name = _clean(li.querySelector('p strong')?.text ?? imgEl?.attributes['alt'] ?? '');
      if (name.isEmpty) continue;

      final buy = li.querySelector('a[href*="operation=buy"]');
      final give = li.querySelector('a[href*="operation=give"]');
      final actionHref = (buy ?? give)?.attributes['href'] ?? '';
      var mid = _magicQueryValue(actionHref, 'mid');
      if (mid.isEmpty) {
        final imgId = imgEl?.parent?.attributes['id'] ?? '';
        mid = imgId.startsWith('magic_') ? imgId.substring(6) : '';
      }

      var priceText = '';
      for (final p in li.querySelectorAll('p')) {
        if (p.querySelector('strong.xi1') != null) {
          priceText = _clean(p.text);
          break;
        }
      }
      if (priceText.isEmpty) {
        final paragraphs = li.querySelectorAll('p');
        if (paragraphs.length > 1) priceText = _clean(paragraphs[1].text);
      }

      items.add(MagicItem(
        mid: mid,
        name: name,
        image: _absolute(imgEl?.attributes['src']),
        description: _clean(li.querySelector('.tip_c')?.text ?? ''),
        priceText: priceText,
        price: _clean(li.querySelector('strong.xi1')?.text ?? ''),
        soldOut: buy == null,
        canGive: give != null,
        saleVolume: _clean(li.querySelector('em.xg1')?.text ?? ''),
      ));
    }
    return items;
  }

  /// 我的道具（`home.php?mod=magic&action=mybox`）。
  Future<MagicBox> fetchMagicBox({int page = 1}) async {
    final result = await _getDesktopPage('home.php', {
      'mod': 'magic',
      'action': 'mybox',
      'page': '$page',
    });
    _ensureOk(result);
    final doc = parser.parse(result.body);

    final items = <MyMagic>[];
    for (final li in doc.querySelectorAll('ul.mgcl li')) {
      final imgEl = li.querySelector('.mg_img img') ?? li.querySelector('img');
      final name = _clean(li.querySelector('p strong')?.text ?? imgEl?.attributes['alt'] ?? '');
      if (name.isEmpty) continue;

      final use = li.querySelector('a[href*="operation=use"]');
      final give = li.querySelector('a[href*="operation=give"]');
      final sell = li.querySelector('a[href*="operation=sell"]');
      final drop = li.querySelector('a[href*="operation=drop"]');
      final actionHref = (use ?? give ?? sell ?? drop)?.attributes['href'] ??
          li.querySelector('a[href*="magicid="]')?.attributes['href'] ??
          '';
      final id = _firstInt(RegExp(r'[?&](?:amp;)?magicid=(\d+)').firstMatch(actionHref)?.group(1));
      if (id == null || id <= 0) continue;

      final fonts = li.querySelectorAll('p font');
      final num = _firstInt(_clean(fonts.isNotEmpty ? fonts.first.text : '')) ?? 0;
      final weight = fonts.length > 1 ? _clean(fonts[1].text) : '';

      items.add(MyMagic(
        id: id,
        name: name,
        image: _absolute(imgEl?.attributes['src']),
        description: _clean(li.querySelector('.tip_c')?.text ?? ''),
        num: num,
        weight: weight,
        canUse: use != null,
        canGive: give != null,
        canSell: sell != null,
        canDrop: drop != null,
      ));
    }
    return MagicBox(
      capacity: _clean(doc.querySelector('p.tbmu')?.text ?? ''),
      items: items,
    );
  }

  /// 道具日志（`action=log&operation=uselog|buylog|givelog|receivelog`）。
  Future<List<MagicLogEntry>> fetchMagicLogs(String type, {int page = 1}) async {
    final operation = const {'uselog', 'buylog', 'givelog', 'receivelog'}.contains(type)
        ? type
        : 'uselog';
    final result = await _getDesktopPage('home.php', {
      'mod': 'magic',
      'action': 'log',
      'operation': operation,
      'page': '$page',
    });
    _ensureOk(result);
    final doc = parser.parse(result.body);

    final items = <MagicLogEntry>[];
    for (final tr in doc.querySelectorAll('table.dt tr')) {
      final cells = tr.querySelectorAll('td');
      if (cells.length < 3) continue;
      final values = cells.map((cell) => _clean(cell.text)).toList();
      if (values.first.isEmpty) continue;
      items.add(MagicLogEntry(
        title: values[0],
        time: values.length > 1 ? values[1] : '',
        detail: values.skip(2).where((value) => value.isNotEmpty).join(' · '),
      ));
    }
    return items;
  }

  /// 购买道具。`mid` 为商店里的道具 identifier。
  Future<String> buyMagic({required String mid, int num = 1}) async {
    if (mid.isEmpty) throw SiteException('该道具当前不可购买');
    final formhash = await _fetchMagicFormhash(action: 'shop', operation: 'buy', mid: mid);
    return _submitMagic(action: 'shop', form: {
      'formhash': formhash,
      'operation': 'buy',
      'mid': mid,
      'magicnum': '$num',
      'operatesubmit': 'yes',
    });
  }

  /// 购买后直接赠送给他人。
  Future<String> giftMagicFromShop({
    required String mid,
    required String username,
    int num = 1,
    String message = '',
  }) async {
    if (mid.isEmpty) throw SiteException('该道具当前不可赠送');
    final formhash = await _fetchMagicFormhash(action: 'shop', operation: 'give', mid: mid);
    return _submitMagic(action: 'shop', form: {
      'formhash': formhash,
      'operation': 'give',
      'mid': mid,
      'magicnum': '$num',
      'tousername': username,
      'givemessage': message,
      'operatesubmit': 'yes',
    });
  }

  /// 读取「使用道具」操作页的表单字段。
  Future<MagicUseForm> fetchMagicUseForm(int magicId) async {
    final page = await _getDesktopPage('home.php', {
      'mod': 'magic',
      'action': 'mybox',
      'operation': 'use',
      'magicid': '$magicId',
      'infloat': 'yes',
    });
    _ensureOk(page);
    final doc = parser.parse(page.body);
    final formhash = _findFormhash(page.body);
    if (formhash.isEmpty) {
      throw SiteException(_messageText(doc) ?? '该道具当前无法使用');
    }

    final form = doc.querySelector('form#magicform') ??
        doc.querySelector('form[action*="mod=magic"]');
    final hidden = <String, String>{};
    final fields = <MagicFormField>[];
    final radios = <String>{};
    if (form != null) {
      for (final input in form.querySelectorAll('input')) {
        final name = (input.attributes['name'] ?? '').trim();
        if (name.isEmpty) continue;
        final type = (input.attributes['type'] ?? 'text').toLowerCase();
        final value = input.attributes['value'] ?? '';
        if (type == 'hidden') {
          if (const {'formhash', 'operation', 'magicid', 'usesubmit', 'handlekey'}.contains(name)) {
            continue;
          }
          hidden[name] = value;
          continue;
        }
        if (name == 'magicid' || type == 'submit' || type == 'button' || type == 'reset') continue;
        if (type == 'radio') {
          if (!radios.add(name)) continue;
          fields.add(MagicFormField(
            name: name,
            label: _magicFieldLabel(input),
            type: MagicFieldType.radio,
            value: value == '1' ? '1' : '0',
            options: const [MagicFieldOption('1', '是'), MagicFieldOption('0', '否')],
          ));
          continue;
        }
        if (type == 'checkbox') continue;
        fields.add(MagicFormField(
          name: name,
          label: _magicFieldLabel(input),
          value: value,
        ));
      }
      for (final select in form.querySelectorAll('select')) {
        final name = (select.attributes['name'] ?? '').trim();
        if (name.isEmpty || name == 'magicid') continue;
        final options = <MagicFieldOption>[];
        var selected = '';
        for (final option in select.querySelectorAll('option')) {
          final value = (option.attributes['value'] ?? '').trim();
          if (value.isEmpty) continue;
          options.add(MagicFieldOption(value, _clean(option.text)));
          if (option.attributes.containsKey('selected')) selected = value;
        }
        if (options.isEmpty) continue;
        fields.add(MagicFormField(
          name: name,
          label: _magicFieldLabel(select),
          type: MagicFieldType.select,
          value: selected.isEmpty ? options.first.value : selected,
          options: options,
        ));
      }
      for (final area in form.querySelectorAll('textarea')) {
        final name = (area.attributes['name'] ?? '').trim();
        if (name.isEmpty) continue;
        fields.add(MagicFormField(
          name: name,
          label: _magicFieldLabel(area),
          type: MagicFieldType.textarea,
          value: _clean(area.text),
        ));
      }
    }
    return MagicUseForm(formhash: formhash, hidden: hidden, fields: fields);
  }

  Future<String> useMagic({
    required int magicId,
    required MagicUseForm form,
    Map<String, String> values = const {},
  }) {
    return _submitMagic(action: 'mybox', form: {
      'formhash': form.formhash,
      'operation': 'use',
      'magicid': '$magicId',
      'usesubmit': 'yes',
      ...form.hidden,
      ...values,
    });
  }

  Future<String> giveMagic({
    required int magicId,
    required String username,
    int num = 1,
    String message = '',
  }) async {
    final formhash = await _fetchMagicFormhash(action: 'mybox', operation: 'give', magicId: magicId);
    return _submitMagic(action: 'mybox', form: {
      'formhash': formhash,
      'operation': 'give',
      'magicid': '$magicId',
      'tousername': username,
      'magicnum': '$num',
      'givemessage': message,
      'operatesubmit': 'yes',
    });
  }

  Future<String> sellMagic({required int magicId, int num = 1}) async {
    final formhash = await _fetchMagicFormhash(action: 'mybox', operation: 'sell', magicId: magicId);
    return _submitMagic(action: 'mybox', form: {
      'formhash': formhash,
      'operation': 'sell',
      'magicid': '$magicId',
      'magicnum': '$num',
      'operatesubmit': 'yes',
    });
  }

  Future<String> dropMagic({required int magicId, int num = 1}) async {
    final formhash = await _fetchMagicFormhash(action: 'mybox', operation: 'drop', magicId: magicId);
    return _submitMagic(action: 'mybox', form: {
      'formhash': formhash,
      'operation': 'drop',
      'magicid': '$magicId',
      'magicnum': '$num',
      'operatesubmit': 'yes',
    });
  }

  /// 读取道具操作页里的 formhash（操作页是站点唯一稳定输出该凭证的地方）。
  Future<String> _fetchMagicFormhash({
    required String action,
    required String operation,
    String? mid,
    int? magicId,
  }) async {
    final page = await _getDesktopPage('home.php', {
      'mod': 'magic',
      'action': action,
      'operation': operation,
      if (mid != null) 'mid': mid,
      if (magicId != null) 'magicid': '$magicId',
      'infloat': 'yes',
    });
    _ensureOk(page);
    final formhash = _findFormhash(page.body);
    if (formhash.isEmpty) {
      throw SiteException(_messageText(parser.parse(page.body)) ?? '该操作当前不可用');
    }
    return formhash;
  }

  Future<String> _submitMagic({required String action, required Map<String, String> form}) async {
    final result = await _http.post(
      'home.php',
      query: {'mod': 'magic', 'action': action, 'mobile': 'no'},
      form: form,
      referer: AppConfig.uri('home.php', {'mod': 'magic', 'action': action}).toString(),
      userAgent: _desktopUserAgent,
    );
    _http.removeCookie('mobile');
    _ensureOk(result);

    final doc = parser.parse(result.body);
    final box = doc.querySelector('#messagetext');
    final message = _messageText(doc);
    if (box != null) {
      final classes = box.attributes['class'] ?? '';
      if (classes.contains('alert_error') ||
          (message != null && _looksLikeError(message))) {
        throw SiteException(message ?? '操作失败，请稍后重试');
      }
    } else if (message != null && _looksLikeError(message)) {
      throw SiteException(message);
    }
    return message ?? '操作成功';
  }

  /// 桌面消息页的正文（`#messagetext` 的第一个段落）。
  String? _messageText(Document doc) {
    final box = doc.querySelector('#messagetext');
    if (box != null) {
      final text = _clean(box.querySelector('p')?.text ?? box.text);
      if (text.isNotEmpty) return text;
    }
    return _pageMessage(doc);
  }

  String _magicQueryValue(String href, String key) {
    final match = RegExp('[?&](?:amp;)?$key=([^&]+)').firstMatch(href);
    final value = match?.group(1) ?? '';
    if (value.isEmpty) return '';
    try {
      return Uri.decodeComponent(value);
    } catch (_) {
      return value;
    }
  }

  /// 表单字段标签：优先取紧邻的提示段落，其次取表格行的表头。
  String _magicFieldLabel(Element element) {
    var previous = element.previousElementSibling;
    while (previous != null && previous.localName == 'script') {
      previous = previous.previousElementSibling;
    }
    final text = _clean(previous?.text ?? '');
    if (text.isNotEmpty && text.length <= 60) return text;
    final th = element.parent?.parent?.querySelector('th');
    final header = _clean(th?.text ?? '');
    return header.length <= 60 ? header : '';
  }

  /// 通用站点模块：返回（提示文案, 列表行）。
  Future<(String, List<SiteRow>)> fetchModule(String path, Map<String, String> query) async {
    final result = await _http.get(path, query: query);
    _ensureOk(result);
    final doc = parser.parse(result.body);

    final tip = _clean(
      doc.querySelector('.comiis_password_top p')?.text ??
          doc.querySelector('.alert_info')?.text ??
          doc.querySelector('.alert_error')?.text ??
          '',
    );

    final rows = <SiteRow>[];
    final seen = <String>{};
    for (final li in doc.querySelectorAll('.comiis_bodybox li, #ct li, .comiis_list01 li')) {
      final classes = li.attributes['class'] ?? '';
      if (classes.contains('comiis_left_Touch')) continue;
      final link = li.querySelector('a[href]');
      final href = _absolute(link?.attributes['href']);
      final text = _clean(li.text);
      if (text.isEmpty || text.length > 300) continue;
      final img = li.querySelector('img');
      final title = _clean(
        li.querySelector('.tit, .title, h3, h4, strong')?.text ?? link?.text ?? text,
      );
      if (title.isEmpty || !seen.add('$title|$href')) continue;
      final rest = _clean(text.replaceFirst(title, ''));
      rows.add(SiteRow(
        title: title,
        subtitle: rest,
        image: _absolute(img?.attributes['src']),
        href: href,
      ));
      if (rows.length >= 60) break;
    }
    return (tip, rows);
  }

  /// 积分商城商品详情（keke_integralmall 插件页）。
  Future<MallProduct> fetchMallProduct(int tid) async {
    final result = await _http.get(
      'keke_integralmall-view.html',
      query: {'tid': '$tid', 'mobile': '2'},
    );
    _ensureOk(result);
    final doc = parser.parse(result.body);

    String pick(String selector) => _clean(doc.querySelector(selector)?.text ?? '');

    final records = <SiteRow>[];
    final seen = <String>{};
    for (final tr in doc.querySelectorAll('.comiis_bodybox tr')) {
      final cells = tr.querySelectorAll('td');
      if (cells.length < 3) continue;
      final values = <String>[];
      for (final cell in cells) {
        final value = _clean(cell.text);
        if (value.isNotEmpty) values.add(value);
      }
      if (values.length < 3) continue;
      if (!seen.add(values.join('|'))) continue;
      records.add(SiteRow(title: values.first, subtitle: values.skip(1).join(' · ')));
      if (records.length >= 20) break;
    }

    return MallProduct(
      tid: tid,
      title: _clean(
        doc.querySelector('.comiis_viewtit h2')?.text ??
            doc.querySelector('h2')?.text ??
            doc.querySelector('title')?.text ??
            '',
      ),
      image: _absolute(
        doc.querySelector('.mallitem img')?.attributes['src'] ??
            doc.querySelector('.item_l img')?.attributes['src'] ??
            doc.querySelector('.comiis_bodybox img')?.attributes['src'],
      ),
      price: pick('.price-real'),
      marketPrice: pick('.price-sell'),
      stock: pick('.count-take'),
      sold: pick('.count-rest'),
      countdown: pick('#countdown'),
      views: pick('.item-assure b'),
      warning: pick('.item-warning'),
      buyHref: _absolute(doc.querySelector('a.buy-btn')?.attributes['href']),
      statusHref: _absolute(doc.querySelector('a.detail-btn')?.attributes['href']),
      records: records,
    );
  }

  /// 读取插件操作页的正文文本（例如查看卡密状态）。
  Future<String> fetchPluginText(String href) async {
    final uri = Uri.tryParse(href);
    if (uri == null) throw SiteException('链接无效');
    final result = await _http.get(uri.path.replaceFirst('/', ''), query: uri.queryParameters);
    _ensureOk(result);
    final doc = parser.parse(result.body);
    final text = _clean((doc.querySelector('.comiis_bodybox') ?? doc.body)?.text ?? '');
    final message = _pageMessage(doc);
    final output = text.isEmpty ? (message ?? '') : text;
    return output.length > 800 ? '${output.substring(0, 800)}…' : output;
  }

  /// 执行站点模块行上的原生操作（GET，例如领取勋章、购买道具）。
  Future<String> performModuleAction(String href) async {
    final uri = Uri.tryParse(href);
    if (uri == null) throw SiteException('链接无效');
    final result = await _http.get(
      uri.path.replaceFirst('/', ''),
      query: uri.queryParameters,
      referer: AppConfig.uri('home.php', {'mod': 'space', 'do': 'profile', 'mobile': '2'}).toString(),
    );
    _ensureOk(result);
    final message = _pageMessage(parser.parse(result.body));
    if (message != null && _looksLikeError(message)) throw SiteException(message);
    return message ?? '操作成功';
  }

  String decode(List<int> bytes) => WafSolver.decodeUtf8(bytes);
}
