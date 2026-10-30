import 'package:flutter/material.dart';

import '../../core/video_link.dart';
import 'smart_image.dart';

/// 正文里的视频播放区域。
///
/// 帖子作者习惯把演示视频写成一条外链，点开要跳浏览器。这里把它做成
/// 一块可点击的播放卡片：有封面、有播放按钮，点一下就在应用内播放。
class VideoCard extends StatelessWidget {
  const VideoCard({
    super.key,
    required this.video,
    this.cover,
    this.title,
    this.onTap,
  });

  final VideoLink video;

  /// 可选封面（B站视频封面等）。为空时用来源色渐变占位。
  final String? cover;

  /// 卡片标题，默认「视频演示」。
  final String? title;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = _accent(video.kind);

    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 10),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (cover != null && cover!.isNotEmpty)
                        SmartImage(url: cover!, fit: BoxFit.cover, radius: BorderRadius.zero)
                      else
                        DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                Color.alphaBlend(accent.withValues(alpha: 0.55), const Color(0xFF14161C)),
                                const Color(0xFF14161C),
                              ],
                            ),
                          ),
                        ),
                      // 压暗一层，保证播放按钮和标签在任何封面上都清楚。
                      const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Color(0x33000000), Color(0x66000000)],
                          ),
                        ),
                      ),
                      Center(
                        child: Container(
                          width: 58,
                          height: 58,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.92),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(color: Colors.black.withValues(alpha: 0.28), blurRadius: 18, offset: const Offset(0, 4)),
                            ],
                          ),
                          child: Icon(Icons.play_arrow_rounded, size: 36, color: accent),
                        ),
                      ),
                      Positioned(
                        left: 10,
                        top: 10,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.45),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            video.kind.label,
                            style: const TextStyle(fontSize: 11, height: 1.2, color: Colors.white, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                      if (video.videoId != null)
                        Positioned(
                          right: 10,
                          bottom: 10,
                          child: Text(
                            video.videoId!,
                            style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.8)),
                          ),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 11),
                  child: Row(
                    children: [
                      Icon(Icons.movie_outlined, size: 17, color: scheme.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title ?? '视频演示',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 14, height: 1.3, fontWeight: FontWeight.w600, color: scheme.onSurface),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              video.subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 11.5, height: 1.3, color: scheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right_rounded, size: 18, color: scheme.outline),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static Color _accent(VideoKind kind) {
    switch (kind) {
      case VideoKind.bilibili:
        return const Color(0xFFFB7299);
      case VideoKind.youtube:
        return const Color(0xFFFF0033);
      case VideoKind.douyin:
        return const Color(0xFF25F4EE);
      case VideoKind.kuaishou:
        return const Color(0xFFFF7A00);
      case VideoKind.ixigua:
        return const Color(0xFFFF4B4B);
      case VideoKind.tencent:
        return const Color(0xFF2AA3FF);
      case VideoKind.youku:
        return const Color(0xFF1AA9E0);
      case VideoKind.acfun:
        return const Color(0xFFFD4C5D);
      case VideoKind.weibo:
        return const Color(0xFFE6162D);
      case VideoKind.direct:
      case VideoKind.other:
        return const Color(0xFF5B8DEF);
    }
  }
}
