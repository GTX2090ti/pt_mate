import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'downloader_config.dart';
import 'downloader_models.dart';
import 'downloader_service.dart';
import '../storage/storage_service.dart';

/// 做种健康度监控
///
/// 定期检查已完成任务：当分享率与做种时间达到配置阈值时标记为"可删种"，
/// 并在任务页健康度面板展示。qBittorrent 原生接口会返回这些字段，
/// 我们基于 /torrents/info 数据本地计算。
class SeedHealthMonitor {
  SeedHealthMonitor._();

  static final SeedHealthMonitor instance = SeedHealthMonitor._();

  static const String _configKey = 'downloader.seedHealthConfig.v1';

  Timer? _timer;

  /// 启动监控（应用启动时调用）
  void start() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(minutes: 2), (_) {
      unawaited(_checkOnce());
    });
    unawaited(_checkOnce());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// 读取健康度配置
  Future<SeedHealthConfig> loadConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_configKey);
    if (raw == null || raw.isEmpty) return const SeedHealthConfig();
    try {
      return SeedHealthConfig.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (_) {
      return const SeedHealthConfig();
    }
  }

  /// 保存健康度配置
  Future<void> saveConfig(SeedHealthConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_configKey, jsonEncode(config.toJson()));
  }

  /// 对任务列表计算健康度
  ///
  /// 返回"已达可删种标准"的任务（已完成 + 做种时长达标 + 分享率达标）。
  /// [tasks] 来自 qBittorrent /torrents/info
  /// [config] 健康度配置
  static List<DownloadTask> findReadyToDelete(
    List<DownloadTask> tasks,
    SeedHealthConfig config,
  ) {
    if (!config.enabled) return [];
    final result = <DownloadTask>[];
    for (final task in tasks) {
      // 仅已完成
      if (task.progress < 1.0) continue;
      // 做种时间（秒）-> 分钟
      final seedMinutes = task.timeActive / 60;
      final ratioOk = task.ratio >= config.minRatio;
      final timeOk = seedMinutes >= config.minSeedMinutes;
      if (ratioOk && timeOk) {
        result.add(task);
      }
    }
    return result;
  }

  Future<void> _checkOnce() async {
    try {
      final config = await loadConfig();
      if (!config.enabled) return;

      final defId = await StorageService.instance.loadDefaultDownloaderId();
      if (defId == null) return;
      final configMaps = await StorageService.instance.loadDownloaderConfigs();
      if (configMaps.isEmpty) return;
      final configMap = configMaps.firstWhere(
        (c) => c['id'] == defId,
        orElse: () => configMaps.first,
      );
      final downloaderConfig = DownloaderConfig.fromJson(configMap);
      if (downloaderConfig.type != DownloaderType.qbittorrent) return;

      final password = await StorageService.instance.loadDownloaderPassword(
        downloaderConfig.id,
      );
      if ((password ?? '').isEmpty) return;

      final client = DownloaderService.instance.getClient(
        config: downloaderConfig,
        password: password!,
      );
      final tasks = await client.getTasks() as List<DownloadTask>;
      final ready = findReadyToDelete(tasks, config);

      if (kDebugMode && ready.isNotEmpty) {
        debugPrint(
          '🌱 健康度检查: ${ready.length} 个任务已达可删种标准（${ready.map((t) => t.name).take(3).join(', ')}）',
        );
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('🌱 健康度检查失败: $e');
      }
    }
  }
}
