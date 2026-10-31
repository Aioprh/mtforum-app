import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

import '../core/app_config.dart';
import '../data/forum_repository.dart';
import '../data/models.dart';

/// 工具执行过程中可以直接抛给 AI 的错误。
class McpToolException implements Exception {
  const McpToolException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 一个 MCP 工具的声明与实现。
class McpTool {
  const McpTool({
    required this.name,
    required this.title,
    required this.description,
    required this.inputSchema,
    required this.run,
    this.write = false,
  });

  final String name;
  final String title;
  final String description;
  final Map<String, dynamic> inputSchema;

  /// 会改动站内数据的操作（发帖、回复、签到）。控制台里可以整体关掉。
  final bool write;

  final Future<Object?> Function(Map<String, dynamic> args) run;

  /// `tools/list` 里返回的形态，字段遵循 MCP 2025-06-18 规范。
  Map<String, dynamic> describe() => <String, dynamic>{
        'name': name,
        'title': title,
        'description': description,
        'inputSchema': inputSchema,
        'annotations': <String, dynamic>{
          'title': title,
          'readOnlyHint': !write,
          'destructiveHint': false,
          'idempotentHint': !write,
          'openWorldHint': true,
        },
      };
}

/// 把论坛仓库的能力映射成 AI 能调用的函数。
///
/// 所有工具都复用 App 内已登录的 [HttpSession]，所以调用方不需要再传账号密码，
/// 权限就是手机上这个账号的权限。
class McpTools {
  McpTools({ForumRepository? repository})
      : _repo = repository ?? ForumRepository.instance;

  final ForumRepository _repo;

  late final List<McpTool> all = <McpTool>[
    McpTool(
      name: 'forum_list_boards',
      title: '列出全部版块',
      description:
          '返回站点的版块分类，以及每个版块的 fid、名称、今日发帖数。'
          '发帖或按版块翻帖前，先用它确认 fid。',
      inputSchema: const <String, dynamic>{
        'type': 'object',
        'properties': <String, dynamic>{},
        'additionalProperties': false,
      },
      run: (_) => _listBoards(),
    ),
    McpTool(
      name: 'forum_list_threads',
      title: '拉取版块帖子列表',
      description: '按 fid 分页拉取主题列表，返回 tid、标题、作者、回复数、浏览数。',
      inputSchema: const <String, dynamic>{
        'type': 'object',
        'properties': <String, dynamic>{
          'fid': <String, dynamic>{'type': 'integer', 'description': '版块 id'},
          'page': <String, dynamic>{
            'type': 'integer',
            'description': '页码，从 1 开始，默认 1',
            'minimum': 1,
          },
        },
        'required': <String>['fid'],
        'additionalProperties': false,
      },
      run: _listThreads,
    ),
    McpTool(
      name: 'forum_get_thread',
      title: '读取帖子内容',
      description:
          '读取指定主题的正文与楼层，返回纯文本（图片以 [图片] 标记）。'
          '要回复某一楼时，从 posts 里取该楼的 pid 传给 forum_reply。',
      inputSchema: const <String, dynamic>{
        'type': 'object',
        'properties': <String, dynamic>{
          'tid': <String, dynamic>{'type': 'integer', 'description': '主题 id'},
          'page': <String, dynamic>{
            'type': 'integer',
            'description': '楼层页码，默认 1',
            'minimum': 1,
          },
          'max_posts': <String, dynamic>{
            'type': 'integer',
            'description': '最多返回几层，默认 10，上限 30',
            'minimum': 1,
            'maximum': 30,
          },
        },
        'required': <String>['tid'],
        'additionalProperties': false,
      },
      run: _getThread,
    ),
    McpTool(
      name: 'forum_search',
      title: '搜索帖子',
      description: '按关键词搜索主题，可选限定版块。返回 tid、标题、作者与摘要。',
      inputSchema: const <String, dynamic>{
        'type': 'object',
        'properties': <String, dynamic>{
          'keyword': <String, dynamic>{'type': 'string', 'description': '搜索关键词'},
          'fid': <String, dynamic>{
            'type': 'integer',
            'description': '限定版块 id，0 表示全站',
          },
          'page': <String, dynamic>{
            'type': 'integer',
            'description': '页码，默认 1',
            'minimum': 1,
          },
        },
        'required': <String>['keyword'],
        'additionalProperties': false,
      },
      run: _search,
    ),
    McpTool(
      name: 'forum_reply',
      title: '回复帖子',
      description:
          '在主题下发表回复。传 reply_to_pid 表示回复某一楼，网页端会显示成带引用的回复；'
          '不传就是普通回帖。正文支持 Discuz 代码（如 [b]粗体[/b]）。',
      write: true,
      inputSchema: const <String, dynamic>{
        'type': 'object',
        'properties': <String, dynamic>{
          'tid': <String, dynamic>{'type': 'integer', 'description': '主题 id'},
          'message': <String, dynamic>{'type': 'string', 'description': '回复正文'},
          'reply_to_pid': <String, dynamic>{
            'type': 'integer',
            'description': '可选，被回复楼层的 pid；不传则为普通回复',
          },
        },
        'required': <String>['tid', 'message'],
        'additionalProperties': false,
      },
      run: _reply,
    ),
    McpTool(
      name: 'forum_create_thread',
      title: '发表新主题',
      description: '在指定版块发一个新帖。subject 为标题，message 为正文（支持 Discuz 代码）。',
      write: true,
      inputSchema: const <String, dynamic>{
        'type': 'object',
        'properties': <String, dynamic>{
          'fid': <String, dynamic>{'type': 'integer', 'description': '版块 id'},
          'subject': <String, dynamic>{'type': 'string', 'description': '帖子标题'},
          'message': <String, dynamic>{'type': 'string', 'description': '帖子正文'},
        },
        'required': <String>['fid', 'subject', 'message'],
        'additionalProperties': false,
      },
      run: _createThread,
    ),
    McpTool(
      name: 'forum_me',
      title: '当前登录账号',
      description: '返回 App 内当前登录的账号信息（uid、用户名、等级、积分等）。',
      inputSchema: const <String, dynamic>{
        'type': 'object',
        'properties': <String, dynamic>{},
        'additionalProperties': false,
      },
      run: (_) => _me(),
    ),
    McpTool(
      name: 'forum_sign_in',
      title: '每日签到',
      description: '替当前账号执行一次签到。已签到会返回站点提示。',
      write: true,
      inputSchema: const <String, dynamic>{
        'type': 'object',
        'properties': <String, dynamic>{},
        'additionalProperties': false,
      },
      run: (_) => _signIn(),
    ),
  ];

