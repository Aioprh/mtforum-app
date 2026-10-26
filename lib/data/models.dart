class ForumBoard {
  const ForumBoard({
    required this.fid,
    required this.name,
    this.icon = '',
    this.todayPosts = 0,
  });

  final int fid;
  final String name;
  final String icon;
  final int todayPosts;
}

class ForumCategory {
  const ForumCategory({required this.name, required this.boards});

  final String name;
  final List<ForumBoard> boards;
}

class ThreadSummary {
  const ThreadSummary({
    required this.tid,
    required this.title,
    required this.url,
    this.excerpt = '',
    this.author = '',
    this.avatar = '',
    this.uid = 0,
    this.time = '',
    this.boardName = '',
    this.images = const <String>[],
    this.replies = 0,
    this.views = 0,
  });

  final int tid;
  final String title;
  final String url;
  final String excerpt;
  final String author;
  final String avatar;
  final int uid;
  final String time;
  final String boardName;
  final List<String> images;
  final int replies;
  final int views;
}

class ForumComment {
  const ForumComment({
    required this.author,
    required this.text,
    this.uid = 0,
    this.time = '',
  });

  final String author;
  final String text;
  final int uid;
  final String time;
}

/// 投票选项。
class PollOption {
  const PollOption({required this.id, required this.text, this.votes = 0});

  final int id;
  final String text;
  final int votes;
}

/// 主题投票。
class Poll {
  const Poll({
    this.options = const <PollOption>[],
    this.multiple = false,
    this.total = 0,
    this.voted = false,
    this.expired = false,
  });

  final List<PollOption> options;
  final bool multiple;
  final int total;
  final bool voted;
  final bool expired;
}

/// 消息通知（回复提醒、@提醒、系统通知）。
class NoticeItem {
  const NoticeItem({
    required this.title,
    this.text = '',
    this.time = '',
    this.url = '',
    this.kind = '',
  });

  final String title;
  final String text;
  final String time;
  final String url;
  final String kind;
}

/// 一次打赏记录（Discuz 评分日志）。
class RateRecord {
  const RateRecord({
    required this.username,
    this.uid = 0,
    this.score = '',
    this.reason = '',
  });

  final String username;
  final int uid;
  final String score;
  final String reason;
}

/// 站点允许的打赏项（好评 / 金币等，取决于用户组评分类别）。
class RateField {
  const RateField({
    required this.id,
    required this.label,
    this.min = 0,
    this.max = 1,
    this.left = 1,
    this.presets = const <int>[],
  });

  final int id;
  final String label;
  final int min;
  final int max;

  /// 今日剩余可评分额度（站点评分表「今日剩余」）。
  final int left;

  /// 站点下拉实际给出的可选分值（已按今日剩余裁剪）。
  final List<int> presets;

  /// 本次实际可选的最大分值。
  int get ceiling => max < left ? max : left;
}

class RateOptions {
  const RateOptions({this.fields = const <RateField>[], this.canNotify = false});

  final List<RateField> fields;
  final bool canNotify;

  /// 解析失败时的兜底：站点普通用户组每项每天上限均为 1。
  static const RateOptions fallback = RateOptions(
    fields: <RateField>[
      RateField(id: 1, label: '好评', max: 1),
      RateField(id: 2, label: '金币', max: 1),
    ],
  );
}

class ForumPost {
  ForumPost({
    required this.pid,
    required this.author,
    required this.avatar,
    required this.time,
    required this.html,
    required this.floor,
    this.uid = 0,
    this.level = '',
    this.location = '',
    this.isOp = false,
    this.likes = 0,
    this.images = const <String>[],
    this.comments = const <ForumComment>[],
    this.rates = const <RateRecord>[],
    this.rateSummary = '',
  });

  final int pid;
  final String author;
  final String avatar;
  final String time;
  final String html;
  final int floor;
  final int uid;
  final String level;
  final String location;
  final bool isOp;
  final int likes;
  final List<String> images;
  final List<ForumComment> comments;
  final List<RateRecord> rates;
  final String rateSummary;

  String get floorLabel => floor == 1 ? '楼主' : '$floor 楼';

  ForumPost copyWith({int? floor, int? uid, String? avatar}) => ForumPost(
        pid: pid,
        author: author,
        avatar: avatar ?? this.avatar,
        time: time,
        html: html,
        floor: floor ?? this.floor,
        uid: uid ?? this.uid,
        level: level,
        location: location,
        isOp: isOp,
        likes: likes,
        images: images,
        comments: comments,
        rates: rates,
        rateSummary: rateSummary,
      );
}

