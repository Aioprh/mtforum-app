import 'package:flutter/material.dart';

import '../../core/http_session.dart';
import '../../data/models.dart';
import '../../state/app_state.dart';
import '../widgets/smart_image.dart';
import '../widgets/state_views.dart';
import 'login_page.dart';

/// 积分商城商品详情（原生，不跳浏览器）。
class MallProductPage extends StatefulWidget {
  const MallProductPage({super.key, required this.tid});

  final int tid;

  @override
  State<MallProductPage> createState() => _MallProductPageState();
}

class _MallProductPageState extends State<MallProductPage> {
  MallProduct? _product;
  bool _loading = true;
  bool _busy = false;
  String? _error;

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
      final product = await AppState.instance.repo.fetchMallProduct(widget.tid);
      if (!mounted) return;
      setState(() {
        _product = product;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e is SiteException ? e.message : '加载失败，请稍后重试';
      });
    }
  }

  Future<void> _buy() async {
    final product = _product;
    if (product == null || product.buyHref.isEmpty || _busy) return;
    if (!AppState.instance.isLoggedIn) {
      final ok = await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => const LoginPage()),
      );
      if (ok == true) await _buy();
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('确认抢购'),
        content: Text('${product.title}\n${product.price}，抢购后不支持退换。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('确认抢购')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final message = await AppState.instance.repo.performModuleAction(product.buyHref);
      messenger.showSnackBar(SnackBar(content: Text(message)));
      await _load();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e is SiteException ? e.message : '抢购失败，请稍后重试')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showStatus() async {
    final product = _product;
    if (product == null || product.statusHref.isEmpty || _busy) return;
    if (!AppState.instance.isLoggedIn) {
      final ok = await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => const LoginPage()),
      );
      if (ok != true) return;
    }
    if (!mounted) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final text = await AppState.instance.repo.fetchPluginText(product.statusHref);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('卡密状态'),
          content: SingleChildScrollView(
            child: SelectableText(
              text.isEmpty ? '暂无记录' : text,
              style: const TextStyle(fontSize: 13, height: 1.6),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('关闭')),
          ],
        ),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e is SiteException ? e.message : '查询失败，请稍后重试')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final product = _product;
    return Scaffold(
      appBar: AppBar(
        title: Text(product?.title ?? '商品详情', maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? ErrorView(message: _error!, onRetry: _load)
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 20),
                      children: [
                        if (product!.image.isNotEmpty)
                          Container(
                            decoration: BoxDecoration(
                              color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            padding: const EdgeInsets.all(12),
                            child: AspectRatio(
                              aspectRatio: 16 / 10,
                              child: SmartImage(url: product.image, fit: BoxFit.contain),
                            ),
                          ),
                        const SizedBox(height: 14),
                        Text(
                          product.title,
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, height: 1.4),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            if (product.price.isNotEmpty)
                              Text(
                                product.price,
                                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: scheme.primary),
                              ),
                            const SizedBox(width: 10),
                            if (product.marketPrice.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 2),
                                child: Text(
                                  product.marketPrice,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: scheme.outline,
                                    decoration: TextDecoration.lineThrough,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            if (product.stock.isNotEmpty) _chip(scheme, product.stock),
                            if (product.sold.isNotEmpty) _chip(scheme, product.sold),
                            if (product.views.isNotEmpty) _chip(scheme, '浏览 ${product.views}'),
                          ],
                        ),
                        if (product.countdown.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Icon(Icons.timer_outlined, size: 16, color: scheme.primary),
                              const SizedBox(width: 6),
                              Text(
                                '剩余时间 ${product.countdown}',
                                style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ],
                        if (product.warning.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: scheme.errorContainer.withValues(alpha: 0.35),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              product.warning,
                              style: TextStyle(fontSize: 11.5, height: 1.5, color: scheme.onSurfaceVariant),
                            ),
                          ),
                        ],
                        const SizedBox(height: 20),
                        Row(
                          children: [
                            const Text('兑换记录', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
                            const SizedBox(width: 8),
                            Text('最近 ${product.records.length} 条', style: TextStyle(fontSize: 11, color: scheme.outline)),
                          ],
                        ),
                        const SizedBox(height: 10),
                        if (product.records.isEmpty)
                          const EmptyView(text: '还没有人兑换该商品', icon: Icons.receipt_long_outlined)
                        else
                          for (final record in product.records) ...[
                            Material(
                              color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
                              borderRadius: BorderRadius.circular(12),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        record.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                                      ),
                                    ),
                                    if (record.subtitle.isNotEmpty)
                                      Text(
                                        record.subtitle,
                                        style: TextStyle(fontSize: 11, color: scheme.outline),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                          ],
                      ],
                    ),
                  ),
      ),
      bottomNavigationBar: product == null
          ? null
          : SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
                child: Row(
                  children: [
                    if (product.statusHref.isNotEmpty)
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _busy ? null : _showStatus,
                          child: const Text('查看卡密状态'),
                        ),
                      ),
                    if (product.statusHref.isNotEmpty) const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: FilledButton.icon(
                        onPressed: _busy || product.buyHref.isEmpty ? null : _buy,
                        icon: _busy
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.shopping_cart_checkout_rounded, size: 18),
                        label: Text(product.buyHref.isEmpty ? '暂不可抢购' : '立即抢购'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _chip(ColorScheme scheme, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(text, style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
    );
  }
}
