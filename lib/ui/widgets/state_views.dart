import 'package:flutter/material.dart';

class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.message, this.onRetry, this.compact = false});

  final String message;
  final VoidCallback? onRetry;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 28, vertical: compact ? 16 : 60),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_rounded, size: compact ? 34 : 54, color: scheme.outline),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13.5, height: 1.5, color: scheme.onSurfaceVariant),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('重新加载'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class EmptyView extends StatelessWidget {
  const EmptyView({super.key, required this.text, this.icon = Icons.forum_outlined});

  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 50),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 46, color: scheme.outline.withValues(alpha: 0.6)),
            const SizedBox(height: 12),
            Text(text, textAlign: TextAlign.center, style: TextStyle(fontSize: 13.5, color: scheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}

/// 首屏骨架屏，避免空白等待。
class FeedSkeleton extends StatefulWidget {
  const FeedSkeleton({super.key, this.count = 5});

  final int count;

  @override
  State<FeedSkeleton> createState() => _FeedSkeletonState();
}

class _FeedSkeletonState extends State<FeedSkeleton> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final base = scheme.surfaceContainerHighest.withValues(alpha: 0.45);
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final opacity = 0.45 + _controller.value * 0.35;
        Widget bar(double width, double height, {double radius = 6}) => Container(
              width: width,
              height: height,
              decoration: BoxDecoration(
                color: base.withValues(alpha: opacity),
                borderRadius: BorderRadius.circular(radius),
              ),
            );
        return ListView.separated(
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
          itemCount: widget.count,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (_, __) => Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.35)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    bar(32, 32, radius: 16),
                    const SizedBox(width: 10),
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [bar(80, 11), const SizedBox(height: 6), bar(50, 9)]),
                  ],
                ),
                const SizedBox(height: 14),
                bar(double.infinity, 14),
                const SizedBox(height: 8),
                bar(double.infinity, 14),
                const SizedBox(height: 12),
                bar(210, 10),
              ],
            ),
          ),
        );
      },
    );
  }
}
