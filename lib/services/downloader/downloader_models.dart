/// 通用下载器数据模型
///
/// 这些模型提供了统一的接口，用于不同下载器实现之间的数据交换
library;
import '../../utils/format.dart';

/// 下载器类型枚举
enum DownloaderType {
  qbittorrent('qbittorrent', 'qBittorrent'),
  transmission('transmission', 'Transmission'),
  rutorrent('rutorrent', 'ruTorrent');

  const DownloaderType(this.value, this.displayName);

  final String value;
  final String displayName;

  /// 是否支持独立于分类的任务标签。
  bool get supportsTags => switch (this) {
    DownloaderType.qbittorrent || DownloaderType.transmission => true,
    DownloaderType.rutorrent => false,
  };

  static DownloaderType fromString(String value) {
    for (final type in DownloaderType.values) {
      if (type.value == value) {
        return type;
      }
    }
    throw ArgumentError('Unknown downloader type: $value');
  }
}

/// 传输信息
class TransferInfo {
  final int upSpeed;
  final int dlSpeed;
  final int upTotal;
  final int dlTotal;

  const TransferInfo({
    required this.upSpeed,
    required this.dlSpeed,
    required this.upTotal,
    required this.dlTotal,
  });

  factory TransferInfo.fromJson(Map<String, dynamic> json) {
    return TransferInfo(
      upSpeed: json['upSpeed'] ?? 0,
      dlSpeed: json['dlSpeed'] ?? 0,
      upTotal: json['upTotal'] ?? 0,
      dlTotal: json['dlTotal'] ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'upSpeed': upSpeed,
      'dlSpeed': dlSpeed,
      'upTotal': upTotal,
      'dlTotal': dlTotal,
    };
  }
}

/// 服务器状态
class ServerState {
  final int freeSpaceOnDisk;

  const ServerState({
    required this.freeSpaceOnDisk,
  });

  factory ServerState.fromJson(Map<String, dynamic> json) {
    return ServerState(
      freeSpaceOnDisk: json['freeSpaceOnDisk'] ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'freeSpaceOnDisk': freeSpaceOnDisk,
    };
  }
}

/// 下载任务状态
class DownloadTaskState {
  static const String error = 'error';
  static const String missingFiles = 'missingFiles';
  static const String uploading = 'uploading';
  static const String pausedUP = 'pausedUP';
  static const String queuedUP = 'queuedUP';
  static const String stalledUP = 'stalledUP';
  static const String checkingUP = 'checkingUP';
  static const String forcedUP = 'forcedUP';
  static const String allocating = 'allocating';
  static const String downloading = 'downloading';
  static const String metaDL = 'metaDL';
  static const String pausedDL = 'pausedDL';
  static const String queuedDL = 'queuedDL';
  static const String stalledDL = 'stalledDL';
  static const String checkingDL = 'checkingDL';
  static const String forcedDL = 'forcedDL';
  static const String stoppedDL = 'stoppedDL';
  static const String checkingResumeData = 'checkingResumeData';
  static const String moving = 'moving';
  static const String unknown = 'unknown';

  static bool isDownloading(String state) {
    return state == downloading || state == forcedDL ||
           state == metaDL || state == stalledDL;
  }

  static bool isPaused(String state) {
    return state == pausedDL || state == pausedUP;
  }
}

/// 下载任务
class DownloadTask {
  final String hash;
  final String name;
  final String state;
  final int size;
  final double progress;
  final int dlspeed;
  final int upspeed;
  final int eta;
  final String category;
  final List<String> tags;
  final int completionOn;
  final String contentPath;
  final int addedOn;
  final int amountLeft;
  final double ratio;
  final int timeActive;
  final int uploaded;

  const DownloadTask({
    required this.hash,
    required this.name,
    required this.state,
    required this.size,
    required this.progress,
    required this.dlspeed,
    required this.upspeed,
    required this.eta,
    required this.category,
    required this.tags,
    required this.completionOn,
    required this.contentPath,
    required this.addedOn,
    required this.amountLeft,
    required this.ratio,
    required this.timeActive,
    required this.uploaded
  });

