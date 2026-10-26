import 'package:flutter/material.dart';

import '../../core/http_session.dart';
import '../../data/models.dart';
import '../../state/app_state.dart';
import '../widgets/smart_image.dart';
import '../widgets/state_views.dart';

/// 道具中心：商店 / 我的道具 / 记录，全部原生实现。
class MagicPage extends StatelessWidget {
  const MagicPage({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('道具中心'),
          bottom: const TabBar(
            tabs: [
              Tab(text: '商店'),
              Tab(text: '我的道具'),
              Tab(text: '记录'),
            ],
          ),
        ),
        body: const SafeArea(
          top: false,
          child: TabBarView(
            children: [
              _MagicShopTab(),
              _MagicBoxTab(),
              _MagicLogTab(),
            ],
          ),
        ),
      ),
    );
  }
}

String _errorText(Object error, String fallback) =>
    error is SiteException ? error.message : fallback;

Widget _sectionTitle(ColorScheme scheme, String title, [String trailing = '']) {
  return Row(
    children: [
      Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
      if (trailing.isNotEmpty) ...[
        const SizedBox(width: 8),
        Text(trailing, style: TextStyle(fontSize: 11, color: scheme.outline)),
      ],
    ],
  );
}

Widget _card(ColorScheme scheme, Widget child) {
  return Container(
    padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
    decoration: BoxDecoration(
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
      borderRadius: BorderRadius.circular(14),
    ),
    child: child,
  );
}

// ---------------------------------------------------------------------------
// 商店
// ---------------------------------------------------------------------------

class _MagicShopTab extends StatefulWidget {
  const _MagicShopTab();

  @override
  State<_MagicShopTab> createState() => _MagicShopTabState();
}

