import 'package:flutter/material.dart';

import '../../core/http_session.dart';
import '../../data/models.dart';
import '../../state/app_state.dart';
import '../widgets/glass_app_bar.dart';
import '../widgets/glass_controls.dart';
import '../widgets/state_views.dart';
import 'region_picker_sheet.dart';

/// 资料设置：基本资料 / 联系方式 / 个人信息。
///
/// 这三块在原站是 `home.php?mod=spacecp&ac=profile` 下的三个 op，共用同一张
/// 表单模板。这里做成三个分段、各自独立保存——改个签名不用连带把联系方式
/// 一起提交，出错时影响面也小。
///
/// 每个字段都带一个可见范围（Discuz 的 `privacy[字段]`），原站把它做成输入框
/// 右侧的小下拉；这里保持同样的位置，点开是玻璃浮层。
class ProfileSettingsPage extends StatefulWidget {
  const ProfileSettingsPage({super.key});

  @override
  State<ProfileSettingsPage> createState() => _ProfileSettingsPageState();
}

class _ProfileSettingsPageState extends State<ProfileSettingsPage> {
  static const List<(int, String)> _tabs = [
    (0, '基本资料'),
    (1, '联系方式'),
    (2, '个人信息'),
  ];

  static const List<(String, String)> _privacyOptions = [
    ('0', '公开'),
    ('1', '好友可见'),
    ('3', '保密'),
  ];

  static const List<(int, String)> _genderOptions = [
    (0, '保密'),
    (1, '男'),
    (2, '女'),
  ];

  final _occupation = TextEditingController();
  final _realname = TextEditingController();
  final _qq = TextEditingController();
  final _mobile = TextEditingController();
  final _bio = TextEditingController();
  final _customStatus = TextEditingController();
  final _signature = TextEditingController();

  ProfileBaseSettings? _base;
  ProfileContactSettings? _contact;
  ProfileInfoSettings? _info;

  final Map<String, String> _basePrivacy = {};
  final Map<String, String> _contactPrivacy = {};
  final Map<String, String> _infoPrivacy = {};

  int _tab = 0;
  int _gender = 0;
  String _birthYear = '';
  String _birthMonth = '';
  String _birthDay = '';

