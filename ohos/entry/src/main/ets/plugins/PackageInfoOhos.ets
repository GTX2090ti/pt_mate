/*
 * [移植适配-OHOS] package_info_plus 鸿蒙实现
 *
 * 上游 package_info_plus 没有 ohos 平台实现。Dart 侧 PackageInfo.fromPlatform()
 * 走 MethodChannel('dev.fluttercommunity.plus/package_info')，因无接收端，
 * 引擎回一条空消息（日志：No registered handler for message），于是
 * package_info_plus_platform_interface 的 MethodChannelPackageInfo.getAll() 里
 *   final map = await _channel.invokeMapMethod<String, dynamic>('getAll');
 *   ... map!['appName'] ...
 * 在 `map!` 处抛「Null check operator used on a null value」。
 *
 * 影响面（备份链路第一步就取应用版本号）：
 *   BackupService._createBackupInCurrentEpoch → PackageInfo.fromPlatform()
 *     → 本地「导出备份」失败
 *     → WebDAV「上传备份」失败（exportBackupWithWebDAV 先建备份再上传）
 *
 * channel: dev.fluttercommunity.plus/package_info （StandardMethodCodec）
 * 协议：getAll() → Map<String, String?>，键为
 *   appName / packageName / version / buildNumber / buildSignature /
 *   installerStore / installTime / updateTime
 * 其中 installTime / updateTime 需为「毫秒时间戳字符串」或 null
 * （Dart 侧 _parseNullableStringMillis 用 int.tryParse 解析，空串即 null）。
 */

import common from '@ohos.app.ability.common';
import { bundleManager } from '@kit.AbilityKit';
import { MethodChannel, MethodCall, MethodResult } from '@ohos/flutter_ohos';
import { FlutterPlugin, FlutterPluginBinding } from '@ohos/flutter_ohos';
import Log from '@ohos/flutter_ohos/src/main/ets/util/Log';

const TAG = 'PackageInfoOhos';
const CHANNEL_NAME = 'dev.fluttercommunity.plus/package_info';

export default class PackageInfoOhos implements FlutterPlugin {
  private channel: MethodChannel | null = null;
  private context: common.Context | null = null;

  getUniqueClassName(): string {
    return 'PackageInfoOhos';
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.context = binding.getApplicationContext();
    this.channel = new MethodChannel(binding.getBinaryMessenger(), CHANNEL_NAME);
    this.channel.setMethodCallHandler({
      onMethodCall: (call: MethodCall, result: MethodResult): void => {
        if (call.method === 'getAll') {
          try {
            result.success(this.collect());
          } catch (e) {
            const msg = this.errMsg(e);
            Log.e(TAG, `getAll failed: ${msg}`);
            result.error(TAG, msg, null);
          }
          return;
        }
        // 8.x 只调用 getAll；其余方法宽容回包，避免掐断调用链
        Log.w(TAG, `unhandled method ${call.method}, replying null`);
        result.success(null);
      },
    });
    Log.i(TAG, 'package_info_plus ohos implementation attached');
  }

  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    if (this.channel != null) {
      this.channel.setMethodCallHandler(null);
      this.channel = null;
    }
    this.context = null;
  }

  /** 组装 package_info 协议要求的字段。取不到的项退化为空串，不阻断调用方。 */
  private collect(): Record<string, Object> {
    const ctx = this.context;
    if (ctx == null) {
      throw new Error('application context unavailable');
    }

    // 兜底来源：Ability 的 Context 上直接带 ApplicationInfo
    // 注意：ApplicationInfo 上只有 name/label/labelId/installSource，
    // versionName / versionCode 只存在于 BundleInfo，必须走 bundleManager。
    const appInfo = ctx.applicationInfo;
    let packageName: string = appInfo.name;
    let appLabelId: number = appInfo.labelId;
    let installerStore: string = appInfo.installSource;
    let version = '';
    let buildNumber = '';

    // 权威来源：bundleManager 自查询
    try {
      const info = bundleManager.getBundleInfoForSelfSync(
        bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION,
      );
      if (info != null) {
        packageName = info.name;
        version = info.versionName;
        buildNumber = info.versionCode.toString();
        if (info.appInfo != null) {
          appLabelId = info.appInfo.labelId;
          installerStore = info.appInfo.installSource;
        }
      }
    } catch (e) {
      Log.w(TAG, `getBundleInfoForSelfSync failed, using applicationInfo: ${this.errMsg(e)}`);
    }

    // label 是资源 id，需经 resourceManager 解析成展示名（如「PT-Mate」）
    let appName = '';
    try {
      appName = ctx.resourceManager.getStringSync(appLabelId);
    } catch (e) {
      Log.w(TAG, `resolve app label failed: ${this.errMsg(e)}`);
    }
    if (appName.length === 0) {
      appName = packageName;
    }

    // installTime / updateTime 无对应系统能力：回空串 → Dart 侧 int.tryParse
    // 得 null → 字段为 null，不会抛异常。
    const out: Record<string, Object> = {
      'appName': appName,
      'packageName': packageName,
      'version': version,
      'buildNumber': buildNumber,
      'buildSignature': '',
      'installerStore': installerStore,
      'installTime': '',
      'updateTime': '',
    };
    Log.i(TAG, `package info: ${packageName} ${version} (${buildNumber}) label=${appName}`);
    return out;
  }

  private errMsg(e: Object): string {
    return e instanceof Error ? (e.message ?? 'unknown error') : String(e);
  }
}
