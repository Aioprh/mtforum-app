import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/app_config.dart';
import '../../core/native_bridge.dart';
import '../../services/download_manager.dart';
import '../../services/update_service.dart';
import '../widgets/thread_glass.dart';

/// 检测更新；有新版本就打开安装面板。
///
/// [silent] 用于「顺手检查一下」的场景：已是最新时不打扰用户。
Future<void> checkForUpdates(BuildContext context, {bool silent = false}) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  void toast(String text) => messenger
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
  try {
    final check = await UpdateService.check();
    if (!context.mounted) return;
    if (check.hasUpdate) {
      // 面板自己跑，别让调用方的「检查中」一直转到用户关窗。
      unawaited(UpdateSheet.show(context, check.release!));
      return;
    }
    if (check.failed) {
      toast(check.error);
      return;
    }
    if (silent) return;
    toast('已经是最新版本了');
  } catch (error) {
    // 检查更新不该把页面搞崩：弹窗、网络、解析任何一环出问题都只提示一句。
    if (!silent) toast('检查更新失败：$error');
  }
}

/// 更新面板：版本说明 + 按架构选包 + 下载 + 拉起系统安装器。
class UpdateSheet extends StatefulWidget {
  const UpdateSheet({super.key, required this.release});

  final AppRelease release;

  static Future<void> show(BuildContext context, AppRelease release) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.3),
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => UpdateSheet(release: release),
    );
  }

  @override
  State<UpdateSheet> createState() => _UpdateSheetState();
}

class _UpdateSheetState extends State<UpdateSheet> {
  String _abi = '';
  ReleaseAsset? _selected;

  /// 用户手动点过安装包后，异步回来的 ABI 就不能再改他的选择。
  bool _manual = false;
  bool _downloading = false;
  double _progress = 0;
  DownloadRecord? _record;
  String? _error;

  @override
  void initState() {
    super.initState();
    // 先选上第一个，保证面板一打开就有可点的下载按钮；ABI 查回来再换成本机包。
    _selected = widget.release.apks.isEmpty ? null : widget.release.apks.first;
    _detectAbi();
  }

  Future<void> _detectAbi() async {
    final abi = await NativeBridge.supportedAbi();
    if (!mounted) return;
    setState(() {
      _abi = abi;
      // 默认选本机架构的包；认不出来就退回通用包，再不行保留第一个。
      if (!_manual) _selected = widget.release.assetFor(abi) ?? _selected;
    });
  }

