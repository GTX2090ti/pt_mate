/*
 * [移植适配-OHOS] 手工插件注册
 *
 * flutter_ohos 的 GeneratedPluginRegistrant 由构建工具根据「pubspec 中声明了
 * ohos 平台」的插件生成。当前这些桥接插件是在本仓库内手写的（上游无 ohos 实现），
 * 不会进入生成的 registrant；因此在此统一挂载到引擎，避免 Dart 侧 MethodChannel
 * 调用无接收端（MissingPluginException / 永久挂起 / Null check 崩溃）。
 *
 * 注意：本文件为手工维护，构建不会覆盖；GeneratedPluginRegistrant 每次构建
 * 重新生成，请勿把手工注册代码写进那个文件。
 */

import { FlutterEngine, Log } from '@ohos/flutter_ohos';
import SharedPreferencesOhos from './SharedPreferencesOhos';
import SecureStorageOhos from './SecureStorageOhos';
import PathProviderOhos from './PathProviderOhos';
import PackageInfoOhos from './PackageInfoOhos';
import FilePickerOhos from './FilePickerOhos';

const TAG = 'ManualPluginRegistrant';

export class ManualPluginRegistrant {

  static registerWith(flutterEngine: FlutterEngine) {
    const registry = flutterEngine.getPlugins();
    if (registry == null) {
      Log.e(TAG, 'plugin registry unavailable, skip manual registration');
      return;
    }

    const plugins = [
      new SharedPreferencesOhos(),
      new SecureStorageOhos(),
      new PathProviderOhos(),
      new PackageInfoOhos(),
      new FilePickerOhos(),
    ];

    for (const plugin of plugins) {
      try {
        registry.add(plugin);
        Log.i(TAG, `registered ${plugin.getUniqueClassName()}`);
      } catch (e) {
        const msg = e instanceof Error ? (e.message ?? '') : String(e);
        Log.e(TAG, `failed to register ${plugin.getUniqueClassName()}: ${msg}`);
      }
    }
  }
}
