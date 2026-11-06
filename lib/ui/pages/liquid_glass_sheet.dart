import 'package:flutter/material.dart';

import '../../state/app_state.dart';
import '../widgets/glass_compose_button.dart';
import '../widgets/thread_glass.dart';

/// 面板里调好的各项数值。写回 [AppState] 由调用方统一做，
/// 面板只负责呈现和收集，这样不受存储顺序影响，也方便单独测。
class LiquidGlassSettings {
  const LiquidGlassSettings({
    required this.glassEnabled,
    required this.navEnabled,
    required this.navOpacity,
    required this.navBlur,
    required this.composeOpacity,
    required this.composeBlur,
    required this.threadOpacity,
    required this.threadBlur,
  });

  final bool glassEnabled;
  final bool navEnabled;
  final double navOpacity;
  final double navBlur;
  final double composeOpacity;
  final double composeBlur;
  final double threadOpacity;
  final double threadBlur;
}

// 与 AppState 里的初始值保持一致，改一处记得同步另一处。
const double _navOpacityDefault = 0.25;
const double _navBlurDefault = 30;
const double _composeOpacityDefault = 0.28;
const double _composeBlurDefault = 26;
const double _threadOpacityDefault = 0.55;
const double _threadBlurDefault = 22;

/// 打开液态玻璃设置面板；用户未保存时返回 null。
Future<LiquidGlassSettings?> showLiquidGlassSheet(BuildContext context) {
  return showModalBottomSheet<LiquidGlassSettings>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    builder: (_) => const LiquidGlassSheet(),
  );
}

/// 液态玻璃设置面板。
///
/// 顶部一个总开关，下面按「底栏 / 发帖按钮 / 顶栏与输入条」三块卡片分开调。
/// 总开关关掉时，卡片里的参数仍然留在原位（只是变灰、不可拖），
/// 重新打开立刻按原值恢复，不用重新调一遍。
class LiquidGlassSheet extends StatefulWidget {
  const LiquidGlassSheet({super.key});

  @override
  State<LiquidGlassSheet> createState() => _LiquidGlassSheetState();
}

class _LiquidGlassSheetState extends State<LiquidGlassSheet> {
  late bool _glassEnabled = AppState.instance.glassEnabled;
  late bool _navEnabled = AppState.instance.floatingGlassNav;
  late double _navOpacity = AppState.instance.floatingGlassNavOpacity;
  late double _navBlur = AppState.instance.floatingGlassNavBlur;
  late double _composeOpacity = AppState.instance.composeGlassOpacity;
  late double _composeBlur = AppState.instance.composeGlassBlur;
  late double _threadOpacity = AppState.instance.threadGlassOpacity;
  late double _threadBlur = AppState.instance.threadGlassBlur;

