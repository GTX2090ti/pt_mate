import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/storage/storage_service.dart';
import '../services/theme/theme_manager.dart';
import '../services/downloader/downloader_config.dart';
import '../services/downloader/downloader_service.dart';
import '../utils/notification_helper.dart';
import 'download_health_page.dart';
import 'speed_scheduler_page.dart';
import 'rss_auto_download_page.dart';

/// qB 客户端风格的下载管理设置页
/// 板块化布局：外观 / 高级，与 qBittorrent 客户端设置页一致
class QbSettingsPage extends StatefulWidget {
  const QbSettingsPage({super.key});

  @override
  State<QbSettingsPage> createState() => _QbSettingsPageState();
}

class _QbSettingsPageState extends State<QbSettingsPage> {
  int _refreshInterval = 5; // 秒
  bool _showAllTasks = false;
  bool _loading = true;

  // 分类管理
  DownloaderConfig? _config;
  String? _password;
  List<String> _categories = [];
  bool _catsLoading = false;
  String? _catsError;

  @override
  void initState() {
    super.initState();
    _load();
    _loadDownloader();
  }

  Future<void> _loadDownloader() async {
    try {
      final defId = await StorageService.instance.loadDefaultDownloaderId();
      if (defId == null) return;
      final configs = await StorageService.instance.loadDownloaderConfigs();
      final configMap = configs.firstWhere(
        (e) => e['id'] == defId,
        orElse: () =>
            configs.isNotEmpty ? configs.first : throw Exception('未找到默认下载器'),
      );
      final config = DownloaderConfig.fromJson(configMap);
      final pwd = await StorageService.instance.loadDownloaderPassword(
        config.id,
      );
      if (!mounted) return;
      setState(() {
        _config = config;
        _password = pwd;
      });
      await _loadCategories();
    } catch (_) {
      // 无下载器配置时不显示分类板块错误
    }
  }

  Future<void> _loadCategories() async {
    final config = _config;
    final pwd = _password;
    if (config == null || (pwd ?? '').isEmpty) return;
    setState(() {
      _catsLoading = true;
      _catsError = null;
    });
    try {
      final cats = await DownloaderService.instance.getCategories(
        config: config,
        password: pwd!,
      );
      if (!mounted) return;
      setState(() {
        _categories = cats;
        _catsLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _catsError = '加载分类失败：$e';
        _catsLoading = false;
      });
    }
  }

