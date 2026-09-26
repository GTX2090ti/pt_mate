import 'package:flutter/material.dart';

import '../services/storage/storage_service.dart';
import '../services/downloader/downloader_config.dart';
import '../services/downloader/downloader_models.dart';
import '../services/downloader/downloader_service.dart';
import '../services/downloader/seed_health_monitor.dart';
import '../services/downloader/disk_guard_service.dart';
import 'downloader_settings_page.dart';
import '../utils/format.dart';

/// 下载健康度面板
///
/// 展示磁盘空间状态、做种健康度（可删种列表）、限速调度状态。
class DownloadHealthPage extends StatefulWidget {
  const DownloadHealthPage({super.key});

  @override
  State<DownloadHealthPage> createState() => _DownloadHealthPageState();
}

class _DownloadHealthPageState extends State<DownloadHealthPage> {
  bool _loading = true;
  String? _error;

  // 磁盘
  int _freeSpace = 0;
  DiskGuardConfig? _diskConfig;

  // 健康度
  SeedHealthConfig? _seedConfig;
  List<DownloadTask> _readyToDelete = [];

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
      if (configMaps.isEmpty) {
        setState(() {
          _loading = false;
          _error = '未配置下载器';
        });
        return;
      }
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

      final diskConfig = await DiskGuardService.instance.loadConfig();
      final seedConfig = await SeedHealthMonitor.instance.loadConfig();

      final client = DownloaderService.instance.getClient(
        config: config,
        password: password!,
      );
      final serverState = await client.getServerState();
      final tasks = await client.getTasks();

      final ready = SeedHealthMonitor.findReadyToDelete(tasks, seedConfig);