  factory DownloadTask.fromJson(Map<String, dynamic> json) {
    return DownloadTask(
      hash: json['hash'] ?? '',
      name: json['name'] ?? '',
      state: json['state'] ?? DownloadTaskState.unknown,
      size: json['size'] is int
          ? json['size'] as int
          : FormatUtil.parseInt(json['size']) ?? 0,
      progress: json['progress'] is double ? json['progress'] : double.tryParse('${json['progress'] ?? 0}') ?? 0,
      dlspeed: json['dlspeed'] is int
          ? json['dlspeed'] as int
          : FormatUtil.parseInt(json['dlspeed']) ?? 0,
      upspeed: json['upspeed'] is int
          ? json['upspeed'] as int
          : FormatUtil.parseInt(json['upspeed']) ?? 0,
      eta: json['eta'] is int
          ? json['eta'] as int
          : FormatUtil.parseInt(json['eta']) ?? 0,
      category: json['category'] ?? '',
      tags: json['tags'] is String
          ? (json['tags'] as String).split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList()
          : (json['tags'] is List ? (json['tags'] as List).map((e) => e.toString()).toList() : <String>[]),
      completionOn: json['completionOn'] is int
          ? json['completionOn'] as int
          : FormatUtil.parseInt(json['completionOn']) ?? 0,
      contentPath: json['contentPath'] ?? '',
      addedOn: json['addedOn'] is int
          ? json['addedOn'] as int
          : FormatUtil.parseInt(json['addedOn']) ?? 0,
      amountLeft: json['amountLeft'] is int
          ? json['amountLeft'] as int
          : FormatUtil.parseInt(json['amountLeft']) ?? 0,
      ratio: json['ratio'] is double ? json['ratio'] : double.tryParse('${json['ratio'] ?? 0}') ?? 0,
      timeActive: json['timeActive'] is int
          ? json['timeActive'] as int
          : FormatUtil.parseInt(json['timeActive']) ?? 0,
      uploaded: json['uploaded'] is int
          ? json['uploaded'] as int
          : FormatUtil.parseInt(json['uploaded']) ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'hash': hash,
      'name': name,
      'state': state,
      'size': size,
      'progress': progress,
      'dlspeed': dlspeed,
      'upspeed': upspeed,
      'eta': eta,
      'category': category,
      'tags': tags,
      'completionOn': completionOn,
      'contentPath': contentPath,
      'addedOn': addedOn,
      'amountLeft': amountLeft,
      'ratio': ratio,
      'timeActive': timeActive,
      'uploaded': uploaded,
    };
  }

  bool get isDownloading => DownloadTaskState.isDownloading(state);
  bool get isPaused => DownloadTaskState.isPaused(state);
}

/// 添加任务参数
class AddTaskParams {
  final String url;
  final String? category;
  final List<String>? tags;
  final String? savePath;
  final bool? autoTMM;
  /// 是否添加后暂停（不立即开始），默认空表示遵循下载器默认行为
  final bool? startPaused;

  const AddTaskParams({
    required this.url,
    this.category,
    this.tags,
    this.savePath,
    this.autoTMM,
    this.startPaused,
  });

  AddTaskParams copyWith({
    String? url,
    String? category,
    List<String>? tags,
    String? savePath,
    bool? autoTMM,
    bool? startPaused,
  }) => AddTaskParams(
    url: url ?? this.url,
    category: category ?? this.category,
    tags: tags ?? this.tags,
    savePath: savePath ?? this.savePath,
    autoTMM: autoTMM ?? this.autoTMM,
    startPaused: startPaused ?? this.startPaused,
  );

  factory AddTaskParams.fromJson(Map<String, dynamic> json) {
    return AddTaskParams(
      url: json['url'] ?? '',
      category: json['category'],
      tags: json['tags'] is List ? (json['tags'] as List).map((e) => e.toString()).toList() : null,
      savePath: json['savePath'],
      autoTMM: json['autoTMM'],
      startPaused: json['startPaused'] is bool ? json['startPaused'] : (json['startPaused']?.toString() == 'true' ? true : null),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'url': url,
      if (category != null) 'category': category,
      if (tags != null) 'tags': tags,
      if (savePath != null) 'savePath': savePath,
      if (autoTMM != null) 'autoTMM': autoTMM,
      if (startPaused != null) 'startPaused': startPaused,
    };
  }
}

