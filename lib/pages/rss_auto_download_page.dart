import 'package:flutter/material.dart';

import '../services/downloader/downloader_models.dart';
import '../services/downloader/rss_auto_download_service.dart';
import 'package:pt_mate/utils/notification_helper.dart';

/// RSS 自动下载管理页
///
/// 管理 qBittorrent 内置 RSS 订阅源与自动下载规则。
class RssAutoDownloadPage extends StatefulWidget {
  const RssAutoDownloadPage({super.key});

  @override
  State<RssAutoDownloadPage> createState() => _RssAutoDownloadPageState();
}

class _RssAutoDownloadPageState extends State<RssAutoDownloadPage> {
  bool _loading = true;
  String? _error;
  List<RssFeed> _feeds = [];
  List<RssRule> _rules = [];

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
      final feeds = await RssAutoDownloadService.instance.getFeeds();
      final rules = await RssAutoDownloadService.instance.getRules();
      if (!mounted) return;
      setState(() {
        _feeds = feeds;
        _rules = rules;
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

  Future<void> _addFeed() async {
    final controller = TextEditingController();
    final url = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('添加 RSS 订阅源'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'https://example.com/rss',
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
      await RssAutoDownloadService.instance.addFeed(url.trim());
      if (!mounted) return;
      NotificationHelper.showInfo(context, '订阅源已添加');
      await _load();
    } catch (e) {
      if (!mounted) return;
      NotificationHelper.showError(context, '添加失败: $e');
    }
  }

  Future<void> _addRule() async {
    final result = await showDialog<_RssRuleDraft>(
      context: context,
      builder: (_) => _RssRuleEditor(allFeeds: _feeds),
    );
    if (result == null) return;
    try {
      await RssAutoDownloadService.instance.saveRule(
        RssRule(
          name: result.name,
          enabled: result.enabled,
          mustContain: result.mustContain,
          mustNotContain: result.mustNotContain,
          useRegex: result.useRegex,
          affectedFeeds: result.affectedFeeds,
          ignoreDays: 0,
          lastMatch: '',
          savePath: result.savePath,
          assignedCategory: result.category,
          assignedTags: result.tags,
          episodeFilter: '',
        ),
      );
      if (!mounted) return;
      NotificationHelper.showInfo(context, '规则已保存');
      await _load();
    } catch (e) {
      if (!mounted) return;
      NotificationHelper.showError(context, '保存失败: $e');
    }
  }

  Future<void> _editRule(RssRule rule) async {
    final result = await showDialog<_RssRuleDraft>(
      context: context,
      builder: (_) => _RssRuleEditor(initial: rule, allFeeds: _feeds),
    );
    if (result == null) return;
    try {
      await RssAutoDownloadService.instance.saveRule(
        RssRule(
          name: rule.name,
          enabled: result.enabled,
          mustContain: result.mustContain,
          mustNotContain: result.mustNotContain,
          useRegex: result.useRegex,
          affectedFeeds: result.affectedFeeds,
          ignoreDays: 0,
          lastMatch: '',
          savePath: result.savePath,
          assignedCategory: result.category,
          assignedTags: result.tags,
          episodeFilter: '',
        ),
      );
      if (!mounted) return;
      NotificationHelper.showInfo(context, '规则已更新');
      await _load();
    } catch (e) {
      if (!mounted) return;
      NotificationHelper.showError(context, '保存失败: $e');
    }
  }

  Future<void> _removeRule(RssRule rule) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除规则'),
        content: Text('确定删除规则 "${rule.name}" 吗？'),
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
      await RssAutoDownloadService.instance.removeRule(rule.name);
      if (!mounted) return;
      NotificationHelper.showInfo(context, '规则已删除');
      await _load();
    } catch (e) {
      if (!mounted) return;
      NotificationHelper.showError(context, '删除失败: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('RSS 自动下载'),
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
                          const SizedBox(height: 12),
                          Text(
                            'RSS 功能依赖 qBittorrent 服务端（4.4+）',
                            style: TextStyle(
                              fontSize: 12,
                              color: scheme.secondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Row(
                        children: [
                          Text(
                            '订阅源（${_feeds.length}）',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          const Spacer(),
                          TextButton.icon(
                            onPressed: _addFeed,
                            icon: const Icon(Icons.add, size: 18),
                            label: const Text('添加订阅'),
                          ),
                        ],
                      ),
                      if (_feeds.isEmpty)
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(
                            '暂无订阅源。添加 PT 站点的 RSS 地址后即可自动追踪新资源。',
                            style: TextStyle(color: scheme.secondary),
                          ),
                        )
                      else
                        ..._feeds.map(
                          (feed) => Card(
                            elevation: 0,
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                              side: BorderSide(
                                color: scheme.outlineVariant.withValues(
                                  alpha: 0.5,
                                ),
                              ),
                            ),
                            child: ListTile(
                              title: Text(
                                feed.title.isEmpty ? feed.url : feed.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 13),
                              ),
                              subtitle: Text(
                                feed.url,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 11),
                              ),
                              leading: Icon(
                                feed.isUpdating
                                    ? Icons.sync
                                    : Icons.rss_feed,
                                color: scheme.primary,
                              ),
                            ),
                          ),
                        ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Text(
                            '自动下载规则（${_rules.length}）',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          const Spacer(),
                          TextButton.icon(
                            onPressed: _addRule,
                            icon: const Icon(Icons.add, size: 18),
                            label: const Text('添加规则'),
                          ),
                        ],
                      ),
                      if (_rules.isEmpty)
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(
                            '暂无规则。规则按关键词匹配订阅源中的标题，命中后自动添加下载任务。',
                            style: TextStyle(color: scheme.secondary),
                          ),
                        )
                      else
                        ..._rules.map(
                          (rule) => Card(
                            elevation: 0,
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                              side: BorderSide(
                                color: scheme.outlineVariant.withValues(
                                  alpha: 0.5,
                                ),
                              ),
                            ),
                            child: ListTile(
                              title: Row(
                                children: [
                                  Icon(
                                    rule.enabled
                                        ? Icons.check_circle
                                        : Icons.cancel,
                                    size: 16,
                                    color: rule.enabled
                                        ? Colors.green
                                        : scheme.outline,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      rule.name,
                                      maxLines: 1,
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
                                  if (rule.mustContain.isNotEmpty)
                                    Text(
                                      '包含: ${rule.mustContain}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 11),
                                    ),
                                  if (rule.mustNotContain.isNotEmpty)
                                    Text(
                                      '排除: ${rule.mustNotContain}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 11),
                                    ),
                                  if (rule.assignedCategory.isNotEmpty ||
                                      rule.assignedTags.isNotEmpty)
                                    Text(
                                      '分类: ${rule.assignedCategory.isEmpty ? '-' : rule.assignedCategory} · 标签: ${rule.assignedTags.isEmpty ? '-' : rule.assignedTags}',
                                      style: const TextStyle(fontSize: 11),
                                    ),
                                ],
                              ),
                              trailing: PopupMenuButton<String>(
                                onSelected: (value) {
                                  switch (value) {
                                    case 'edit':
                                      _editRule(rule);
                                      break;
                                    case 'remove':
                                      _removeRule(rule);
                                      break;
                                  }
                                },
                                itemBuilder: (context) => [
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
                          ),
                        ),
                      const SizedBox(height: 24),
                      Text(
                        '提示：规则由 qBittorrent 服务端执行，无需保持本应用运行。支持正则（useRegex）。',
                        style: TextStyle(fontSize: 12, color: scheme.secondary),
                      ),
                    ],
                  )),
    );
  }
}

