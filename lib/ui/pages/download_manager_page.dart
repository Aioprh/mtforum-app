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

  @override
  Widget build(BuildContext context) {
    final records = DownloadManager.instance.records;
    return Scaffold(
      appBar: AppBar(title: const Text('下载管理'), actions: [
        IconButton(tooltip: '刷新', onPressed: () async { await DownloadManager.instance.load(); if (mounted) setState(() {}); }, icon: const Icon(Icons.refresh_rounded)),
      ]),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : records.isEmpty
              ? const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.download_for_offline_outlined, size: 48), SizedBox(height: 12), Text('暂无下载记录')]))
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: records.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final record = records[index];
                    final file = File(record.path);
                    return Card(child: ListTile(
                      leading: const Icon(Icons.insert_drive_file_outlined),
                      title: Text(record.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: FutureBuilder<bool>(
                        future: file.exists(),
                        builder: (context, snapshot) => Text(
                          snapshot.data == true ? '${_size(file.lengthSync())} · 已保存到应用私有目录' : '文件不存在或已被删除',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      onTap: () async {
                        final uri = Uri.tryParse(record.url);
                        if (uri != null) await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
                      },
                      trailing: PopupMenuButton<String>(
                        onSelected: (value) async {
                          if (value == 'copy') {
                            await Clipboard.setData(ClipboardData(text: record.path));
                            if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('文件路径已复制')));
                          } else if (value == 'delete') {
                            final yes = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
                              title: const Text('删除下载记录'),
                              content: const Text('同时删除本地文件？'),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
                                FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('删除')),
                              ],
                            ));
                            if (yes == true) {
                              await DownloadManager.instance.remove(record, deleteFile: true);
                              if (mounted) setState(() {});
                            }
                          }
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'copy', child: Text('复制文件路径')),
                          PopupMenuItem(value: 'delete', child: Text('删除记录/文件')),
                        ],
                      ),
                    ));
                  },
                ),
    );
  }
}
