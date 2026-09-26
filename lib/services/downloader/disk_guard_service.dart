import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../utils/format.dart';
import 'downloader_models.dart';

/// 磁盘空间守卫
///
/// 1. 下载前检查：添加任务时校验剩余空间是否足够（含预留空间）。
/// 2. 空间预警：任务页刷新时显示剩余空间状态。
class DiskGuardService {
  DiskGuardService._();

  static final DiskGuardService instance = DiskGuardService._();

  static const String _configKey = 'downloader.diskGuardConfig.v1';

  /// 读取磁盘守卫配置
  Future<DiskGuardConfig> loadConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_configKey);
    if (raw == null || raw.isEmpty) return const DiskGuardConfig();
    try {
      return DiskGuardConfig.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (_) {
      return const DiskGuardConfig();
    }
  }

  /// 保存磁盘守卫配置
  Future<void> saveConfig(DiskGuardConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_configKey, jsonEncode(config.toJson()));
  }

  /// 判断剩余空间是否触发预警
  bool isWarning(int freeSpaceBytes, DiskGuardConfig config) {
    if (!config.enabled) return false;
    return freeSpaceBytes < config.warnThresholdBytes;
  }

  /// 下载前检查：剩余空间是否足够容纳 [downloadSizeBytes]
  ///
  /// 返回 null 表示允许；否则返回失败原因字符串。
  Future<String?> checkBeforeDownload({
    required int freeSpaceBytes,
    required int downloadSizeBytes,
    DiskGuardConfig? config,
  }) async {
    final effective = config ?? await loadConfig();
    if (!effective.checkBeforeAdd) return null;
    final needed = downloadSizeBytes + effective.reserveBytes;
    if (freeSpaceBytes < needed) {
      return '磁盘空间不足：剩余 ${_fmt(freeSpaceBytes)}，需要 ${_fmt(needed)}（含预留 ${_fmt(effective.reserveBytes)}）';
    }
    return null;
  }

  static String _fmt(int bytes) {
    return FormatUtil.formatFileSize(bytes);
  }
}
