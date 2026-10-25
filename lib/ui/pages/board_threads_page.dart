import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../../state/app_state.dart';
import '../widgets/thread_feed.dart';
import 'compose_page.dart';

/// 单个版块的主题列表。
class BoardThreadsPage extends StatefulWidget {
  const BoardThreadsPage({super.key, required this.fid, required this.name});

  final int fid;
  final String name;

  @override
  State<BoardThreadsPage> createState() => _BoardThreadsPageState();
}

class _BoardThreadsPageState extends State<BoardThreadsPage> {
  Future<List<ThreadSummary>> _loader(int page) =>
      AppState.instance.repo.fetchBoardThreads(widget.fid, page: page);

  Future<void> _openCompose() async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ComposePage(initialFid: widget.fid, initialBoardName: widget.name),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: '发帖',
            onPressed: _openCompose,
            icon: const Icon(Icons.edit_rounded),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: ThreadFeed(
          loader: _loader,
          emptyText: '该版块暂时还没有主题',
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 24),
          header: _header(context),
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 0, 2, 12),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 14,
            decoration: BoxDecoration(color: scheme.primary, borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(width: 8),
          Text(
            '${widget.name} · 最新主题',
            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
