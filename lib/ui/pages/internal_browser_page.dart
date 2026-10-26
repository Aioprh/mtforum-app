import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/app_config.dart';
import '../../core/http_session.dart';
import '../../services/download_manager.dart';
import 'download_manager_page.dart';

class InternalBrowserPage extends StatefulWidget {
  const InternalBrowserPage({super.key, required this.url, this.title = '内部浏览器'});
  final String url;
  final String title;

  @override
  State<InternalBrowserPage> createState() => _InternalBrowserPageState();
}

class _InternalBrowserPageState extends State<InternalBrowserPage> {
  late final WebViewController _controller;
  String _url = '';
  String _title = '正在加载…';
  int _progress = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _url = widget.url;
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(ThemeData().scaffoldBackgroundColor)
      ..setNavigationDelegate(NavigationDelegate(
        onProgress: (value) {
          if (mounted) setState(() { _progress = value; _loading = value < 100; });
        },
        onPageStarted: (url) {
          if (mounted) setState(() { _url = url; _loading = true; _progress = 0; });
        },
        onPageFinished: (url) async {
          final title = await _controller.getTitle();
          if (mounted) setState(() { _url = url; _title = (title?.trim().isNotEmpty ?? false) ? title!.trim() : '内部浏览器'; _loading = false; _progress = 100; });
        },
        onNavigationRequest: (request) {
          final uri = Uri.tryParse(request.url);
          if (uri == null) return NavigationDecision.prevent;
          if (uri.scheme == 'http' || uri.scheme == 'https' || uri.scheme == 'about' || uri.scheme == 'data') {
            return NavigationDecision.navigate;
          }
          return NavigationDecision.prevent;
        },
      ))
      ..loadRequest(Uri.parse(widget.url), headers: {
        'User-Agent': AppConfig.userAgent,
        if (HttpSession.instance.cookieHeader.isNotEmpty) 'Cookie': HttpSession.instance.cookieHeader,
      });
  }

  Future<void> _openExternal() async {
    final uri = Uri.tryParse(_url);
    if (uri == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('打开外部浏览器'),
        content: const Text('将离开 MT论坛，交由系统浏览器打开当前链接。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('打开')),
        ],
      ),
    );
    if (confirmed == true) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _download() async {
    final uri = Uri.tryParse(_url);
    if (uri == null || !{'http', 'https'}.contains(uri.scheme)) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('下载文件'),
        content: Text('下载当前地址的内容？\n${uri.pathSegments.isEmpty ? _title : uri.pathSegments.last}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('开始下载')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      final record = await DownloadManager.instance.download(_url);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('下载完成：${record.name}')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('下载失败：$e')));
    }
  }

  Future<void> _back() async {
    if (await _controller.canGoBack()) {
      await _controller.goBack();
    } else if (mounted) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(onPressed: _back, icon: const Icon(Icons.arrow_back_rounded)),
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15)),
          Text(_url, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.labelSmall),
        ]),
        actions: [
          IconButton(tooltip: '下载当前页面', onPressed: _download, icon: const Icon(Icons.download_rounded)),
          IconButton(tooltip: '下载管理', onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DownloadManagerPage())), icon: const Icon(Icons.download_for_offline_outlined)),
          IconButton(tooltip: '外部浏览器打开', onPressed: _openExternal, icon: const Icon(Icons.open_in_browser_rounded)),
          PopupMenuButton<String>(
            onSelected: (value) async {
              final messenger = ScaffoldMessenger.of(context);
              if (value == 'refresh') await _controller.reload();
              if (value == 'copy') {
                await Clipboard.setData(ClipboardData(text: _url));
                messenger.showSnackBar(const SnackBar(content: Text('链接已复制')));
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'refresh', child: Text('刷新')),
              PopupMenuItem(value: 'copy', child: Text('复制链接')),
            ],
          ),
        ],
      ),
      body: Column(children: [
        if (_loading) LinearProgressIndicator(value: _progress == 0 ? null : _progress / 100, minHeight: 2),
        Expanded(child: WebViewWidget(controller: _controller)),
      ]),
    );
  }
}
