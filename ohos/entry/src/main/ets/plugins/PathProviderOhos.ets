/*
 * [移植适配-OHOS] path_provider 鸿蒙实现
 *
 * 上游 path_provider 没有 ohos 平台实现，GeneratedPluginRegistrant 为空，
 * Dart 侧调用 channel 会永久挂起。此文件在 Ability 的 Context 上直接解析
 * 应用沙箱目录并回包，替代插件行为。
 *
 * channel: plugins.flutter.io/path_provider （MethodChannel + StandardMethodCodec）
 */

import common from '@ohos.app.ability.common';
import { fileIo } from '@kit.CoreFileKit';
import { MethodChannel, MethodCall, MethodResult } from '@ohos/flutter_ohos';
import { FlutterPlugin, FlutterPluginBinding } from '@ohos/flutter_ohos';
import Log from '@ohos/flutter_ohos/src/main/ets/util/Log';

const TAG = 'PathProviderOhos';
const CHANNEL_NAME = 'plugins.flutter.io/path_provider';

export default class PathProviderOhos implements FlutterPlugin {
  private channel: MethodChannel | null = null;
  private context: common.Context | null = null;

  getUniqueClassName(): string {
    return 'PathProviderOhos';
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.context = binding.getApplicationContext();
    this.channel = new MethodChannel(binding.getBinaryMessenger(), CHANNEL_NAME);
    this.channel.setMethodCallHandler({
      onMethodCall: (call: MethodCall, result: MethodResult): void => {
        try {
          result.success(this.resolve(call.method));
        } catch (e) {
          const msg = e instanceof Error ? (e.message ?? '') : String(e);
          Log.e(TAG, `path_provider ${call.method} failed: ${msg}`);
          result.error('path_provider_error', msg, null);
        }
      },
    });
    Log.i(TAG, 'path_provider ohos implementation attached');
  }

  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    if (this.channel != null) {
      this.channel.setMethodCallHandler(null);
      this.channel = null;
    }
    this.context = null;
  }

  /** 解析并确保目录存在，返回绝对路径。 */
  private resolve(method: string): string {
    const ctx = this.context;
    if (ctx == null) {
      throw new Error('application context unavailable');
    }
    const filesDir = ctx.filesDir;

    switch (method) {
      // getApplicationDocumentsDirectory -> filesDir（应用私有、随应用卸载删除）
      case 'getApplicationDocumentsDirectory':
        return this.ensure(filesDir);

      // getApplicationSupportDirectory -> filesDir（鸿蒙无 support 概念，统一到 filesDir）
      case 'getApplicationSupportDirectory':
        return this.ensure(filesDir);

      // getTemporaryDirectory -> cacheDir
      case 'getTemporaryDirectory':
        return this.ensure(ctx.cacheDir);

      // 以下为 path_provider 的次要接口，鸿蒙上统一映射，避免 Dart 侧抛异常
      case 'getLibraryDirectory':
        return this.ensure(filesDir);

      case 'getExternalStorageDirectory':
      case 'getDownloadsDirectory':
        // [移植适配-OHOS] 如需真实下载目录，改为应用沙箱内子目录，避免权限申请
        return this.ensure(`${filesDir}/Downloads`);

      case 'getExternalCacheDirectories':
        return this.ensure(ctx.cacheDir);

      case 'getExternalStorageDirectories':
        return this.ensure(`${filesDir}/External`);

      default:
        // 未实现的方法回落到 filesDir，保持宽容，避免启动链路被掐断
        Log.w(TAG, `unknown method ${method}, fallback to filesDir`);
        return this.ensure(filesDir);
    }
  }

  /** 目录不存在则创建，返回绝对路径。 */
  private ensure(path: string): string {
    try {
      if (!fileIo.accessSync(path)) {
        fileIo.mkdirSync(path, true);
      }
    } catch (e) {
      const msg = e instanceof Error ? (e.message ?? '') : String(e);
      Log.w(TAG, `ensure dir failed ${path}: ${msg}`);
    }
    return path;
  }
}
