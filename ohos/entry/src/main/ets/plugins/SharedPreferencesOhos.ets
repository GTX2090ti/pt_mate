/*
 * [移植适配-OHOS] shared_preferences 鸿蒙实现
 *
 * 上游 shared_preferences 无 ohos 实现，Dart 侧 SharedPreferences.getInstance()
 * 同样会挂起。站点配置、显示设置、更新检查等都依赖它。
 *
 * 底层使用 @kit.ArkData 的 preferences（键值持久化），语义对齐
 * shared_preferences 2.x 的 channel 协议。
 *
 * channel: plugins.flutter.io/shared_preferences
 *
 * ArkTS 约束备忘：
 *  - 禁止用 obj[key] 做动态字段访问（arkts-no-props-by-index）
 *  - 禁止 any/unknown（arkts-no-any-unknown）
 *  故此处统一用 Map 承载中间数据，读写时显式取值。
 */

import common from '@ohos.app.ability.common';
import { preferences } from '@kit.ArkData';
import { MethodChannel, MethodCall, MethodResult, Any } from '@ohos/flutter_ohos';
import { FlutterPlugin, FlutterPluginBinding } from '@ohos/flutter_ohos';
import Log from '@ohos/flutter_ohos/src/main/ets/util/Log';

const TAG = 'SharedPreferencesOhos';
const CHANNEL_NAME = 'plugins.flutter.io/shared_preferences';
const PREFIX = 'flutter.';
const STORE_NAME = 'ptmate_prefs';

export default class SharedPreferencesOhos implements FlutterPlugin {
  private channel: MethodChannel | null = null;
  private context: common.Context | null = null;
  private store: preferences.Preferences | null = null;

