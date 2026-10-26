import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/download_manager.dart';

class DownloadManagerPage extends StatefulWidget {
  const DownloadManagerPage({super.key});

  @override
  State<DownloadManagerPage> createState() => _DownloadManagerPageState();
}

class _DownloadManagerPageState extends State<DownloadManagerPage> {
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    DownloadManager.instance.load().whenComplete(() {
      if (mounted) setState(() => _loading = false);
    });
  }

  String _size(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String _statusText(DownloadRecord record) {
    switch (record.status) {
      case 'downloading':
        final total = record.totalBytes;
        if (total > 0) {
          final percent = (record.receivedBytes * 100 / total).clamp(0, 100).round();
          return '下载中 $percent% · ${_size(record.receivedBytes)} / ${_size(total)}';
        }
        return '下载中 · 已接收 ${_size(record.receivedBytes)}';
      case 'completed':
        return '已完成 · ${_size(record.receivedBytes)}';
      case 'failed':
        return '下载失败：${record.error}';
      case 'interrupted':
        return record.error.isEmpty ? '下载中断' : record.error;
      default:
        return record.status;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('下载管理'),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: () async {
              await DownloadManager.instance.load();
              if (mounted) setState(() {});
            },
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: DownloadManager.instance,
        builder: (context, _) {
          final records = DownloadManager.instance.records;
          if (_loading) return const Center(child: CircularProgressIndicator());
          if (records.isEmpty) {
            return const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.download_for_offline_outlined, size: 48),
                  SizedBox(height: 12),
                  Text('暂无下载记录'),
                  SizedBox(height: 6),
                  Text('在内部浏览器中下载的文件会显示在这里', style: TextStyle(fontSize: 12)),
                ],
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: records.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final record = records[index];
              final file = File(record.path);
              final downloading = record.status == 'downloading';
              return Card(
                child: ListTile(
                  leading: Icon(
                    downloading ? Icons.downloading_rounded : record.status == 'completed'
                        ? Icons.insert_drive_file_outlined
                        : Icons.error_outline_rounded,
                  ),
                  title: Text(record.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_statusText(record), maxLines: 2, overflow: TextOverflow.ellipsis),
                      if (downloading && record.totalBytes > 0) ...[
                        const SizedBox(height: 6),
                        LinearProgressIndicator(
                          value: (record.receivedBytes / record.totalBytes).clamp(0.0, 1.0),
                        ),
                      ],
                      if (record.status == 'completed')
                        FutureBuilder<bool>(
                          future: file.exists(),
                          builder: (context, snapshot) => Text(
                            snapshot.data == true ? '已保存到应用私有目录' : '文件不存在或已被删除',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                    ],
                  ),
                  onTap: () async {
                    if (record.status == 'completed' && await file.exists()) {
                      final uri = Uri.tryParse(record.url);
                      if (uri != null) await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
                    } else if (record.status != 'downloading') {
                      await Clipboard.setData(ClipboardData(text: record.url));
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('下载链接已复制，可重新打开后下载')));
                      }
                    }
                  },
                  trailing: PopupMenuButton<String>(
                    onSelected: (value) async {
                      final messenger = ScaffoldMessenger.of(context);
                      if (value == 'copy') {
                        await Clipboard.setData(ClipboardData(text: record.path));
                        messenger.showSnackBar(const SnackBar(content: Text('文件路径已复制')));
                      } else if (value == 'delete') {
                        final yes = await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('删除下载记录'),
                            content: const Text('同时删除本地文件？'),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
                              FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('删除')),
                            ],
                          ),
                        );
                        if (yes == true) {
                          await DownloadManager.instance.remove(record, deleteFile: true);
                        }
                      } else if (value == 'open') {
                        final uri = Uri.tryParse(record.url);
                        if (uri != null) await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'open', child: Text('重新打开链接')),
                      PopupMenuItem(value: 'copy', child: Text('复制文件路径')),
                      PopupMenuItem(value: 'delete', child: Text('删除记录/文件')),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
