import 'package:flutter/material.dart';

import '../../data/models.dart';
import 'thread_glass.dart';
import 'user_avatar.dart';

/// 用户搜索结果里的一行。
///
/// 和帖子卡片同一套玻璃底：淡填充 + 发丝描边，头像用站点头像，
/// 右侧箭头提示可以进主页。
class UserHitCard extends StatelessWidget {
  const UserHitCard({
    super.key,
    required this.user,
    this.blocked = false,
    this.onTap,
  });

  final UserProfile user;

  /// 是否在本机屏蔽名单里。
  final bool blocked;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final detail = [
      if (user.group.isNotEmpty) user.group,
      if (user.credits.isNotEmpty) '积分 ${user.credits}',
    ].join(' · ');
    return Material(
      color: Colors.transparent,
      child: Ink(
        decoration: BoxDecoration(
          color: ThreadGlass.fill(context, lightAlpha: 0.52, darkAlpha: 0.10),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: ThreadGlass.borderColor(context), width: 0.8),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 11, 10, 11),
            child: Row(
              children: [
                UserAvatar(url: user.avatar, name: user.username, size: 44),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              user.username,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          if (blocked) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: scheme.error.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(5),
                              ),
                              child: Text(
                                '已屏蔽',
                                style: TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w700,
                                  color: scheme.error,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (detail.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          detail,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, size: 18, color: scheme.outline),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
