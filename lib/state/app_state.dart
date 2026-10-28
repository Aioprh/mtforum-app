import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/http_session.dart';
import '../data/forum_repository.dart';
import '../data/models.dart';

class AppState extends ChangeNotifier {
  AppState._();

  static final AppState instance = AppState._();

  static const String _themeKey = 'mt_forum_theme';
  static const String _themeSeedKey = 'mt_forum_theme_seed';
  static const String _floatingGlassNavKey = 'mt_forum_floating_glass_nav';
  static const String _autoSignInDateKey = 'mt_forum_auto_signin_date';
  bool _autoSignInRunning = false;
  String? _autoSignInAttemptDate;

  final ForumRepository repo = ForumRepository.instance;
  final HttpSession session = HttpSession.instance;

  ThemeMode themeMode = ThemeMode.system;
  Color themeSeedColor = const Color(0xFF607080);
  bool floatingGlassNav = false;
  UserProfile? profile;
  bool localReady = false;
  bool profileLoading = false;
  String? profileError;

  List<ForumCategory>? _boards;
  List<ThreadSummary>? _announcements;

  bool get isLoggedIn => session.hasLoginCookie;

  Future<void> bootstrapLocal() async {
    await repo.init();
    final prefs = await SharedPreferences.getInstance();
    final theme = prefs.getString(_themeKey);
    themeSeedColor = Color(prefs.getInt(_themeSeedKey) ?? 0xFF607080);
    floatingGlassNav = prefs.getBool(_floatingGlassNavKey) ?? false;
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
    final now = DateTime.now();
    final today =
        '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    if (_autoSignInAttemptDate == today) return;

    _autoSignInRunning = true;
    _autoSignInAttemptDate = today;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getString(_autoSignInDateKey) == today) return;
      await repo.signIn();
      await prefs.setString(_autoSignInDateKey, today);
    } catch (_) {
      // 静默失败，不打扰用户；未保存日期，下一次启动可重新尝试。
    } finally {
      _autoSignInRunning = false;
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