  McpTool? byName(String name) {
    for (final tool in all) {
      if (tool.name == name) return tool;
    }
    return null;
  }

  // ------------------------------------------------------------ 具体实现

  Future<Object?> _listBoards() async {
    final categories = await _repo.fetchBoards();
    return <String, Object?>{
      'categories': <Object?>[
        for (final category in categories)
          <String, Object?>{
            'name': category.name,
            'boards': <Object?>[
              for (final board in category.boards)
                <String, Object?>{
                  'fid': board.fid,
                  'name': board.name,
                  'today_posts': board.todayPosts,
                },
            ],
          },
      ],
    };
  }

  Future<Object?> _listThreads(Map<String, dynamic> args) async {
    final fid = _int(args['fid']);
    if (fid <= 0) {
      throw const McpToolException('fid 必须是正整数，可先用 forum_list_boards 查询');
    }
    final page = _int(args['page'], fallback: 1).clamp(1, 200);
    final threads = await _repo.fetchBoardThreads(fid, page: page);
    return <String, Object?>{
      'fid': fid,
      'page': page,
      'count': threads.length,
      'threads': <Object?>[for (final t in threads) _summary(t)],
    };
  }

  Future<Object?> _getThread(Map<String, dynamic> args) async {
    final tid = _int(args['tid']);
    if (tid <= 0) throw const McpToolException('tid 必须是正整数');
    final page = _int(args['page'], fallback: 1).clamp(1, 200);
    final maxPosts = _int(args['max_posts'], fallback: 10).clamp(1, 30);
    final detail = await _repo.fetchThread(tid, page: page);
    return <String, Object?>{
      'tid': detail.tid,
      'title': detail.title,
      'fid': detail.fid,
      'board': detail.boardName,
      'author': detail.author,
      'time': detail.time,
      'views': detail.views,
      'replies': detail.replies,
      'page': page,
      'has_more': detail.hasMore,
      'url': _threadUrl(detail.tid),
      'posts': <Object?>[
        for (final post in detail.posts.take(maxPosts))
          <String, Object?>{
            'pid': post.pid,
            'floor': post.floor,
            'author': post.author,
            'uid': post.uid,
            'time': post.time,
            'is_op': post.isOp,
            'text': htmlToText(post.html),
            if (post.images.isNotEmpty) 'images': post.images,
            if (post.comments.isNotEmpty)
              'comments': <Object?>[
                for (final comment in post.comments)
                  <String, Object?>{
                    'author': comment.author,
                    'text': comment.text,
                    'time': comment.time,
                  },
              ],
          },
      ],
    };
  }

  Future<Object?> _search(Map<String, dynamic> args) async {
    final keyword = _str(args['keyword']);
    if (keyword.isEmpty) throw const McpToolException('keyword 不能为空');
    final fid = _int(args['fid']);
    final page = _int(args['page'], fallback: 1).clamp(1, 50);
    final threads = await _repo.search(keyword, fid: fid, page: page);
    return <String, Object?>{
      'keyword': keyword,
      'fid': fid,
      'page': page,
      'count': threads.length,
      'threads': <Object?>[for (final t in threads) _summary(t)],
    };
  }

