import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/app_config.dart';
import '../../core/http_session.dart';

/// 带站点 Referer / Cookie 的网络图片，未加载完成时显示柔和占位。
class SmartImage extends StatelessWidget {
  const SmartImage({
    super.key,
    required this.url,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.radius = BorderRadius.zero,
    this.cacheWidth,
  });

  final String url;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius radius;
  final int? cacheWidth;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final placeholder = Container(
      width: width,
      height: height,
      color: scheme.surfaceContainerHighest,
      alignment: Alignment.center,
      child: Icon(Icons.image_outlined, color: scheme.onSurfaceVariant.withValues(alpha: 0.5), size: 22),
    );

    if (url.trim().isEmpty) {
      return ClipRRect(borderRadius: radius, child: placeholder);
    }

    final parsed = Uri.tryParse(url);
    if (parsed != null && parsed.scheme == 'file') {
      return ClipRRect(
        borderRadius: radius,
        child: Image.file(
          File(parsed.toFilePath()),
          width: width,
          height: height,
          fit: fit,
          cacheWidth: cacheWidth,
          errorBuilder: (_, __, ___) => placeholder,
        ),
      );
    }

    final cookie = HttpSession.instance.cookieHeader;
    return ClipRRect(
      borderRadius: radius,
      child: Image.network(
        url,
        width: width,
        height: height,
        fit: fit,
        cacheWidth: cacheWidth,
        gaplessPlayback: true,
        headers: {
          'Referer': AppConfig.base,
          'User-Agent': AppConfig.userAgent,
          if (cookie.isNotEmpty) 'Cookie': cookie,
        },
        errorBuilder: (_, __, ___) => placeholder,
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          final total = progress.expectedTotalBytes;
          final value = total == null ? null : progress.cumulativeBytesLoaded / total;
          return Stack(
            fit: StackFit.expand,
            children: [
              placeholder,
              if (value != null)
                Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2, value: value, color: scheme.primary),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
