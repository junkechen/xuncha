// lib/providers/settings_provider.dart
// 设置持久化服务 - 解决系统设置/通知设置/界面设置无反应问题

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/audio_service.dart';

class SettingsProvider extends ChangeNotifier {
  SharedPreferences? _prefs;
  bool _isLoaded = false;

  // ========== 通知设置 ==========
  bool _pushEnabled = true;
  bool _soundEnabled = true;
  bool _vibrateEnabled = false;

  // ========== 界面设置 ==========
  bool _darkMode = false;
  bool _largeFont = false;

  // ========== 数据设置 ==========
  bool _autoSync = true;
  bool _wifiSync = true;

  // ========== 消息通知设置 ==========
  bool _newIssueNotify = true;
  bool _overdueNotify = true;
  bool _auditNotify = true;
  bool _dailyReport = false;

  // ========== Getters ==========
  bool get isLoaded => _isLoaded;

  bool get pushEnabled => _pushEnabled;
  bool get soundEnabled => _soundEnabled;
  bool get vibrateEnabled => _vibrateEnabled;

  bool get darkMode => _darkMode;
  bool get largeFont => _largeFont;

  bool get autoSync => _autoSync;
  bool get wifiSync => _wifiSync;

  bool get newIssueNotify => _newIssueNotify;
  bool get overdueNotify => _overdueNotify;
  bool get auditNotify => _auditNotify;
  bool get dailyReport => _dailyReport;

  // ========== 初始化 ==========
  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    _loadSettings();
    _isLoaded = true;
    notifyListeners();
  }

  void _loadSettings() {
    if (_prefs == null) return;

    // 通知设置
    _pushEnabled = _prefs!.getBool('push_enabled') ?? true;
    _soundEnabled = _prefs!.getBool('sound_enabled') ?? true;
    _vibrateEnabled = _prefs!.getBool('vibrate_enabled') ?? false;

    // 界面设置
    _darkMode = _prefs!.getBool('dark_mode') ?? false;
    _largeFont = _prefs!.getBool('large_font') ?? false;

    // 数据设置
    _autoSync = _prefs!.getBool('auto_sync') ?? true;
    _wifiSync = _prefs!.getBool('wifi_sync') ?? true;

    // 消息通知设置
    _newIssueNotify = _prefs!.getBool('new_issue_notify') ?? true;
    _overdueNotify = _prefs!.getBool('overdue_notify') ?? true;
    _auditNotify = _prefs!.getBool('audit_notify') ?? true;
    _dailyReport = _prefs!.getBool('daily_report') ?? false;

    // 同步到 AudioService
    AudioService.instance.setSoundEnabled(_soundEnabled);
  }

  // ========== 通知设置方法 ==========
  void setPushEnabled(bool value) {
    _pushEnabled = value;
    _prefs?.setBool('push_enabled', value);
    notifyListeners();
  }

  void setSoundEnabled(bool value) {
    _soundEnabled = value;
    _prefs?.setBool('sound_enabled', value);
    AudioService.instance.setSoundEnabled(value);
    notifyListeners();
  }

  void setVibrateEnabled(bool value) {
    _vibrateEnabled = value;
    _prefs?.setBool('vibrate_enabled', value);
    notifyListeners();
  }

  // ========== 界面设置方法 ==========
  void setDarkMode(bool value) {
    _darkMode = value;
    _prefs?.setBool('dark_mode', value);
    notifyListeners();
  }

  void setLargeFont(bool value) {
    _largeFont = value;
    _prefs?.setBool('large_font', value);
    notifyListeners();
  }

  // ========== 数据设置方法 ==========
  void setAutoSync(bool value) {
    _autoSync = value;
    _prefs?.setBool('auto_sync', value);
    notifyListeners();
  }

  void setWifiSync(bool value) {
    _wifiSync = value;
    _prefs?.setBool('wifi_sync', value);
    notifyListeners();
  }

  // ========== 消息通知设置方法 ==========
  void setNewIssueNotify(bool value) {
    _newIssueNotify = value;
    _prefs?.setBool('new_issue_notify', value);
    notifyListeners();
  }

  void setOverdueNotify(bool value) {
    _overdueNotify = value;
    _prefs?.setBool('overdue_notify', value);
    notifyListeners();
  }

  void setAuditNotify(bool value) {
    _auditNotify = value;
    _prefs?.setBool('audit_notify', value);
    notifyListeners();
  }

  void setDailyReport(bool value) {
    _dailyReport = value;
    _prefs?.setBool('daily_report', value);
    notifyListeners();
  }

  // ========== 批量保存（系统设置） ==========
  Future<void> saveSystemSettings({
    bool? pushEnabled,
    bool? soundEnabled,
    bool? vibrateEnabled,
    bool? darkMode,
    bool? largeFont,
    bool? autoSync,
    bool? wifiSync,
  }) async {
    if (pushEnabled != null) {
      _pushEnabled = pushEnabled;
      await _prefs?.setBool('push_enabled', pushEnabled);
    }
    if (soundEnabled != null) {
      _soundEnabled = soundEnabled;
      await _prefs?.setBool('sound_enabled', soundEnabled);
      AudioService.instance.setSoundEnabled(soundEnabled);
    }
    if (vibrateEnabled != null) {
      _vibrateEnabled = vibrateEnabled;
      await _prefs?.setBool('vibrate_enabled', vibrateEnabled);
    }
    if (darkMode != null) {
      _darkMode = darkMode;
      await _prefs?.setBool('dark_mode', darkMode);
    }
    if (largeFont != null) {
      _largeFont = largeFont;
      await _prefs?.setBool('large_font', largeFont);
    }
    if (autoSync != null) {
      _autoSync = autoSync;
      await _prefs?.setBool('auto_sync', autoSync);
    }
    if (wifiSync != null) {
      _wifiSync = wifiSync;
      await _prefs?.setBool('wifi_sync', wifiSync);
    }
    notifyListeners();
  }

  // ========== 批量保存（消息通知设置） ==========
  Future<void> saveNotificationSettings({
    bool? newIssueNotify,
    bool? overdueNotify,
    bool? auditNotify,
    bool? dailyReport,
  }) async {
    if (newIssueNotify != null) {
      _newIssueNotify = newIssueNotify;
      await _prefs?.setBool('new_issue_notify', newIssueNotify);
    }
    if (overdueNotify != null) {
      _overdueNotify = overdueNotify;
      await _prefs?.setBool('overdue_notify', overdueNotify);
    }
    if (auditNotify != null) {
      _auditNotify = auditNotify;
      await _prefs?.setBool('audit_notify', auditNotify);
    }
    if (dailyReport != null) {
      _dailyReport = dailyReport;
      await _prefs?.setBool('daily_report', dailyReport);
    }
    notifyListeners();
  }
}
