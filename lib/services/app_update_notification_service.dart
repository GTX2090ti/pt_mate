import 'package:flutter/foundation.dart';

/// 应用更新下载进度通知服务。
///
/// 鸿蒙移植：flutter_local_notifications 无 ohos 端口，此服务降级为 no-op
/// （_available 恒为 false，所有展示方法直接返回）。
/// Android 原行为见 .port_backup/app_update_notification_service.dart。
class AppUpdateNotificationService {
  AppUpdateNotificationService();

  static final AppUpdateNotificationService instance =
      AppUpdateNotificationService();

  static const int notificationId = 26001;
  static const String cancelActionId = 'cancel_app_update';

  VoidCallback? _onCancelRequested;

  Future<void> initialize({VoidCallback? onCancelRequested}) async {
    _onCancelRequested = onCancelRequested ?? _onCancelRequested;
  }

  Future<void> showPreparing(String message) async {}

  Future<void> showProgress({
    required String message,
    required double? progress,
  }) async {}

  Future<void> showInstalling(String message) async {}

  Future<void> showCanceled() async {}

  Future<void> showFailed(String message) async {}
}