  Future<void> _download() async {
    final asset = _selected;
    if (asset == null || _downloading) return;
    setState(() {
      _downloading = true;
      _progress = 0;
      _error = null;
    });
    try {
      final record = await DownloadManager.instance.download(
        asset.url,
        suggestedFilename: asset.name,
        onProgress: (received, total) {
          if (!mounted || total <= 0) return;
          setState(() => _progress = (received / total).clamp(0.0, 1.0));
        },
      );
      if (!mounted) return;
      setState(() {
        _record = record;
        _downloading = false;
        _progress = 1;
      });
      await _install(record);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _downloading = false;
        _error = '下载失败：${_short(e)}';
      });
    }
  }

  Future<void> _install(DownloadRecord record) async {
    final ok = await NativeBridge.installApk(record.path, name: record.name);
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _error = '没能拉起系统安装器，可以到「我的 → 下载管理」里手动安装');
  }

  String _short(Object error) {
    final text = error.toString();
    return text.length > 70 ? '${text.substring(0, 70)}…' : text;
  }

  String get _notes {
    final notes = widget.release.notes
        .replaceAll(RegExp(r'^#{1,6}\s*', multiLine: true), '')
        .replaceAll(RegExp(r'\*\*(.+?)\*\*'), r'$1')
        .replaceAll(RegExp(r'^\s*[-*]\s+', multiLine: true), '· ')
        .replaceAll(RegExp(r'\[([^\]]+)\]\([^)]+\)'), r'$1')
        .trim();
    if (notes.isEmpty) return '这次发布没有附更新说明，可以点下面的链接查看提交记录。';
    // CI 自动生成的 release 说明只有一行 Full Changelog，展示出来等于没说。
    if (notes.startsWith('Full Changelog')) {
      return '这次发布没有附详细说明，可以点下面的链接查看完整提交记录。';
    }
    return notes;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final apks = widget.release.apks;
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.8,
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
              padding: const EdgeInsets.fromLTRB(20, 10, 8, 0),
              child: Row(
                children: [
                  const Text('发现新版本', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: scheme.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Text(
                      'v${widget.release.version}',
                      style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: scheme.primary),
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, size: 20),
                    visualDensity: VisualDensity.compact,
                    tooltip: '关闭',
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                children: [
                  Text(
                    '当前版本 ${AppConfig.versionLabel} → v${widget.release.version}',
                    style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      _sectionTitle(scheme, '更新说明'),
                      const Spacer(),
                      TextButton(
                        onPressed: () => launchUrl(
                          Uri.parse(
                            'https://github.com/${UpdateService.repo}/releases/tag/${widget.release.tag}',
                          ),
                          mode: LaunchMode.externalApplication,
                        ),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Text('在 GitHub 查看', style: TextStyle(fontSize: 11)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                    constraints: const BoxConstraints(maxHeight: 168),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(13),
                      border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.35)),
                    ),
                    child: SingleChildScrollView(
                      child: Text(
                        _notes,
                        style: TextStyle(fontSize: 12, height: 1.65, color: scheme.onSurfaceVariant),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _sectionTitle(scheme, '选择安装包'),
                  const SizedBox(height: 6),
                  for (final asset in apks) ...[
                    _AssetTile(
                      asset: asset,
                      selected: asset.name == _selected?.name,
                      isDevice: _abi.isNotEmpty && asset.abi == _abi,
                      onTap: _downloading
                          ? null
                          : () => setState(() {
                                _selected = asset;
                                _manual = true;
                              }),
                    ),
                    const SizedBox(height: 7),
                  ],
                  if (apks.isEmpty)
                    Text(
                      '这次发布没有可用的 APK',
                      style: TextStyle(fontSize: 12, color: scheme.error),
                    ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(
                        _error!,
                        style: TextStyle(fontSize: 11.5, height: 1.5, color: scheme.error),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                8,
                20,
                12 + MediaQuery.viewInsetsOf(context).bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_downloading) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: _progress > 0 ? _progress : null,
                        minHeight: 5,
                        backgroundColor: scheme.surfaceContainerHighest,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        _progress > 0 ? '下载中 ${(_progress * 100).round()}%' : '正在连接…',
                        style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  SizedBox(
                    width: double.infinity,
                    height: 47,
                    child: FilledButton(
                      onPressed: _downloading || apks.isEmpty
                          ? null
                          : (_record != null ? () => _install(_record!) : _download),
                      style: FilledButton.styleFrom(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: Text(
                        _downloading
                            ? '下载中…'
                            : _record != null
                                ? '立即安装'
                                : '下载并安装',
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '安装包来自 GitHub Releases，下载后会交给系统安装器处理。',
                    style: TextStyle(fontSize: 10.5, color: scheme.outline),
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

Widget _sectionTitle(ColorScheme scheme, String text) => Text(
      text,
      style: TextStyle(
        fontSize: 11.5,
        fontWeight: FontWeight.w800,
        color: scheme.onSurfaceVariant.withValues(alpha: 0.9),
      ),
    );

/// 一个安装包选项：架构、体积、本机标记共用一行。
class _AssetTile extends StatelessWidget {
  const _AssetTile({
    required this.asset,
    required this.selected,
    required this.isDevice,
    required this.onTap,
  });

  final ReleaseAsset asset;
  final bool selected;
  final bool isDevice;
  final VoidCallback? onTap;

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
              ? scheme.primary.withValues(alpha: 0.1)
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
            padding: const EdgeInsets.fromLTRB(13, 10, 12, 10),
            child: Row(
              children: [
                Icon(
                  selected ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded,
                  size: 18,
                  color: selected ? scheme.primary : scheme.outline,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            asset.abi == 'universal' ? '通用包' : asset.abi,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: selected ? scheme.primary : scheme.onSurface,
                            ),
                          ),
                          if (isDevice) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: scheme.primary.withValues(alpha: 0.14),
                                borderRadius: BorderRadius.circular(5),
                              ),
                              child: Text(
                                '本机',
                                style: TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w700,
                                  color: scheme.primary,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${asset.label}${asset.sizeText.isEmpty ? '' : ' · ${asset.sizeText}'}',
                        style: TextStyle(fontSize: 10.5, color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