  Future<void> _addCategory() async {
    final config = _config;
    final pwd = _password;
    if (config == null || (pwd ?? '').isEmpty) {
      NotificationHelper.showError(context, '未配置下载器');
      return;
    }
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        final ctrl = TextEditingController();
        return AlertDialog(
          title: const Text('新增分类'),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: '分类名称',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.pop(dialogContext, ctrl.text.trim()),
              child: const Text('创建'),
            ),
          ],
        );
      },
    );
    if (result == null || result.isEmpty) return;
    try {
      await DownloaderService.instance.createCategory(
        config: config,
        password: pwd!,
        category: result,
      );
      if (!mounted) return;
      NotificationHelper.showInfo(context, '分类已创建');
      await _loadCategories();
    } catch (e) {
      if (!mounted) return;
      NotificationHelper.showError(context, '创建失败：$e');
    }
  }

  Future<void> _deleteCategory(String category) async {
    final config = _config;
    final pwd = _password;
    if (config == null || (pwd ?? '').isEmpty) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除分类'),
        content: Text('确定删除分类"$category"吗？（不会删除已归类任务的文件）'),
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
      await DownloaderService.instance.deleteCategory(
        config: config,
        password: pwd!,
        category: category,
      );
      if (!mounted) return;
      NotificationHelper.showInfo(context, '分类已删除');
      await _loadCategories();
    } catch (e) {
      if (!mounted) return;
      NotificationHelper.showError(context, '删除失败：$e');
    }
  }

  Future<void> _load() async {
    final interval = await StorageService.instance
        .loadDownloadTasksRefreshInterval();
    final showAll = await StorageService.instance.loadDownloadTasksShowAll();
    if (!mounted) return;
    setState(() {
      _refreshInterval = interval;
      _showAllTasks = showAll;
      _loading = false;
    });
  }

  Future<void> _saveRefreshInterval(int seconds) async {
    setState(() {
      _refreshInterval = seconds;
    });
    await StorageService.instance
        .saveDownloadTasksRefreshInterval(seconds);
    if (!mounted) return;
    NotificationHelper.showInfo(context, '刷新间隔已设为 $seconds 秒');
  }

  Future<void> _saveShowAll(bool value) async {
    setState(() {
      _showAllTasks = value;
    });
    await StorageService.instance.saveDownloadTasksShowAll(value);
  }

  String _getThemeModeText(AppThemeMode mode) {
    switch (mode) {
      case AppThemeMode.system:
        return '跟随系统（夜间模式跟随系统）';
      case AppThemeMode.light:
        return '浅色';
      case AppThemeMode.dark:
        return '深色';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
        leading: IconButton(
          tooltip: '返回',
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        automaticallyImplyLeading: false,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                _sectionHeader(context, '外观'),
                Card(
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                      color: Theme.of(
                        context,
                      ).colorScheme.outlineVariant.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Column(
                    children: [
                      Consumer<ThemeManager>(
                        builder: (context, themeManager, child) {
                          return Column(
                            children: [
                              ListTile(
                                leading: const Icon(Icons.brightness_6),
                                title: const Text('主题'),
                                subtitle: Text(
                                  _getThemeModeText(themeManager.themeMode),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                ),
                                child: SegmentedButton<AppThemeMode>(
                                  segments: const [
                                    ButtonSegment(
                                      value: AppThemeMode.system,
                                      label: Text('自动'),
                                      icon: Icon(Icons.brightness_auto),
                                    ),
                                    ButtonSegment(
                                      value: AppThemeMode.light,
                                      label: Text('浅色'),
                                      icon: Icon(Icons.light_mode),
                                    ),
                                    ButtonSegment(
                                      value: AppThemeMode.dark,
                                      label: Text('深色'),
                                      icon: Icon(Icons.dark_mode),
                                    ),
                                  ],
                                  selected: {themeManager.themeMode},
                                  onSelectionChanged: (selection) {
                                    themeManager.setThemeMode(selection.first);
                                  },
                                ),
                              ),
                              const SizedBox(height: 8),
                            ],
                          );
                        },
                      ),
                      const Divider(height: 1, indent: 56),
                      Consumer<ThemeManager>(
                        builder: (context, themeManager, child) {
                          return SwitchListTile(
                            secondary: const Icon(Icons.palette),
                            title: const Text('动态取色'),
                            subtitle: const Text('根据壁纸自动调整主题色'),
                            value: themeManager.useDynamicColor,
                            onChanged: (value) {
                              themeManager.setUseDynamicColor(value);
                            },
                          );
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _sectionHeader(context, '分类'),
                Card(
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                      color: Theme.of(
                        context,
                      ).colorScheme.outlineVariant.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Column(
                    children: [
                      if (_catsLoading)
                        const Padding(
                          padding: EdgeInsets.all(16),
                          child: Center(
                            child: SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                              ),
                            ),
                          ),
                        )
                      else if (_catsError != null)
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            children: [
                              Text(
                                _catsError!,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.red,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 8),
                              OutlinedButton.icon(
                                onPressed: _loadCategories,
                                icon: const Icon(Icons.refresh, size: 18),
                                label: const Text('重试'),
                              ),
                            ],
                          ),
                        )
                      else if (_config == null ||
                          (_password ?? '').isEmpty)
                        const ListTile(
                          leading: Icon(Icons.info_outline),
                          title: Text('未配置下载器'),
                          subtitle: Text('在下载器设置中添加后即可管理分类'),
                        )
                      else if (_categories.isEmpty)
                        ListTile(
                          leading: const Icon(Icons.folder_open),
                          title: const Text('暂无分类'),
                          subtitle: const Text('点击下方按钮新增'),
                        )
                      else
                        ..._categories.map(
                          (c) => ListTile(
                            dense: true,
                            leading: const Icon(Icons.folder_outlined),
                            title: Text(c),
                            trailing: IconButton(
                              tooltip: '删除分类',
                              icon: const Icon(
                                Icons.delete_outline,
                                size: 20,
                                color: Colors.red,
                              ),
                              onPressed: () => _deleteCategory(c),
                            ),
                          ),
                        ),
                      const Divider(height: 1, indent: 16),
                      ListTile(
                        leading: const Icon(Icons.add),
                        title: const Text('新增分类'),
                        textColor: Theme.of(context).colorScheme.primary,
                        trailing: const Icon(Icons.chevron_right),
                        onTap: _addCategory,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _sectionHeader(context, '任务工具'),
                Card(
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                      color: Theme.of(
                        context,
                      ).colorScheme.outlineVariant.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.monitor_heart_outlined),
                        title: const Text('下载健康'),
                        subtitle: const Text('做种健康度、保种提醒与磁盘预警'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const DownloadHealthPage(),
                            ),
                          );
                        },
                      ),
                      const Divider(height: 1, indent: 56),
                      ListTile(
                        leading: const Icon(Icons.schedule),
                        title: const Text('限速调度'),
                        subtitle: const Text('按时间段自动限速/提速'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const SpeedSchedulerPage(),
                            ),
                          );
                        },
                      ),
                      const Divider(height: 1, indent: 56),
                      ListTile(
                        leading: const Icon(Icons.rss_feed),
                        title: const Text('RSS 自动下载'),
                        subtitle: const Text('按 RSS 规则自动下载新种子'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const RssAutoDownloadPage(),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _sectionHeader(context, '高级'),
                Card(
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                      color: Theme.of(
                        context,
                      ).colorScheme.outlineVariant.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.autorenew),
                        title: const Text('自动刷新间隔'),
                        subtitle: const Text('任务列表自动刷新间隔'),
                        trailing: DropdownButton<int>(
                          value: _refreshInterval,
                          underline: const SizedBox.shrink(),
                          items: const [
                            DropdownMenuItem(value: 3, child: Text('3 秒')),
                            DropdownMenuItem(value: 5, child: Text('5 秒')),
                            DropdownMenuItem(value: 10, child: Text('10 秒')),
                            DropdownMenuItem(value: 30, child: Text('30 秒')),
                          ],
                          onChanged: (value) {
                            if (value != null) _saveRefreshInterval(value);
                          },
                        ),
                      ),
                      const Divider(height: 1, indent: 56),
                      SwitchListTile(
                        secondary: const Icon(Icons.filter_list),
                        title: const Text('显示全部任务'),
                        subtitle: const Text('默认显示所有状态的任务（含完成/暂停）'),
                        value: _showAllTasks,
                        onChanged: _saveShowAll,
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _sectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          title,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}