  void _save() {
    Navigator.pop(
      context,
      LiquidGlassSettings(
        glassEnabled: _glassEnabled,
        navEnabled: _navEnabled,
        navOpacity: _navOpacity,
        navBlur: _navBlur,
        composeOpacity: _composeOpacity,
        composeBlur: _composeBlur,
        threadOpacity: _threadOpacity,
        threadBlur: _threadBlur,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.92,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _header(scheme),
            Flexible(
              // 内容固定就三节，用 SingleChildScrollView 一次建好：
              // 惰性列表会让下半截卡片在滚到之前根本不存在，找控件和
              // 读屏都不方便。
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(18, 2, 18, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _masterSwitch(scheme),
                    if (!_glassEnabled) ...[
                      const SizedBox(height: 10),
                      _offHint(scheme),
                    ],
                    const SizedBox(height: 14),
                    _navCard(scheme),
                    const SizedBox(height: 12),
                    _composeCard(scheme),
                    const SizedBox(height: 12),
                    _chromeCard(scheme),
                  ],
                ),
              ),
            ),
            _saveBar(scheme),
          ],
        ),
      ),
    );
  }

  Widget _header(ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 8, 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '液态玻璃',
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 3),
                Text(
                  '底栏、发帖按钮与页面顶栏各用一套材质，调好后点保存生效',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.45,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => Navigator.pop(context),
            tooltip: '关闭',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.close_rounded, size: 20),
          ),
        ],
      ),
    );
  }

  /// 顶部总开关：一张主色卡片，一眼能看出玻璃现在是开还是关。
  Widget _masterSwitch(ColorScheme scheme) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            scheme.primary.withValues(alpha: dark ? 0.30 : 0.17),
            scheme.primary.withValues(alpha: dark ? 0.12 : 0.05),
          ],
        ),
        border: Border.all(
          color: scheme.primary.withValues(alpha: dark ? 0.34 : 0.18),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.blur_on_rounded, size: 20, color: scheme.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '启用液态玻璃',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 2),
                Text(
                  _glassEnabled ? '半透明材质已应用到全局' : '界面改为不透明样式，也不再做背景模糊',
                  style: TextStyle(
                    fontSize: 11.5,
                    height: 1.35,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Switch.adaptive(
            key: const ValueKey('glass-master-switch'),
            value: _glassEnabled,
            onChanged: (value) => setState(() => _glassEnabled = value),
          ),
        ],
      ),
    );
  }

  Widget _offHint(ColorScheme scheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, size: 15, color: scheme.onTertiaryContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '下面的数值暂时不生效，重新打开后会按现在调好的样子恢复',
              style: TextStyle(
                fontSize: 11.5,
                height: 1.4,
                color: scheme.onTertiaryContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _navCard(ColorScheme scheme) {
    return _GroupCard(
      icon: Icons.space_dashboard_rounded,
      title: '底部导航栏',
      description: '悬浮在页面之上，只换背景材质',
      action: Switch.adaptive(
        key: const ValueKey('glass-nav-switch'),
        value: _navEnabled,
        onChanged: (value) => setState(() => _navEnabled = value),
      ),
      resetLabel: '底栏恢复默认',
      onReset: () => setState(() {
        _navOpacity = _navOpacityDefault;
        _navBlur = _navBlurDefault;
      }),
      enabled: _glassEnabled,
      child: Column(
        children: [
          _slider(
            label: '玻璃透明度',
            value: _navOpacity,
            min: 0.05,
            max: 0.65,
            divisions: 12,
            onChanged: (value) => setState(() => _navOpacity = value),
          ),
          _slider(
            label: '背景模糊度',
            value: _navBlur,
            min: 0,
            max: 40,
            divisions: 16,
            percent: false,
            onChanged: (value) => setState(() => _navBlur = value),
          ),
        ],
      ),
    );
  }

  Widget _composeCard(ColorScheme scheme) {
    return _GroupCard(
      icon: Icons.auto_awesome_rounded,
      title: '发帖按钮',
      description: '右下角悬浮按钮，可边调边看',
      resetLabel: '发帖按钮恢复默认',
      onReset: () => setState(() {
        _composeOpacity = _composeOpacityDefault;
        _composeBlur = _composeBlurDefault;
      }),
      enabled: _glassEnabled,
      child: Column(
        children: [
          _composePreview(scheme),
          const SizedBox(height: 4),
          _slider(
            label: '玻璃透明度',
            value: _composeOpacity,
            min: 0.05,
            max: 0.75,
            divisions: 14,
            onChanged: (value) => setState(() => _composeOpacity = value),
          ),
          _slider(
            label: '背景模糊度',
            value: _composeBlur,
            min: 0,
            max: 40,
            divisions: 16,
            percent: false,
            onChanged: (value) => setState(() => _composeBlur = value),
          ),
        ],
      ),
    );
  }

  Widget _chromeCard(ColorScheme scheme) {
    return _GroupCard(
      icon: Icons.layers_rounded,
      title: '顶栏与输入条',
      description: '帖子页、私信等页面的顶栏与底部输入区共用',
      resetLabel: '顶栏恢复默认',
      onReset: () => setState(() {
        _threadOpacity = _threadOpacityDefault;
        _threadBlur = _threadBlurDefault;
      }),
      enabled: _glassEnabled,
      child: Column(
        children: [
          _chromePreview(scheme),
          const SizedBox(height: 4),
          _slider(
            label: '玻璃透明度',
            value: _threadOpacity,
            min: 0.05,
            max: 0.85,
            divisions: 16,
            onChanged: (value) => setState(() => _threadOpacity = value),
          ),
          _slider(
            label: '背景模糊度',
            value: _threadBlur,
            min: 0,
            max: 40,
            divisions: 16,
            percent: false,
            onChanged: (value) => setState(() => _threadBlur = value),
          ),
        ],
      ),
    );
  }

  /// 发帖按钮预览：玻璃压在一片彩色文字上，模糊强度一眼能看出来。
  Widget _composePreview(ColorScheme scheme) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Container(
        height: 84,
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              scheme.primaryContainer,
              scheme.tertiaryContainer,
              scheme.secondaryContainer,
            ],
          ),
        ),
        child: Stack(
          children: [
            Positioned(left: 16, top: 18, child: _previewBar(scheme, 84, 0.30)),
            Positioned(left: 16, top: 38, child: _previewBar(scheme, 136, 0.18)),
            Positioned(
              right: 14,
              bottom: 14,
              child: GlassComposeButton(
                opacity: _composeOpacity,
                blur: _composeBlur,
                onPressed: () {},
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 顶栏 + 输入条预览：上下两条玻璃压在色块上，一起看是否协调。
  Widget _chromePreview(ColorScheme scheme) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        height: 100,
        child: Stack(
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      scheme.primaryContainer,
                      scheme.tertiaryContainer,
                    ],
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 34, 14, 38),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _previewBar(scheme, 158, 0.30),
                    const SizedBox(height: 9),
                    _previewBar(scheme, 220, 0.20),
                  ],
                ),
              ),
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: GlassBackdrop(
                opacity: _threadOpacity,
                blur: _threadBlur,
                showBorder: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    children: [
                      Icon(Icons.arrow_back_rounded, size: 16, color: scheme.onSurface),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          '帖子标题',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: scheme.onSurface,
                          ),
                        ),
                      ),
                      Icon(Icons.ios_share_rounded, size: 15, color: scheme.onSurfaceVariant),
                      const SizedBox(width: 9),
                      Icon(Icons.more_vert_rounded, size: 15, color: scheme.onSurfaceVariant),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: GlassBackdrop(
                opacity: _threadOpacity,
                blur: _threadBlur,
                showBorder: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  child: Row(
                    children: [
                      Icon(Icons.sentiment_satisfied_alt_rounded, size: 16, color: scheme.onSurfaceVariant),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Container(
                          height: 26,
                          alignment: Alignment.centerLeft,
                          padding: const EdgeInsets.symmetric(horizontal: 11),
                          decoration: BoxDecoration(
                            color: scheme.surface.withValues(alpha: 0.55),
                            borderRadius: BorderRadius.circular(13),
                          ),
                          child: Text(
                            '写下你的回复…',
                            style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(Icons.image_outlined, size: 16, color: scheme.onSurfaceVariant),
                      const SizedBox(width: 8),
                      Icon(Icons.send_rounded, size: 16, color: scheme.primary),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _previewBar(ColorScheme scheme, double width, double alpha) => Container(
    width: width,
    height: 9,
    decoration: BoxDecoration(
      color: scheme.onPrimaryContainer.withValues(alpha: alpha),
      borderRadius: BorderRadius.circular(5),
    ),
  );

  Widget _slider({
    required String label,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required ValueChanged<double> onChanged,
    bool percent = true,
  }) {
    return _GlassSlider(
      label: label,
      value: value,
      min: min,
      max: max,
      divisions: divisions,
      percent: percent,
      onChanged: onChanged,
    );
  }

  Widget _saveBar(ColorScheme scheme) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 12),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(
          top: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.45)),
        ),
      ),
      child: SizedBox(
        width: double.infinity,
        height: 48,
        child: FilledButton(
          onPressed: _save,
          style: FilledButton.styleFrom(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          child: const Text('保存设置', style: TextStyle(fontWeight: FontWeight.w700)),
        ),
      ),
    );
  }
}

