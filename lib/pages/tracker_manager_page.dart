import 'dart:async';

import 'package:flutter/material.dart';

import '../services/storage/storage_service.dart';
import '../services/downloader/downloader_config.dart';
import '../services/downloader/downloader_models.dart';
import '../services/downloader/downloader_service.dart';
import '../utils/format.dart';
import 'package:pt_mate/utils/notification_helper.dart';
import 'torrent_peers_page.dart';
import 'torrent_files_page.dart';

/// Tracker 管理页
///
/// 查看指定任务的全部 Tracker 状态（红种/工作/未连接）、
/// 一键 reannounce、添加/编辑/删除 Tracker。
class TrackerManagerPage extends StatefulWidget {
  final String taskHash;
  final String taskName;

  const TrackerManagerPage({
    super.key,
    required this.taskHash,
    required this.taskName,
  });

  @override
  State<TrackerManagerPage> createState() => _TrackerManagerPageState();
}

class _TrackerManagerPageState extends State<TrackerManagerPage> {
  bool _loading = true;
  String? _error;
  List<TorrentTracker> _trackers = [];
  DownloaderConfig? _config;
  String? _password;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final defId = await StorageService.instance.loadDefaultDownloaderId();
      if (defId == null) {
        setState(() {
          _loading = false;
          _error = '未配置下载器';
        });
        return;
      }
      final configMaps = await StorageService.instance.loadDownloaderConfigs();
      final configMap = configMaps.firstWhere(
        (c) => c['id'] == defId,
        orElse: () => configMaps.first,
      );
      final config = DownloaderConfig.fromJson(configMap);
      final password = await StorageService.instance.loadDownloaderPassword(
        config.id,
      );
      if ((password ?? '').isEmpty) {
        setState(() {
          _loading = false;
          _error = '未保存密码';
        });
        return;
      }
      _config = config;
      _password = password;

      if (config.type != DownloaderType.qbittorrent) {
        setState(() {
          _loading = false;
          _error = 'Tracker 管理仅支持 qBittorrent 下载器（当前：${config.type.displayName}）';
        });
        return;
      }