      if (!mounted) return;
      setState(() {
        _freeSpace = serverState.freeSpaceOnDisk;
        _diskConfig = diskConfig;
        _seedConfig = seedConfig;

        _readyToDelete = ready;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '加载失败: $e';
      });
    }
  }

  Future<void> _toggleSeedHealth(bool enabled) async {
    final current = _seedConfig ?? const SeedHealthConfig();
    final updated = SeedHealthConfig(
      enabled: enabled,
      minRatio: current.minRatio,
      minSeedMinutes: current.minSeedMinutes,
      notifyWhenReady: current.notifyWhenReady,
    );
    await SeedHealthMonitor.instance.saveConfig(updated);
    setState(() {
      _seedConfig = updated;
    });
    await _load();
  }

  Future<void> _editSeedThresholds() async {
    final current = _seedConfig ?? const SeedHealthConfig();
    final ratioController = TextEditingController(
      text: current.minRatio.toString(),
    );
    final minutesController = TextEditingController(
      text: current.minSeedMinutes.toString(),
    );
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('做种健康度阈值'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: ratioController,
              keyboardType: TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: '最低分享率',
                helperText: '例如 1.0 表示上传量 ≥ 下载量',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: minutesController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: '最少做种分钟数',
                helperText: '例如 4320 = 72 小时',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (saved != true) return;
    final ratio = double.tryParse(ratioController.text.trim());
    final minutes = int.tryParse(minutesController.text.trim());
    if (ratio == null || minutes == null || ratio < 0 || minutes < 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请输入有效数值')));
      return;
    }
    final updated = SeedHealthConfig(
      enabled: current.enabled,
      minRatio: ratio,
      minSeedMinutes: minutes,
      notifyWhenReady: current.notifyWhenReady,
    );
    await SeedHealthMonitor.instance.saveConfig(updated);
    setState(() {
      _seedConfig = updated;
    });
    await _load();
  }

  Future<void> _deleteTask(String hash, bool deleteFiles) async {
    try {
      final client = DownloaderService.instance.getClient(
        config: _config!,
        password: _password!,
      );
      await client.deleteTask(hash, deleteFiles: deleteFiles);
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('删除失败: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('下载健康度'),
        leading: IconButton(
          tooltip: '返回',
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : (_error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.error_outline,
                            size: 48,
                            color: scheme.error,
                          ),
                          const SizedBox(height: 12),
                          Text(_error!, textAlign: TextAlign.center),
                          const SizedBox(height: 16),
                          FilledButton(
                            onPressed: () =>
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        const DownloaderSettingsPage(),
                                  ),
                                ),
                            child: const Text('去配置下载器'),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _buildDiskCard(scheme),
                      const SizedBox(height: 16),
                      _buildSeedHealthCard(scheme),
                      const SizedBox(height: 16),
                      if (_readyToDelete.isNotEmpty)
                        _buildReadyToDeleteSection(scheme),
                      if (_readyToDelete.isEmpty &&
                          (_seedConfig?.enabled ?? false))
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(
                            '暂无已达可删种标准的任务',
                            style: TextStyle(color: scheme.secondary),
                            textAlign: TextAlign.center,
                          ),
                        ),
                    ],
                  )),
    );
  }

  Widget _buildDiskCard(ColorScheme scheme) {
    final config = _diskConfig ?? const DiskGuardConfig();
    final warning = DiskGuardService.instance.isWarning(_freeSpace, config);
    final color = warning ? scheme.error : Colors.green;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: color.withValues(alpha: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  warning ? Icons.warning_amber : Icons.storage,
                  color: color,
                ),
                const SizedBox(width: 8),
                Text(
                  '磁盘空间',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              '剩余 ${Formatters.dataFromBytes(_freeSpace)}',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              warning
                  ? '低于预警阈值 ${Formatters.dataFromBytes(config.warnThresholdBytes)}，请及时清理'
                  : '下载前检查${config.checkBeforeAdd ? '已开启（预留 ${Formatters.dataFromBytes(config.reserveBytes)}）' : '未开启'}',
              style: TextStyle(fontSize: 12, color: scheme.secondary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSeedHealthCard(ColorScheme scheme) {
    final config = _seedConfig ?? const SeedHealthConfig();
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: scheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  config.enabled ? Icons.eco : Icons.eco_outlined,
                  color: config.enabled ? Colors.green : scheme.outline,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '做种健康度监控',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                Switch(
                  value: config.enabled,
                  onChanged: _toggleSeedHealth,
                ),
              ],
            ),
            if (config.enabled) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '分享率 ≥ ${config.minRatio.toStringAsFixed(2)}',
                      style: TextStyle(fontSize: 13, color: scheme.secondary),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      '做种 ≥ ${_formatMinutes(config.minSeedMinutes)}',
                      style: TextStyle(fontSize: 13, color: scheme.secondary),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: _editSeedThresholds,
                  icon: const Icon(Icons.tune, size: 18),
                  label: const Text('调整阈值'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildReadyToDeleteSection(ColorScheme scheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green, size: 20),
            const SizedBox(width: 8),
            Text(
              '可删种（${_readyToDelete.length}）',
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ],
        ),
        const SizedBox(height: 8),
        ..._readyToDelete.map(
          (task) => Card(
            elevation: 0,
            margin: const EdgeInsets.symmetric(vertical: 4),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(
                color: Colors.green.withValues(alpha: 0.3),
              ),
            ),
            child: ListTile(
              title: Text(
                task.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13),
              ),
              subtitle: Text(
                '分享率 ${task.ratio.toStringAsFixed(2)} · 做种 ${_formatMinutes(task.timeActive ~/ 60)}',
                style: const TextStyle(fontSize: 11),
              ),
              trailing: IconButton(
                tooltip: '删除任务',
                icon: Icon(Icons.delete_outline, color: scheme.error),
                onPressed: () => _confirmDelete(task),
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _confirmDelete(DownloadTask task) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除任务'),
        content: const Text('是否同时删除文件？'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              _deleteTask(task.hash, false);
            },
            child: const Text('仅任务'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              _deleteTask(task.hash, true);
            },
            child: const Text('同时删除文件'),
          ),
        ],
      ),
    );
  }

  String _formatMinutes(int minutes) {
    if (minutes < 60) return '$minutes 分钟';
    if (minutes < 1440) return '${(minutes / 60).toStringAsFixed(1)} 小时';
    return '${(minutes / 1440).toStringAsFixed(1)} 天';
  }
}
