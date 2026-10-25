import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_config.dart';
import '../../core/http_session.dart';

class ImageViewerPage extends StatefulWidget {
  const ImageViewerPage({super.key, required this.images, this.initialIndex = 0});

  final List<String> images;
  final int initialIndex;

  @override
  State<ImageViewerPage> createState() => _ImageViewerPageState();
}

class _ImageViewerPageState extends State<ImageViewerPage> {
  late final PageController _controller = PageController(initialPage: widget.initialIndex);
  late int _index = widget.initialIndex;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cookie = HttpSession.instance.cookieHeader;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(statusBarColor: Colors.transparent, statusBarIconBrightness: Brightness.dark),
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            PageView.builder(
              controller: _controller,
              itemCount: widget.images.length,
              onPageChanged: (index) => setState(() => _index = index),
              itemBuilder: (context, index) => InteractiveViewer(
                minScale: 0.8,
                maxScale: 4,
                child: Center(
                  child: Image.network(
                    widget.images[index],
                    headers: {
                      'Referer': AppConfig.base,
                      'User-Agent': AppConfig.userAgent,
                      if (cookie.isNotEmpty) 'Cookie': cookie,
                    },
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined, color: Colors.white38, size: 46),
                    loadingBuilder: (context, child, progress) => progress == null
                        ? child
                        : const Center(child: CircularProgressIndicator(color: Colors.white70, strokeWidth: 2)),
                  ),
                ),
              ),
            ),
            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              left: 8,
              right: 8,
              child: Row(
                children: [
                  IconButton.filledTonal(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                    style: IconButton.styleFrom(backgroundColor: Colors.black45, foregroundColor: Colors.white),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(20)),
                    child: Text(
                      '${_index + 1} / ${widget.images.length}',
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: MediaQuery.of(context).padding.bottom + 18,
              child: Center(
                child: TextButton.icon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: widget.images[_index]));
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('图片链接已复制')));
                  },
                  icon: const Icon(Icons.link_rounded, color: Colors.white70),
                  label: const Text('复制图片链接', style: TextStyle(color: Colors.white70)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