/// 获取任务列表参数
class GetTasksParams {
  final String? filter;
  final String? category;
  final String? tag;
  final String? sort;
  final bool? reverse;
  final int? limit;
  final int? offset;

  const GetTasksParams({
    this.filter,
    this.category,
    this.tag,
    this.sort,
    this.reverse,
    this.limit,
    this.offset,
  });

  factory GetTasksParams.fromJson(Map<String, dynamic> json) {
    return GetTasksParams(
      filter: json['filter'],
      category: json['category'],
      tag: json['tag'],
      sort: json['sort'],
      reverse: json['reverse'],
      limit: json['limit'],
      offset: json['offset'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (filter != null) 'filter': filter,
      if (category != null) 'category': category,
      if (tag != null) 'tag': tag,
      if (sort != null) 'sort': sort,
      if (reverse != null) 'reverse': reverse,
      if (limit != null) 'limit': limit,
      if (offset != null) 'offset': offset,
    };
  }
}

/// Tracker 信息（单个任务的单个 tracker 状态）
class TorrentTracker {
  final String url;
  final int status;
  final String message;
  final int numPeers;
  final int numSeeds;
  final int numLeeches;
  final int numDownloads;
  final int lastSeen;
  final int tier;
  final int seeds;
  final int leeches;
  final int peers;

  const TorrentTracker({
    required this.url,
    required this.status,
    required this.message,
    required this.numPeers,
    required this.numSeeds,
    required this.numLeeches,
    required this.numDownloads,
    required this.lastSeen,
    required this.tier,
    required this.seeds,
    required this.leeches,
    required this.peers,
  });

  /// status: 0=disabled, 1=not contacted yet, 2=working, 3=updating, 4=not working
  bool get isWorking => status == 2 || status == 3;
  bool get isDisabled => status == 0;
  bool get isError => status == 4;

  factory TorrentTracker.fromJson(Map<String, dynamic> json) {
    return TorrentTracker(
      url: json['url'] ?? '',
      status: json['status'] is int
        ? json['status'] as int
        : FormatUtil.parseInt(json['status']) ?? 0,
      message: json['msg'] ?? '',
      numPeers: json['num_peers'] is int
        ? json['num_peers'] as int
        : FormatUtil.parseInt(json['num_peers']) ?? 0,
      numSeeds: json['num_seeds'] is int
        ? json['num_seeds'] as int
        : FormatUtil.parseInt(json['num_seeds']) ?? 0,
      numLeeches: json['num_leeches'] is int
        ? json['num_leeches'] as int
        : FormatUtil.parseInt(json['num_leeches']) ?? 0,
      numDownloads: json['num_downloaded'] is int
        ? json['num_downloaded'] as int
        : FormatUtil.parseInt(json['num_downloaded']) ?? 0,
      lastSeen: json['last_seen'] is int
        ? json['last_seen'] as int
        : FormatUtil.parseInt(json['last_seen']) ?? 0,
      tier: json['tier'] is int
        ? json['tier'] as int
        : FormatUtil.parseInt(json['tier']) ?? 0,
      seeds: json['seeds'] is int
        ? json['seeds'] as int
        : FormatUtil.parseInt(json['seeds']) ?? 0,
      leeches: json['leeches'] is int
        ? json['leeches'] as int
        : FormatUtil.parseInt(json['leeches']) ?? 0,
      peers: json['peers'] is int
        ? json['peers'] as int
        : FormatUtil.parseInt(json['peers']) ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'url': url,
      'status': status,
      'msg': message,
      'num_peers': numPeers,
      'num_seeds': numSeeds,
      'num_leeches': numLeeches,
      'num_downloads': numDownloads,
      'last_seen': lastSeen,
      'tier': tier,
      'seeds': seeds,
      'leeches': leeches,
      'peers': peers,
    };
  }
}

/// 任务详情（qBittorrent /torrents/properties）
class TorrentProperties {
  final int addedOn;
  final int completionOn;
  final String savePath;
  final String contentPath;
  final int seedingTime;
  final int totalSize;
  final double shareRatio;
  final int upTotal;
  final int dlTotal;
  final int timeActive;
  final int numSeeds;
  final int numLeeches;
  final int numPeers;
  final int dlSpeed;
  final int upSpeed;

