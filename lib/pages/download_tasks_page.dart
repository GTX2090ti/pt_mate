import 'package:flutter/material.dart';
import 'dart:async';
import 'package:dio/dio.dart';
import '../services/storage/storage_service.dart';
import '../services/downloader/downloader_config.dart';
import '../services/downloader/downloader_service.dart';
import '../services/downloader/downloader_models.dart';
import '../services/downloader/seed_health_monitor.dart';
import '../services/downloader/disk_guard_service.dart';
import '../utils/format.dart';

import '../widgets/responsive_layout.dart';
import '../widgets/qb_speed_indicator.dart';
import 'downloader_settings_page.dart';
import 'package:pt_mate/utils/notification_helper.dart';
import 'tracker_manager_page.dart';
import 'download_health_page.dart';
import 'qb_settings_page.dart';
import '../widgets/category_picker_dialog.dart';
import '../utils/screen_utils.dart';

enum SortField {
  name,
  dlSpeed,
  upSpeed,
  addedOn,
  completionOn,
  ratio,
  size,
  progress,
}

/// qBittorrent 用于表示"无限"ETA 的值（100天，单位：秒）
const int kInfinityEtaInSeconds = 8640000;

class DownloadTasksPage extends StatefulWidget {
  const DownloadTasksPage({super.key});

  @override
  State<DownloadTasksPage> createState() => _DownloadTasksPageState();
}

/// 任务状态筛选
enum _TaskFilter {
  all('全部'),
  downloading('下载中'),
  uploading('做种中'),
  paused('已暂停'),
  completed('已完成');

  const _TaskFilter(this.label);
  final String label;
}

class _DownloadTasksPageState extends State<DownloadTasksPage> {
  Timer? _refreshTimer;
  StreamSubscription<String>? _configChangeSubscription;

  // 状态变量
  bool _isLoading = true;
  String? _errorMessage;
  List<DownloadTask> _tasks = [];
  TransferInfo? _transferInfo;
  ServerState? _serverState;
  DownloaderConfig? _downloaderConfig;
  String? _password;
  bool _showAllTasks = false; // 控制是否显示全部任务
  // ===== 专业增强状态 =====
  bool _selectionMode = false; // 批量选择模式
  final Set<String> _selectedHashes = {}; // 选中的任务哈希
  DiskGuardConfig? _diskGuardConfig; // 磁盘守卫配置
  List<DownloadTask> _readyToDelete = []; // 已达可删种标准的任务
  String _searchQuery = ''; // 搜索关键词
  final TextEditingController _searchController = TextEditingController();

  // 排序状态
  SortField _sortField = SortField.addedOn;
  bool _sortAscending = false;

  // 状态筛选 Tab（qB 风格）
  _TaskFilter _statusFilter = _TaskFilter.all;

  @override
  void initState() {
    super.initState();
    StorageService.instance.loadDownloadTasksShowAll().then((value) {
      if (mounted) {
        setState(() {
          _showAllTasks = value;
        });
      }
    });
    _loadDownloaderConfig();
    _startAutoRefresh();

    // 监听配置变更
    _configChangeSubscription = DownloaderService.instance.configChangeStream
        .listen((configId) {
          // 当配置发生变更时，重置 client 并重新加载配置
          _resetClient();
          _loadDownloaderConfig();
        });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _configChangeSubscription?.cancel();
    _searchController.dispose();
    _resetClient(); // 清理 client 实例
    super.dispose();
  }

  // 启动自动刷新（间隔从设置读取）
  void _startAutoRefresh() {
    StorageService.instance.loadDownloadTasksRefreshInterval().then((seconds) {
      if (!mounted) return;
      _refreshTimer = Timer.periodic(Duration(seconds: seconds), (timer) {
        if (_downloaderConfig != null && _password != null && mounted) {
          _loadTasks(silent: true); // 使用静默模式
        }
      });
    });
  }

  // 加载下载器配置
  Future<void> _loadDownloaderConfig() async {
    try {
      final defId = await StorageService.instance.loadDefaultDownloaderId();
      if (defId == null) {
        setState(() {
          _isLoading = false;
          _downloaderConfig = null;
          _password = null;
          _errorMessage = '未配置下载器';
        });
        return;
      }

      final configs = await StorageService.instance.loadDownloaderConfigs();
      final configMap = configs.firstWhere(
        (e) => e['id'] == defId,
        orElse: () =>
            configs.isNotEmpty ? configs.first : throw Exception('未找到默认下载器'),
      );

      final config = DownloaderConfig.fromJson(configMap);
      final password = await StorageService.instance.loadDownloaderPassword(
        config.id,
      );
      if ((password ?? '').isEmpty) {
        setState(() {
          _isLoading = false;
          _downloaderConfig = config;
          _password = null;
          _errorMessage = '未保存密码';
        });
        return;
      }

      setState(() {
        _downloaderConfig = config;
        _password = password;
      });

      // 配置更改时重置 client
      _resetClient();

      await _loadTasks();
    } catch (e) {
      setState(() {
        _isLoading = false;
        _downloaderConfig = null;
        _password = null;
        _errorMessage = '加载配置失败: $e';
      });
    }
  }

