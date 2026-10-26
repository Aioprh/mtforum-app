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

/// 好友（空间好友列表）。
class FriendItem {
  const FriendItem({
    required this.uid,
    required this.username,
    this.avatar = '',
    this.note = '',
  });

  final int uid;
  final String username;
  final String avatar;
  final String note;
}

/// 私信会话摘要。
class PmConversation {
  const PmConversation({
    required this.uid,
    required this.name,
    this.avatar = '',
    this.preview = '',
    this.time = '',
    this.unread = false,
  });

  final int uid;
  final String name;
  final String avatar;
  final String preview;
  final String time;
  final bool unread;
}

/// 单条私信。
class PmMessage {
  const PmMessage({
    required this.text,
    this.author = '',
    this.uid = 0,
    this.time = '',
    this.mine = false,
  });

  final String text;
  final String author;
  final int uid;
  final String time;
  final bool mine;
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
  const RateOptions({
    this.fields = const <RateField>[],
    this.canNotify = false,
    this.notice = '',
  });

  final List<RateField> fields;
  final bool canNotify;

  /// 站点返回的不可打赏提示（如 24 小时内额度已用完）。
  final String notice;

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

  String get floorLabel {
    if (floor <= 1) return '楼主';
    // 对齐 bbs.binmt.cc 评论区的座位式楼层标签。
    const seats = <String>['沙发', '椅子', '板凳', '地毯', '凉席', '报纸', '地板'];
    final index = floor - 2;
    return index >= 0 && index < seats.length ? seats[index] : '$floor 楼';
  }

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

/// 积分项（金币、威望、贡献等）。
class CreditItem {
  const CreditItem({required this.name, required this.value, this.highlight = false});

  final String name;
  final String value;
  final bool highlight;
}

/// 积分页的余额摘要。
class CreditSummary {
  const CreditSummary({
    this.items = const <CreditItem>[],
    this.total = '',
    this.formula = '',
  });

  final List<CreditItem> items;
  final String total;
  final String formula;
}

/// 积分交易记录。
class CreditLog {
  const CreditLog({
    required this.operation,
    required this.change,
    required this.detail,
    required this.time,
  });

  final String operation;
  final String change;
  final String detail;
  final String time;
}

/// 道具商店条目。
class MagicItem {
  const MagicItem({
    required this.mid,
    required this.name,
    this.image = '',
    this.description = '',
    this.priceText = '',
    this.price = '',
    this.soldOut = false,
    this.canGive = false,
    this.saleVolume = '',
  });

  /// 道具 identifier，购买/赠送时作为 `mid` 提交。
  final String mid;
  final String name;
  final String image;
  final String description;
  final String priceText;
  final String price;
  final bool soldOut;

  /// 站点是否开放「购买后赠送」。
  final bool canGive;

  /// 热销榜上的已售数量文案。
  final String saleVolume;
}

/// 我的道具。
class MyMagic {
  const MyMagic({
    required this.id,
    required this.name,
    this.image = '',
    this.description = '',
    this.num = 0,
    this.weight = '',
    this.canUse = false,
    this.canGive = false,
    this.canSell = false,
    this.canDrop = false,
  });

  /// 数字道具 id，使用/赠送/出售/丢弃时作为 `magicid` 提交。
  final int id;
  final String name;
  final String image;
  final String description;
  final int num;
  final String weight;
  final bool canUse;
  final bool canGive;
  final bool canSell;
  final bool canDrop;
}

/// 我的道具页内容。
class MagicBox {
  const MagicBox({this.capacity = '', this.items = const <MyMagic>[]});

  final String capacity;
  final List<MyMagic> items;
}

/// 道具日志条目。
class MagicLogEntry {
  const MagicLogEntry({required this.title, this.time = '', this.detail = ''});

  final String title;
  final String time;
  final String detail;
}

enum MagicFieldType { text, radio, select, textarea }

class MagicFieldOption {
  const MagicFieldOption(this.value, this.label);

  final String value;
  final String label;
}

/// 使用道具时站点要求的表单字段（如主题 ID、颜色等）。
class MagicFormField {
  const MagicFormField({
    required this.name,
    this.label = '',
    this.type = MagicFieldType.text,
    this.value = '',
    this.options = const <MagicFieldOption>[],
  });

  final String name;
  final String label;
  final MagicFieldType type;
  final String value;
  final List<MagicFieldOption> options;
}

/// 使用道具的操作页表单。
class MagicUseForm {
  const MagicUseForm({
    required this.formhash,
    this.hidden = const <String, String>{},
    this.fields = const <MagicFormField>[],
  });

  final String formhash;
  final Map<String, String> hidden;
  final List<MagicFormField> fields;
}

/// 积分商城下单：确认页解析出的表单。
class MallCheckout {
  const MallCheckout({
    this.action = '',
    this.formhash = '',
    this.hidden = const <String, String>{},
    this.fields = const <MagicFormField>[],
    this.preview = '',
  });

  /// 表单提交地址；为空表示该页已是结果页。
  final String action;
  final String formhash;
  final Map<String, String> hidden;
  final List<MagicFormField> fields;

  /// 确认页 / 结果页上的可见文本（商品信息、卡密等）。
  final String preview;

  bool get isForm => action.isNotEmpty;
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
    this.startAt,
    this.endAt,
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

  /// 抢购开始 / 结束时间，剩余时间由客户端实时计算。
  final DateTime? startAt;
  final DateTime? endAt;
  final String views;
  final String warning;
  final String buyHref;
  final String statusHref;
  final List<SiteRow> records;
}
