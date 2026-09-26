import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'downloader_config.dart';
import 'downloader_models.dart';
import 'downloader_service.dart';
import '../storage/storage_service.dart';

/// 限速调度器
///
/// 按时间段规则自动切换 qBittorrent 全局下载/上传限速。
/// 本地实现（不依赖 qB 原生 scheduler），规则存储于 SharedPreferences。
class SpeedSchedulerService {
  SpeedSchedulerService._();

  static final SpeedSchedulerService instance = SpeedSchedulerService._();

  static const String _prefsKey = 'downloader.speedSchedule.v1';
  static const String _enabledKey = 'downloader.speedScheduleEnabled.v1';

  Timer? _timer;
  bool _running = false;
  SpeedScheduleEntry? _lastApplied;

  // 最近一次应用的规则（供 UI 展示）
  SpeedScheduleEntry? lastAppliedEntry;
  DateTime? lastAppliedAt;

  /// 读取调度规则
  Future<List<SpeedScheduleEntry>> loadSchedule() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = (jsonDecode(raw) as List)
          .map((e) => SpeedScheduleEntry.fromJson(e as Map<String, dynamic>))
          .toList();
      return list;
    } catch (_) {
      return [];
    }
  }

  /// 保存调度规则
  Future<void> saveSchedule(List<SpeedScheduleEntry> entries) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefsKey,
      jsonEncode(entries.map((e) => e.toJson()).toList()),
    );
  }

  /// 调度开关
  Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_enabledKey) ?? false;
  }

  Future<void> setEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, enabled);
  }

  /// 启动调度（应用启动时调用）
  void start() {
    if (_running) return;
    _running = true;
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      unawaited(_tick());
    });
    unawaited(_tick());
  }

  void stop() {
    _running = false;
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _tick() async {
    try {
      final enabled = await isEnabled();
      if (!enabled) return;

      final schedule = await loadSchedule();
      if (schedule.isEmpty) return;

      // 获取默认下载器
      final defId = await StorageService.instance.loadDefaultDownloaderId();
      if (defId == null) return;
      final configMaps = await StorageService.instance.loadDownloaderConfigs();
      if (configMaps.isEmpty) return;
      final configMap = configMaps.firstWhere(
        (c) => c['id'] == defId,
        orElse: () => configMaps.first,
      );
      final config = DownloaderConfig.fromJson(configMap);
      if (config.type != DownloaderType.qbittorrent) return;

      final password = await StorageService.instance.loadDownloaderPassword(
        config.id,
      );
      if ((password ?? '').isEmpty) return;

      final now = DateTime.now();
      final weekday = now.weekday; // 1=周一 ... 7=周日
      final minuteOfDay = now.hour * 60 + now.minute;

      // 找到当前生效的规则
      SpeedScheduleEntry? active;
      for (final entry in schedule) {
        if (entry.covers(weekday, minuteOfDay)) {
          active = entry;
          break;
        }
      }

      if (active == null) return; // 当前无规则，不动限速

      // 与上次应用相同则跳过
      if (_lastApplied != null &&
          _sameEntry(_lastApplied!, active)) {
        return;
      }

      final client = DownloaderService.instance.getClient(
        config: config,
        password: password!,
      ) as dynamic;

      await client.setGlobalDownloadLimit(active.dlLimitKib);
      await client.setGlobalUploadLimit(active.upLimitKib);

      _lastApplied = active;
      lastAppliedEntry = active;
      lastAppliedAt = DateTime.now();

      if (kDebugMode) {
        debugPrint(
          '⏱ 限速调度应用: DL=${active.dlLimitKib}KiB/s UP=${active.upLimitKib}KiB/s @${now.hour}:${now.minute}',
        );
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('⏱ 限速调度失败: $e');
      }
    }
  }

  bool _sameEntry(SpeedScheduleEntry a, SpeedScheduleEntry b) {
    return a.dlLimitKib == b.dlLimitKib && a.upLimitKib == b.upLimitKib;
  }
}
