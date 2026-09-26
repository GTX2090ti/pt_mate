import 'dart:async';

import 'package:flutter/material.dart';

import '../services/downloader/downloader_config.dart';
import '../services/downloader/downloader_models.dart';
import '../services/downloader/downloader_service.dart';
import '../utils/format.dart';
import 'package:pt_mate/utils/notification_helper.dart';

/// 任务文件视图
/// 对应 qBittorrent 客户端种子详情的"文件"标签，可嵌入 Tab 页
/// 显示文件列表，支持勾选下载/跳过文件（通过文件优先级实现）
class TorrentFilesView extends StatefulWidget {
  final String taskHash;
  final DownloaderConfig config;
  final String password;

  const TorrentFilesView({
    super.key,
    required this.taskHash,
    required this.config,
    required this.password,
  });

  @override
  State<TorrentFilesView> createState() => _TorrentFilesViewState();
}

class _TorrentFilesViewState extends State<TorrentFilesView>
    with AutomaticKeepAliveClientMixin {
  List<TorrentFile> _files = [];
  bool _loading = true;
  String? _error;
  bool _applying = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final files = await DownloaderService.instance.getTorrentFiles(
        config: widget.config,
        password: widget.password,
        hash: widget.taskHash,
      );
      if (!mounted) return;
      setState(() {
        _files = files;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        if (!silent) _error = '加载文件失败：$e';
        _loading = false;
      });
    }
  }

  /// 打开文件选择对话框：勾选要下载的文件，其余跳过
  Future<void> _openFileSelector() async {
    final files = _files;
    if (files.isEmpty) return;
    final selected = <int>{};
    for (final f in files) {
      if (f.selected) selected.add(f.index);
    }

    // 全屏选择页
    final result = await Navigator.of(context).push<Set<int>>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _FileSelectorPage(
          files: files,
          initiallySelected: selected,
        ),
      ),
    );

    if (result == null) return;

    // 勾选的文件设为优先级 1（普通），未勾选的设为 0（跳过）
    setState(() => _applying = true);
    try {
      final selectedIds = result.toList()..sort();
      final skippedIds = files
          .where((f) => !selectedIds.contains(f.index))
          .map((f) => f.index)
          .toList();
      if (skippedIds.isNotEmpty) {
        await DownloaderService.instance.setFilePriority(
          config: widget.config,
          password: widget.password,
          hash: widget.taskHash,
          ids: skippedIds,
          priority: 0,
        );
      }
      if (selectedIds.isNotEmpty) {
        await DownloaderService.instance.setFilePriority(
          config: widget.config,
          password: widget.password,
          hash: widget.taskHash,
          ids: selectedIds,
          priority: 1,
        );
      }
      if (!mounted) return;
      NotificationHelper.showInfo(context, '文件选择已应用');
      await _load(silent: true);
    } catch (e) {
      if (!mounted) return;
      NotificationHelper.showError(context, '应用失败：$e');
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final scheme = Theme.of(context).colorScheme;
    return _loading
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
        : _files.isEmpty
        ? Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.folder_open, size: 64, color: scheme.outline),
                const SizedBox(height: 12),
                Text(
                  '没有文件',
                  style: TextStyle(fontSize: 16, color: scheme.outline),
                ),
                const SizedBox(height: 4),
                Text(
                  '该任务没有可管理的文件',
                  style: TextStyle(fontSize: 12, color: scheme.outline),
                ),
              ],
            ),
          )
        : Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                color: scheme.surfaceContainerLow,
                child: Row(
                  children: [
                    Text(
                      '共 ${_files.length} 个文件 · '
                      '${_files.where((f) => f.selected).length} 个选中',
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.secondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: _applying ? null : _openFileSelector,
                      icon: _applying
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                              ),
                            )
                          : const Icon(Icons.checklist, size: 16),
                      label: const Text('选择文件'),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.only(bottom: 16),
                  itemCount: _files.length,
                  itemBuilder: (context, index) {
                    return _buildFileCard(_files[index]);
                  },
                ),
              ),
            ],
          );
  }

  Widget _buildFileCard(TorrentFile file) {
    final scheme = Theme.of(context).colorScheme;
    final selected = file.selected;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: selected
              ? scheme.primary.withValues(alpha: 0.4)
              : scheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  selected
                      ? Icons.insert_drive_file_outlined
                      : Icons.block,
                  size: 16,
                  color: selected ? scheme.primary : scheme.outline,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    file.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: selected ? null : scheme.outline,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: selected
                        ? scheme.primaryContainer
                        : scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    selected ? '下载' : '跳过',
                    style: TextStyle(
                      fontSize: 10,
                      color: selected
                          ? scheme.onPrimaryContainer
                          : scheme.outline,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  Formatters.dataFromBytes(file.size),
                  style: TextStyle(fontSize: 11, color: scheme.secondary),
                ),
                const Spacer(),
                Text(
                  '${(file.progress * 100).toStringAsFixed(1)}%',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: selected ? null : scheme.outline,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: file.progress.clamp(0.0, 1.0),
                minHeight: 4,
                backgroundColor: scheme.surfaceContainerHighest,
              ),
            ),
          ],
        ),
      ),
    );
  }
}


/// 全屏文件选择页：勾选要下载的文件，其余跳过
class _FileSelectorPage extends StatefulWidget {
  final List<TorrentFile> files;
  final Set<int> initiallySelected;

  const _FileSelectorPage({
    required this.files,
    required this.initiallySelected,
  });

  @override
  State<_FileSelectorPage> createState() => _FileSelectorPageState();
}

class _FileSelectorPageState extends State<_FileSelectorPage> {
  late final Set<int> _selected = {...widget.initiallySelected};

  void _selectAll() {
    setState(() {
      _selected
        ..clear()
        ..addAll(widget.files.map((f) => f.index));
    });
  }

  void _clearAll() {
    setState(() {
      _selected.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final files = widget.files;
    return Scaffold(
      appBar: AppBar(
        title: Text('选择下载文件（${_selected.length}/${files.length}）'),
        actions: [
          TextButton(
            onPressed: _clearAll,
            child: const Text('全不选'),
          ),
          TextButton(
            onPressed: _selectAll,
            child: const Text('全选'),
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            child: Text(
              '已选 ${_selected.length} 个 · 取消勾选的文件将跳过下载',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.secondary,
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              itemCount: files.length,
              itemBuilder: (context, index) {
                final f = files[index];
                final checked = _selected.contains(f.index);
                return CheckboxListTile(
                  dense: true,
                  value: checked,
                  title: Text(
                    f.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13),
                  ),
                  subtitle: Text(
                    '${Formatters.dataFromBytes(f.size)}'
                    ' · ${(f.progress * 100).toStringAsFixed(1)}%'
                    '${f.selected ? '' : ' · 未下载'}',
                    style: const TextStyle(fontSize: 11),
                  ),
                  onChanged: (value) {
                    setState(() {
                      if (value == true) {
                        _selected.add(f.index);
                      } else {
                        _selected.remove(f.index);
                      }
                    });
                  },
                );
              },
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('取消'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: _selected.isEmpty
                      ? null
                      : () => Navigator.of(context).pop(_selected),
                  child: const Text('确定'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