  /// 居住地四个字段。页面上的地址串只是它们的拼接结果，提交时按字段走，
  /// 免得跟老代码一样靠空格去猜哪一段是省、哪一段是区。
  /// 页面显示的那一行地址；跟四个字段分开存，清除时才能一起清干净。
  String _resideText = '';
  String _resideProvince = '';
  String _resideCity = '';
  String _resideDist = '';
  String _resideCommunity = '';

  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _occupation.dispose();
    _realname.dispose();
    _qq.dispose();
    _mobile.dispose();
    _bio.dispose();
    _customStatus.dispose();
    _signature.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!AppState.instance.isLoggedIn) {
      setState(() {
        _loading = false;
        _error = '登录后才能修改资料';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repo = AppState.instance.repo;
      final results = await Future.wait<Object>([
        repo.fetchProfileBase(),
        repo.fetchProfileContact(),
        repo.fetchProfileInfo(),
      ]);
      if (!mounted) return;
      final base = results[0] as ProfileBaseSettings;
      final contact = results[1] as ProfileContactSettings;
      final info = results[2] as ProfileInfoSettings;
      setState(() {
        _base = base;
        _contact = contact;
        _info = info;
        _basePrivacy
          ..clear()
          ..addAll(base.privacy);
        _contactPrivacy
          ..clear()
          ..addAll(contact.privacy);
        _infoPrivacy
          ..clear()
          ..addAll(info.privacy);
        _gender = base.gender;
        _birthYear = base.birthYear;
        _birthMonth = base.birthMonth;
        _birthDay = base.birthDay;
        _resideText = base.resideText;
        _resideProvince = base.resideProvince;
        _resideCity = base.resideCity;
        _resideDist = base.resideDist;
        _resideCommunity = base.resideCommunity;
        _occupation.text = base.occupation;
        _realname.text = base.realname;
        _qq.text = contact.qq;
        _mobile.text = contact.mobile;
        _bio.text = info.bio;
        _customStatus.text = info.customStatus;
        _signature.text = info.signature;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _message(e);
      });
    }
  }

  String _message(Object error) => error is SiteException ? error.message : '$error';

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _save() async {
    if (_saving) return;
    FocusScope.of(context).unfocus();
    setState(() => _saving = true);
    try {
      final repo = AppState.instance.repo;
      final message = switch (_tab) {
        0 => await repo.saveProfileBase(
            _base!.copyWith(
              occupation: _occupation.text.trim(),
              realname: _realname.text.trim(),
              gender: _gender,
              birthYear: _birthYear,
              birthMonth: _birthMonth,
              birthDay: _birthDay,
              resideText: _resideText,
              resideProvince: _resideProvince,
              resideCity: _resideCity,
              resideDist: _resideDist,
              resideCommunity: _resideCommunity,
              privacy: Map<String, String>.from(_basePrivacy),
            ),
          ),
        1 => await repo.saveProfileContact(
            _contact!.copyWith(
              qq: _qq.text.trim(),
              mobile: _mobile.text.trim(),
              privacy: Map<String, String>.from(_contactPrivacy),
            ),
          ),
        _ => await repo.saveProfileInfo(
            _info!.copyWith(
              bio: _bio.text,
              customStatus: _customStatus.text.trim(),
              signature: _signature.text,
              privacy: Map<String, String>.from(_infoPrivacy),
            ),
          ),
      };
      _toast(message);
      // 头衔、签名会出现在个人卡上，保存后顺手刷新，免得回去还是旧的。
      AppState.instance.refreshProfile(silent: true);
      await _load();
    } catch (e) {
      _toast(_message(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickPrivacy(String field, Map<String, String> holder) async {
    final picked = await showGlassOptionSheet<String>(
      context,
      title: '谁可以看',
      options: _privacyOptions,
      selected: holder[field] ?? '0',
    );
    if (!mounted || picked == null) return;
    setState(() => holder[field] = picked);
  }

  Future<void> _pickGender() async {
    final picked = await showGlassOptionSheet<int>(
      context,
      title: '性别',
      options: _genderOptions,
      selected: _gender,
    );
    if (!mounted || picked == null) return;
    setState(() => _gender = picked);
  }

  Future<void> _pickBirthday() async {
    final now = DateTime.now();
    final years = <(String, String)>[
      ('', '不填'),
      for (var y = now.year; y >= now.year - 100; y--) ('$y', '$y 年'),
    ];
    final year = await showGlassOptionSheet<String>(
      context,
      title: '出生年份',
      options: years,
      selected: _birthYear,
    );
    if (!mounted || year == null) return;

    final months = <(String, String)>[
      ('', '不填'),
      for (var m = 1; m <= 12; m++) ('$m', '$m 月'),
    ];
    final month = await showGlassOptionSheet<String>(
      context,
      title: '出生月份',
      options: months,
      selected: _birthMonth,
    );
    if (!mounted || month == null) return;

    final days = <(String, String)>[
      ('', '不填'),
      for (var d = 1; d <= 31; d++) ('$d', '$d 日'),
    ];
    final day = await showGlassOptionSheet<String>(
      context,
      title: '出生日期',
      options: days,
      selected: _birthDay,
    );
    if (!mounted || day == null) return;
    setState(() {
      _birthYear = year;
      _birthMonth = month;
      _birthDay = day;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: const GlassAppBar(title: Text('资料设置')),
      body: SafeArea(
        top: false,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? ErrorView(message: _error!, onRetry: _load)
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
                      if (_tab == 0) ..._baseFields(scheme),
                      if (_tab == 1) ..._contactFields(scheme),
                      if (_tab == 2) ..._infoFields(scheme),
                      const SizedBox(height: 22),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: _saving ? null : _save,
                          child: _saving
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Text('保存'),
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }

  // ------------------------------------------------------------ 基本资料

  List<Widget> _baseFields(ColorScheme scheme) {
    return [
      _card(scheme, [
        _field(
          scheme,
          label: '职业',
          controller: _occupation,
          privacyField: 'occupation',
          privacy: _basePrivacy,
          hint: '例如：学生、程序员',
        ),
        _genderRow(scheme),
        _birthdayRow(scheme),
        _regionRow(scheme),
        _field(
          scheme,
          label: '真实姓名',
          controller: _realname,
          privacyField: 'realname',
          privacy: _basePrivacy,
          hint: '仅用于站点实名场景',
        ),
      ]),
      _note(scheme, '居住地按站点地区库选择省 / 市 / 区，选完记得保存；街道信息请到网页版填写。'),
    ];
  }

  Widget _genderRow(ColorScheme scheme) {
    final label = _genderOptions.firstWhere((o) => o.$1 == _gender).$2;
    return _labelled(
      scheme,
      label: '性别',
      privacyField: 'gender',
      privacy: _basePrivacy,
      child: GlassSelectRow(value: label, onTap: _pickGender, leading: Icons.wc_rounded),
    );
  }

  Widget _birthdayRow(ColorScheme scheme) {
    final text = _birthYear.isEmpty
        ? ''
        : '$_birthYear-${_birthMonth.padLeft(2, '0')}-${_birthDay.padLeft(2, '0')}';
    return _labelled(
      scheme,
      label: '生日',
      privacyField: 'birthday',
      privacy: _basePrivacy,
      child: GlassSelectRow(
        value: text,
        placeholder: '未设置',
        leading: Icons.cake_outlined,
        onTap: _pickBirthday,
      ),
    );
  }

  Widget _regionRow(ColorScheme scheme) {
    return _labelled(
      scheme,
      label: '居住地',
      privacyField: 'residecity',
      privacy: _basePrivacy,
      child: GlassSelectRow(
        value: _resideText,
        placeholder: '未设置',
        leading: Icons.place_outlined,
        onTap: _pickRegion,
      ),
    );
  }

  Future<void> _pickRegion() async {
    final repo = AppState.instance.repo;
    final picked = await RegionPickerSheet.show(
      context,
      loader: ({int provinceId = 0, int cityId = 0}) =>
          repo.fetchRegions(provinceId: provinceId, cityId: cityId),
      province: _resideProvince,
      city: _resideCity,
      dist: _resideDist,
    );
    if (!mounted || picked == null) return;
    setState(() {
      _resideProvince = picked.province;
      _resideCity = picked.city;
      _resideDist = picked.dist;
      _resideCommunity = '';
      _resideText = picked.text;
    });
  }

  // ------------------------------------------------------------ 联系方式

  List<Widget> _contactFields(ColorScheme scheme) {
    final contact = _contact!;
    return [
      _card(scheme, [
        _field(
          scheme,
          label: 'QQ',
          controller: _qq,
          privacyField: 'qq',
          privacy: _contactPrivacy,
          hint: '填写 QQ 号',
          keyboardType: TextInputType.number,
        ),
        _field(
          scheme,
          label: '手机',
          controller: _mobile,
          privacyField: 'mobile',
          privacy: _contactPrivacy,
          hint: '填写手机号',
          keyboardType: TextInputType.phone,
        ),
        _labelled(
          scheme,
          label: '邮箱',
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(13, 13, 13, 13),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.4)),
            ),
            child: Text(
              contact.email.isEmpty ? '未绑定' : contact.email,
              style: TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w500,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ]),
      _note(scheme, '邮箱是账号凭据，站点只允许在「密码安全」页修改，App 内暂不提供。'),
    ];
  }

  // ------------------------------------------------------------ 个人信息

  List<Widget> _infoFields(ColorScheme scheme) {
    return [
      _card(scheme, [
        _field(
          scheme,
          label: '自我介绍',
          controller: _bio,
          privacyField: 'bio',
          privacy: _infoPrivacy,
          hint: '介绍一下自己',
          maxLines: 4,
          maxLength: 500,
        ),
        _labelled(
          scheme,
          label: '自定头衔',
          child: GlassField(
            controller: _customStatus,
            hintText: '显示在用户名下方，留空则显示用户组',
            maxLength: 30,
          ),
        ),
        _labelled(
          scheme,
          label: '个人签名',
          child: GlassField(
            controller: _signature,
            hintText: '支持 [b] [color] [img] 等 Discuz 代码',
            minLines: 3,
            maxLines: 6,
            maxLength: 300,
          ),
        ),
      ]),
      _note(scheme, '签名会出现在每个楼层下方，长度受用户组限制。'),
    ];
  }

  // ------------------------------------------------------------ 组件

  Widget _card(ColorScheme scheme, List<Widget> children) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 16),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(height: 16),
            children[i],
          ],
        ],
      ),
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

  Widget _field(
    ColorScheme scheme, {
    required String label,
    required TextEditingController controller,
    required Map<String, String> privacy,
    String? privacyField,
    String? hint,
    int maxLines = 1,
    int? maxLength,
    TextInputType? keyboardType,
  }) {
    return _labelled(
      scheme,
      label: label,
      privacyField: privacyField,
      privacy: privacy,
      child: GlassField(
        controller: controller,
        hintText: hint,
        minLines: maxLines > 1 ? maxLines : 1,
        maxLines: maxLines,
        maxLength: maxLength,
        keyboardType: keyboardType,
      ),
    );
  }

  Widget _labelled(
    ColorScheme scheme, {
    required String label,
    required Widget child,
    String? privacyField,
    Map<String, String>? privacy,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: scheme.onSurfaceVariant.withValues(alpha: 0.9),
              ),
            ),
            const Spacer(),
            if (privacyField != null && privacy != null)
              _privacyChip(scheme, privacyField, privacy),
          ],
        ),
        const SizedBox(height: 7),
        child,
      ],
    );
  }

  Widget _privacyChip(ColorScheme scheme, String field, Map<String, String> holder) {
    final value = holder[field] ?? '0';
    final label = _privacyOptions.firstWhere(
      (o) => o.$1 == value,
      orElse: () => _privacyOptions.first,
    ).$2;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => _pickPrivacy(field, holder),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.visibility_outlined, size: 13, color: scheme.primary),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: scheme.primary),
            ),
            Icon(Icons.expand_more_rounded, size: 14, color: scheme.primary),
          ],
        ),
      ),
    );
  }
}
