import 'package:flutter/material.dart';

import '../../core/http_session.dart';
import '../../data/models.dart';
import '../widgets/thread_glass.dart';

/// 居住地选择结果：站点分省 / 市 / 区三级，街道留空。
class RegionPick {
  const RegionPick({required this.province, required this.city, required this.dist});

  final String province;
  final String city;
  final String dist;

  String get text => [province, city, dist].where((e) => e.isNotEmpty).join(' ');
}

/// 省 / 市 / 区三级选择浮层。
///
/// 数据来自站点自己的地区库（`op=district` 的 ajax），所以选出来的名称和
/// 网页端提交的一模一样，不会出现「App 里选不了、只能去网页版」的死路。
/// 省列表一次拉全，市、区按需下钻。
class RegionPickerSheet extends StatefulWidget {
  const RegionPickerSheet({
    super.key,
    required this.loader,
    this.province = '',
    this.city = '',
    this.dist = '',
  });

  /// 传 `provinceId` 拿市，再传 `cityId` 拿区；都不传就是省列表。
  final Future<List<RegionOption>> Function({int provinceId, int cityId}) loader;

  /// 打开时尝试回填的已有地址。
  final String province;
  final String city;
  final String dist;

  static Future<RegionPick?> show(
    BuildContext context, {
    required Future<List<RegionOption>> Function({int provinceId, int cityId}) loader,
    String province = '',
    String city = '',
    String dist = '',
  }) {
    return showModalBottomSheet<RegionPick>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.26),
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => RegionPickerSheet(
        loader: loader,
        province: province,
        city: city,
        dist: dist,
      ),
    );
  }

  @override
  State<RegionPickerSheet> createState() => _RegionPickerSheetState();
}

class _RegionPickerSheetState extends State<RegionPickerSheet> {
  /// 正在浏览的层级：0 省 / 1 市 / 2 区。
  int _level = 0;
  List<RegionOption> _provinces = const [];
  List<RegionOption> _cities = const [];
  List<RegionOption> _dists = const [];
  RegionOption? _province;
  RegionOption? _city;
  RegionOption? _dist;
  bool _loading = true;
  String? _error;

