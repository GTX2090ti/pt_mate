import 'package:flutter/material.dart';

import '../services/downloader/downloader_config.dart';
import '../services/downloader/downloader_service.dart';
import '../utils/notification_helper.dart';

/// 分类选择对话框：列出 qB 服务器分类，支持新建
/// 返回选中的分类名（空字符串 = 无分类）；取消返回 null
class CategoryPickerDialog extends StatefulWidget {
  final DownloaderConfig config;
  final String password;
  final bool allowCreate;

  const CategoryPickerDialog({
    super.key,
    required this.config,
    required this.password,
    this.allowCreate = true,
  });

  static Future<String?> show(
    BuildContext context, {
    required DownloaderConfig config,
    required String password,
    bool allowCreate = true,
  }) {
    return showDialog<String>(
      context: context,
      builder: (_) => CategoryPickerDialog(
        config: config,
        password: password,
        allowCreate: allowCreate,
      ),
    );
  }

  @override
  State<CategoryPickerDialog> createState() => _CategoryPickerDialogState();
}

class _CategoryPickerDialogState extends State<CategoryPickerDialog> {
  List<String> _categories = [];
  bool _loading = true;
  String? _error;

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
      final cats = await DownloaderService.instance.getCategories(
        config: widget.config,
        password: widget.password,
      );
      if (!mounted) return;
      setState(() {
        _categories = cats;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '加载分类失败：$e';
        _loading = false;
      });
    }
  }

  Future<void> _createCategory() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('新建分类'),
        content: TextField(
          controller: controller,
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
                Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('创建'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    try {
      await DownloaderService.instance.createCategory(
        config: widget.config,
        password: widget.password,
        category: name,
      );
      if (!mounted) return;
      NotificationHelper.showInfo(context, '分类已创建');
      await _load();
    } catch (e) {
      if (!mounted) return;
      NotificationHelper.showError(context, '创建失败：$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('选择分类'),
      content: SizedBox(
        width: 360,
        height: 320,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(_error!, style: const TextStyle(color: Colors.red)),
                    const SizedBox(height: 16),
                    ElevatedButton(onPressed: _load, child: const Text('重试')),
                  ],
                ),
              )
            : ListView(
                children: [
                  ListTile(
                    leading: const Icon(Icons.clear),
                    title: const Text('无分类'),
                    onTap: () => Navigator.pop(context, ''),
                  ),
                  ..._categories.map(
                    (c) => ListTile(
                      leading: const Icon(Icons.folder_outlined),
                      title: Text(c),
                      onTap: () => Navigator.pop(context, c),
                    ),
                  ),
                  if (widget.allowCreate)
                    ListTile(
                      leading: const Icon(Icons.add),
                      title: const Text('新建分类…'),
                      textColor: Theme.of(context).colorScheme.primary,
                      onTap: _createCategory,
                    ),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
      ],
    );
  }
}
