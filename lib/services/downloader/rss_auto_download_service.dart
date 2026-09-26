import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'downloader_config.dart';
import 'downloader_models.dart';
import 'downloader_service.dart';
import '../storage/storage_service.dart';

/// RSS 自动下载联动服务
///
/// 基于 qBittorrent 原生 RSS 能力：管理订阅源、自动下载规则，
/// 并支持"一键把当前任务页匹配 RSS 标题"与手动刷新。
/// 规则直接写入 qB 的 /rss/setRule，由 qB 服务端自动执行下载。
class RssAutoDownloadService {
  RssAutoDownloadService._();

  static final RssAutoDownloadService instance = RssAutoDownloadService._();

  static const String _localRuleBackupKey = 'downloader.rssRulesBackup.v1';

  /// 获取默认下载器的 client（null 表示未配置）
  Future<dynamic> _client() async {
    final defId = await StorageService.instance.loadDefaultDownloaderId();
    if (defId == null) return null;
    final configMaps = await StorageService.instance.loadDownloaderConfigs();
    if (configMaps.isEmpty) return null;
    final configMap = configMaps.firstWhere(
      (c) => c['id'] == defId,
      orElse: () => configMaps.first,
    );
    final config = DownloaderConfig.fromJson(configMap);
    if (config.type != DownloaderType.qbittorrent) return null;
    final password = await StorageService.instance.loadDownloaderPassword(
      config.id,
    );
    if ((password ?? '').isEmpty) return null;
    return DownloaderService.instance.getClient(
      config: config,
      password: password!,
    );
  }

  /// 添加 RSS 订阅源
  Future<void> addFeed(String url) async {
    final client = await _client();
    if (client == null) throw StateError('未配置 qBittorrent 下载器');
    await client.addRssFeed(url);
  }

  /// 获取订阅源列表
  Future<List<RssFeed>> getFeeds() async {
    final client = await _client();
    if (client == null) return [];
    return await client.getRssFeeds() as List<RssFeed>;
  }

  /// 获取 RSS 文章
  Future<List<RssArticle>> getItems() async {
    final client = await _client();
    if (client == null) return [];
    return await client.getRssItems() as List<RssArticle>;
  }

  /// 刷新 RSS
  Future<void> refresh(String itemPath) async {
    final client = await _client();
    if (client == null) return;
    await client.refreshRssItem(itemPath);
  }

  /// 获取规则列表
  Future<List<RssRule>> getRules() async {
    final client = await _client();
    if (client == null) return [];
    final rules = await client.getRssRules() as List<RssRule>;
    // 备份到本地，便于 UI 显示
    await _backupLocal(rules);
    return rules;
  }

  /// 保存规则（新增或更新）
  Future<void> saveRule(RssRule rule) async {
    final client = await _client();
    if (client == null) throw StateError('未配置 qBittorrent 下载器');
    await client.setRssRule(rule.name, rule);
  }

  /// 删除规则
  Future<void> removeRule(String name) async {
    final client = await _client();
    if (client == null) throw StateError('未配置 qBittorrent 下载器');
    await client.removeRssRule(name);
  }

  Future<void> _backupLocal(List<RssRule> rules) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _localRuleBackupKey,
      jsonEncode(
        rules
            .map(
              (r) => {'name': r.name, ...r.toRuleJson()},
            )
            .toList(),
      ),
    );
  }

  /// 读取本地备份规则（qB 不可达时展示用）
  Future<List<RssRule>> getLocalBackup() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_localRuleBackupKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list.map((e) {
        final map = e as Map<String, dynamic>;
        final name = map['name'] as String? ?? '';
        return RssRule.fromJson(name, map);
      }).toList();
    } catch (_) {
      return [];
    }
  }
}