  // 获取或创建 client 实例
  dynamic _getClient() {
    if (_downloaderConfig == null || _password == null) {
      return null;
    }

    // 使用 DownloaderService 的缓存机制（包含配置更新回调）
    return DownloaderService.instance.getClient(
      config: _downloaderConfig!,
      password: _password!,
    );
  }

  /// 重置客户端
  void _resetClient() {
    // 清除 DownloaderService 中的缓存
    if (_downloaderConfig != null) {
      DownloaderService.instance.clearConfigCache(_downloaderConfig!.id);
    }
  }

  // 加载下载任务
  Future<void> _loadTasks({bool silent = false}) async {
    if (_downloaderConfig == null || _password == null) return;

    if (!silent) {
      setState(() {
        _isLoading = true;
        _errorMessage = '';
      });
    }

    try {
      final client = _getClient();
      if (client == null) return;

      final List<dynamic> futures = await Future.wait([
        client.getTasks(),
        client.getTransferInfo(),
        client.getServerState(),
      ]);

      final diskConfig = await DiskGuardService.instance.loadConfig();
      final seedConfig = await SeedHealthMonitor.instance.loadConfig();
      final tasks = futures[0] as List<DownloadTask>;
      final ready = SeedHealthMonitor.findReadyToDelete(tasks, seedConfig);

      setState(() {
        _tasks = tasks;
        _transferInfo = futures[1] as TransferInfo;
        _serverState = futures[2] as ServerState;
        _diskGuardConfig = diskConfig;
        _readyToDelete = ready;
        if (!silent) _isLoading = false;
        _errorMessage = null; // 清除错误信息
      });
    } catch (e) {
      // 静默模式下不更新错误状态，避免干扰用户
      if (!silent) {
        setState(() {
          _isLoading = false;
          _errorMessage = _friendlyTaskError(e);
        });
      }
    }
  }

  /// 把下载器连接异常转成可操作的中文提示
  String _friendlyTaskError(Object e) {
    if (e is DioException) {
      switch (e.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
          return '连接下载器超时：请检查手机与下载器是否在同一网络（WiFi 下访问内网地址；流量下需公网地址/内网穿透）';
        case DioExceptionType.connectionError:
          return '无法连接下载器：请确认下载器在线、地址端口正确，且手机网络可访问该地址';
        default:
          break;
      }
    }
    return '加载任务失败: $e';
  }

