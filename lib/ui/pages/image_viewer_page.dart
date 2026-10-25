import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_config.dart';
import '../../core/http_session.dart';
import '../../core/native_bridge.dart';

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
  bool _saving = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _saveToGallery() async {
    if (_saving) return;
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final url = widget.images[_index];
      final client = HttpClient();
      try {
        final request = await client.getUrl(Uri.parse(url));
        request.headers.set('Referer', AppConfig.base);
        request.headers.set('User-Agent', AppConfig.userAgent);
        final cookie = HttpSession.instance.cookieHeader;
        if (cookie.isNotEmpty) request.headers.set('Cookie', cookie);
        final response = await request.close();
        if (response.statusCode != HttpStatus.ok) {
          throw Exception('图片下载失败（${response.statusCode}）');
        }
        final builder = BytesBuilder(copy: false);
        await for (final chunk in response) {
          builder.add(chunk);
        }
        final bytes = builder.takeBytes();
        final ok = await NativeBridge.saveImage(
          bytes,
          name: 'mt_forum_${DateTime.now().millisecondsSinceEpoch}.jpg',
        );
        messenger.showSnackBar(SnackBar(content: Text(ok ? '已保存到相册' : '保存失败，请检查存储权限')));
      } finally {
        client.close();
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
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
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  TextButton.icon(
                    onPressed: _saving ? null : _saveToGallery,
                    icon: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70),
                          )
                        : const Icon(Icons.download_rounded, color: Colors.white70),
                    label: const Text('保存到相册', style: TextStyle(color: Colors.white70)),
                  ),
                  const SizedBox(width: 12),
                  TextButton.icon(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: widget.images[_index]));
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('图片链接已复制')));
                    },
                    icon: const Icon(Icons.link_rounded, color: Colors.white70),
                    label: const Text('复制图片链接', style: TextStyle(color: Colors.white70)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