  const TorrentProperties({
    required this.addedOn,
    required this.completionOn,
    required this.savePath,
    required this.contentPath,
    required this.seedingTime,
    required this.totalSize,
    required this.shareRatio,
    required this.upTotal,
    required this.dlTotal,
    required this.timeActive,
    required this.numSeeds,
    required this.numLeeches,
    required this.numPeers,
    required this.dlSpeed,
    required this.upSpeed,
  });

  factory TorrentProperties.fromJson(Map<String, dynamic> json) {
    return TorrentProperties(
      addedOn: (json['added_on'] ?? 0) is int
          ? json['added_on'] as int
          : FormatUtil.parseInt(json['added_on']) ?? 0,
      completionOn: (json['completion_on'] ?? 0) is int
          ? json['completion_on'] as int
          : FormatUtil.parseInt(json['completion_on']) ?? 0,
      savePath: json['save_path'] ?? '',
      contentPath: json['content_path'] ?? '',
      seedingTime: (json['seeding_time'] ?? 0) is int
          ? json['seeding_time'] as int
          : FormatUtil.parseInt(json['seeding_time']) ?? 0,
      totalSize: (json['total_size'] ?? 0) is int
          ? json['total_size'] as int
          : FormatUtil.parseInt(json['total_size']) ?? 0,
      shareRatio: json['share_ratio'] is double
          ? json['share_ratio'] as double
          : double.tryParse('${json['share_ratio'] ?? 0}') ?? 0,
      upTotal: (json['up_total'] ?? 0) is int
          ? json['up_total'] as int
          : FormatUtil.parseInt(json['up_total']) ?? 0,
      dlTotal: (json['dl_total'] ?? 0) is int
          ? json['dl_total'] as int
          : FormatUtil.parseInt(json['dl_total']) ?? 0,
      timeActive: (json['time_active'] ?? 0) is int
          ? json['time_active'] as int
          : FormatUtil.parseInt(json['time_active']) ?? 0,
      numSeeds: (json['num_seeds'] ?? 0) is int
          ? json['num_seeds'] as int
          : FormatUtil.parseInt(json['num_seeds']) ?? 0,
      numLeeches: (json['num_leeches'] ?? 0) is int
          ? json['num_leeches'] as int
          : FormatUtil.parseInt(json['num_leeches']) ?? 0,
      numPeers: (json['num_peers'] ?? 0) is int
          ? json['num_peers'] as int
          : FormatUtil.parseInt(json['num_peers']) ?? 0,
      dlSpeed: (json['dl_speed'] ?? 0) is int
          ? json['dl_speed'] as int
          : FormatUtil.parseInt(json['dl_speed']) ?? 0,
      upSpeed: (json['up_speed'] ?? 0) is int
          ? json['up_speed'] as int
          : FormatUtil.parseInt(json['up_speed']) ?? 0,
    );
  }
}

/// 全局传输偏好（qBittorrent /app/preferences 相关字段）
class GlobalPreferences {
  final int dlLimit;
  final int upLimit;
  final int altDlLimit;
  final int altUpLimit;
  final int speedLimitMode;
  final bool schedulerEnabled;
  final bool dlLimitApplied;
  final bool upLimitApplied;

  const GlobalPreferences({
    required this.dlLimit,
    required this.upLimit,
    required this.altDlLimit,
    required this.altUpLimit,
    required this.speedLimitMode,
    required this.schedulerEnabled,
    required this.dlLimitApplied,
    required this.upLimitApplied,
  });

  /// speedLimitMode: 0=global, 1=alt, 2=scheduler
  bool get isAltMode => speedLimitMode == 1;
  bool get isSchedulerMode => speedLimitMode == 2;

