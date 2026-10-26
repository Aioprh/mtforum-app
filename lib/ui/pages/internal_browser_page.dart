import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

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
  InAppWebViewController? _controller;
  String _url = '';
  String _title = '正在加载…';
  int _progress = 0;
  bool _loading = true;
  final Set<String> _activeDownloads = <String>{};

  @override
  void initState() {
    super.initState();
    _url = widget.url;
    _title = widget.title;
  }

  Future<void> _openExternal() async {
    final uri = Uri.tryParse(_url);
    if (uri == null || !{'http', 'https'}.contains(uri.scheme)) return;
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

  Future<void> _downloadCurrentPage() async {
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
    if (ok == true) {
      await _startDownload(_url, suggestedFilename: uri.pathSegments.isEmpty ? null : uri.pathSegments.last);
    }
  }

  /// WebView 页面触发文件下载时会走这里，统一接入应用下载管理器。
  Future<void> _startDownload(
    String rawUrl, {
    String? suggestedFilename,
    String? userAgent,
    String? contentDisposition,
  }) async {
    final uri = Uri.tryParse(rawUrl);
    if (uri == null || !{'http', 'https'}.contains(uri.scheme)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('不支持此下载链接')));
      }
      return;
    }
    if (!_activeDownloads.add(rawUrl)) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('该文件已在下载中')));
      return;
    }
    try {
      final cookies = await CookieManager.instance().getCookies(url: WebUri(rawUrl));
      final webCookieHeader = cookies.map((cookie) => '${cookie.name}=${cookie.value}').join('; ');
      final record = await DownloadManager.instance.download(
        rawUrl,
        suggestedFilename: suggestedFilename,
        headers: {
          'User-Agent': (userAgent?.trim().isNotEmpty ?? false) ? userAgent!.trim() : AppConfig.userAgent,
          'Referer': _url,
          if (webCookieHeader.isNotEmpty) 'Cookie': webCookieHeader,
          if (webCookieHeader.isEmpty && HttpSession.instance.cookieHeader.isNotEmpty && uri.host == Uri.parse(AppConfig.base).host)
            'Cookie': HttpSession.instance.cookieHeader,
        },
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('下载完成：${record.name}')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('下载失败：$e')));
      }
    } finally {
      _activeDownloads.remove(rawUrl);
    }
  }

  Future<void> _back() async {
    final controller = _controller;
    if (controller != null && await controller.canGoBack()) {
      await controller.goBack();
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
          IconButton(tooltip: '下载当前页面', onPressed: _downloadCurrentPage, icon: const Icon(Icons.download_rounded)),
          IconButton(tooltip: '下载管理', onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DownloadManagerPage())), icon: const Icon(Icons.download_for_offline_outlined)),
          IconButton(tooltip: '外部浏览器打开', onPressed: _openExternal, icon: const Icon(Icons.open_in_browser_rounded)),
          PopupMenuButton<String>(
            onSelected: (value) async {
              final messenger = ScaffoldMessenger.of(context);
              if (value == 'refresh') await _controller?.reload();
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
        Expanded(
          child: InAppWebView(
            initialUrlRequest: URLRequest(
              url: WebUri(widget.url),
              headers: {
                'User-Agent': AppConfig.userAgent,
                if (HttpSession.instance.cookieHeader.isNotEmpty)
                  'Cookie': HttpSession.instance.cookieHeader,
              },
            ),
            initialSettings: InAppWebViewSettings(
              javaScriptEnabled: true,
              domStorageEnabled: true,
              useShouldOverrideUrlLoading: true,
              allowsBackForwardNavigationGestures: true,
              thirdPartyCookiesEnabled: true,
              supportMultipleWindows: false,
            ),
            onWebViewCreated: (controller) => _controller = controller,
            onProgressChanged: (controller, progress) {
              if (mounted) {
                setState(() {
                  _progress = progress;
                  _loading = progress < 100;
                });
              }
            },
            onLoadStart: (controller, url) {
              if (mounted) {
                setState(() {
                  _url = url?.toString() ?? _url;
                  _loading = true;
                  _progress = 0;
                });
              }
            },
            onLoadStop: (controller, url) async {
              final title = await controller.getTitle();
              if (mounted) {
                setState(() {
                  _url = url?.toString() ?? _url;
                  _title = (title?.trim().isNotEmpty ?? false) ? title!.trim() : widget.title;
                  _loading = false;
                  _progress = 100;
                });
              }
            },
            onDownloadStartRequest: (controller, request) {
              _startDownload(
                request.url.toString(),
                suggestedFilename: request.suggestedFilename,
                userAgent: request.userAgent,
                contentDisposition: request.contentDisposition,
              );
            },
            shouldOverrideUrlLoading: (controller, action) async {
              final uri = Uri.tryParse(action.request.url?.toString() ?? '');
              if (uri == null) return NavigationActionPolicy.CANCEL;
              if (uri.scheme == 'http' || uri.scheme == 'https' || uri.scheme == 'about' || uri.scheme == 'data') {
                return NavigationActionPolicy.ALLOW;
              }
              return NavigationActionPolicy.CANCEL;
            },
          ),
        ),
      ]),
    );
  }
}
