import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/http_session.dart';
import '../core/sign_in_status.dart';
import '../data/forum_repository.dart';
import '../data/models.dart';

class AppState extends ChangeNotifier {
  AppState._();

  static final AppState instance = AppState._();

  static const String _themeKey = 'mt_forum_theme';
  static const String _themeSeedKey = 'mt_forum_theme_seed';
  static const String _floatingGlassNavKey = 'mt_forum_floating_glass_nav';
  static const String _floatingGlassNavOpacityKey = 'mt_forum_floating_glass_nav_opacity';
  static const String _floatingGlassNavBlurKey = 'mt_forum_floating_glass_nav_blur';
  static const String _composeGlassOpacityKey = 'mt_forum_compose_glass_opacity';
  static const String _composeGlassBlurKey = 'mt_forum_compose_glass_blur';
  static const String _autoSignInDateKey = 'mt_forum_auto_signin_date';
  bool _autoSignInRunning = false;
  String? _autoSignInAttemptDate;

  /// 已确认签到成功的自然日（本地缓存），配合 [signedInToday] 给「我的」卡片用。
  String? _signInDay;

  /// 手动签到进行中，用来在卡片上转圈、防连点。
  bool signingIn = false;

  final ForumRepository repo = ForumRepository.instance;
  final HttpSession session = HttpSession.instance;

  ThemeMode themeMode = ThemeMode.system;
  Color themeSeedColor = const Color(0xFF607080);
  bool floatingGlassNav = false;
  double floatingGlassNavOpacity = 0.25;
  double floatingGlassNavBlur = 30.0;

  /// 发帖悬浮按钮的液态玻璃外观：透明度与背景模糊度。
  double composeGlassOpacity = 0.28;
  double composeGlassBlur = 26.0;
  UserProfile? profile;
  bool localReady = false;
  bool profileLoading = false;
  String? profileError;

  List<ForumCategory>? _boards;
  List<ThreadSummary>? _announcements;

  bool get isLoggedIn => session.hasLoginCookie;

  /// 今天是否已经签到。未登录时没有意义，卡片也不显示。
  bool get signedInToday => signedInOn(_signInDay, DateTime.now());

  Future<void> bootstrapLocal() async {
    await repo.init();
    final prefs = await SharedPreferences.getInstance();
    final theme = prefs.getString(_themeKey);
    themeSeedColor = Color(prefs.getInt(_themeSeedKey) ?? 0xFF607080);
    floatingGlassNav = prefs.getBool(_floatingGlassNavKey) ?? false;
    floatingGlassNavOpacity = (prefs.getDouble(_floatingGlassNavOpacityKey) ?? 0.25).clamp(0.05, 0.65).toDouble();
    floatingGlassNavBlur = (prefs.getDouble(_floatingGlassNavBlurKey) ?? 30.0).clamp(0.0, 40.0).toDouble();
    composeGlassOpacity = (prefs.getDouble(_composeGlassOpacityKey) ?? 0.28).clamp(0.05, 0.75).toDouble();
    composeGlassBlur = (prefs.getDouble(_composeGlassBlurKey) ?? 26.0).clamp(0.0, 40.0).toDouble();
    _signInDay = prefs.getString(_autoSignInDateKey);
    themeMode = switch (theme) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
    localReady = true;
    notifyListeners();
    if (isLoggedIn) {
      refreshProfile();
      // 不阻塞首屏；同一自然日成功后持久化日期，重复打开不会重复签到。
      autoSignInOncePerDay();
    }
  }

  /// 登录状态下每日最多自动签到一次。仅在成功（含服务端提示已签到）后记录日期；
  /// 网络失败时不写入日期，下一次启动仍可重试。整个过程不展示提示。
  Future<void> autoSignInOncePerDay() async {
    if (!isLoggedIn || _autoSignInRunning) return;
    final today = signInDayKey(DateTime.now());
    if (_autoSignInAttemptDate == today) return;

    _autoSignInRunning = true;
    _autoSignInAttemptDate = today;
    try {
      final prefs = await SharedPreferences.getInstance();
      // 本地已经有今天的记录：直接认，不必再打一次接口。
      _signInDay ??= prefs.getString(_autoSignInDateKey);
      if (_signInDay == today) {
        notifyListeners();
        return;
      }
      await repo.signIn();
      _signInDay = today;
      await prefs.setString(_autoSignInDateKey, today);
      // 卡片上的「今日未签到」要跟着翻成「已签到」。
      notifyListeners();
    } catch (_) {
      // 静默失败，不打扰用户；未保存日期，下一次启动可重新尝试。
    } finally {
      _autoSignInRunning = false;
    }
  }