      final client = DownloaderService.instance.getClient(
        config: config,
        password: password!,
      );
      final trackers = await client.getTrackers(widget.taskHash)
          as List<TorrentTracker>;
      if (!mounted) return;
      setState(() {
        _trackers = trackers;
        _loading = false;
      });
    } catch (e, st) {
      print('[TRACKER] 加载异常: $e');
      print('[TRACKER] $st');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '加载 Tracker 失败: ${e.runtimeType}: $e';
      });
    }
  }

  Future<void> _reannounceAll() async {
    try {
      final client = DownloaderService.instance.getClient(
        config: _config!,
        password: _password!,
      );
      await client.reannounceTorrents([widget.taskHash]);
      if (!mounted) return;
      NotificationHelper.showInfo(context, '已重新宣告所有 Tracker');
      await _load();
    } catch (e) {
      if (!mounted) return;
      NotificationHelper.showError(context, '重新宣告失败: $e');
    }
  }

  Future<void> _addTracker() async {
    final controller = TextEditingController();
    final url = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('添加 Tracker'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'https://tracker.example.com/announce',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('添加'),
          ),
        ],
      ),
    );
    if (url == null || url.trim().isEmpty) return;
    try {
      final client = DownloaderService.instance.getClient(
        config: _config!,
        password: _password!,
      );
      await client.addTracker(widget.taskHash, url.trim());
      if (!mounted) return;
      NotificationHelper.showInfo(context, 'Tracker 已添加');
      await _load();
    } catch (e) {
      if (!mounted) return;
      NotificationHelper.showError(context, '添加失败: $e');
    }
  }

  Future<void> _editTracker(TorrentTracker tracker) async {
    final controller = TextEditingController(text: tracker.url);
    final url = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('编辑 Tracker'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: '新 URL'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (url == null || url.trim().isEmpty || url.trim() == tracker.url) {
      return;
    }
    try {
      final client = DownloaderService.instance.getClient(
        config: _config!,
        password: _password!,
      );
      await client.editTracker(widget.taskHash, tracker.url, url.trim());
      if (!mounted) return;
      NotificationHelper.showInfo(context, 'Tracker 已更新');
      await _load();
    } catch (e) {
      if (!mounted) return;
      NotificationHelper.showError(context, '更新失败: $e');
    }
  }

  Future<void> _removeTracker(TorrentTracker tracker) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除 Tracker'),
        content: Text('确定删除 ${tracker.url} 吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      final client = DownloaderService.instance.getClient(
        config: _config!,
        password: _password!,
      );
      await client.removeTrackers(widget.taskHash, [tracker.url]);
      if (!mounted) return;
      NotificationHelper.showInfo(context, 'Tracker 已删除');
      await _load();
    } catch (e) {
      if (!mounted) return;
      NotificationHelper.showError(context, '删除失败: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Tracker / 节点 / 文件'),
          leading: IconButton(
            tooltip: '返回',
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.of(context).pop(),
          ),
          automaticallyImplyLeading: false,
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Tracker'),
              Tab(text: '节点'),
              Tab(text: '文件'),
            ],
          ),
          actions: [
            IconButton(
              tooltip: '重新宣告',
              onPressed: _loading ? null : _reannounceAll,
              icon: const Icon(Icons.sync),
            ),
            IconButton(
              tooltip: '添加 Tracker',
              onPressed: _loading ? null : _addTracker,
              icon: const Icon(Icons.add_link),
            ),
          ],
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Text(
                widget.taskName,
                style: Theme.of(context).textTheme.titleSmall,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            Expanded(
              child: TabBarView(
                children: [
                  _loading
                      ? const Center(child: CircularProgressIndicator())
                      : ListView.builder(
                          itemCount: _trackers.length,
                          padding: const EdgeInsets.only(bottom: 32),
                          itemBuilder: (context, index) {
                            final tracker = _trackers[index];
                            return _buildTrackerCard(tracker);
                          },
                        ),
                  if (_config != null && (_password ?? '').isNotEmpty)
                    TorrentPeersView(
                      taskHash: widget.taskHash,
                      config: _config!,
                      password: _password!,
                    )
                  else
                    const Center(child: Text('加载配置中…')),
                  if (_config != null && (_password ?? '').isNotEmpty)
                    TorrentFilesView(
                      taskHash: widget.taskHash,
                      config: _config!,
                      password: _password!,
                    )
                  else
                    const Center(child: Text('加载配置中…')),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Tracker 状态文案（对应 qB status: 0=已禁用 1=未联系 2=正常 3=更新中 4=红种）
  String _trackerStatusText(TorrentTracker tracker) {
    switch (tracker.status) {
      case 0:
        return '已禁用';
      case 1:
        return '未联系';
      case 2:
        return '正常';
      case 3:
        return '更新中';
      case 4:
        return '红种';
      default:
        return '未知';
    }
  }

  /// -1/负数 表示未知或未联系，显示为 '-'
  String _trackerNum(int value) => value < 0 ? '-' : '$value';

  Widget _buildTrackerCard(TorrentTracker tracker) {
    final scheme = Theme.of(context).colorScheme;
    final statusColor = tracker.isError
        ? scheme.error
        : (tracker.isDisabled
              ? scheme.outline
              : (tracker.isWorking ? Colors.green : scheme.tertiary));
    final statusText = _trackerStatusText(tracker);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: statusColor.withValues(alpha: 0.5),
          width: tracker.isError ? 1.5 : 1,
        ),
      ),
      child: ListTile(
        title: Row(
          children: [
            Icon(Icons.circle, size: 10, color: statusColor),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                tracker.url,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13),
              ),
            ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    statusText,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: statusColor,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '层级 ${_trackerNum(tracker.tier)}',
                  style: TextStyle(fontSize: 11, color: scheme.secondary),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '节点 ${_trackerNum(tracker.numPeers)} · 种子 ${_trackerNum(tracker.numSeeds)} · 下载者 ${_trackerNum(tracker.numLeeches)} · 已下载 ${_trackerNum(tracker.numDownloads)}',
              style: TextStyle(fontSize: 11, color: scheme.secondary),
            ),
            if (tracker.message.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                tracker.message,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: tracker.isError
                      ? FontWeight.w600
                      : FontWeight.normal,
                  color: tracker.isError ? scheme.error : scheme.secondary,
                ),
              ),
            ],
            const SizedBox(height: 2),
            Text(
              '最后活动: ${_formatLastSeen(tracker.lastSeen)}',
              style: TextStyle(fontSize: 10, color: scheme.secondary),
            ),
          ],
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (value) {
            switch (value) {
              case 'edit':
                _editTracker(tracker);
                break;
              case 'remove':
                _removeTracker(tracker);
                break;
              case 'reannounce':
                _reannounceTracker(tracker.url);
                break;
            }
          },
          itemBuilder: (context) => [
            const PopupMenuItem<String>(
              value: 'reannounce',
              child: Text('重新宣告'),
            ),
            const PopupMenuItem<String>(
              value: 'edit',
              child: Text('编辑'),
            ),
            const PopupMenuItem<String>(
              value: 'remove',
              child: Text('删除'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _reannounceTracker(String url) async {
    try {
      final client = DownloaderService.instance.getClient(
        config: _config!,
        password: _password!,
      );
      await client.reannounceTorrents([widget.taskHash]);
      if (!mounted) return;
      NotificationHelper.showInfo(context, '已重新宣告');
    } catch (e) {
      if (!mounted) return;
      NotificationHelper.showError(context, '重新宣告失败: $e');
    }
  }

  String _formatLastSeen(int lastSeen) {
    if (lastSeen <= 0) return '从未';
    final diff = DateTime.now().difference(
      DateTime.fromMillisecondsSinceEpoch(lastSeen * 1000),
    );
    return FormatUtil.formatEta(diff.inSeconds);
  }
}
