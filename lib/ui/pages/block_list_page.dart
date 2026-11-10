import 'package:flutter/material.dart';

import '../../core/block_list.dart';
import '../widgets/glass_app_bar.dart';
import '../widgets/glass_controls.dart';
import '../widgets/glass_dialog.dart';
import '../widgets/state_views.dart';

/// 屏蔽管理：本机的用户黑名单和评论关键词。
///
/// 站点黑名单只限制互动，内容照样能看，所以客户端另存一份。这里既是查看
/// 入口，也能手动补一个用户名或关键词——有时候是在别处看到的，懒得回帖子里找。
class BlockListPage extends StatefulWidget {
  const BlockListPage({super.key});

  @override
  State<BlockListPage> createState() => _BlockListPageState();
}

class _BlockListPageState extends State<BlockListPage> {
  static const List<(int, String)> _tabs = [
    (0, '屏蔽用户'),
    (1, '评论关键词'),
  ];

  final _username = TextEditingController();
  final _keyword = TextEditingController();
  int _tab = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    BlockList.instance.addListener(_onChanged);
    BlockList.instance.load().whenComplete(() {
      if (mounted) setState(() => _loading = false);
    });
  }

  @override
  void dispose() {
    BlockList.instance.removeListener(_onChanged);
    _username.dispose();
    _keyword.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _addUser() async {
    final name = _username.text.trim();
    if (name.isEmpty) {
      _toast('先填一个用户名');
      return;
    }
    final added = await BlockList.instance.blockUser(name);
    if (!mounted) return;
    if (!added) {
      _toast('「$name」已经在名单里了');
      return;
    }
    _username.clear();
    FocusScope.of(context).unfocus();
    _toast('已屏蔽「$name」');
  }

  Future<void> _addKeyword() async {
    final word = _keyword.text.trim();
    if (word.isEmpty) {
      _toast('先填一个关键词');
      return;
    }
    final added = await BlockList.instance.addKeyword(word);
    if (!mounted) return;
    if (!added) {
      _toast('「$word」已经在名单里了');
      return;
    }
    _keyword.clear();
    FocusScope.of(context).unfocus();
    _toast('已屏蔽包含「$word」的评论');
  }

  Future<void> _removeUser(BlockedUser user) async {
    final ok = await showGlassDialog<bool>(
      context: context,
      builder: (context) => GlassDialog(
        title: const Text('解除屏蔽'),
        content: Text('解除后「${user.name}」的主题和回复会重新显示。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('解除')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await BlockList.instance.unblockUser(user);
    if (mounted) _toast('已解除对「${user.name}」的屏蔽');
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final block = BlockList.instance;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: const GlassAppBar(title: Text('屏蔽管理')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: glassPagePadding(context, top: 10, bottom: 34),
              children: [
                Center(
                  child: GlassSegmented<int>(
                    segments: _tabs,
                    value: _tab,
                    onChanged: (value) => setState(() => _tab = value),
                    expand: true,
                  ),
                ),
                const SizedBox(height: 16),
                if (_tab == 0) ..._userTab(scheme, block) else ..._keywordTab(scheme, block),
              ],
            ),
    );
  }

  // ------------------------------------------------------------ 屏蔽用户

  List<Widget> _userTab(ColorScheme scheme, BlockList block) {
    return [
      _card(scheme, [
        _hint(scheme, '被屏蔽的人：主题列表里不再出现 TA 的帖子，帖子里 TA 的楼层和楼中楼点评也会隐藏。'),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: GlassField(
                controller: _username,
                hintText: '输入用户名，手动添加',
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _addUser(),
              ),
            ),
            const SizedBox(width: 9),
            SizedBox(
              height: 46,
              child: FilledButton(
                onPressed: _addUser,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: const Text('添加', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ]),
      const SizedBox(height: 14),
      if (block.users.isEmpty)
        SizedBox(height: 240, child: EmptyView(text: '还没有屏蔽任何用户'))
      else
        _card(scheme, [
          for (var i = 0; i < block.users.length; i++) ...[
            if (i > 0) Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.4)),
            _userRow(scheme, block.users[i]),
          ],
        ]),
      _note(scheme, '屏蔽只影响本机显示，不会通知对方，也不影响站点上的正常浏览。'),
    ];
  }

  Widget _userRow(ColorScheme scheme, BlockedUser user) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: scheme.error.withValues(alpha: 0.09),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(Icons.person_off_outlined, size: 19, color: scheme.error),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
                ),
                if (user.since.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      '屏蔽于 ${user.since}',
                      style: TextStyle(fontSize: 10.5, color: scheme.outline),
                    ),
                  ),
              ],
            ),
          ),
          TextButton(
            onPressed: () => _removeUser(user),
            style: TextButton.styleFrom(
              foregroundColor: scheme.onSurfaceVariant,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('解除', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------ 关键词

  List<Widget> _keywordTab(ColorScheme scheme, BlockList block) {
    return [
      _card(scheme, [
        _hint(scheme, '评论或楼层正文里出现这些词时，那条内容会整条隐藏。英文不区分大小写，多个关键词之间是「或」的关系。'),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: GlassField(
                controller: _keyword,
                hintText: '例如：广告、加群、代下',
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _addKeyword(),
              ),
            ),
            const SizedBox(width: 9),
            SizedBox(
              height: 46,
              child: FilledButton(
                onPressed: _addKeyword,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: const Text('添加', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ]),
      const SizedBox(height: 14),
      if (block.keywords.isEmpty)
        SizedBox(height: 240, child: EmptyView(text: '还没有屏蔽关键词'))
      else
        _card(scheme, [
          for (var i = 0; i < block.keywords.length; i++) ...[
            if (i > 0) Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.4)),
            _keywordRow(scheme, block.keywords[i]),
          ],
        ]),
      _note(scheme, '关键词屏蔽只在本机生效，用来挡住广告、拉群之类的回复。'),
    ];
  }

  Widget _keywordRow(ColorScheme scheme, String word) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(Icons.tag_rounded, size: 17, color: scheme.onSurfaceVariant),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              word,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500),
            ),
          ),
          IconButton(
            onPressed: () async {
              await BlockList.instance.removeKeyword(word);
              if (mounted) _toast('已取消屏蔽「$word」');
            },
            icon: const Icon(Icons.close_rounded, size: 18),
            visualDensity: VisualDensity.compact,
            tooltip: '取消屏蔽',
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------ 组件

  Widget _card(ColorScheme scheme, List<Widget> children) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
    );
  }

  Widget _hint(ColorScheme scheme, String text) {
    return Text(
      text,
      style: TextStyle(fontSize: 11.5, height: 1.7, color: scheme.onSurfaceVariant),
    );
  }

  Widget _note(ColorScheme scheme, String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 12, 6, 0),
      child: Text(
        text,
        style: TextStyle(fontSize: 11.5, height: 1.5, color: scheme.onSurfaceVariant),
      ),
    );
  }
}