  factory GlobalPreferences.fromJson(Map<String, dynamic> json) {
    return GlobalPreferences(
      dlLimit: (json['dl_limit'] ?? -1) is int
          ? json['dl_limit'] as int
          : FormatUtil.parseInt(json['dl_limit']) ?? -1,
      upLimit: (json['up_limit'] ?? -1) is int
          ? json['up_limit'] as int
          : FormatUtil.parseInt(json['up_limit']) ?? -1,
      altDlLimit: (json['alt_dl_limit'] ?? -1) is int
          ? json['alt_dl_limit'] as int
          : FormatUtil.parseInt(json['alt_dl_limit']) ?? -1,
      altUpLimit: (json['alt_up_limit'] ?? -1) is int
          ? json['alt_up_limit'] as int
          : FormatUtil.parseInt(json['alt_up_limit']) ?? -1,
      speedLimitMode: (json['speed_limit_mode'] ?? 0) is int
          ? json['speed_limit_mode'] as int
          : FormatUtil.parseInt(json['speed_limit_mode']) ?? 0,
      schedulerEnabled: json['scheduler_enabled'] ?? false,
      dlLimitApplied: json['dl_limit_applied'] ?? false,
      upLimitApplied: json['up_limit_applied'] ?? false,
    );
  }
}

/// RSS 订阅源
class RssFeed {
  final String url;
  final String title;
  final int lastBuildDate;
  final bool isUpdating;
  final bool hasNewItems;

  const RssFeed({
    required this.url,
    required this.title,
    required this.lastBuildDate,
    required this.isUpdating,
    required this.hasNewItems,
  });

  factory RssFeed.fromJson(Map<String, dynamic> json) {
    return RssFeed(
      url: json['url'] ?? '',
      title: json['title'] ?? '',
      lastBuildDate: (json['lastBuildDate'] ?? 0) is int
          ? json['lastBuildDate'] as int
          : FormatUtil.parseInt(json['lastBuildDate']) ?? 0,
      isUpdating: json['isUpdating'] ?? false,
      hasNewItems: json['hasNewItems'] ?? false,
    );
  }
}

/// RSS 文章
class RssArticle {
  final String title;
  final String link;
  final String description;
  final int date;
  final bool isRead;

  const RssArticle({
    required this.title,
    required this.link,
    required this.description,
    required this.date,
    required this.isRead,
  });

  factory RssArticle.fromJson(Map<String, dynamic> json) {
    return RssArticle(
      title: json['title'] ?? '',
      link: json['link'] ?? '',
      description: json['description'] ?? '',
      date: (json['date'] ?? 0) is int
          ? json['date'] as int
          : FormatUtil.parseInt(json['date']) ?? 0,
      isRead: json['isRead'] ?? false,
    );
  }
}

/// RSS 自动下载规则（qBittorrent /rss/setRule）
class RssRule {
  final String name;
  final bool enabled;
  final String mustContain;
  final String mustNotContain;
  final bool useRegex;
  final List<String> affectedFeeds;
  final int ignoreDays;
  final String lastMatch;
  final String savePath;
  final String assignedCategory;
  final String assignedTags;
  final String episodeFilter;

  const RssRule({
    required this.name,
    required this.enabled,
    required this.mustContain,
    required this.mustNotContain,
    required this.useRegex,
    required this.affectedFeeds,
    required this.ignoreDays,
    required this.lastMatch,
    required this.savePath,
    required this.assignedCategory,
    required this.assignedTags,
    required this.episodeFilter,
  });

  factory RssRule.fromJson(String name, Map<String, dynamic> json) {
    return RssRule(
      name: name,
      enabled: json['enabled'] ?? false,
      mustContain: json['mustContain'] ?? '',
      mustNotContain: json['mustNotContain'] ?? '',
      useRegex: json['useRegex'] ?? false,
      affectedFeeds: (json['affectedFeeds'] as List<dynamic>? ?? const [])
          .cast<String>(),
      ignoreDays: (json['ignoreDays'] as num?)?.toInt() ?? 0,
      lastMatch: json['lastMatch'] ?? '',
      savePath: json['savePath'] ?? '',
      assignedCategory: json['assignedCategory'] ?? '',
      assignedTags: json['assignedTags'] ?? '',
      episodeFilter: json['episodeFilter'] ?? '',
    );
  }