  @override
  Widget build(BuildContext context) {
    return ResponsiveLayout(
      currentRoute: '/download_tasks',
      appBar: AppBar(
        title: Text(_selectionMode ? '已选 ${_selectedHashes.length} 项' : '下载管理'),
        leading: _selectionMode
            ? IconButton(
                tooltip: '退出批量选择',
                icon: const Icon(Icons.close),
                onPressed: () {
                  setState(() {
                    _selectionMode = false;
                    _selectedHashes.clear();
                  });
                },
              )
            : null,
        actions: [
          if (_selectionMode) ...[
            IconButton(
              tooltip: '全选',
              icon: const Icon(Icons.select_all),
              onPressed: _selectAll,
            ),
            IconButton(
              tooltip: '批量暂停',
              icon: const Icon(Icons.pause),
              onPressed: _selectedHashes.isEmpty ? null : () => _bulkPause(),
            ),
            IconButton(
              tooltip: '批量恢复',
              icon: const Icon(Icons.play_arrow),
              onPressed: _selectedHashes.isEmpty ? null : () => _bulkResume(),
            ),
            IconButton(
              tooltip: '批量删除',
              icon: const Icon(Icons.delete_outline),
              onPressed: _selectedHashes.isEmpty ? null : () => _bulkDelete(),
            ),
          ] else ...[
            const QbSpeedIndicator(),
          ],
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                if (_errorMessage != null && _errorMessage!.isNotEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    color: _downloaderConfig == null
                        ? Theme.of(context).colorScheme.primaryContainer
                        : Theme.of(context).colorScheme.errorContainer,
                    child: _downloaderConfig == null
                        ? Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                '未配置下载器',
                                style: TextStyle(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onPrimaryContainer,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(width: 12),
                              TextButton(
                                onPressed: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          const DownloaderSettingsPage(),
                                      settings: const RouteSettings(
                                        name: '/downloader_settings',
                                      ),
                                    ),
                                  );
                                },
                                style: TextButton.styleFrom(
                                  side: BorderSide(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.outline,
                                    width: 1.0,
                                  ),
                                ),
                                child: const Text('去配置'),
                              ),
                            ],
                          )
                        : Text(
                            _errorMessage!,
                            style: TextStyle(
                              color: Theme.of(
                                context,
                              ).colorScheme.onErrorContainer,
                              fontSize: 14,
                            ),
                            textAlign: TextAlign.center,
                          ),
                  ),
                if (_serverState != null &&
                    _diskGuardConfig != null &&
                    DiskGuardService.instance.isWarning(
                      _serverState!.freeSpaceOnDisk,
                      _diskGuardConfig!,
                    ))
                  _buildDiskWarningBanner(),
                if (_readyToDelete.isNotEmpty && !_selectionMode)
                  _buildSeedHealthBanner(),
                // 搜索和过滤UI
                _buildSearchAndFilterBar(),
                // 传输状态指示
                _buildTransferStateBar(),
                Expanded(child: _buildAllTasksList()),
              ],
            ),
      floatingActionButton: Builder(
        builder: (context) {
          final isDesktop = ScreenUtils.isLargeScreen(context);
          return Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (isDesktop)
                FloatingActionButton.extended(
                  heroTag: 'switch_downloader',
                  onPressed: _showDownloaderPicker,
                  icon: const Icon(Icons.swap_vert),
                  label: const Text('切换'),
                )
              else
                FloatingActionButton(
                  heroTag: 'switch_downloader',
                  tooltip: '切换',
                  onPressed: _showDownloaderPicker,
                  child: const Icon(Icons.swap_vert),
                ),
              const SizedBox(height: 16),
              if (isDesktop)
                FloatingActionButton.extended(
                  heroTag: 'refresh_download',
                  onPressed: () {
                    _loadTasks();
                    NotificationHelper.showInfo(context, '刷新任务列表');
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text('刷新'),
                )
              else
                FloatingActionButton(
                  heroTag: 'refresh_download',
                  tooltip: '刷新',
                  onPressed: () {
                    _loadTasks();
                    NotificationHelper.showInfo(context, '刷新任务列表');
                  },
                  child: const Icon(Icons.refresh),
                ),
              const SizedBox(height: 16),
              // 设置入口（右下角方形齿轮按钮，打开 qB 风格设置页）
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: IconButton(
                  tooltip: '设置',
                  icon: const Icon(Icons.settings, color: Colors.white),
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const QbSettingsPage(),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // 暂停任务
  Future<void> _pauseTask(String hash) async {
    if (_downloaderConfig == null || _password == null) return;

    try {
      final client = _getClient();
      if (client == null) return;

      await client.pauseTask(hash);

      if (!mounted) return;
      NotificationHelper.showInfo(context, '已暂停');
    } catch (e) {
      if (!mounted) return;
      NotificationHelper.showError(context, '暂停失败: $e');
    }
  }

  // 恢复任务
  Future<void> _resumeTask(String hash) async {
    if (_downloaderConfig == null || _password == null) return;

    try {
      final client = _getClient();
      if (client == null) return;

      await client.resumeTask(hash);
      if (!mounted) return;
      NotificationHelper.showInfo(context, '已启动');
    } catch (e) {
      if (!mounted) return;
      NotificationHelper.showError(context, '恢复失败: $e');
    }
  }

  // 删除任务
  Future<void> _deleteTask(String hash, bool deleteFiles) async {
    if (_downloaderConfig == null || _password == null) return;

    try {
      final client = _getClient();
      if (client == null) return;

      await client.deleteTask(hash, deleteFiles: deleteFiles);

      if (!mounted) return;
      NotificationHelper.showInfo(context, deleteFiles ? '已删除任务和文件' : '已删除任务');
    } catch (e) {
      if (!mounted) return;
      NotificationHelper.showError(context, '删除任务失败: $e');
    }
  }
  // ===== 批量操作 =====
  void _selectAll() {
    setState(() {
      if (_selectedHashes.length == _tasks.length) {
        _selectedHashes.clear();
      } else {
        _selectedHashes.addAll(_tasks.map((t) => t.hash));
      }
    });
  }

  Future<void> _bulkPause() async {
    try {
      final client = _getClient();
      if (client == null) return;
      await client.pauseTasks(_selectedHashes.toList());
      if (!mounted) return;
      NotificationHelper.showInfo(context, '已暂停 ' + _selectedHashes.length.toString() + ' 个任务');
      setState(() {
        _selectionMode = false;
        _selectedHashes.clear();
      });
      await _loadTasks(silent: true);
    } catch (e) {
      if (!mounted) return;
      NotificationHelper.showError(context, '批量暂停失败: ' + e.toString());
    }
  }

  Future<void> _bulkResume() async {
    try {
      final client = _getClient();
      if (client == null) return;
      await client.resumeTasks(_selectedHashes.toList());
      if (!mounted) return;
      NotificationHelper.showInfo(context, '已恢复 ' + _selectedHashes.length.toString() + ' 个任务');
      setState(() {
        _selectionMode = false;
        _selectedHashes.clear();
      });
      await _loadTasks(silent: true);
    } catch (e) {
      if (!mounted) return;
      NotificationHelper.showError(context, '批量恢复失败: ' + e.toString());
    }
  }

  Future<void> _bulkDelete() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('批量删除'),
        content: const Text('是否同时删除文件？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('仅任务'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('同时删除文件'),
          ),
        ],
      ),
    );
    if (confirm == null) return;
    try {
      final client = _getClient();
      if (client == null) return;
      await client.deleteTasks(_selectedHashes.toList(), deleteFiles: confirm);
      if (!mounted) return;
      NotificationHelper.showInfo(context, '已删除 ' + _selectedHashes.length.toString() + ' 个任务');
      setState(() {
        _selectionMode = false;
        _selectedHashes.clear();
      });
      await _loadTasks(silent: true);
    } catch (e) {
      if (!mounted) return;
      NotificationHelper.showError(context, '批量删除失败: ' + e.toString());
    }
  }

  // 修改单个任务分类
  Future<void> _setTaskCategory(DownloadTask task) async {
    final config = _downloaderConfig;
    final pwd = _password;
    if (config == null || (pwd ?? '').isEmpty) {
      NotificationHelper.showError(context, '未配置下载器');
      return;
    }
    final category = await CategoryPickerDialog.show(
      context,
      config: config,
      password: pwd!,
      allowCreate: true,
    );
    if (category == null) return;
    try {
      await DownloaderService.instance.setCategory(
        config: config,
        password: pwd,
        hashes: [task.hash],
        category: category,
      );
      if (!mounted) return;
      NotificationHelper.showInfo(
        context,
        category.isEmpty ? '已清除分类' : '已分类为：$category',
      );
      await _loadTasks(silent: true);
    } catch (e) {
      if (!mounted) return;
      NotificationHelper.showError(context, '修改分类失败: $e');
    }
  }

  // 批量修改分类
  Future<void> _bulkSetCategory() async {
    final config = _downloaderConfig;
    final pwd = _password;
    if (config == null || (pwd ?? '').isEmpty) {
      NotificationHelper.showError(context, '未配置下载器');
      return;
    }
    final category = await CategoryPickerDialog.show(
      context,
      config: config,
      password: pwd!,
      allowCreate: true,
    );
    if (category == null) return;
    try {
      await DownloaderService.instance.setCategory(
        config: config,
        password: pwd,
        hashes: _selectedHashes.toList(),
        category: category,
      );
      if (!mounted) return;
      NotificationHelper.showInfo(
        context,
        '已为 ${_selectedHashes.length} 个任务设置分类：$category',
      );
      setState(() {
        _selectionMode = false;
        _selectedHashes.clear();
      });
      await _loadTasks(silent: true);
    } catch (e) {
      if (!mounted) return;
      NotificationHelper.showError(context, '批量修改分类失败: $e');
    }
  }

  Future<void> _setPriority(int priority) async {
    try {
      final client = _getClient();
      if (client == null) return;
      await client.setTorrentPriority(_selectedHashes.toList(), priority);
      if (!mounted) return;
      NotificationHelper.showInfo(context, '优先级已更新');
      setState(() {
        _selectionMode = false;
        _selectedHashes.clear();
      });
      await _loadTasks(silent: true);
    } catch (e) {
      if (!mounted) return;
      NotificationHelper.showError(context, '设置优先级失败: ' + e.toString());
    }
  }

  void _showPriorityMenu() {
    showModalBottomSheet<int>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text(
                '批量操作',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              trailing: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(sheetContext),
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.skip_next),
              title: const Text('优先级: 跳过'),
              subtitle: const Text('不参与下载队列'),
              onTap: () {
                Navigator.pop(sheetContext);
                _setPriority(-1);
              },
            ),
            ListTile(
              leading: const Icon(Icons.horizontal_rule),
              title: const Text('优先级: 普通'),
              onTap: () {
                Navigator.pop(sheetContext);
                _setPriority(0);
              },
            ),
            ListTile(
              leading: const Icon(Icons.arrow_upward),
              title: const Text('优先级: 高'),
              onTap: () {
                Navigator.pop(sheetContext);
                _setPriority(1);
              },
            ),
            ListTile(
              leading: const Icon(Icons.vertical_align_top),
              title: const Text('优先级: 最高'),
              onTap: () {
                Navigator.pop(sheetContext);
                _setPriority(2);
              },
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.folder_copy_outlined),
              title: const Text('批量修改分类'),
              onTap: () {
                Navigator.pop(sheetContext);
                _bulkSetCategory();
              },
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.replay),
              title: const Text('批量重新校验'),
              onTap: () {
                Navigator.pop(sheetContext);
                _bulkRecheck();
              },
            ),
            ListTile(
              leading: const Icon(Icons.sync),
              title: const Text('批量重新宣告'),
              onTap: () {
                Navigator.pop(sheetContext);
                _bulkReannounce();
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _bulkRecheck() async {
    try {
      final client = _getClient();
      if (client == null) return;
      await client.recheckTorrents(_selectedHashes.toList());
      if (!mounted) return;
      NotificationHelper.showInfo(context, '已发起 ' + _selectedHashes.length.toString() + ' 个任务校验');
      setState(() {
        _selectionMode = false;
        _selectedHashes.clear();
      });
    } catch (e) {
      if (!mounted) return;
      NotificationHelper.showError(context, '批量校验失败: ' + e.toString());
    }
  }

  Future<void> _bulkReannounce() async {
    try {
      final client = _getClient();
      if (client == null) return;
      await client.reannounceTorrents(_selectedHashes.toList());
      if (!mounted) return;
      NotificationHelper.showInfo(context, '已重新宣告 ' + _selectedHashes.length.toString() + ' 个任务');
      setState(() {
        _selectionMode = false;
        _selectedHashes.clear();
      });
    } catch (e) {
      if (!mounted) return;
      NotificationHelper.showError(context, '批量重新宣告失败: ' + e.toString());
    }
  }

  // 构建搜索和过滤UI
  Widget _buildSearchAndFilterBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        children: [
          // 状态筛选 Tab（qB 风格）
          SizedBox(
            height: 36,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: _TaskFilter.values.map((f) {
                final selected = _statusFilter == f;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(f.label),
                    selected: selected,
                    showCheckmark: false,
                    onSelected: (_) {
                      setState(() {
                        _statusFilter = f;
                      });
                    },
                    labelStyle: TextStyle(
                      fontSize: 12,
                      fontWeight: selected
                          ? FontWeight.w600
                          : FontWeight.normal,
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              // 搜索框
              Expanded(
                child: SizedBox(
                  height: 40,
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: '搜索...',
                      prefixIcon: const Icon(Icons.search, size: 20),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 16),
                              tooltip: '清除搜索',
                              onPressed: () {
                                _searchController.clear();
                                setState(() {
                                  _searchQuery = '';
                                });
                              },
                            )
                          : null,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: Theme.of(
                        context,
                      ).colorScheme.surfaceContainerHighest,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                      ),
                      isDense: true,
                    ),
                    style: const TextStyle(fontSize: 14),
                    onChanged: (value) {
                      setState(() {
                        _searchQuery = value;
                      });
                    },
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // 排序按钮
              PopupMenuButton<SortField>(
                icon: const Icon(Icons.sort),
                tooltip: '排序方式',
                initialValue: _sortField,
                onSelected: (SortField value) {
                  setState(() {
                    _sortField = value;
                  });
                },
                itemBuilder: (BuildContext context) =>
                    <PopupMenuEntry<SortField>>[
                      const PopupMenuItem<SortField>(
                        value: SortField.addedOn,
                        child: Text('添加时间'),
                      ),
                      const PopupMenuItem<SortField>(
                        value: SortField.completionOn,
                        child: Text('完成时间'),
                      ),
                      const PopupMenuItem<SortField>(
                        value: SortField.dlSpeed,
                        child: Text('下载速度'),
                      ),
                      const PopupMenuItem<SortField>(
                        value: SortField.upSpeed,
                        child: Text('上传速度'),
                      ),
                      const PopupMenuItem<SortField>(
                        value: SortField.ratio,
                        child: Text('分享率'),
                      ),
                      const PopupMenuItem<SortField>(
                        value: SortField.size,
                        child: Text('大小'),
                      ),
                      const PopupMenuItem<SortField>(
                        value: SortField.progress,
                        child: Text('进度'),
                      ),
                      const PopupMenuItem<SortField>(
                        value: SortField.name,
                        child: Text('名称'),
                      ),
                    ],
              ),

              // 排序方向
              IconButton(
                icon: Icon(
                  _sortAscending ? Icons.arrow_upward : Icons.arrow_downward,
                ),
                tooltip: _sortAscending ? '升序' : '降序',
                onPressed: () {
                  setState(() {
                    _sortAscending = !_sortAscending;
                  });
                },
              ),

              // 过滤切换
              IconButton(
                icon: Icon(
                  _showAllTasks ? Icons.filter_alt_off : Icons.filter_alt,
                ),
                tooltip: _showAllTasks ? '显示全部' : '仅显示活跃',
                onPressed: () {
                  setState(() {
                    _showAllTasks = !_showAllTasks;
                  });
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTransferStateBar() {
    if (_transferInfo == null || _serverState == null) {
      return const SizedBox.shrink();
    }

    if (ScreenUtils.isLargeScreen(context)) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Row(
              children: [
                Icon(
                  Icons.cloud_download,
                  size: 16,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 4),
                Text(
                  '下载: ${Formatters.dataFromBytes(_transferInfo!.dlTotal)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          Expanded(
            child: Row(
              children: [
                Icon(
                  Icons.cloud_upload,
                  size: 16,
                  color: Theme.of(context).colorScheme.tertiary,
                ),
                const SizedBox(width: 4),
                Text(
                  '上传: ${Formatters.dataFromBytes(_transferInfo!.upTotal)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDiskWarningBanner() {
    return Material(
      color: Theme.of(context).colorScheme.errorContainer,
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const DownloadHealthPage(),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Icon(
                Icons.warning_amber,
                size: 16,
                color: Theme.of(context).colorScheme.onErrorContainer,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '磁盘空间不足：剩余 ' +
                      Formatters.dataFromBytes(_serverState!.freeSpaceOnDisk) +
                      '，点击查看详情',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onErrorContainer,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSeedHealthBanner() {
    return Material(
      color: Colors.green.withValues(alpha: 0.12),
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const DownloadHealthPage(),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Icon(Icons.eco, size: 16, color: Colors.green.shade700),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _readyToDelete.length.toString() + ' 个任务已达可删种标准，点击查看',
                  style: TextStyle(fontSize: 12, color: Colors.green.shade800),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAllTasksList() {
    // 首先根据状态 Tab 过滤任务
    List<DownloadTask> statusFilteredTasks = _tasks.where((task) {
      switch (_statusFilter) {
        case _TaskFilter.all:
          return true;
        case _TaskFilter.downloading:
          return DownloadTaskState.isDownloading(task.state) ||
              task.state == DownloadTaskState.queuedDL ||
              task.state == DownloadTaskState.checkingDL ||
              task.state == DownloadTaskState.allocating ||
              task.state == DownloadTaskState.checkingResumeData ||
              task.state == DownloadTaskState.moving;
        case _TaskFilter.uploading:
          return task.state == DownloadTaskState.uploading ||
              task.state == DownloadTaskState.forcedUP ||
              task.state == DownloadTaskState.stalledUP ||
              task.state == DownloadTaskState.queuedUP ||
              task.state == DownloadTaskState.checkingUP;
        case _TaskFilter.paused:
          return DownloadTaskState.isPaused(task.state) ||
              task.state == DownloadTaskState.stoppedDL;
        case _TaskFilter.completed:
          return task.progress >= 1.0 &&
              (task.state == DownloadTaskState.uploading ||
                  task.state == DownloadTaskState.forcedUP ||
                  task.state == DownloadTaskState.stalledUP ||
                  task.state == DownloadTaskState.queuedUP ||
                  task.state == DownloadTaskState.checkingUP ||
                  task.state == DownloadTaskState.pausedUP);
      }
    }).toList();

    // 兼容旧开关：showAll 为 false 时仅显示活跃状态
    if (!_showAllTasks && _statusFilter == _TaskFilter.all) {
      statusFilteredTasks = statusFilteredTasks
          .where(
            (task) =>
                task.state == DownloadTaskState.downloading ||
                task.state == DownloadTaskState.uploading ||
                task.state == DownloadTaskState.pausedDL ||
                task.state == DownloadTaskState.stalledDL ||
                task.state == DownloadTaskState.stoppedDL,
          )
          .toList();
    }

    // 然后根据搜索关键词过滤任务名称
    final filteredTasks = _searchQuery.isEmpty
        ? statusFilteredTasks
        : statusFilteredTasks
              .where(
                (task) => task.name.toLowerCase().contains(
                  _searchQuery.toLowerCase(),
                ),
              )
              .toList();

    // 排序
    filteredTasks.sort((a, b) {
      int cmp;
      switch (_sortField) {
        case SortField.name:
          cmp = a.name.compareTo(b.name);
          break;
        case SortField.dlSpeed:
          cmp = a.dlspeed.compareTo(b.dlspeed);
          break;
        case SortField.upSpeed:
          cmp = a.upspeed.compareTo(b.upspeed);
          break;
        case SortField.addedOn:
          cmp = a.addedOn.compareTo(b.addedOn);
          break;
        case SortField.completionOn:
          cmp = a.completionOn.compareTo(b.completionOn);
          break;
        case SortField.ratio:
          cmp = a.ratio.compareTo(b.ratio);
          break;
        case SortField.size:
          cmp = a.size.compareTo(b.size);
          break;
        case SortField.progress:
          cmp = a.progress.compareTo(b.progress);
          break;
      }
      return _sortAscending ? cmp : -cmp;
    });

    if (filteredTasks.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.inbox_outlined,
              size: 64,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 12),
            Text(
              '没有下载任务',
              style: TextStyle(
                fontSize: 16,
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _searchQuery.isNotEmpty
                  ? '换个关键词试试'
                  : '下拉可刷新任务列表',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadTasks,
      child: ListView.builder(
        itemCount: filteredTasks.length,
        padding: const EdgeInsets.only(
          left: 16,
          top: 4,
          right: 16,
          bottom: 150,
        ),
        itemBuilder: (context, index) {
          final task = filteredTasks[index];
          return _buildTaskCard(task);
        },
      ),
    );
  }

  void _showDownloaderPicker() async {
    final configMaps = await StorageService.instance.loadDownloaderConfigs();
    if (configMaps.isEmpty) {
      if (mounted) NotificationHelper.showInfo(context, '未配置下载器');
      return;
    }

    final configs = configMaps
        .map((e) => DownloaderConfig.fromJson(e))
        .toList();
    final defaultId = await StorageService.instance.loadDefaultDownloaderId();

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: const Text(
                  '切换下载器',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(sheetContext),
                ),
              ),
              const Divider(height: 1),
              ...configs.map((config) {
                final isActive = config.id == defaultId;
                return ListTile(
                  leading: Icon(
                    isActive
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                    color: isActive ? Theme.of(context).primaryColor : null,
                  ),
                  title: Text(config.name),
                  subtitle: Text('${config.type.displayName} - ${config.host}'),
                  onTap: () async {
                    Navigator.pop(sheetContext);
                    if (!isActive) {
                      await StorageService.instance.saveDownloaderConfigs(
                        configs,
                        defaultId: config.id,
                      );
                      DownloaderService.instance.notifyConfigChanged(config.id);
                      if (mounted) {
                        NotificationHelper.showInfo(
                          context,
                          '已切换至 ${config.name}',
                        );
                      }
                    }
                  },
                );
              }),
            ],
          ),
        );
      },
    );
  }

  // 确认删除
  void _confirmDelete(DownloadTask task) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除任务'),
        content: const Text('是否同时删除文件？'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _deleteTask(task.hash, false);
            },
            child: const Text('仅任务'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _deleteTask(task.hash, true);
            },
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('同时删除文件'),
          ),
        ],
      ),
    );
  }

  Widget _buildTaskCard(DownloadTask task) {
    final bool isDownloading =
        task.state == DownloadTaskState.downloading ||
        task.state == DownloadTaskState.stalledDL ||
        task.state == DownloadTaskState.metaDL ||
        task.state == DownloadTaskState.forcedDL ||
        task.state == DownloadTaskState.queuedDL ||
        task.state == DownloadTaskState.checkingDL ||
        task.state == DownloadTaskState.allocating ||
        task.state == DownloadTaskState.checkingResumeData;
    final bool isPaused =
        task.state == DownloadTaskState.pausedDL ||
        task.state == DownloadTaskState.pausedUP ||
        task.state == DownloadTaskState.queuedUP ||
        task.state == DownloadTaskState.error ||
        task.state == DownloadTaskState.stoppedDL ||
        task.state == DownloadTaskState.missingFiles;

    final bool isSelected = _selectedHashes.contains(task.hash);
    // 状态徽章文案与颜色
    String statusText;
    Color statusColor;
    if (task.state == DownloadTaskState.error ||
        task.state == DownloadTaskState.missingFiles) {
      statusText = '错误';
      statusColor = Theme.of(context).colorScheme.error;
    } else if (task.progress >= 1.0) {
      statusText = task.state == DownloadTaskState.pausedUP
          ? '已完成·暂停'
          : '已完成';
      statusColor = Colors.green;
    } else if (DownloadTaskState.isDownloading(task.state)) {
      statusText = '下载中';
      statusColor = Theme.of(context).colorScheme.primary;
    } else if (DownloadTaskState.isPaused(task.state) ||
        task.state == DownloadTaskState.stoppedDL) {
      statusText = '已暂停';
      statusColor = Theme.of(context).colorScheme.tertiary;
    } else if (task.state == DownloadTaskState.uploading ||
        task.state == DownloadTaskState.forcedUP ||
        task.state == DownloadTaskState.stalledUP ||
        task.state == DownloadTaskState.queuedUP ||
        task.state == DownloadTaskState.checkingUP) {
      statusText = '做种中';
      statusColor = Colors.green;
    } else {
      statusText = '等待中';
      statusColor = Theme.of(context).colorScheme.secondary;
    }
    return GestureDetector(
      onTap: () {
        if (_selectionMode) return;
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => TrackerManagerPage(
              taskHash: task.hash,
              taskName: task.name,
            ),
          ),
        );
      },
      onLongPress: () {
        setState(() {
          _selectionMode = true;
          _selectedHashes.add(task.hash);
        });
      },
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(
            color: _selectionMode && isSelected
                ? Theme.of(context).colorScheme.primary
                : Theme.of(
                    context,
                  ).colorScheme.outlineVariant.withValues(alpha: 0.5),
            width: _selectionMode && isSelected ? 2 : 1,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top Row: Title and Actions
              Row(
                children: [
                  if (_selectionMode)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Icon(
                        isSelected
                            ? Icons.check_circle
                            : Icons.radio_button_unchecked,
                        size: 20,
                        color: isSelected
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.outline,
                      ),
                    ),
                  // Title and Info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                task.name,
                                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: statusColor.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                statusText,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: statusColor,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                      // Category and Tags
                      if (task.category.isNotEmpty || task.tags.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Row(
                            children: [
                              if (task.category.isNotEmpty)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.primaryContainer,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    task.category,
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onPrimaryContainer,
                                    ),
                                  ),
                                ),
                              if (task.category.isNotEmpty &&
                                  task.tags.isNotEmpty)
                                const SizedBox(width: 6),
                              ...task.tags.map(
                                (tag) => Padding(
                                  padding: const EdgeInsets.only(right: 4),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.secondaryContainer,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      tag,
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onSecondaryContainer,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      // Status Info Row 1: Static Info
                      Row(
                        children: [
                          // Size
                          Text(
                            FormatUtil.formatFileSize(task.size),
                            style: TextStyle(
                              fontSize: 11,
                              color: Theme.of(context).colorScheme.secondary,
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Uploaded
                          Icon(
                            Icons.upload_file,
                            size: 12,
                            color: Theme.of(context).colorScheme.secondary,
                          ),
                          const SizedBox(width: 2),
                          Text(
                            FormatUtil.formatFileSize(task.uploaded),
                            style: TextStyle(
                              fontSize: 11,
                              color: Theme.of(context).colorScheme.secondary,
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Ratio
                          Icon(
                            Icons.compare_arrows,
                            size: 12,
                            color: Theme.of(context).colorScheme.secondary,
                          ),
                          const SizedBox(width: 2),
                          Text(
                            task.ratio.toStringAsFixed(2),
                            style: TextStyle(
                              fontSize: 11,
                              color: Theme.of(context).colorScheme.secondary,
                            ),
                          ),
                        ],
                      ),

                      // Status Info Row 2: Dynamic Info (Speed & ETA)
                      if (task.dlspeed > 0 ||
                          task.upspeed > 0 ||
                          (isDownloading &&
                              task.eta > 0 &&
                              task.eta < kInfinityEtaInSeconds))
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Row(
                            children: [
                              // DL Speed
                              if (task.dlspeed > 0) ...[
                                Icon(
                                  Icons.download,
                                  size: 12,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                                const SizedBox(width: 2),
                                Text(
                                  FormatUtil.formatSpeed(task.dlspeed),
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.primary,
                                  ),
                                ),
                                const SizedBox(width: 8),
                              ],
                              // UP Speed
                              if (task.upspeed > 0) ...[
                                Icon(
                                  Icons.upload,
                                  size: 12,
                                  color: Theme.of(context).colorScheme.tertiary,
                                ),
                                const SizedBox(width: 2),
                                Text(
                                  FormatUtil.formatSpeed(task.upspeed),
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.tertiary,
                                  ),
                                ),
                                const SizedBox(width: 8),
                              ],
                              // ETA
                              if (isDownloading &&
                                  task.eta > 0 &&
                                  task.eta < kInfinityEtaInSeconds) ...[
                                Icon(
                                  Icons.timer,
                                  size: 12,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.secondary,
                                ),
                                const SizedBox(width: 2),
                                Text(
                                  FormatUtil.formatEta(task.eta),
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.secondary,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                // Actions
                if (_selectionMode)
                  IconButton(
                    icon: const Icon(Icons.more_vert, size: 20),
                    tooltip: '批量操作',
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 32,
                    ),
                    padding: EdgeInsets.zero,
                    onPressed: _showPriorityMenu,
                  )
                else ...[
                  IconButton(
                    icon: Icon(
                      isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                      size: 20,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    tooltip: isPaused ? '恢复' : '暂停',
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 32,
                    ),
                    padding: EdgeInsets.zero,
                    onPressed: () =>
                        isPaused ? _resumeTask(task.hash) : _pauseTask(task.hash),
                  ),
                  IconButton(
                    icon: const Icon(Icons.folder_outlined, size: 20),
                    tooltip: '修改分类',
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 32,
                    ),
                    padding: EdgeInsets.zero,
                    onPressed: () => _setTaskCategory(task),
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.delete_outline,
                      size: 20,
                      color: Colors.red,
                    ),
                    tooltip: '删除',
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 32,
                    ),
                    padding: EdgeInsets.zero,
                    onPressed: () => _confirmDelete(task),
                  ),
                ],
              ],
            ),

            const SizedBox(height: 6),

            // Progress Bar
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: task.progress,
                      minHeight: 4,
                      backgroundColor: Theme.of(
                        context,
                      ).colorScheme.surfaceContainerHighest,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        isDownloading
                            ? Theme.of(context).colorScheme.primary
                            : (task.progress >= 1.0
                                  ? Colors.green
                                  : Theme.of(context).colorScheme.secondary),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${(task.progress * 100).toStringAsFixed(1)}%',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      ),
    );
  }
}