  /// 手动签到。返回给用户的提示文案；返回 null 表示正在签到、忽略这次点击。
  Future<String?> signInNow() async {
    if (!isLoggedIn) return '请先登录后再签到';
    if (signedInToday) return '今天已经签过到了';
    if (_autoSignInRunning) return '正在签到，稍等一下';
    if (signingIn) return null;

    signingIn = true;
    notifyListeners();
    try {
      final message = await repo.signIn();
      final today = signInDayKey(DateTime.now());
      _signInDay = today;
      _autoSignInAttemptDate = today;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_autoSignInDateKey, today);
      return message;
    } on SiteException catch (e) {
      return e.message;
    } catch (_) {
      return '签到失败，请稍后重试';
    } finally {
      signingIn = false;
      notifyListeners();
    }
  }

  Future<void> refreshProfile({bool silent = true}) async {
    if (!isLoggedIn) {
      profile = null;
      return;
    }
    profileLoading = true;
    if (!silent) notifyListeners();
    try {
      profile = await repo.fetchMyProfile(fallbackName: profile?.username ?? '');
      profileError = null;
    } on SiteException catch (e) {
      profileError = e.message;
      if (e.message.contains('登录') && e.message.contains('失效')) {
        await repo.logout();
        profile = null;
      }
    } catch (_) {
      profileError = '个人资料加载失败';
    } finally {
      profileLoading = false;
      notifyListeners();
    }
  }

  Future<UserProfile> login(String username, String password, {int questionId = 0, String answer = ''}) async {
    final user = await repo.login(username, password, questionId: questionId, answer: answer);
    profile = user;
    profileError = null;
    _boards = null;
    notifyListeners();
    autoSignInOncePerDay();
    return user;
  }

  Future<void> logout() async {
    await repo.logout();
    profile = null;
    profileError = null;
    _announcements = null;
    // 签到是按账号算的，换号后不能沿用上一个人的「今天已签到」。
    _signInDay = null;
    _autoSignInAttemptDate = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_autoSignInDateKey);
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    themeMode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeKey, switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
    });
  }

  Future<void> setFloatingGlassNav(bool enabled) async {
    floatingGlassNav = enabled;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_floatingGlassNavKey, enabled);
  }

  Future<void> setFloatingGlassNavAppearance({required double opacity, required double blur}) async {
    floatingGlassNavOpacity = opacity.clamp(0.05, 0.65).toDouble();
    floatingGlassNavBlur = blur.clamp(0.0, 40.0).toDouble();
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_floatingGlassNavOpacityKey, floatingGlassNavOpacity);
    await prefs.setDouble(_floatingGlassNavBlurKey, floatingGlassNavBlur);
  }

  /// 调整发帖悬浮按钮的玻璃透明度与模糊度并持久化。
  Future<void> setComposeGlassAppearance({required double opacity, required double blur}) async {
    composeGlassOpacity = opacity.clamp(0.05, 0.75).toDouble();
    composeGlassBlur = blur.clamp(0.0, 40.0).toDouble();
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_composeGlassOpacityKey, composeGlassOpacity);
    await prefs.setDouble(_composeGlassBlurKey, composeGlassBlur);
  }

  Future<void> setThemeSeedColor(Color color) async {
    themeSeedColor = color;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_themeSeedKey, color.toARGB32());
  }

  Future<List<ForumCategory>> boards({bool force = false}) async {
    if (!force && _boards != null) return _boards!;
    final value = await repo.fetchBoards();
    _boards = value;
    return value;
  }

  Future<List<ThreadSummary>> announcements({bool force = false}) async {
    if (!force && _announcements != null) return _announcements!;
    final value = await repo.fetchAnnouncements();
    _announcements = value;
    return value;
  }
}
