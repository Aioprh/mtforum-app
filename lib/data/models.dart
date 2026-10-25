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

  String get floorLabel => floor == 1 ? '楼主' : '$floor 楼';

  ForumPost copyWith({int? floor}) => ForumPost(
        pid: pid,
        author: author,
        avatar: avatar,
        time: time,
        html: html,
        floor: floor ?? this.floor,
        uid: uid,
        level: level,
        location: location,
        isOp: isOp,
        likes: likes,
        images: images,
        comments: comments,
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
    this.notice = '',
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
  final String notice;

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
        notice: notice,
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