/// 一块分组卡：图标 + 标题 + 说明 + 右侧开关，下面是参数区。
///
/// 以前这些内容直接摊在面板上，节与节之间只靠一条细线分隔，开关、滑杆、
/// 预览块混在一起，滚动时不知道哪几项属于哪一节。改成卡片后每节的边界清楚，
/// 「恢复默认」也跟着待在自己那节里。
class _GroupCard extends StatelessWidget {
  const _GroupCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.child,
    this.action,
    this.resetLabel,
    this.onReset,
    this.enabled = true,
  });

  final IconData icon;
  final String title;
  final String description;
  final Widget child;
  final Widget? action;
  final String? resetLabel;
  final VoidCallback? onReset;

  /// 总开关关闭时参数区变灰且不可拖，但开关本身仍可点。
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.35)),
      ),
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(icon, size: 18, color: scheme.primary),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        height: 1.4,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (action != null) ...[const SizedBox(width: 6), action!],
            ],
          ),
          const SizedBox(height: 11),
          Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.35)),
          const SizedBox(height: 4),
          AnimatedOpacity(
            duration: const Duration(milliseconds: 160),
            opacity: enabled ? 1 : 0.42,
            child: IgnorePointer(ignoring: !enabled, child: child),
          ),
          if (resetLabel != null)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: enabled ? onReset : null,
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(resetLabel!, style: const TextStyle(fontSize: 12)),
              ),
            ),
        ],
      ),
    );
  }
}

/// 「名称 + 数值 + 滑杆」，数值放在右侧的小胶囊里，拖动时数字不变形。
class _GlassSlider extends StatelessWidget {
  const _GlassSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
    this.percent = true,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final ValueChanged<double> onChanged;
  final bool percent;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = percent ? '${(value * 100).round()}%' : value.round().toString();
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurface,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Text(
                  text,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: scheme.primary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3.5,
              activeTrackColor: scheme.primary,
              inactiveTrackColor: scheme.primary.withValues(alpha: 0.16),
              thumbColor: scheme.primary,
              overlayColor: scheme.primary.withValues(alpha: 0.12),
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
              showValueIndicator: ShowValueIndicator.never,
            ),
            child: Slider(
              value: value.clamp(min, max).toDouble(),
              min: min,
              max: max,
              divisions: divisions,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}
