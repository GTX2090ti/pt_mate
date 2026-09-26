// Keep the public `onConfigUpdated` named parameter stable.
// ignore_for_file: prefer_initializing_formals

import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';

import '../../models/app_models.dart';
import '../network/timeout_retry.dart';
import '../../utils/format.dart';

import 'downloader_client.dart';
import 'downloader_config.dart';
import 'downloader_models.dart';
import 'torrent_file_downloader_mixin.dart';
import '../network/proxy_service.dart';

/// qBittorrent下载器客户端实现
class QbittorrentClient
    with TorrentFileDownloaderMixin
    implements DownloaderClient {
  final QbittorrentConfig config;
  final String password;

  // HTTP客户端和会话管理
  late final Dio _dio;
  String? _authCookieHeader;

  // 缓存的版本信息，避免重复调用 API
  String? _cachedVersion;

  // 配置更新回调
  final Function(QbittorrentConfig)? _onConfigUpdated;

  QbittorrentClient({
    required this.config,
    required this.password,
    Function(QbittorrentConfig)? onConfigUpdated,
    Dio? dio,
  }) : _onConfigUpdated = onConfigUpdated {
    _dio = dio ?? _createDio(config);
  }

  static Dio _createDio(QbittorrentConfig config) {
    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 20),
        receiveTimeout: const Duration(seconds: 30),
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/143.0.0.0 Safari/537.36',
        },
        followRedirects: true,
        maxRedirects: 5,
      ),
    );
    // 仅在用户明确允许时才禁用证书验证
    if (config.allowSelfSignedCert) {
      dio.httpClientAdapter = IOHttpClientAdapter(
        createHttpClient: () {
          final HttpClient client = HttpClient()
            ..badCertificateCallback = (
              X509Certificate cert,
              String host,
              int port,
            ) => true;
          return client;
        },
      );
    }
    return dio;
  }

  /// 获取基础URL
  String get _baseUrl => _buildBase(config);

  /// 构建基础URL，处理各种格式的主机地址
  String _buildBase(QbittorrentConfig c) {
    var urlStr = c.host.trim();
    // 补全协议
    if (!urlStr.startsWith(RegExp(r'https?://'))) {
      urlStr = 'http://$urlStr';
    }

    try {
      final uri = Uri.parse(urlStr);
      // 优先使用配置中的端口，如果配置为0且URL中包含端口则使用URL中的端口
      final port = (c.port > 0) ? c.port : (uri.hasPort ? uri.port : null);

      // 构建新的URI，保留原有的path
      final newUri = uri.replace(port: port);
      var result = newUri.toString();

      // 移除末尾的斜杠，因为API路径通常以斜杠开头
      if (result.endsWith('/')) {
        result = result.substring(0, result.length - 1);
      }
      return result;
    } catch (e) {
      return urlStr;
    }
  }

  /// 获取API路径前缀（根据版本决定）
  String get _apiPrefix {
    if (config.version != null && config.version!.isNotEmpty) {
      // 解析版本号，判断是否支持新API路径
      final versionParts = config.version!.split('.');
      if (versionParts.isNotEmpty) {
        final majorVersion = FormatUtil.parseInt(versionParts[0]) ?? 0;
        final minorVersion = versionParts.length > 1
            ? FormatUtil.parseInt(versionParts[1]) ?? 0
            : 0;

        // qBittorrent 4.1+ 使用 /api/v2/ 路径
        if (majorVersion > 4 || (majorVersion == 4 && minorVersion >= 1)) {
          return '/api/v2';
        }
      }
    }
    // 默认使用新版本路径，如果失败会自动降级
    return '/api/v2';
  }

  /// 执行HTTP请求
  Future<Response> _request(
    String method,
    String endpoint, {
    Map<String, String>? headers,
    Map<String, dynamic>? body,
    bool requireAuth = true,
  }) async {
    final url = '$_baseUrl$_apiPrefix$endpoint';

    // 如果需要认证且没有会话，先登录
    if (requireAuth && _authCookieHeader == null) {
      await _login();
    }

    final requestHeaders = <String, String>{...?headers};

    // 添加会话Cookie
    if (_authCookieHeader != null) {
      requestHeaders['Cookie'] = _authCookieHeader!;
    }

    try {
      Response response;

      switch (method.toUpperCase()) {
        case 'GET':
          response = await _dio.get(
            url,
            queryParameters: body,
            options: Options(headers: requestHeaders),
          );
          break;
        case 'POST':
          if (body != null) {
            // /torrents/add 使用 multipart/form-data 提交
            if (endpoint.contains('/torrents/add')) {
              final formData = FormData.fromMap(body);
              response = await _dio.post(
                url,
                data: formData,
                options: Options(
                  headers: requestHeaders,
                  contentType: 'multipart/form-data',
                ),
              );
            } else {
              // 其他接口保持 application/x-www-form-urlencoded
              response = await _dio.post(
                url,
                data: body,
                options: Options(
                  headers: {
                    ...requestHeaders,
                    'Content-Type': 'application/x-www-form-urlencoded',
                  },
                ),
              );
            }
          } else {
            response = await _dio.post(
              url,
              options: Options(headers: requestHeaders),
            );
          }
          break;
        default:
          throw UnsupportedError('HTTP method $method not supported');
      }

      return response;
    } on DioException catch (e) {
      // 网络层失败时触发代理可达性探测（代理不可达自动回退直连）
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.sendTimeout ||
          e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.connectionError) {
        ProxyService.instance.scheduleProbeIfNeeded();
      }
      if (isTimeoutError(e)) rethrow;

      // 检查响应状态
      if (e.response?.statusCode == 403) {
        // 会话可能已过期，清除会话并重试一次
        if (_authCookieHeader != null) {
          _authCookieHeader = null;
          return _request(
            method,
            endpoint,
            headers: headers,
            body: body,
            requireAuth: requireAuth,
          );
        }
        throw Exception('Authentication failed');
      }

      if (e.response?.statusCode != null && e.response!.statusCode! >= 400) {
        throw HttpException(
          'HTTP ${e.response!.statusCode}: ${e.response!.data}',
        );
      }

      throw Exception('Request failed: ${e.message}');
    }
  }

  /// 登录获取会话
  Future<void> _login() async {
    try {
      final response = await _dio.post(
        '$_baseUrl$_apiPrefix/auth/login',
        data:
            'username=${Uri.encodeComponent(config.username)}&password=${Uri.encodeComponent(password)}',
        options: Options(
          headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        ),
      );

      if (!_isSuccessfulStatus(response.statusCode)) {
        throw Exception('Login failed: ${response.data}');
      }

      final cookieHeader = _extractCookieHeader(response.headers['set-cookie']);
      if (cookieHeader == null || cookieHeader.isEmpty) {
        throw Exception(
          'Failed to extract authentication cookies from login response',
        );
      }

      _authCookieHeader = cookieHeader;
    } on DioException catch (e) {
      if (isTimeoutError(e)) rethrow;

      throw Exception('Login failed: ${e.message}');
    }
  }

  bool _isSuccessfulStatus(int? statusCode) {
    return statusCode != null && statusCode >= 200 && statusCode < 300;
  }

  String? _extractCookieHeader(List<String>? setCookieHeaders) {
    if (setCookieHeaders == null || setCookieHeaders.isEmpty) {
      return null;
    }

    final cookieMap = <String, String>{};
    final cookieOrder = <String>[];

    for (final header in setCookieHeaders) {
      final firstPart = header.split(';').first.trim();
      final separatorIndex = firstPart.indexOf('=');
      if (separatorIndex <= 0) {
        continue;
      }

      final name = firstPart.substring(0, separatorIndex).trim();
      final value = firstPart.substring(separatorIndex + 1).trim();
      if (name.isEmpty) {
        continue;
      }

      if (!cookieMap.containsKey(name)) {
        cookieOrder.add(name);
      }
      cookieMap[name] = value;
    }

    if (cookieMap.isEmpty) {
      return null;
    }

    return cookieOrder.map((name) => '$name=${cookieMap[name]}').join('; ');
  }

  @visibleForTesting
  String? get debugAuthCookieHeader => _authCookieHeader;

  @visibleForTesting
  String? debugExtractCookieHeader(List<String>? setCookieHeaders) {
    return _extractCookieHeader(setCookieHeaders);
  }

  @override
  Future<void> testConnection() async {
    try {
      await _login();
      // 尝试获取版本信息来验证连接
      await getVersion();
    } catch (e) {
      throw Exception('Connection test failed: $e');
    }
  }

  @override
  Future<TransferInfo> getTransferInfo() async {
    final response = await _request('GET', '/transfer/info');
    final data = response.data as Map<String, dynamic>;
    return TransferInfo(
      upSpeed: data['up_info_speed'] ?? 0,
      dlSpeed: data['dl_info_speed'] ?? 0,
      upTotal: data['up_info_data'] ?? 0,
      dlTotal: data['dl_info_data'] ?? 0,
    );
  }

  @override
  Future<ServerState> getServerState() async {
    final response = await _request('GET', '/sync/maindata');
    final data = response.data as Map<String, dynamic>;

    // 从 server_state 字段中获取服务器状态信息
    final serverState = data['server_state'] as Map<String, dynamic>? ?? {};
    final freeSpaceOnDisk = (serverState['free_space_on_disk'] ?? 0) is int
        ? serverState['free_space_on_disk'] as int
        : FormatUtil.parseInt(serverState['free_space_on_disk']) ?? 0;

    return ServerState(freeSpaceOnDisk: freeSpaceOnDisk);
  }

  @override
  Future<List<DownloadTask>> getTasks([GetTasksParams? params]) async {
    final queryParams = <String, dynamic>{};

    if (params != null) {
      if (params.filter != null) queryParams['filter'] = params.filter;
      if (params.category != null) queryParams['category'] = params.category;
      if (params.tag != null) queryParams['tag'] = params.tag;
      if (params.sort != null) queryParams['sort'] = params.sort;
      if (params.reverse != null) queryParams['reverse'] = params.reverse;
      if (params.limit != null) queryParams['limit'] = params.limit;
      if (params.offset != null) queryParams['offset'] = params.offset;
    }

    final response = await _request('GET', '/torrents/info', body: queryParams);
    final List<dynamic> data = response.data as List<dynamic>;

    return data.map((torrent) => _convertToDownloadTask(torrent)).toList();
  }

  @override
  Future<void> addTask(AddTaskParams params, {SiteConfig? siteConfig}) async {
    final body = <String, dynamic>{};

    // 本地中转支持：当启用且为种子URL时，先在本地下载种子并以文件上传
    // 如果URL以 ## 开头，强制使用本地中转
    var url = params.url;
    var forceRelay = false;
    if (url.startsWith('##')) {
      url = url.substring(2);
      forceRelay = true;
    }

    final useRelay = config.useLocalRelay || forceRelay;
    if (!useRelay) {
      body['urls'] = url;
    } else {
      final torrentData = await downloadTorrentFileCommon(
        _dio,
        url,
        siteConfig: siteConfig,
      );
      body['torrents'] = MultipartFile.fromBytes(
        torrentData,
        filename: 'ptmate.torrent',
      );
    }

    if (params.category != null) body['category'] = params.category;
    if (params.tags != null && params.tags!.isNotEmpty) {
      body['tags'] = params.tags!.join(',');
    }
    if (params.savePath != null) body['savepath'] = params.savePath;
    if (params.autoTMM != null) body['autoTMM'] = params.autoTMM;
    // qBittorrent: 使用 'stopped' 字段控制是否添加后暂停
    if (params.startPaused != null) {
      body['stopped'] = params.startPaused.toString();
      body['stopCondition'] = 'None';
    }

    await _request('POST', '/torrents/add', body: body);
  }

  /// 根据版本获取暂停任务的 API 路径
  String _getPauseApiPath(String? version) {
    if (version == null) return '/torrents/pause'; // 默认使用 4.x 的路径

    // 移除版本号前的 'v' 前缀（如果存在）
    String cleanVersion = version.toLowerCase().startsWith('v')
        ? version.substring(1)
        : version;

    // 解析版本号，判断是 4.x 还是 5.x
    final versionParts = cleanVersion.split('.');
    if (versionParts.isNotEmpty) {
      final majorVersion = FormatUtil.parseInt(versionParts[0]);
      if (majorVersion != null && majorVersion >= 5) {
        return '/torrents/stop'; // 5.x 使用 stop
      }
    }
    return '/torrents/pause'; // 4.x 使用 pause
  }

  /// 根据版本获取恢复任务的 API 路径
  String _getResumeApiPath(String? version) {
    if (version == null) return '/torrents/resume'; // 默认使用 4.x 的路径

    // 移除版本号前的 'v' 前缀（如果存在）
    String cleanVersion = version.toLowerCase().startsWith('v')
        ? version.substring(1)
        : version;

    // 解析版本号，判断是 4.x 还是 5.x
    final versionParts = cleanVersion.split('.');
    if (versionParts.isNotEmpty) {
      final majorVersion = FormatUtil.parseInt(versionParts[0]);
      if (majorVersion != null && majorVersion >= 5) {
        return '/torrents/start'; // 5.x 使用 start
      }
    }
    return '/torrents/resume'; // 4.x 使用 resume
  }

  @override
  Future<void> pauseTasks(List<String> hashes) async {
    // 获取版本信息来决定使用哪个 API
    String? version = _cachedVersion ?? config.version;
    if (version == null || version.isEmpty) {
      try {
        version = await getVersion(); // 这会自动缓存版本信息
      } catch (e) {
        // 如果获取版本失败，使用默认路径
        version = null;
      }
    }

    final apiPath = _getPauseApiPath(version);
    await _request('POST', apiPath, body: {'hashes': hashes.join('|')});
  }

  @override
  Future<void> resumeTasks(List<String> hashes) async {
    // 获取版本信息来决定使用哪个 API
    String? version = _cachedVersion ?? config.version;
    if (version == null || version.isEmpty) {
      try {
        version = await getVersion(); // 这会自动缓存版本信息
      } catch (e) {
        // 如果获取版本失败，使用默认路径
        version = null;
      }
    }

    final apiPath = _getResumeApiPath(version);
    await _request('POST', apiPath, body: {'hashes': hashes.join('|')});
  }

  @override
  Future<void> deleteTasks(
    List<String> hashes, {
    bool deleteFiles = false,
  }) async {
    await _request(
      'POST',
      '/torrents/delete',
      body: {'hashes': hashes.join('|'), 'deleteFiles': deleteFiles.toString()},
    );
  }

  @override
  Future<List<String>> getCategories() async {
    final response = await _request('GET', '/torrents/categories');
    final Map<String, dynamic> data = response.data as Map<String, dynamic>;
    return data.keys.toList();
  }

  @override
  Future<List<String>> getTags() async {
    final response = await _request('GET', '/torrents/tags');
    final List<dynamic> data = response.data as List<dynamic>;
    return data.cast<String>();
  }

  @override
  Future<String> getVersion() async {
    // 如果已经缓存了版本信息，直接返回
    if (_cachedVersion != null) {
      return _cachedVersion!;
    }

    final response = await _request('GET', '/app/version');
    final version = response.data.replaceAll('"', ''); // 移除可能的引号

    // 缓存版本信息
    _cachedVersion = version;

    // 如果配置中没有版本信息且有回调，触发配置更新
    if ((config.version == null || config.version?.isEmpty == true)) {
      final callback = _onConfigUpdated;
      if (callback != null) {
        final updatedConfig = config.copyWith(version: version);
        callback(updatedConfig);
      }
    }

    return version;
  }

  @override
  Future<List<String>> getPaths() async {
    // 获取所有种子的信息，包括保存路径
    final response = await _request('GET', '/torrents/info');
    final List<dynamic> data = response.data as List<dynamic>;

    final Set<String> allPaths = {};

    for (final torrent in data) {
      final savePath = torrent['save_path'] as String?;
      if (savePath != null && savePath.isNotEmpty) {
        allPaths.add(savePath);
      }
    }

    final paths = allPaths.toList();
    paths.sort(); // 按字母顺序排序
    return paths;
  }

  @override
  Future<void> pauseTask(String hash) async {
    await pauseTasks([hash]);
  }

  @override
  Future<void> resumeTask(String hash) async {
    await resumeTasks([hash]);
  }

  @override
  Future<void> deleteTask(String hash, {bool deleteFiles = false}) async {
    await deleteTasks([hash], deleteFiles: deleteFiles);
  }

  /// 将qBittorrent API响应转换为DownloadTask
  DownloadTask _convertToDownloadTask(Map<String, dynamic> torrent) {
    return DownloadTask(
      hash: torrent['hash'] ?? '',
      name: torrent['name'] ?? '',
      state: torrent['state'] ?? '',
      size: torrent['size'] ?? 0,
      progress: (torrent['progress'] ?? 0.0).toDouble(),
      dlspeed: torrent['dlspeed'] ?? 0,
      upspeed: torrent['upspeed'] ?? 0,
      eta: torrent['eta'] ?? 0,
      category: torrent['category'] ?? '',
      tags:
          torrent['tags']
              ?.toString()
              .split(',')
              .where((tag) => tag.isNotEmpty)
              .toList() ??
          [],
      completionOn: torrent['completion_on'] ?? 0,
      contentPath: torrent['content_path'] ?? '',
      addedOn: torrent['added_on'] ?? 0,
      amountLeft: torrent['amount_left'] ?? 0,
      ratio: (torrent['ratio'] ?? 0.0).toDouble(),
      timeActive: torrent['time_active'] ?? 0,
      uploaded: torrent['uploaded'] ?? 0,
    );
  }

  /// 获取包含版本信息的配置
  /// 如果当前配置中没有版本信息，会自动获取并返回更新后的配置
  Future<QbittorrentConfig> getUpdatedConfig() async {
    // 如果配置中已有版本信息且与缓存一致，直接返回
    if (config.version != null && config.version!.isNotEmpty) {
      return config;
    }

    try {
      // 获取版本信息（会自动缓存）
      final version = await getVersion();

      // 创建包含版本信息的新配置
      return config.copyWith(version: version);
    } catch (e) {
      // 如果获取版本失败，返回原配置
      return config;
    }
  }

  /// 确保配置中有版本信息，如果没有则自动获取
  /// 返回更新后的配置（如果版本信息被更新）
  Future<QbittorrentConfig> ensureVersionInfo({
    Function(QbittorrentConfig)? onVersionUpdated,
  }) async {
    // 如果配置中已有版本信息，直接返回
    if (config.version != null && config.version!.isNotEmpty) {
      return config;
    }

    try {
      // 获取版本信息
      final version = await getVersion();

      // 创建包含版本信息的新配置
      final updatedConfig = config.copyWith(version: version);

      // 如果提供了回调，通知调用者配置已更新
      onVersionUpdated?.call(updatedConfig);

      return updatedConfig;
    } catch (e) {
      // 如果获取版本失败，返回原配置（使用默认的 API 路径）
      return config;
    }
  }

  /// 暂停单个任务（带版本更新回调）
  Future<void> pauseTaskWithVersionUpdate(
    String hash, {
    Function(QbittorrentConfig)? onConfigUpdated,
  }) async {
    await pauseTask(hash);

    // 如果需要更新配置，确保版本信息
    if (onConfigUpdated != null) {
      final updatedConfig = await ensureVersionInfo();
      if (updatedConfig != config) {
        onConfigUpdated(updatedConfig);
      }
    }
  }

  /// 恢复单个任务（带版本更新回调）
  Future<void> resumeTaskWithVersionUpdate(
    String hash, {
    Function(QbittorrentConfig)? onConfigUpdated,
  }) async {
    await resumeTask(hash);

    // 如果需要更新配置，确保版本信息
    if (onConfigUpdated != null) {
      final updatedConfig = await ensureVersionInfo();
      if (updatedConfig != config) {
        onConfigUpdated(updatedConfig);
      }
    }
  }

  /// 释放资源
  void dispose() {
    _dio.close();
  }

  // ============================================================
  // 专业增强 API：Tracker 管理
  // ============================================================

  /// 获取指定任务的 Tracker 列表
  Future<List<TorrentTracker>> getTrackers(String hash) async {
    final response = await _request(
      'GET',
      '/torrents/trackers',
      body: {'hash': hash},
    );
    final List<dynamic> data = response.data as List<dynamic>;
    print('[TRACKER] getTrackers hash=$hash 返回 ${data.length} 条');
    if (data.isNotEmpty) {
      print('[TRACKER] getTrackers 首条原始: ${data.first}');
    }
    return data
        .map((e) => TorrentTracker.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// 批量重新宣告（reannounce）Tracker
  Future<void> reannounceTorrents(List<String> hashes) async {
    await _request('POST', '/torrents/reannounce', body: {
      'hashes': hashes.join('|'),
    });
  }

  /// 添加 Tracker 到指定任务
  Future<void> addTracker(String hash, String trackerUrl) async {
    await _request('POST', '/torrents/addTrackers', body: {
      'hash': hash,
      'urls': trackerUrl,
    });
  }

  /// 编辑 Tracker（替换原 URL）
  Future<void> editTracker(
    String hash,
    String originalUrl,
    String newUrl,
  ) async {
    await _request('POST', '/torrents/editTrackers', body: {
      'hash': hash,
      'origUrl': originalUrl,
      'newUrl': newUrl,
    });
  }

  /// 删除 Tracker
  Future<void> removeTrackers(String hash, List<String> urls) async {
    await _request('POST', '/torrents/removeTrackers', body: {
      'hash': hash,
      'urls': urls.join('\n'),
    });
  }

  // ============================================================
  // 专业增强 API：任务属性 / 健康度
  // ============================================================

  /// 获取任务详细属性（做种时间、分享率等）
  Future<TorrentProperties> getTorrentProperties(String hash) async {
    final response = await _request(
      'GET',
      '/torrents/properties',
      body: {'hash': hash},
    );
    return TorrentProperties.fromJson(response.data as Map<String, dynamic>);
  }

  // ============================================================
  // 专业增强 API：优先级 / 队列
  // ============================================================

  /// 设置任务优先级
  /// [priority]: -1=跳过, 0=普通, 1=高, 2=最高
  Future<void> setTorrentPriority(
    List<String> hashes,
    int priority,
  ) async {
    await _request('POST', '/torrents/setPriority', body: {
      'hashes': hashes.join('|'),
      'priority': priority.toString(),
    });
  }

  /// 队列最前（topPrio）
  Future<void> topPriority(List<String> hashes) async {
    await _request('POST', '/torrents/topPrio', body: {
      'hashes': hashes.join('|'),
    });
  }

  /// 队列最后（bottomPrio）
  Future<void> bottomPriority(List<String> hashes) async {
    await _request('POST', '/torrents/bottomPrio', body: {
      'hashes': hashes.join('|'),
    });
  }

  /// 队列上移（increasePrio）
  Future<void> increasePriority(List<String> hashes) async {
    await _request('POST', '/torrents/increasePrio', body: {
      'hashes': hashes.join('|'),
    });
  }

  /// 队列下移（decreasePrio）
  Future<void> decreasePriority(List<String> hashes) async {
    await _request('POST', '/torrents/decreasePrio', body: {
      'hashes': hashes.join('|'),
    });
  }

  // ============================================================
  // 专业增强 API：批量标签 / 分类
  // ============================================================

  /// 批量添加标签
  Future<void> addTags(List<String> hashes, List<String> tags) async {
    await _request('POST', '/torrents/addTags', body: {
      'hashes': hashes.join('|'),
      'tags': tags.join(','),
    });
  }

  /// 批量移除标签
  Future<void> removeTags(List<String> hashes, List<String> tags) async {
    await _request('POST', '/torrents/removeTags', body: {
      'hashes': hashes.join('|'),
      'tags': tags.join(','),
    });
  }

  /// 批量设置分类
  Future<void> setCategory(List<String> hashes, String category) async {
    await _request('POST', '/torrents/setCategory', body: {
      'hashes': hashes.join('|'),
      'category': category,
    });
  }

  /// 批量重新校验（recheck）
  Future<void> recheckTorrents(List<String> hashes) async {
    await _request('POST', '/torrents/recheck', body: {
      'hashes': hashes.join('|'),
    });
  }

  /// 新增分类
  Future<void> createCategory(String category,
      {String? savePath}) async {
    await _request('POST', '/torrents/createCategory', body: {
      'category': category,
      if (savePath != null && savePath.isNotEmpty) 'savePath': savePath,
    });
  }

  /// 删除分类（不会删除种子）
  Future<void> deleteCategory(String category) async {
    await _request('POST', '/torrents/removeCategories', body: {
      'categories': category,
    });
  }

  /// 重命名分类
  Future<void> renameCategory(String oldName, String newName) async {
    await _request('POST', '/torrents/editCategory', body: {
      'category': oldName,
      'name': newName,
    });
  }

  /// 获取任务的连接节点（Peers）列表
  /// 来自 GET /sync/torrentPeers
  Future<List<TorrentPeer>> getTorrentPeers(String hash) async {
    final response = await _request('GET', '/sync/torrentPeers', body: {
      'hash': hash,
    });
    final Map<String, dynamic> data = response.data as Map<String, dynamic>;
    final peers = data['peers'];
    if (peers is! Map<String, dynamic>) return const [];
    final list = <TorrentPeer>[];
    peers.forEach((peerId, peerJson) {
      if (peerJson is Map<String, dynamic>) {
        final peer = TorrentPeer.fromJson({
          ...peerJson,
          'peer_id': peerJson['peer_id'] ?? peerId,
        });
        list.add(peer);
      }
    });
    // 按下载速度降序
    list.sort((a, b) => b.dlSpeed.compareTo(a.dlSpeed));
    return list;
  }

  /// 获取任务的文件列表（对应 GET /torrents/files）
  Future<List<TorrentFile>> getTorrentFiles(String hash) async {
    final response = await _request('GET', '/torrents/files', body: {
      'hash': hash,
    });
    final raw = response.data;
    if (raw is! List) return const [];
    final list = <TorrentFile>[];
    for (final item in raw) {
      if (item is Map<String, dynamic>) {
        list.add(TorrentFile.fromJson(item));
      }
    }
    return list;
  }

  /// 设置文件优先级（对应 POST /torrents/filePrio）
  /// priority: 0=跳过(不下载) 1=普通 2=高 3=最高
  /// [ids] 为文件 index 列表（逗号拼接）
  Future<void> setFilePriority({
    required String hash,
    required List<int> ids,
    required int priority,
  }) async {
    if (ids.isEmpty) return;
    await _request('POST', '/torrents/filePrio', body: {
      'hash': hash,
      'id': ids.join(','),
      'priority': priority.toString(),
    });
  }

  // ============================================================
  // 专业增强 API：限速
  // ============================================================

  /// 获取全局偏好（限速配置）
  Future<GlobalPreferences> getGlobalPreferences() async {
    final response = await _request('GET', '/app/preferences');
    final data = response.data as Map<String, dynamic>;
    return GlobalPreferences.fromJson(data);
  }

  /// 设置全局下载限速（KiB/s，-1 表示不限速）
  Future<void> setGlobalDownloadLimit(int limitKib) async {
    await _request('POST', '/transfer/setDownloadLimit', body: {
      'limit': limitKib.toString(),
    });
  }

  /// 设置全局上传限速（KiB/s，-1 表示不限速）
  Future<void> setGlobalUploadLimit(int limitKib) async {
    await _request('POST', '/transfer/setUploadLimit', body: {
      'limit': limitKib.toString(),
    });
  }

  /// 切换限速模式（0=全局, 1=备选, 2=调度）
  Future<void> setSpeedLimitsMode(int mode) async {
    await _request('POST', '/transfer/setSpeedLimitsMode', body: {
      'mode': mode.toString(),
    });
  }

  // ============================================================
  // 专业增强 API：RSS 订阅与规则
  // ============================================================

  /// 添加 RSS 订阅源
  Future<void> addRssFeed(String url, {String? path}) async {
    await _request('POST', '/rss/addFeed', body: {
      'url': url,
      if (path != null) 'path': path,
    });
  }

  /// 获取 RSS 订阅源列表
  Future<List<RssFeed>> getRssFeeds() async {
    final response = await _request('GET', '/rss/feeds');
    final data = response.data as Map<String, dynamic>;
    return data.entries.map((entry) {
      final item = entry.value as Map<String, dynamic>? ?? {};
      return RssFeed.fromJson({
        'url': entry.key,
        'title': item['title'] ?? '',
        'lastBuildDate': item['lastBuildDate'] ?? 0,
        'isUpdating': item['isUpdating'] ?? false,
        'hasNewItems': item['hasNewItems'] ?? false,
      });
    }).toList();
  }

  /// 获取 RSS 文章
  Future<List<RssArticle>> getRssItems({bool withData = true}) async {
    final response = await _request(
      'GET',
      '/rss/items',
      body: {'withData': withData.toString()},
    );
    final data = response.data as Map<String, dynamic>;
    final articles = <RssArticle>[];
    void walk(dynamic node) {
      if (node is! Map) return;
      for (final entry in node.entries) {
        final value = entry.value;
        if (value is Map) {
          if (value.containsKey('title') && value.containsKey('link')) {
            articles.add(RssArticle.fromJson({
              'title': value['title'],
              'link': value['link'],
              'description': value['description'] ?? '',
              'date': value['date'] ?? 0,
              'isRead': value['isRead'] ?? false,
            }));
          } else {
            walk(value);
          }
        }
      }
    }

    walk(data);
    return articles;
  }

  /// 刷新 RSS 订阅
  Future<void> refreshRssItem(String itemPath) async {
    await _request('POST', '/rss/refreshItem', body: {
      'itemPath': itemPath,
    });
  }

  /// 获取 RSS 自动下载规则
  Future<List<RssRule>> getRssRules() async {
    final response = await _request('GET', '/rss/rules');
    final data = response.data as Map<String, dynamic>;
    return data.entries.map((entry) {
      return RssRule.fromJson(
        entry.key,
        entry.value as Map<String, dynamic>? ?? {},
      );
    }).toList();
  }

  /// 设置 RSS 自动下载规则
  Future<void> setRssRule(String ruleName, RssRule rule) async {
    await _request('POST', '/rss/setRule', body: {
      'ruleName': ruleName,
      'ruleDef': jsonEncode(rule.toRuleJson()),
    });
  }

  /// 删除 RSS 规则
  Future<void> removeRssRule(String ruleName) async {
    await _request('POST', '/rss/removeRule', body: {
      'ruleName': ruleName,
    });
  }
}
