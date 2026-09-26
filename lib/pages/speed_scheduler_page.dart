import 'package:flutter/material.dart';

import '../services/downloader/downloader_models.dart';
import '../services/downloader/speed_scheduler_service.dart';
import '../utils/format.dart';

/// 限速调度设置页
///
/// 按"星期 + 时间段"配置下载/上传限速规则，到点自动应用。
/// 规则本地存储，由 SpeedSchedulerService 定时执行。
class SpeedSchedulerPage extends StatefulWidget {
  const SpeedSchedulerPage({super.key});

  @override
  State<SpeedSchedulerPage> createState() => _SpeedSchedulerPageState();
}

class _SpeedSchedulerPageState extends State<SpeedSchedulerPage> {
  bool _enabled = false;
  bool _loading = true;
  List<SpeedScheduleEntry> _entries = [];

  static const List<String> _weekdays = [
    '周一',
    '周二',
    '周三',
    '周四',
    '周五',
    '周六',
    '周日',
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final enabled = await SpeedSchedulerService.instance.isEnabled();
    final entries = await SpeedSchedulerService.instance.loadSchedule();
    if (!mounted) return;
    setState(() {
      _enabled = enabled;
      _entries = entries;
      _loading = false;
    });
  }

  Future<void> _toggle(bool value) async {
    setState(() => _enabled = value);
    await SpeedSchedulerService.instance.setEnabled(value);
    if (value) {
      SpeedSchedulerService.instance.start();
    }
  }

  Future<void> _addEntry() async {
    final result = await showDialog<_SpeedEntryDraft>(
      context: context,
      builder: (_) => const _SpeedEntryEditor(),
    );
    if (result == null) return;
    setState(() {
      _entries.add(
        SpeedScheduleEntry(
          dayOfWeek: result.dayOfWeek,
          startMinuteOfDay: result.startMinute,
          endMinuteOfDay: result.endMinute,
          dlLimitKib: result.dlLimitKib,
          upLimitKib: result.upLimitKib,
        ),
      );
    });
    await _save();
  }

  Future<void> _editEntry(int index) async {
    final current = _entries[index];
    final result = await showDialog<_SpeedEntryDraft>(
      context: context,
      builder: (_) => _SpeedEntryEditor(initial: current),
    );
    if (result == null) return;
    setState(() {
      _entries[index] = SpeedScheduleEntry(
        dayOfWeek: result.dayOfWeek,
        startMinuteOfDay: result.startMinute,
        endMinuteOfDay: result.endMinute,
        dlLimitKib: result.dlLimitKib,
        upLimitKib: result.upLimitKib,
      );
    });
    await _save();
  }

  Future<void> _removeEntry(int index) async {
    setState(() => _entries.removeAt(index));
    await _save();
  }

  Future<void> _save() async {
    await SpeedSchedulerService.instance.saveSchedule(_entries);
    if (_enabled) {
      SpeedSchedulerService.instance.start();
    }
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('调度规则已保存')));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('限速调度'),
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
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: SwitchListTile(
                    title: const Text('启用限速调度'),
                    subtitle: Text(
                      _enabled
                          ? '已开启：到点自动应用限速规则'
                          : '未开启：限速保持手动控制',
                    ),
                    value: _enabled,
                    onChanged: _toggle,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Text(
                      '调度规则',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: _addEntry,
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('添加规则'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (_entries.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      '暂无规则。点击"添加规则"创建时间段限速。',
                      style: TextStyle(color: scheme.secondary),
                      textAlign: TextAlign.center,
                    ),
                  )
                else
                  ..._entries.asMap().entries.map(
                    (entry) => Card(
                      elevation: 0,
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                        side: BorderSide(
                          color: scheme.outlineVariant.withValues(alpha: 0.5),
                        ),
                      ),
                      child: ListTile(
                        title: Text(
                          '${_weekdays[entry.value.dayOfWeek - 1]}  '
                          '${_fmtTime(entry.value.startMinuteOfDay)} - '
                          '${_fmtTime(entry.value.endMinuteOfDay)}',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: Text(
                          '下载 ${_fmtLimit(entry.value.dlLimitKib)} · '
                          '上传 ${_fmtLimit(entry.value.upLimitKib)}',
                          style: const TextStyle(fontSize: 12),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: '编辑',
                              icon: const Icon(Icons.edit_outlined, size: 20),
                              onPressed: () => _editEntry(entry.key),
                            ),
                            IconButton(
                              tooltip: '删除',
                              icon: Icon(
                                Icons.delete_outline,
                                size: 20,
                                color: scheme.error,
                              ),
                              onPressed: () => _removeEntry(entry.key),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 24),
                Text(
                  '说明：限速值为 -1 表示不限速。跨天时间段（如 23:00 → 07:00）表示夜间限速。',
                  style: TextStyle(fontSize: 12, color: scheme.secondary),
                ),
              ],
            ),
    );
  }

  String _fmtTime(int minuteOfDay) {
    final h = minuteOfDay ~/ 60;
    final m = minuteOfDay % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }

  String _fmtLimit(int limitKib) {
    if (limitKib <= 0) return '不限速';
    return '${FormatUtil.formatSpeed(limitKib * 1024)}';
  }
}