  getUniqueClassName(): string {
    return 'SharedPreferencesOhos';
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.context = binding.getApplicationContext();
    this.channel = new MethodChannel(binding.getBinaryMessenger(), CHANNEL_NAME);
    this.channel.setMethodCallHandler({
      onMethodCall: (call: MethodCall, result: MethodResult): void => {
        try {
          this.handle(call, result);
        } catch (e) {
          const msg = e instanceof Error ? (e.message ?? '') : String(e);
          Log.e(TAG, `${call.method} failed: ${msg}`);
          result.error('shared_preferences_error', msg, null);
        }
      },
    });
    Log.i(TAG, 'shared_preferences ohos implementation attached');
  }

  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    if (this.channel != null) {
      this.channel.setMethodCallHandler(null);
      this.channel = null;
    }
    this.store = null;
    this.context = null;
  }

  private prefs(): preferences.Preferences {
    if (this.store != null) {
      return this.store;
    }
    const ctx = this.context;
    if (ctx == null) {
      throw new Error('application context unavailable');
    }
    const options: preferences.Options = { name: STORE_NAME };
    this.store = preferences.getPreferencesSync(ctx, options);
    return this.store;
  }

  private handle(call: MethodCall, result: MethodResult): void {
    const store = this.prefs();

    switch (call.method) {
      case 'getAll': {
        // 协议要求：返回去掉 flutter. 前缀后的键值对
        const out: Map<string, Object> = new Map<string, Object>();
        const all = store.getAllSync() as Record<string, Object>;
        for (const k of Object.keys(all)) {
          if (k.startsWith(PREFIX)) {
            // 列表值必须还原成真正的数组，否则 Dart 侧强转失败（见
            // restoreStringList 的说明）。
            out.set(
              k.substring(PREFIX.length),
              SharedPreferencesOhos.restoreStringList(all[k]),
            );
          }
        }
        result.success(this.mapToObject(out));
        break;
      }

      case 'setBool': {
        const v: Any = this.optArg(call, 'value');
        store.putSync(PREFIX + this.strArg(call, 'key'), v === true);
        store.flushSync();
        result.success(true);
        break;
      }

      case 'setString':
        store.putSync(PREFIX + this.strArg(call, 'key'), this.strArg(call, 'value'));
        store.flushSync();
        result.success(true);
        break;

      case 'setInt': {
        const v: Any = this.optArg(call, 'value');
        store.putSync(PREFIX + this.strArg(call, 'key'), Math.trunc(Number(v)));
        store.flushSync();
        result.success(true);
        break;
      }

      case 'setDouble': {
        const v: Any = this.optArg(call, 'value');
        store.putSync(PREFIX + this.strArg(call, 'key'), Number(v));
        store.flushSync();
        result.success(true);
        break;
      }

      case 'setStringList': {
        const arr: Array<string> = [];
        const rawList: Any = this.optArg(call, 'value');
        if (rawList instanceof Array) {
          const typed = rawList as Array<Object>;
          for (let i = 0; i < typed.length; i++) {
            arr.push(String(typed[i]));
          }
        }
        const listKey = PREFIX + this.strArg(call, 'key');
        try {
          // preferences 原生支持 Array<string>，以数组形态写入，getAll 才能
          // 原样返回数组（见 restoreStringList）。
          store.putSync(listKey, arr);
        } catch (e) {
          // 少数设备/版本不接受数组值，降级为 JSON 文本；读取时由
          // restoreStringList 还原，对 Dart 侧表现一致。
          store.putSync(listKey, JSON.stringify(arr));
        }
        store.flushSync();
        result.success(true);
        break;
      }

      case 'remove':
        store.deleteSync(PREFIX + this.strArg(call, 'key'));
        store.flushSync();
        result.success(true);
        break;

      case 'clear': {
        // 只清 flutter. 前缀的数据，避免误删宿主应用的偏好项
        const all = store.getAllSync() as Record<string, Object>;
        for (const k of Object.keys(all)) {
          if (k.startsWith(PREFIX)) {
            store.deleteSync(k);
          }
        }
        store.flushSync();
        result.success(true);
        break;
      }

      case 'commit':
        store.flushSync();
        result.success(true);
        break;

      default:
        Log.w(TAG, `unhandled method ${call.method}`);
        result.notImplemented();
        break;
    }
  }

  /**
   * [移植适配-OHOS] 还原被降级存储的「字符串列表」。
   *
   * shared_preferences 的 Dart 侧对 getAll() 的返回值直接做强转
   * （`_preferenceCache[key] as List<dynamic>`）。早期实现为规避 preferences
   * 对数组值的兼容问题，把列表 `JSON.stringify` 后以字符串写入，导致：
   *  - 所有 `getStringList()` 调用点抛
   *    `type 'String' is not a subtype of type 'List<dynamic>?' in type cast`
   *  - 备份导出在收集「默认下载标签 / 代理绕过规则」阶段直接中断
   *
   * 这里在读出时把 JSON 数组文本还原成真正的 Array<string>：
   *  - 已是数组：原样返回（新写入路径）
   *  - 非字符串或不是 `[...]` 形态：原样返回
   *  - 解析结果必须是**扁平字符串数组**才还原，避免把以 JSON 文本形式
   *    存储的结构化数据（站点列表、WebDAV 配置历史等对象数组）误判为列表，
   *    否则这些键在 Dart 侧 `getString()` 时会反向崩溃。
   */
  private static restoreStringList(value: Object): Object {
    if (value instanceof Array) {
      return value;
    }
    if (typeof value !== 'string') {
      return value;
    }
    const text: string = (value as string).trim();
    if (text.length < 2 || !text.startsWith('[') || !text.endsWith(']')) {
      return value;
    }
    try {
      const parsed: Object = JSON.parse(text) as Object;
      if (!(parsed instanceof Array)) {
        return value;
      }
      const items = parsed as Array<Object>;
      const out: Array<string> = [];
      for (let i = 0; i < items.length; i++) {
        const item: Object = items[i];
        if (typeof item !== 'string') {
          return value;
        }
        out.push(item as string);
      }
      return out;
    } catch (e) {
      return value;
    }
  }

  private mapToObject(src: Map<string, Object>): Record<string, Object> {
    const out: Record<string, Object> = {};
    src.forEach((v: Object, k: string) => {
      out[k] = v;
    });
    return out;
  }

  /**
   * 【必须走 call.argument()】引擎 StandardMessageCodec 把 Dart 的 Map 解码为
   * ArkTS 原生 Map（readValueOfType 的 `new Map()` 分支），不是普通对象：
   *  - `Object.keys(map)` 恒为空数组
   *  - `map['key']` 索引访问恒为 undefined
   * 引擎的 argument() 内部已兼容 Map / Object 两种情况。
   */
  private strArg(call: MethodCall, name: string): string {
    const v: Any = call.argument(name);
    if (v === null || v === undefined) {
      throw new Error(`missing argument "${name}"`);
    }
    return String(v);
  }

  private optArg(call: MethodCall, name: string): Any {
    return call.argument(name);
  }
}