class _RssRuleDraft {
  final String name;
  final bool enabled;
  final String mustContain;
  final String mustNotContain;
  final bool useRegex;
  final List<String> affectedFeeds;
  final String savePath;
  final String category;
  final String tags;

  const _RssRuleDraft({
    required this.name,
    required this.enabled,
    required this.mustContain,
    required this.mustNotContain,
    required this.useRegex,
    required this.affectedFeeds,
    required this.savePath,
    required this.category,
    required this.tags,
  });
}

class _RssRuleEditor extends StatefulWidget {
  final RssRule? initial;
  final List<RssFeed> allFeeds;

  const _RssRuleEditor({this.initial, this.allFeeds = const []});

  @override
  State<_RssRuleEditor> createState() => _RssRuleEditorState();
}

class _RssRuleEditorState extends State<_RssRuleEditor> {
  late TextEditingController _nameController;
  late TextEditingController _containController;
  late TextEditingController _notContainController;
  late TextEditingController _savePathController;
  late TextEditingController _categoryController;
  late TextEditingController _tagsController;
  late bool _enabled;
  late bool _useRegex;
  late bool _affectedFeeds;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _nameController = TextEditingController(text: initial?.name ?? '');
    _containController = TextEditingController(
      text: initial?.mustContain ?? '',
    );
    _notContainController = TextEditingController(
      text: initial?.mustNotContain ?? '',
    );
    _savePathController = TextEditingController(text: initial?.savePath ?? '');
    _categoryController = TextEditingController(
      text: initial?.assignedCategory ?? '',
    );
    _tagsController = TextEditingController(text: initial?.assignedTags ?? '');
    _enabled = initial?.enabled ?? true;
    _useRegex = initial?.useRegex ?? false;
    _affectedFeeds = (initial?.affectedFeeds ?? const []).isEmpty;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _containController.dispose();
    _notContainController.dispose();
    _savePathController.dispose();
    _categoryController.dispose();
    _tagsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.initial == null ? '添加规则' : '编辑规则'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: '规则名称'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _containController,
              decoration: const InputDecoration(
                labelText: '必须包含（关键词，逗号分隔）',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notContainController,
              decoration: const InputDecoration(
                labelText: '必须不包含（可选）',
              ),
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              title: const Text('使用正则匹配'),
              value: _useRegex,
              onChanged: (v) => setState(() => _useRegex = v),
              dense: true,
              contentPadding: EdgeInsets.zero,
            ),
            SwitchListTile(
              title: const Text('应用到全部订阅源'),
              value: _affectedFeeds,
              onChanged: (v) => setState(() => _affectedFeeds = v),
              dense: true,
              contentPadding: EdgeInsets.zero,
            ),
            SwitchListTile(
              title: const Text('启用'),
              value: _enabled,
              onChanged: (v) => setState(() => _enabled = v),
              dense: true,
              contentPadding: EdgeInsets.zero,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _savePathController,
              decoration: const InputDecoration(
                labelText: '保存路径（可选，留空用默认）',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _categoryController,
              decoration: const InputDecoration(labelText: '分类（可选）'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _tagsController,
              decoration: const InputDecoration(labelText: '标签（逗号分隔，可选）'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('保存'),
        ),
      ],
    );
  }

  void _submit() {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请输入规则名称')));
      return;
    }
    Navigator.pop(
      context,
      _RssRuleDraft(
        name: name,
        enabled: _enabled,
        mustContain: _containController.text.trim(),
        mustNotContain: _notContainController.text.trim(),
        useRegex: _useRegex,
        affectedFeeds: _affectedFeeds
            ? widget.allFeeds.map((f) => f.url).toList()
            : const [],
        savePath: _savePathController.text.trim(),
        category: _categoryController.text.trim(),
        tags: _tagsController.text.trim(),
      ),
    );
  }
}