  Map<String, dynamic> toRuleJson() {
    return {
      'enabled': enabled,
      'mustContain': mustContain,
      'mustNotContain': mustNotContain,
      'useRegex': useRegex,
      'affectedFeeds': affectedFeeds,
      'ignoreDays': ignoreDays,
      'lastMatch': lastMatch,
      'savePath': savePath,
      'assignedCategory': assignedCategory,
      'assignedTags': assignedTags,
      'episodeFilter': episodeFilter,
    };
  }
}

/// 限速调度时间段规则（本地增强功能，非 qB 原生 scheduler）
class SpeedScheduleEntry {
  final int dayOfWeek; // 1=周一 ... 7=周日
  final int startMinuteOfDay; // 0-1439
  final int endMinuteOfDay; // 0-1439, 跨天允许（end > start）
  final int dlLimitKib; // -1 = 不限速
  final int upLimitKib; // -1 = 不限速

  const SpeedScheduleEntry({
    required this.dayOfWeek,
    required this.startMinuteOfDay,
    required this.endMinuteOfDay,
    required this.dlLimitKib,
    required this.upLimitKib,
  });

  Map<String, dynamic> toJson() => {
    'dayOfWeek': dayOfWeek,
    'startMinuteOfDay': startMinuteOfDay,
    'endMinuteOfDay': endMinuteOfDay,
    'dlLimitKib': dlLimitKib,
    'upLimitKib': upLimitKib,
  };

  factory SpeedScheduleEntry.fromJson(Map<String, dynamic> json) {
    return SpeedScheduleEntry(
      dayOfWeek: json['dayOfWeek'] ?? 1,
      startMinuteOfDay: json['startMinuteOfDay'] ?? 0,
      endMinuteOfDay: json['endMinuteOfDay'] ?? 1439,
      dlLimitKib: json['dlLimitKib'] ?? -1,
      upLimitKib: json['upLimitKib'] ?? -1,
    );
  }

  /// 判断给定时刻是否落在此时间段内（支持跨天，如 23:00 -> 07:00）
  bool covers(int weekday, int minuteOfDay) {
    if (weekday != dayOfWeek) return false;
    if (startMinuteOfDay <= endMinuteOfDay) {
      return minuteOfDay >= startMinuteOfDay && minuteOfDay < endMinuteOfDay;
    }
    // 跨天：end 视为次日
    return minuteOfDay >= startMinuteOfDay || minuteOfDay < endMinuteOfDay;
  }
}

/// 做种健康度配置
class SeedHealthConfig {
  final bool enabled;
  final double minRatio;
  final int minSeedMinutes; // 最少做种分钟数
  final bool notifyWhenReady;

  const SeedHealthConfig({
    this.enabled = false,
    this.minRatio = 1.0,
    this.minSeedMinutes = 4320, // 默认 72 小时
    this.notifyWhenReady = true,
  });

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'minRatio': minRatio,
    'minSeedMinutes': minSeedMinutes,
    'notifyWhenReady': notifyWhenReady,
  };

  factory SeedHealthConfig.fromJson(Map<String, dynamic> json) {
    return SeedHealthConfig(
      enabled: json['enabled'] ?? false,
      minRatio: json['minRatio'] is double
          ? json['minRatio'] as double
          : double.tryParse('${json['minRatio'] ?? 1.0}') ?? 1.0,
      minSeedMinutes: json['minSeedMinutes'] ?? 4320,
      notifyWhenReady: json['notifyWhenReady'] ?? true,
    );
  }
}

/// 磁盘预警配置
class DiskGuardConfig {
  final bool enabled;
  final int warnThresholdBytes; // 剩余空间低于此值预警
  final bool checkBeforeAdd; // 添加任务前检查
  final int reserveBytes; // 预留空间（下载前检查用）