class ThreadDetail {
  const ThreadDetail({
    required this.tid,
    required this.title,
    required this.fid,
    required this.boardName,
    required this.author,
    required this.time,
    required this.views,
    required this.replies,
    required this.posts,
    required this.formhash,
    required this.hasMore,
    required this.isLoggedIn,
    this.likes = 0,
    this.dislikes = 0,
    this.uploadHash = '',
    this.uid = 0,
    this.poll,
    this.notice = '',
    this.favorited = false,
    this.favoriteHref = '',
    this.kickToken = '',
    this.kickVotes = 0,
    this.kickLimit = 5,
  });

  final int tid;
  final String title;
  final int fid;
  final String boardName;
  final String author;
  final String time;
  final int views;
  final int replies;
  final List<ForumPost> posts;
  final String formhash;
  final bool hasMore;
  final bool isLoggedIn;
  final int likes;
  final int dislikes;

  /// 当前页面用于附件上传的 hash 与 uid（游客为 0）。
  final String uploadHash;
  final int uid;
  final Poll? poll;
  final String notice;

  /// 是否已收藏该主题，以及页面上收藏/取消收藏的原始链接。
  final bool favorited;
  final String favoriteHref;

  /// 踢帖入口（站点插件 bin_post_report 注入的 token 与当前票数）。
  final String kickToken;
  final int kickVotes;
  final int kickLimit;

  ThreadDetail copyWith({List<ForumPost>? posts, bool? hasMore, int? likes, int? dislikes}) => ThreadDetail(
        tid: tid,
        title: title,
        fid: fid,
        boardName: boardName,
        author: author,
        time: time,
        views: views,
        replies: replies,
        posts: posts ?? this.posts,
        formhash: formhash,
        hasMore: hasMore ?? this.hasMore,
        isLoggedIn: isLoggedIn,
        likes: likes ?? this.likes,
        dislikes: dislikes ?? this.dislikes,
        uploadHash: uploadHash,
        uid: uid,
        poll: poll,
        notice: notice,
        favorited: favorited,
        favoriteHref: favoriteHref,
        kickToken: kickToken,
        kickVotes: kickVotes,
        kickLimit: kickLimit,
      );
}

class ComposeInfo {
  const ComposeInfo({
    required this.formhash,
    required this.uploadHash,
    required this.uid,
  });

  final String formhash;
  final String uploadHash;
  final int uid;
}

class UserProfile {
  const UserProfile({
    required this.uid,
    required this.username,
    this.avatar = '',
    this.level = '',
    this.credits = '',
    this.posts = '',
    this.replies = '',
    this.followers = '',
    this.regTime = '',
    this.group = '',
  });

  final int uid;
  final String username;
  final String avatar;
  final String level;
  final String credits;
  final String posts;
  final String replies;
  final String followers;
  final String regTime;
  final String group;
}

/// 小黑屋记录（forum.php?mod=misc&action=showdarkroom）。
class DarkRoomEntry {
  const DarkRoomEntry({
    required this.uid,
    required this.name,
    required this.action,
    this.expiry = '',
    this.time = '',
  });

  final int uid;
  final String name;
  final String action;
  final String expiry;
  final String time;
}

/// 勋章目录条目。
class MedalItem {
  const MedalItem({required this.name, this.image = '', this.desc = ''});

  final String name;
  final String image;
  final String desc;
}

/// 勋章获得记录。
class MedalRecord {
  const MedalRecord({
    required this.uid,
    required this.name,
    required this.medal,
    this.avatar = '',
    this.time = '',
  });

  final int uid;
  final String name;
  final String medal;
  final String avatar;
  final String time;
}

/// 站点功能模块中的一行（道具、任务、积分、推广等）。
class SiteRow {
  const SiteRow({
    required this.title,
    this.subtitle = '',
    this.image = '',
    this.href = '',
  });

  final String title;
  final String subtitle;
  final String image;
  final String href;
}

/// 积分商城商品详情（keke_integralmall 插件）。
class MallProduct {
  const MallProduct({
    required this.tid,
    required this.title,
    this.image = '',
    this.price = '',
    this.marketPrice = '',
    this.stock = '',
    this.sold = '',
    this.countdown = '',
    this.views = '',
    this.warning = '',
    this.buyHref = '',
    this.statusHref = '',
    this.records = const [],
  });

  final int tid;
  final String title;
  final String image;
  final String price;
  final String marketPrice;
  final String stock;
  final String sold;
  final String countdown;
  final String views;
  final String warning;
  final String buyHref;
  final String statusHref;
  final List<SiteRow> records;
}