class _SpeedEntryDraft {
  final int dayOfWeek;
  final int startMinute;
  final int endMinute;
  final int dlLimitKib;
  final int upLimitKib;

  const _SpeedEntryDraft({
    required this.dayOfWeek,
    required this.startMinute,
    required this.endMinute,
    required this.dlLimitKib,
    required this.upLimitKib,
  });
}

class _SpeedEntryEditor extends StatefulWidget {
  final SpeedScheduleEntry? initial;

  const _SpeedEntryEditor({this.initial});

  @override
  State<_SpeedEntryEditor> createState() => _SpeedEntryEditorState();
}

class _SpeedEntryEditorState extends State<_SpeedEntryEditor> {
  late int _dayOfWeek;
  late TimeOfDay _startTime;
  late TimeOfDay _endTime;
  late TextEditingController _dlController;
  late TextEditingController _upController;
  late bool _dlUnlimited;
  late bool _upUnlimited;

  static const List<String> _weekdays = [
    '周一',
    '周二',
    '周三',
    '周四',
    '周五',
    '周六',
    '周日',
  ];

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _dayOfWeek = initial?.dayOfWeek ?? 1;
    _startTime = TimeOfDay(
      hour: (initial?.startMinuteOfDay ?? 0) ~/ 60,
      minute: (initial?.startMinuteOfDay ?? 0) % 60,
    );
    _endTime = TimeOfDay(
      hour: (initial?.endMinuteOfDay ?? 1439) ~/ 60,
      minute: (initial?.endMinuteOfDay ?? 1439) % 60,
    );
    _dlUnlimited = (initial?.dlLimitKib ?? -1) <= 0;
    _upUnlimited = (initial?.upLimitKib ?? -1) <= 0;
    _dlController = TextEditingController(
      text: _dlUnlimited ? '0' : (initial?.dlLimitKib ?? 0).toString(),
    );
    _upController = TextEditingController(
      text: _upUnlimited ? '0' : (initial?.upLimitKib ?? 0).toString(),
    );
  }

  @override
  void dispose() {
    _dlController.dispose();
    _upController.dispose();
    super.dispose();
  }

  Future<void> _pickStart() async {
    final picked = await showTimePicker(context: context, initialTime: _startTime);
    if (picked != null) setState(() => _startTime = picked);
  }

  Future<void> _pickEnd() async {
    final picked = await showTimePicker(context: context, initialTime: _endTime);
    if (picked != null) setState(() => _endTime = picked);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.initial == null ? '添加调度规则' : '编辑调度规则'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<int>(
              initialValue: _dayOfWeek,
              decoration: const InputDecoration(labelText: '星期'),
              items: List.generate(
                7,
                (i) => DropdownMenuItem(value: i + 1, child: Text(_weekdays[i])),
              ),
              onChanged: (v) {
                if (v != null) setState(() => _dayOfWeek = v);
              },
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _pickStart,
                    child: Text('开始 ${_startTime.format(context)}'),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Text('至'),
                ),
                Expanded(
                  child: OutlinedButton(
                    onPressed: _pickEnd,
                    child: Text('结束 ${_endTime.format(context)}'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              title: const Text('下载不限速'),
              value: _dlUnlimited,
              onChanged: (v) => setState(() => _dlUnlimited = v),
              dense: true,
              contentPadding: EdgeInsets.zero,
            ),
            if (!_dlUnlimited)
              TextField(
                controller: _dlController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: '下载限速 (KiB/s)',
                  helperText: '例如 10240 = 10MB/s',
                ),
              ),
            const SizedBox(height: 8),
            SwitchListTile(
              title: const Text('上传不限速'),
              value: _upUnlimited,
              onChanged: (v) => setState(() => _upUnlimited = v),
              dense: true,
              contentPadding: EdgeInsets.zero,
            ),
            if (!_upUnlimited)
              TextField(
                controller: _upController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: '上传限速 (KiB/s)',
                  helperText: '例如 5120 = 5MB/s',
                ),
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
    final dl = _dlUnlimited ? -1 : int.tryParse(_dlController.text.trim());
    final up = _upUnlimited ? -1 : int.tryParse(_upController.text.trim());
    if (dl == null || up == null || dl < -1 || up < -1) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请输入有效限速值')));
      return;
    }
    final startMinute = _startTime.hour * 60 + _startTime.minute;
    final endMinute = _endTime.hour * 60 + _endTime.minute;
    Navigator.pop(
      context,
      _SpeedEntryDraft(
        dayOfWeek: _dayOfWeek,
        startMinute: startMinute,
        endMinute: endMinute,
        dlLimitKib: dl,
        upLimitKib: up,
      ),
    );
  }
}