class _MagicShopTabState extends State<_MagicShopTab> with AutomaticKeepAliveClientMixin {
  List<MagicItem> _items = [];
  bool _loading = true;
  bool _busy = false;
  bool _hot = false;
  String? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await AppState.instance.repo.fetchMagicShop(hot: _hot);
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _errorText(e, '加载失败，请稍后重试');
      });
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _buy(MagicItem item) async {
    final request = await showDialog<_MagicActionRequest>(
      context: context,
      builder: (_) => _MagicActionDialog(
        title: '购买 ${item.name}',
        confirmText: '确认购买',
        description: item.priceText.isEmpty ? '' : '价格：${item.priceText}',
      ),
    );
    if (request == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final message = await AppState.instance.repo.buyMagic(mid: item.mid, num: request.num);
      _toast(message);
      await _load();
    } catch (e) {
      _toast(_errorText(e, '购买失败，请稍后重试'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _gift(MagicItem item) async {
    final request = await showDialog<_MagicActionRequest>(
      context: context,
      builder: (_) => _MagicActionDialog(
        title: '赠送 ${item.name}',
        confirmText: '确认赠送',
        needUser: true,
        needMessage: true,
        description: item.priceText.isEmpty ? '' : '购买后直接赠送给对方，价格：${item.priceText}',
      ),
    );
    if (request == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final message = await AppState.instance.repo.giftMagicFromShop(
        mid: item.mid,
        username: request.username,
        num: request.num,
        message: request.message,
      );
      _toast(message);
      await _load();
    } catch (e) {
      _toast(_errorText(e, '赠送失败，请稍后重试'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final scheme = Theme.of(context).colorScheme;
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return ErrorView(message: _error!, onRetry: _load);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
        children: [
          Row(
            children: [
              _sectionTitle(scheme, '道具商店', '${_items.length} 件'),
              const Spacer(),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('全部')),
                  ButtonSegment(value: true, label: Text('热销')),
                ],
                selected: {_hot},
                showSelectedIcon: false,
                style: const ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onSelectionChanged: (value) {
                  setState(() => _hot = value.first);
                  _load();
                },
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (_items.isEmpty)
            const EmptyView(text: '道具商店暂未开放', icon: Icons.auto_fix_high_outlined)
          else
            for (final item in _items) ...[
              _card(
                scheme,
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SmartImage(
                          url: item.image,
                          width: 44,
                          height: 44,
                          radius: BorderRadius.circular(10),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.name,
                                style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
                              ),
                              if (item.priceText.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  item.priceText,
                                  style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
                                ),
                              ],
                              if (item.saleVolume.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(
                                  item.saleVolume,
                                  style: TextStyle(fontSize: 10.5, color: scheme.outline),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (item.description.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        item.description,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11.5, height: 1.45, color: scheme.onSurfaceVariant),
                      ),
                    ],
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (item.soldOut)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: Text(
                              '已售完',
                              style: TextStyle(fontSize: 11.5, color: scheme.outline),
                            ),
                          ),
                        if (item.canGive)
                          OutlinedButton(
                            onPressed: _busy || item.mid.isEmpty ? null : () => _gift(item),
                            child: const Text('赠送'),
                          ),
                        if (item.canGive && !item.soldOut) const SizedBox(width: 8),
                        if (!item.soldOut)
                          FilledButton(
                            onPressed: _busy || item.mid.isEmpty ? null : () => _buy(item),
                            child: const Text('购买'),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 我的道具
// ---------------------------------------------------------------------------

class _MagicBoxTab extends StatefulWidget {
  const _MagicBoxTab();

  @override
  State<_MagicBoxTab> createState() => _MagicBoxTabState();
}

class _MagicBoxTabState extends State<_MagicBoxTab> with AutomaticKeepAliveClientMixin {
  MagicBox _box = const MagicBox();
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final box = await AppState.instance.repo.fetchMagicBox();
      if (!mounted) return;
      setState(() {
        _box = box;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _errorText(e, '加载失败，请稍后重试');
      });
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _use(MyMagic item) async {
    final navigator = Navigator.of(context, rootNavigator: true);
    var loading = true;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _BusyDialog(text: '正在读取道具信息…'),
    );
    try {
      final form = await AppState.instance.repo.fetchMagicUseForm(item.id);
      if (loading) {
        loading = false;
        navigator.pop();
      }
      if (!mounted) return;
      final values = await showDialog<Map<String, String>>(
        context: context,
        builder: (_) => _MagicUseDialog(title: '使用 ${item.name}', form: form),
      );
      if (values == null || !mounted) return;
      setState(() => _busy = true);
      final message = await AppState.instance.repo.useMagic(
        magicId: item.id,
        form: form,
        values: values,
      );
      _toast(message);
      await _load();
    } catch (e) {
      if (loading) {
        loading = false;
        navigator.pop();
      }
      _toast(_errorText(e, '使用失败，请稍后重试'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _give(MyMagic item) async {
    final request = await showDialog<_MagicActionRequest>(
      context: context,
      builder: (_) => _MagicActionDialog(
        title: '赠送 ${item.name}',
        confirmText: '确认赠送',
        needUser: true,
        needMessage: true,
        maxNum: item.num,
      ),
    );
    if (request == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final message = await AppState.instance.repo.giveMagic(
        magicId: item.id,
        username: request.username,
        num: request.num,
        message: request.message,
      );
      _toast(message);
      await _load();
    } catch (e) {
      _toast(_errorText(e, '赠送失败，请稍后重试'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sell(MyMagic item) async {
    final request = await showDialog<_MagicActionRequest>(
      context: context,
      builder: (_) => _MagicActionDialog(
        title: '出售 ${item.name}',
        confirmText: '确认出售',
        maxNum: item.num,
        description: '出售后按站点回收价折算积分。',
      ),
    );
    if (request == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final message = await AppState.instance.repo.sellMagic(magicId: item.id, num: request.num);
      _toast(message);
      await _load();
    } catch (e) {
      _toast(_errorText(e, '出售失败，请稍后重试'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _drop(MyMagic item) async {
    final request = await showDialog<_MagicActionRequest>(
      context: context,
      builder: (_) => _MagicActionDialog(
        title: '丢弃 ${item.name}',
        confirmText: '确认丢弃',
        maxNum: item.num,
        description: '丢弃后无法找回。',
      ),
    );
    if (request == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final message = await AppState.instance.repo.dropMagic(magicId: item.id, num: request.num);
      _toast(message);
      await _load();
    } catch (e) {
      _toast(_errorText(e, '丢弃失败，请稍后重试'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final scheme = Theme.of(context).colorScheme;
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return ErrorView(message: _error!, onRetry: _load);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
        children: [
          _sectionTitle(scheme, '我的道具', '${_box.items.length} 种'),
          if (_box.capacity.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              _box.capacity,
              style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
            ),
          ],
          const SizedBox(height: 10),
          if (_box.items.isEmpty)
            const EmptyView(text: '你还没有道具', icon: Icons.inventory_2_outlined)
          else
            for (final item in _box.items) ...[
              _card(
                scheme,
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SmartImage(
                          url: item.image,
                          width: 44,
                          height: 44,
                          radius: BorderRadius.circular(10),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.name,
                                style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                item.weight.isEmpty
                                    ? '数量：${item.num}'
                                    : '数量：${item.num} · 重量：${item.weight}',
                                style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (item.description.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        item.description,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11.5, height: 1.45, color: scheme.onSurfaceVariant),
                      ),
                    ],
                    const SizedBox(height: 10),
                    Wrap(
                      alignment: WrapAlignment.end,
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (item.canUse)
                          FilledButton(
                            onPressed: _busy ? null : () => _use(item),
                            child: const Text('使用'),
                          ),
                        if (item.canGive)
                          OutlinedButton(
                            onPressed: _busy ? null : () => _give(item),
                            child: const Text('赠送'),
                          ),
                        if (item.canSell)
                          OutlinedButton(
                            onPressed: _busy ? null : () => _sell(item),
                            child: const Text('出售'),
                          ),
                        if (item.canDrop)
                          OutlinedButton(
                            onPressed: _busy ? null : () => _drop(item),
                            child: const Text('丢弃'),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 记录
// ---------------------------------------------------------------------------

class _MagicLogTab extends StatefulWidget {
  const _MagicLogTab();

  @override
  State<_MagicLogTab> createState() => _MagicLogTabState();
}

class _MagicLogTabState extends State<_MagicLogTab> with AutomaticKeepAliveClientMixin {
  static const List<(String, String)> _types = [
    ('uselog', '使用'),
    ('buylog', '购买'),
    ('givelog', '赠送'),
    ('receivelog', '收到'),
  ];

  List<MagicLogEntry> _items = [];
  String _type = 'uselog';
  int _page = 1;
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  String? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await AppState.instance.repo.fetchMagicLogs(_type, page: 1);
      if (!mounted) return;
      setState(() {
        _items = items;
        _page = 1;
        _hasMore = items.length >= 20;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _errorText(e, '加载失败，请稍后重试');
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final items = await AppState.instance.repo.fetchMagicLogs(_type, page: _page + 1);
      if (!mounted) return;
      setState(() {
        _page += 1;
        _items = [..._items, ...items];
        _hasMore = items.length >= 20;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_errorText(e, '加载更多失败，请稍后重试'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
          child: Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SegmentedButton<String>(
                    segments: [
                      for (final entry in _types)
                        ButtonSegment(value: entry.$1, label: Text(entry.$2)),
                    ],
                    selected: {_type},
                    showSelectedIcon: false,
                    style: const ButtonStyle(
                      visualDensity: VisualDensity.compact,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onSelectionChanged: (value) {
                      setState(() => _type = value.first);
                      _load();
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? ErrorView(message: _error!, onRetry: _load)
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                        padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
                        children: [
                          _sectionTitle(scheme, '道具记录', '${_items.length} 条'),
                          const SizedBox(height: 10),
                          if (_items.isEmpty)
                            const EmptyView(text: '暂无相关记录', icon: Icons.history_rounded)
                          else ...[
                            for (final item in _items) ...[
                              _card(
                                scheme,
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Expanded(
                                          child: Text(
                                            item.title,
                                            style: const TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ),
                                        if (item.time.isNotEmpty) ...[
                                          const SizedBox(width: 8),
                                          Text(
                                            item.time,
                                            style: TextStyle(fontSize: 10.5, color: scheme.outline),
                                          ),
                                        ],
                                      ],
                                    ),
                                    if (item.detail.isNotEmpty) ...[
                                      const SizedBox(height: 5),
                                      Text(
                                        item.detail,
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          height: 1.4,
                                          color: scheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              const SizedBox(height: 8),
                            ],
                            if (_loadingMore)
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 12),
                                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                              )
                            else if (_hasMore)
                              Center(
                                child: TextButton.icon(
                                  onPressed: _loadMore,
                                  icon: const Icon(Icons.expand_more_rounded, size: 18),
                                  label: const Text('加载更多'),
                                ),
                              ),
                          ],
                        ],
                      ),
                    ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 对话框
// ---------------------------------------------------------------------------

class _MagicActionRequest {
  const _MagicActionRequest({required this.num, this.username = '', this.message = ''});

  final int num;
  final String username;
  final String message;
}

class _MagicActionDialog extends StatefulWidget {
  const _MagicActionDialog({
    required this.title,
    required this.confirmText,
    this.description = '',
    this.needUser = false,
    this.needMessage = false,
    this.maxNum = 99,
  });

  final String title;
  final String confirmText;
  final String description;
  final bool needUser;
  final bool needMessage;
  final int maxNum;

  @override
  State<_MagicActionDialog> createState() => _MagicActionDialogState();
}

class _MagicActionDialogState extends State<_MagicActionDialog> {
  late int _num = _clampNum(1);

  int _clampNum(int value) {
    final max = widget.maxNum < 1 ? 1 : widget.maxNum;
    if (value < 1) return 1;
    return value > max ? max : value;
  }
  final TextEditingController _userController = TextEditingController();
  final TextEditingController _messageController = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _userController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  void _submit() {
    if (widget.needUser && _userController.text.trim().isEmpty) {
      setState(() => _error = '请输入接收人的用户名');
      return;
    }
    Navigator.of(context).pop(_MagicActionRequest(
      num: _num,
      username: _userController.text.trim(),
      message: _messageController.text.trim(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.description.isNotEmpty) ...[
              Text(
                widget.description,
                style: TextStyle(fontSize: 12, height: 1.45, color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 14),
            ],
            Row(
              children: [
                const Text('数量', style: TextStyle(fontSize: 13)),
                const Spacer(),
                IconButton(
                  onPressed: _num <= 1 ? null : () => setState(() => _num -= 1),
                  icon: const Icon(Icons.remove_circle_outline_rounded),
                  visualDensity: VisualDensity.compact,
                ),
                SizedBox(
                  width: 34,
                  child: Text(
                    '$_num',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  onPressed: _num >= widget.maxNum ? null : () => setState(() => _num += 1),
                  icon: const Icon(Icons.add_circle_outline_rounded),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            if (widget.needUser) ...[
              const SizedBox(height: 10),
              TextField(
                controller: _userController,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: '接收人用户名',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
            ],
            if (widget.needMessage) ...[
              const SizedBox(height: 10),
              TextField(
                controller: _messageController,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: '留言（可选）',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: TextStyle(fontSize: 11.5, color: scheme.error)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('取消')),
        FilledButton(onPressed: _submit, child: Text(widget.confirmText)),
      ],
    );
  }
}

class _BusyDialog extends StatelessWidget {
  const _BusyDialog({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Dialog(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 14),
              Flexible(child: Text(text, style: const TextStyle(fontSize: 13))),
            ],
          ),
        ),
      ),
    );
  }
}

/// 使用道具时按站点要求填写的动态表单。
class _MagicUseDialog extends StatefulWidget {
  const _MagicUseDialog({required this.title, required this.form});

  final String title;
  final MagicUseForm form;

  @override
  State<_MagicUseDialog> createState() => _MagicUseDialogState();
}

class _MagicUseDialogState extends State<_MagicUseDialog> {
  final Map<String, TextEditingController> _controllers = {};
  final Map<String, String> _choices = {};

  @override
  void initState() {
    super.initState();
    for (final field in widget.form.fields) {
      if (field.type == MagicFieldType.text || field.type == MagicFieldType.textarea) {
        _controllers[field.name] = TextEditingController(text: field.value);
      } else if (field.options.isNotEmpty) {
        _choices[field.name] = field.options
            .firstWhere((option) => option.value == field.value, orElse: () => field.options.first)
            .value;
      }
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _submit() {
    final values = <String, String>{};
    for (final field in widget.form.fields) {
      if (field.type == MagicFieldType.text || field.type == MagicFieldType.textarea) {
        values[field.name] = _controllers[field.name]?.text.trim() ?? '';
      } else {
        values[field.name] = _choices[field.name] ?? field.value;
      }
    }
    Navigator.of(context).pop(values);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fields = widget.form.fields;
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (fields.isEmpty)
              Text(
                '该道具无需填写参数，确认后立即使用。',
                style: TextStyle(fontSize: 12.5, height: 1.5, color: scheme.onSurfaceVariant),
              ),
            for (final field in fields) ...[
              if (field.label.isNotEmpty) ...[
                Text(
                  field.label,
                  style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 6),
              ],
              _fieldInput(field),
              const SizedBox(height: 12),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('取消')),
        FilledButton(onPressed: _submit, child: const Text('确认使用')),
      ],
    );
  }

  Widget _fieldInput(MagicFormField field) {
    switch (field.type) {
      case MagicFieldType.text:
        final numeric = field.name.contains('id') || field.name.contains('tid');
        return TextField(
          controller: _controllers[field.name],
          keyboardType: numeric ? TextInputType.number : TextInputType.text,
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(
            isDense: true,
            hintText: field.label.isEmpty ? field.name : field.label,
            border: const OutlineInputBorder(),
          ),
        );
      case MagicFieldType.textarea:
        return TextField(
          controller: _controllers[field.name],
          maxLines: 3,
          decoration: InputDecoration(
            isDense: true,
            hintText: field.label.isEmpty ? field.name : field.label,
            border: const OutlineInputBorder(),
          ),
        );
      case MagicFieldType.radio:
        final selected = _choices[field.name] ?? field.value;
        return SegmentedButton<String>(
          segments: [
            for (final option in field.options)
              ButtonSegment(value: option.value, label: Text(option.label)),
          ],
          selected: {selected},
          showSelectedIcon: false,
          style: const ButtonStyle(
            visualDensity: VisualDensity.compact,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          onSelectionChanged: (value) => setState(() => _choices[field.name] = value.first),
        );
      case MagicFieldType.select:
        return DropdownButtonFormField<String>(
          initialValue: _choices[field.name],
          isDense: true,
          decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
          items: [
            for (final option in field.options)
              DropdownMenuItem(value: option.value, child: Text(option.label)),
          ],
          onChanged: (value) {
            if (value == null) return;
            setState(() => _choices[field.name] = value);
          },
        );
    }
  }
}
