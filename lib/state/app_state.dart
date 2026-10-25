import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/http_session.dart';
import '../data/forum_repository.dart';
import '../data/models.dart';

class AppState extends ChangeNotifier {
  AppState._();

  static final AppState instance = AppState._();

  static const String _themeKey = 'mt_forum_theme';

  final ForumRepository repo = ForumRepository.instance;
  final HttpSession session = HttpSession.instance;

  ThemeMode themeMode = ThemeMode.system;
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
    themeMode = switch (theme) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
    localReady = true;
    notifyListeners();
    if (isLoggedIn) {
      refreshProfile();
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