  Future<Object?> _reply(Map<String, dynamic> args) async {
    final tid = _int(args['tid']);
    final message = _str(args['message']);
    if (tid <= 0) throw const McpToolException('tid 必须是正整数');
    if (message.isEmpty) throw const McpToolException('message 不能为空');
    final pid = _int(args['reply_to_pid']);

    // 回复接口需要 fid 与 formhash，只能先从帖子里取；
    // 引用条（noticeauthor / noticetrimstr）也必须由服务端生成，
    // 客户端算不出 authcode，所以还要多取一次回复页。
    final detail = await _repo.fetchThread(tid);
    var noticeAuthor = '';
    var noticeTrim = '';
    var noticeAuthorMsg = '';
    if (pid > 0) {
      final ctx = await _repo.fetchReplyContext(
        tid: tid,
        fid: detail.fid,
        pid: pid,
      );
      noticeAuthor = ctx.noticeAuthor;
      noticeTrim = ctx.noticeTrim;
      noticeAuthorMsg = ctx.noticeAuthorMsg;
    }

    final message_ = await _repo.reply(
      tid: tid,
      fid: detail.fid,
      formhash: detail.formhash,
      message: message,
      replyToPid: pid > 0 ? pid : null,
      noticeAuthor: noticeAuthor,
      noticeTrim: noticeTrim,
      noticeAuthorMsg: noticeAuthorMsg,
    );

    return <String, Object?>{
      'ok': true,
      'tid': tid,
      'reply_to_pid': pid > 0 ? pid : null,
      'site_message': message_,
      'url': _threadUrl(tid),
    };
  }

  Future<Object?> _createThread(Map<String, dynamic> args) async {
    final fid = _int(args['fid']);
    final subject = _str(args['subject']);
    final message = _str(args['message']);
    if (fid <= 0) throw const McpToolException('fid 必须是正整数');
    if (subject.isEmpty) throw const McpToolException('subject 不能为空');
    if (message.isEmpty) throw const McpToolException('message 不能为空');

    final result = await _repo.createThread(
      fid: fid,
      subject: subject,
      message: message,
    );
    return <String, Object?>{
      'ok': true,
      'fid': fid,
      'subject': subject,
      'site_message': result,
    };
  }

  Future<Object?> _me() async {
    final profile = await _repo.fetchMyProfile();
    return <String, Object?>{
      'uid': profile.uid,
      'username': profile.username,
      'level': profile.level,
      'group': profile.group,
      'credits': profile.credits,
      'posts': profile.posts,
      'replies': profile.replies,
      'followers': profile.followers,
      'reg_time': profile.regTime,
    };
  }

  Future<Object?> _signIn() async {
    final result = await _repo.signIn();
    return <String, Object?>{'ok': true, 'site_message': result};
  }

  // ------------------------------------------------------------ 小工具

  Map<String, Object?> _summary(ThreadSummary thread) => <String, Object?>{
        'tid': thread.tid,
        'title': thread.title,
        'author': thread.author,
        'board': thread.boardName,
        'time': thread.time,
        'replies': thread.replies,
        'views': thread.views,
        if (thread.excerpt.isNotEmpty) 'excerpt': thread.excerpt,
        'url': _threadUrl(thread.tid),
      };

  String _threadUrl(int tid) =>
      AppConfig.uri('forum.php', <String, String>{'mod': 'viewthread', 'tid': '$tid'})
          .toString();

  int _int(Object? value, {int fallback = 0}) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse('${value ?? ''}'.trim()) ?? fallback;
  }

  String _str(Object? value) => '${value ?? ''}'.trim();

  /// 把 Discuz 正文转成适合给模型读的纯文本。
  ///
  /// 块级元素前后留换行，`<br>` 换算行，图片压成 `[图片]`——模型不需要 alt，
  /// 但需要知道那里有一张图。
  String htmlToText(String html) {
    if (html.trim().isEmpty) return '';
    final fragment = html_parser.parseFragment(html);
    final buffer = StringBuffer();

    void walk(dom.Node node) {
      if (node is dom.Text) {
        buffer.write(node.text.replaceAll(RegExp(r'[ \t\r\n]+'), ' '));
        return;
      }
      if (node is! dom.Element) return;
      final tag = node.localName ?? '';
      if (tag == 'br') {
        buffer.write('\n');
        return;
      }
      if (tag == 'img') {
        buffer.write('[图片]');
        return;
      }
      if (tag == 'script' || tag == 'style') return;
      if (tag == 'p' || tag == 'div' || tag == 'li' || tag == 'tr') {
        buffer.write('\n');
      }
      for (final child in node.nodes) {
        walk(child);
      }
      if (tag == 'p' ||
          tag == 'div' ||
          tag == 'li' ||
          tag == 'tr' ||
          tag == 'table' ||
          tag == 'blockquote') {
        buffer.write('\n');
      }
    }

    for (final node in fragment.nodes) {
      walk(node);
    }
    return buffer
        .toString()
        .replaceAll(RegExp(r'[ \t]+\n'), '\n')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }
}