  const DiskGuardConfig({
    this.enabled = true,
    this.warnThresholdBytes = 20 * 1024 * 1024 * 1024, // 默认 20GB
    this.checkBeforeAdd = true,
    this.reserveBytes = 10 * 1024 * 1024 * 1024, // 默认预留 10GB
  });

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'warnThresholdBytes': warnThresholdBytes,
    'checkBeforeAdd': checkBeforeAdd,
    'reserveBytes': reserveBytes,
  };

  factory DiskGuardConfig.fromJson(Map<String, dynamic> json) {
    return DiskGuardConfig(
      enabled: json['enabled'] ?? true,
      warnThresholdBytes: json['warnThresholdBytes'] ?? 20 * 1024 * 1024 * 1024,
      checkBeforeAdd: json['checkBeforeAdd'] ?? true,
      reserveBytes: json['reserveBytes'] ?? 10 * 1024 * 1024 * 1024,
    );
  }
}

/// 批量操作的选中项描述
class BulkActionSelection {
  final List<String> hashes;

  const BulkActionSelection({required this.hashes});

  bool get isEmpty => hashes.isEmpty;
}

/// 连接的节点（Peer）信息，来自 /sync/torrentPeers
class TorrentPeer {
  final String peerId;
  final String ip;
  final int port;
  final String client;
  final int connectionType;
  final String country;
  final int dlSpeed;
  final int upSpeed;
  final int downloaded;
  final int uploaded;
  final String flags;
  final String flagsDesc;
  final double progress;
  final double relevance;

  const TorrentPeer({
    required this.peerId,
    required this.ip,
    required this.port,
    required this.client,
    required this.connectionType,
    required this.country,
    required this.dlSpeed,
    required this.upSpeed,
    required this.downloaded,
    required this.uploaded,
    required this.flags,
    required this.flagsDesc,
    required this.progress,
    required this.relevance,
  });

  /// 连接类型描述：0=直连(本地网络) 1=公网直连 2=防火墙后 3=UPnP 4=未知
  String get connectionTypeText {
    switch (connectionType) {
      case 0:
        return '本地';
      case 1:
        return '公网';
      case 2:
        return 'NAT';
      case 3:
        return 'UPnP';
      default:
        return '未知';
    }
  }

  factory TorrentPeer.fromJson(Map<String, dynamic> json) {
    int _num(dynamic v) =>
        v is int ? v : (FormatUtil.parseInt(v) ?? 0);
    double _dbl(dynamic v) =>
        v is double
            ? v
            : (v is int
                  ? v.toDouble()
                  : (double.tryParse('$v') ?? 0.0));
    String _str(dynamic v) => v?.toString() ?? '';
    return TorrentPeer(
      peerId: _str(json['peer_id']),
      ip: _str(json['ip']),
      port: _num(json['port']),
      client: _str(json['client']),
      connectionType: _num(json['connection_type']),
      country: _str(json['country']),
      dlSpeed: _num(json['dl_speed']),
      upSpeed: _num(json['up_speed']),
      downloaded: _num(json['downloaded']),
      uploaded: _num(json['uploaded']),
      flags: _str(json['flags']),
      flagsDesc: _str(json['flags_desc']),
      progress: _dbl(json['progress']),
      relevance: _dbl(json['relevance']),
    );
  }
}


/// 种子文件（对应 qB /torrents/files）
/// priority: 0=跳过(不下载) 1=普通 2=高 3=最高
class TorrentFile {
  final int index;
  final String name;
  final int size;
  final double progress;
  final int priority;
  final bool isSeed;

  const TorrentFile({
    required this.index,
    required this.name,
    required this.size,
    required this.progress,
    required this.priority,
    required this.isSeed,
  });

  /// 是否选中下载（priority != 0）
  bool get selected => priority != 0;

  factory TorrentFile.fromJson(Map<String, dynamic> json) {
    int _num(dynamic v) => v is int ? v : (FormatUtil.parseInt(v) ?? 0);
    double _dbl(dynamic v) =>
        v is double
            ? v
            : (v is int
                  ? v.toDouble()
                  : (double.tryParse('$v') ?? 0.0));
    return TorrentFile(
      index: _num(json['index']),
      name: json['name']?.toString() ?? '',
      size: _num(json['size']),
      progress: _dbl(json['progress']),
      priority: _num(json['priority']),
      isSeed: json['is_seed'] == true,
    );
  }
}