  /// 防重入：连点两级时，先回来的旧请求不能把新层级覆盖掉。
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _loadProvinces();
  }

  List<RegionOption> get _options => switch (_level) {
        0 => _provinces,
        1 => _cities,
        _ => _dists,
      };

  String get _title => switch (_level) {
        0 => '选择省份',
        1 => '选择城市',
        _ => '选择区县',
      };

  RegionOption? _match(List<RegionOption> list, String name) {
    final target = name.trim();
    if (target.isEmpty) return null;
    for (final item in list) {
      if (item.name.trim() == target) return item;
    }
    return null;
  }

  Future<void> _loadProvinces() async {
    final token = ++_request;
    setState(() {
      _loading = true;
      _error = null;
      _level = 0;
      _province = null;
      _city = null;
      _dist = null;
    });
    try {
      final list = await widget.loader();
      if (!mounted || token != _request) return;
      setState(() {
        _provinces = list;
        _loading = false;
      });
      final saved = _match(list, widget.province);
      if (saved != null) await _pickProvince(saved, restore: true);
    } catch (e) {
      if (!mounted || token != _request) return;
      setState(() {
        _loading = false;
        _error = _message(e);
      });
    }
  }

  Future<void> _pickProvince(RegionOption option, {bool restore = false}) async {
    final token = ++_request;
    setState(() {
      _province = option;
      _city = null;
      _dist = null;
      _level = 1;
      _cities = const [];
      _dists = const [];
      _loading = true;
      _error = null;
    });
    try {
      final list = await widget.loader(provinceId: option.id);
      if (!mounted || token != _request) return;
      setState(() {
        _cities = list;
        _loading = false;
      });
      if (list.isEmpty) {
        // 「海外」「其他」这类没有下级，选到省就交卷。
        if (!restore) _finish();
        return;
      }
      final saved = _match(list, widget.city);
      if (saved != null) await _pickCity(saved, restore: restore);
    } catch (e) {
      if (!mounted || token != _request) return;
      setState(() {
        _loading = false;
        _error = _message(e);
      });
    }
  }

  Future<void> _pickCity(RegionOption option, {bool restore = false}) async {
    final token = ++_request;
    setState(() {
      _city = option;
      _dist = null;
      _level = 2;
      _dists = const [];
      _loading = true;
      _error = null;
    });
    try {
      final list = await widget.loader(provinceId: _province?.id ?? 0, cityId: option.id);
      if (!mounted || token != _request) return;
      setState(() {
        _dists = list;
        _loading = false;
      });
      if (list.isEmpty) {
        // 直筒子市（东莞、中山）没有区县，选到市就交卷。
        if (!restore) _finish();
        return;
      }
      // 回填只把已有的区县标出来，不替用户按确定。
      final saved = _match(list, widget.dist);
      if (saved != null) setState(() => _dist = saved);
    } catch (e) {
      if (!mounted || token != _request) return;
      setState(() {
        _loading = false;
        _error = _message(e);
      });
    }
  }

  void _finish({RegionOption? dist}) {
    Navigator.of(context).pop(
      RegionPick(
        province: _province?.name ?? '',
        city: _city?.name ?? '',
        dist: (dist ?? _dist)?.name ?? '',
      ),
    );
  }

  void _goLevel(int level) {
    if (level >= _level) return;
    setState(() {
      _level = level;
      if (level <= 0) {
        _province = null;
        _city = null;
        _dist = null;
      } else if (level == 1) {
        _dist = null;
      }
    });
  }

  String _message(Object error) => error is SiteException ? error.message : '$error';

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.68,
      child: GlassBackdrop(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        opacityScale: 1.06,
        showShadow: true,
        child: Column(
          children: [
            const SizedBox(height: 9),
            Container(
              width: 38,
              height: 4.5,
              decoration: BoxDecoration(
                color: scheme.onSurfaceVariant.withValues(alpha: 0.32),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 8, 2),
              child: Row(
                children: [
                  Text(
                    _title,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '省 / 市 / 区三级联动',
                      style: TextStyle(fontSize: 11.5, color: scheme.outline),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, size: 20),
                    visualDensity: VisualDensity.compact,
                    tooltip: '关闭',
                  ),
                ],
              ),
            ),
            _crumbs(scheme),
            const SizedBox(height: 4),
            Expanded(child: _body(scheme)),
            Padding(
              padding: EdgeInsets.fromLTRB(
                12,
                4,
                18,
                10 + MediaQuery.viewInsetsOf(context).bottom,
              ),
              child: Row(
                children: [
                  TextButton.icon(
                    onPressed: () => Navigator.of(context).pop(
                      const RegionPick(province: '', city: '', dist: ''),
                    ),
                    icon: const Icon(Icons.location_off_outlined, size: 17),
                    label: const Text('清除居住地', style: TextStyle(fontSize: 12.5)),
                  ),
                  const Spacer(),
                  if (!_loading && _error == null)
                    Text(
                      '共 ${_options.length} 项',
                      style: TextStyle(fontSize: 11, color: scheme.outline),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _crumbs(ColorScheme scheme) {
    // 三段固定占位：没选到的那一级显示「省份 / 城市 / 区县」，选过就换成名字。
    // 固定三段比「选一级长一段」稳，不会因为只有一项而缩在中间。
    final crumbs = <(String, int)>[
      (_province?.name ?? '省份', 0),
      (_city?.name ?? '城市', 1),
      (_dist?.name ?? '区县', 2),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 2, 16, 2),
      child: Row(
        children: [
          for (var i = 0; i < crumbs.length; i++) ...[
            if (i > 0)
              Icon(Icons.chevron_right_rounded, size: 15, color: scheme.outline),
            _crumb(scheme, crumbs[i].$1, crumbs[i].$2),
          ],
        ],
      ),
    );
  }

  Widget _crumb(ColorScheme scheme, String label, int level) {
    final active = _level == level;
    final reachable = level <= _level;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: reachable ? () => _goLevel(level) : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: active ? FontWeight.w800 : FontWeight.w600,
            color: active
                ? scheme.primary
                : reachable
                    ? scheme.onSurfaceVariant
                    : scheme.outline.withValues(alpha: 0.55),
          ),
        ),
      ),
    );
  }

  Widget _body(ColorScheme scheme) {
    if (_loading) {
      return const Center(
        child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.4)),
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12.5, height: 1.5, color: scheme.error),
              ),
              const SizedBox(height: 10),
              OutlinedButton(
                onPressed: _retry,
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }
    final options = _options;
    if (options.isEmpty) {
      return Center(
        child: Text(
          '这一级没有选项',
          style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
        ),
      );
    }
    final selected = switch (_level) {
      0 => _province,
      1 => _city,
      _ => _dist,
    };
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
      itemCount: options.length,
      separatorBuilder: (_, __) => const SizedBox(height: 7),
      itemBuilder: (context, index) {
        final option = options[index];
        return _RegionCell(
          name: option.name,
          selected: option.name == selected?.name,
          onTap: () {
            if (_level == 0) {
              _pickProvince(option);
            } else if (_level == 1) {
              _pickCity(option);
            } else {
              _dist = option;
              _finish(dist: option);
            }
          },
        );
      },
    );
  }

  void _retry() {
    if (_level == 0) {
      _loadProvinces();
    } else if (_level == 1 && _province != null) {
      _pickProvince(_province!);
    } else if (_province != null && _city != null) {
      _pickCity(_city!);
    }
  }
}

/// 一个地区选项：选中态用主色描边 + 勾，其余是淡玻璃底。
class _RegionCell extends StatelessWidget {
  const _RegionCell({required this.name, required this.selected, required this.onTap});

  final String name;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(13);
    return Material(
      color: Colors.transparent,
      child: Ink(
        decoration: BoxDecoration(
          borderRadius: radius,
          color: selected
              ? scheme.primary.withValues(alpha: 0.12)
              : ThreadGlass.fill(context, lightAlpha: 0.44, darkAlpha: 0.09),
          border: Border.all(
            color: selected ? scheme.primary : ThreadGlass.borderColor(context),
            width: selected ? 1.2 : 0.9,
          ),
        ),
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    name,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: selected ? scheme.primary : scheme.onSurface,
                    ),
                  ),
                ),
                if (selected) Icon(Icons.check_rounded, size: 17, color: scheme.primary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
