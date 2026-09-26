import 'dart:async';

import 'package:flutter/material.dart';

import '../services/downloader/downloader_config.dart';
import '../services/downloader/downloader_models.dart';
import '../services/downloader/downloader_service.dart';
import '../utils/format.dart';

/// 任务连接节点（Peers）视图
/// 对应 qBittorrent 客户端种子详情的"节点"标签，可嵌入 Tab 页
class TorrentPeersView extends StatefulWidget {
  final String taskHash;
  final DownloaderConfig config;
  final String password;

  const TorrentPeersView({
    super.key,
    required this.taskHash,
    required this.config,
    required this.password,
  });

  @override
  State<TorrentPeersView> createState() => _TorrentPeersViewState();
}

class _TorrentPeersViewState extends State<TorrentPeersView>
    with AutomaticKeepAliveClientMixin {
  List<TorrentPeer> _peers = [];
  bool _loading = true;
  String? _error;
  Timer? _refreshTimer;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) _load(silent: true);
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
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
      final peers = await DownloaderService.instance.getTorrentPeers(
        config: widget.config,
        password: widget.password,
        hash: widget.taskHash,
      );
      if (!mounted) return;
      setState(() {
        _peers = peers;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        if (!silent) _error = '加载节点失败：$e';
        _loading = false;
      });
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
          : _peers.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.hub_outlined, size: 64, color: scheme.outline),
                  const SizedBox(height: 12),
                  Text(
                    '没有节点',
                    style: TextStyle(fontSize: 16, color: scheme.outline),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '下载/做种中会显示已连接的节点',
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
                  child: Text(
                    '共 ${_peers.length} 个节点',
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.secondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.only(bottom: 16),
                    itemCount: _peers.length,
                    itemBuilder: (context, index) {
                      return _buildPeerCard(_peers[index]);
                    },
                  ),
                ),
              ],
            );
  }

  Widget _buildPeerCard(TorrentPeer peer) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: scheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 第一行：IP:端口 + 国旗 + 连接类型
            Row(
              children: [
                Icon(Icons.dns_outlined, size: 14, color: scheme.primary),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    '${peer.ip}:${peer.port}',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (peer.country.isNotEmpty) ...[
                  Text(
                    peer.country,
                    style: TextStyle(
                      fontSize: 11,
                      color: scheme.secondary,
                    ),
                  ),
                  const SizedBox(width: 4),
                ],
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    peer.connectionTypeText,
                    style: TextStyle(
                      fontSize: 10,
                      color: scheme.onSecondaryContainer,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            // 第二行：客户端 + flags
            Row(
              children: [
                Icon(Icons.bolt_outlined, size: 14, color: scheme.secondary),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    peer.client.isEmpty ? '未知客户端' : peer.client,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: scheme.secondary),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            // 第三行：速度
            Row(
              children: [
                _speedBadge(
                  Icons.arrow_downward,
                  '↓ ${Formatters.speedFromBytesPerSec(peer.dlSpeed)}',
                  Colors.green,
                ),
                const SizedBox(width: 8),
                _speedBadge(
                  Icons.arrow_upward,
                  '↑ ${Formatters.speedFromBytesPerSec(peer.upSpeed)}',
                  scheme.primary,
                ),
                const Spacer(),
                Text(
                  '已下 ${Formatters.dataFromBytes(peer.downloaded)}',
                  style: TextStyle(fontSize: 10, color: scheme.secondary),
                ),
                const SizedBox(width: 6),
                Text(
                  '已上 ${Formatters.dataFromBytes(peer.uploaded)}',
                  style: TextStyle(fontSize: 10, color: scheme.secondary),
                ),
              ],
            ),
            const SizedBox(height: 6),
            // 进度条
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: peer.progress.clamp(0.0, 1.0),
                      minHeight: 4,
                      backgroundColor: scheme.surfaceContainerHighest,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${(peer.progress * 100).toStringAsFixed(1)}%',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            if (peer.flagsDesc.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                '${peer.flags} · ${peer.flagsDesc}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 10, color: scheme.outline),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _speedBadge(IconData icon, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 2),
          Text(
            text,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
