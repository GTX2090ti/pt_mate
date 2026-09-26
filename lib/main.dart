import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import 'app.dart';
import 'services/storage/storage_service.dart';
import 'services/logging/log_file_service.dart';
import 'services/network/proxy_service.dart';

void main() async {
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      // [移植适配-OHOS] 启动阶段单步超时护栏。
      // 鸿蒙侧部分平台通道（如 flutter_secure_storage）没有原生实现时，
      // 调用会永久挂起且不抛异常。这里给每一步加超时，保证 runApp 一定能执行。
      Future<void> guardedStartupStep(
        String name,
        Future<void> Function() body,
      ) async {
        try {
          await body().timeout(const Duration(milliseconds: 1200));
        } catch (error) {
          LogFileService.instance.append(
            'startup step "$name" failed: $error',
          );
        }
      }

      String? secureStorageFailureCode;
      await guardedStartupStep('initializeSecureStorage', () async {
        try {
          await StorageService.instance.initializeSecureStorage();
        } on SecureStorageUnavailableException catch (error) {
          secureStorageFailureCode = error.code;
        } catch (error) {
          secureStorageFailureCode = error.runtimeType.toString();
        }
      });

      // [移植适配-OHOS] 首帧优先：先 runApp，其余初始化放后台，避免白屏。
      runApp(const MTeamApp());

      unawaited(guardedStartupStep('loadLogToFileEnabled', () async {
        final enabled = await StorageService.instance.loadLogToFileEnabled();
        await LogFileService.instance.init(enabled: enabled);
        if (secureStorageFailureCode != null) {
          LogFileService.instance.append(
            'Secure storage '
            'profile=${StorageService.instance.secureStorageProfile?.name ?? 'unknown'}, '
            'state=${StorageService.instance.secureStorageState.name}, '
            'code=$secureStorageFailureCode',
          );
        }
      }));

      unawaited(guardedStartupStep('loadVisibleTags', () async {
        await StorageService.instance.loadVisibleTags();
      }));

      // 代理密码依赖安全存储，预检失败时不得初始化代理。
      if (StorageService.instance.canAccessSensitiveStorage) {
        unawaited(guardedStartupStep('ProxyService.init', () async {
          await ProxyService.instance.init();
        }));
      }
    },
    (error, stack) {
      if (!kIsWeb && kDebugMode) {
        LogFileService.instance.append('Uncaught error: $error\n$stack');
      } else if (!kIsWeb) {
        LogFileService.instance.append('Application error category=uncaught');
      }
    },
    zoneSpecification: ZoneSpecification(
      print: (self, parent, zone, line) {
        if (kDebugMode) {
          parent.print(zone, line);
          LogFileService.instance.append(line);
        }
      },
    ),
  );
}
