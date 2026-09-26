/*
 * [移植适配-OHOS] file_picker 鸿蒙实现
 *
 * 上游 file_picker 10.x 没有 ohos 平台实现，GeneratedPluginRegistrant 里不会注册它。
 * Dart 侧 FilePicker.platform.pickFiles() 走 MethodChannel 后无接收端：
 *   - pickFiles → 抛 MissingPluginException，落在 BackupException('导入备份失败: ...')
 *   - saveFile  → Platform.isAndroid/isIOS 均为 false，落到基类 throw UnimplementedError
 *
 * 本实现用鸿蒙系统文件选择器（@kit.CoreFileKit 的 picker.DocumentViewPicker）补齐：
 *   channel 方法 'custom'/'any'/'media'/'image'/'video'/'audio'  → 选择文件
 *   channel 方法 'save'                                        → 选择保存位置
 *   channel 方法 'clear'                                       → 空操作
 *
 * 【设计要点：把选中文件复制进沙箱再返回】
 * Picker 返回的是 URI（形如 file://docs/storage/...），Dart 的 dart:io File()
 * 无法直接读取该形式。因此这里统一把文件复制到 filesDir 下，返回真实沙箱路径，
 * Dart 侧 File(path).readAsString() 才能正常工作。
 *
 * channel: miguelruivo.flutter.plugins.filepicker（StandardMethodCodec）
 */

import common from '@ohos.app.ability.common';
import { picker, fileIo } from '@kit.CoreFileKit';
import { MethodChannel, MethodCall, MethodResult, Any } from '@ohos/flutter_ohos';
import { FlutterPlugin, FlutterPluginBinding } from '@ohos/flutter_ohos';
import Log from '@ohos/flutter_ohos/src/main/ets/util/Log';
import { OhosPluginContext } from './OhosPluginContext';

const TAG = 'FilePickerOhos';
const CHANNEL_NAME = 'miguelruivo.flutter.plugins.filepicker';

export default class FilePickerOhos implements FlutterPlugin {
  private channel: MethodChannel | null = null;
  private appContext: common.Context | null = null;

  getUniqueClassName(): string {
    return 'FilePickerOhos';
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.appContext = binding.getApplicationContext();
    this.channel = new MethodChannel(binding.getBinaryMessenger(), CHANNEL_NAME);
    this.channel.setMethodCallHandler({
      onMethodCall: (call: MethodCall, result: MethodResult): void => {
        this.handle(call, result);
      },
    });
    Log.i(TAG, 'file_picker ohos implementation attached');
  }

  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    if (this.channel != null) {
      this.channel.setMethodCallHandler(null);
      this.channel = null;
    }
    this.appContext = null;
  }

  // ------------------------------------------------------------ channel 分发

  private handle(call: MethodCall, result: MethodResult): void {
    // [移植适配-OHOS] 诊断：确认 Dart 侧实际下发的方法名
    Log.i(TAG, 'handle method=' + call.method);
    switch (call.method) {
      case 'custom':
      case 'any':
      case 'media':
      case 'image':
      case 'video':
      case 'audio':
        this.pickFiles(call, result);
        break;

      case 'save':
        this.saveFile(call, result);
        break;

      case 'clear':
        // 无临时文件需要清理（本实现落盘在沙箱，由系统统一回收）
        result.success(true);
        break;

      default:
        Log.w(TAG, `unhandled method ${call.method}`);
        result.notImplemented();
        break;
    }
  }

  // ------------------------------------------------------------ pickFiles

  private async pickFiles(call: MethodCall, result: MethodResult): Promise<void> {
    const ctx = OhosPluginContext.get();
    if (ctx == null) {
      const msg = 'UIAbilityContext unavailable (EntryAbility did not inject it)';
      Log.e(TAG, `pickFiles failed: ${msg}`);
      result.error(TAG, msg, null);
      return;
    }

    try {
      const options = new picker.DocumentSelectOptions();
      const allowMultiple: Any = call.argument('allowMultipleSelection');
      options.maxSelectNumber = allowMultiple === true ? 100 : 1;

      const filters = this.suffixFilters(call);
      if (filters.length > 0) {
        options.fileSuffixFilters = filters;
      }

      const documentPicker = new picker.DocumentViewPicker(ctx);
      const uris: Array<string> = await documentPicker.select(options);
      Log.i(TAG, `pickFiles selected ${uris.length} file(s)`);

      const files: Array<Record<string, Object>> = [];
      for (const uri of uris) {
        const entry = this.copyToSandbox(ctx, uri);
        if (entry != null) {
          files.push(entry);
        }
      }

      // Dart 侧 result == null 表示用户取消；空数组同样按取消处理更安全
      if (files.length === 0) {
        result.success(null);
        return;
      }
      result.success(files);
    } catch (e) {
      const msg = this.errMsg(e);
      Log.e(TAG, `pickFiles failed: ${msg}`);
      result.error(TAG, msg, null);
    }
  }

  /** 把 Picker 授权的 URI 复制到沙箱，返回 Dart 侧可直接 File() 读取的真实路径。 */
  private copyToSandbox(ctx: common.UIAbilityContext, uri: string): Record<string, Object> | null {
    let src: fileIo.File | null = null;
    let dst: fileIo.File | null = null;
    try {
      src = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY);
      const stat = fileIo.statSync(src.fd);
      const name = this.baseName(uri);
      const path = `${ctx.filesDir}/${name}`;

      dst = fileIo.openSync(
        path,
        fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC,
      );
      fileIo.copyFileSync(src.fd, dst.fd);

      const entry: Record<string, Object> = {
        'name': name,
        'path': path,
        'size': stat.size,
        'identifier': uri,
      };
      Log.i(TAG, `copied "${name}" (${stat.size} bytes) into sandbox`);
      return entry;
    } catch (e) {
      Log.e(TAG, `copy to sandbox failed: ${this.errMsg(e)}`);
      return null;
    } finally {
      if (dst != null) {
        fileIo.closeSync(dst);
      }
      if (src != null) {
        fileIo.closeSync(src);
      }
    }
  }

  // ------------------------------------------------------------ saveFile

  private async saveFile(call: MethodCall, result: MethodResult): Promise<void> {
    const ctx = OhosPluginContext.get();
    if (ctx == null) {
      const msg = 'UIAbilityContext unavailable (EntryAbility did not inject it)';
      Log.e(TAG, `saveFile failed: ${msg}`);
      result.error(TAG, msg, null);
      return;
    }

    let sandboxPath = '';
    try {
      const fileNameArg: Any = call.argument('fileName');
      const fileName = fileNameArg == null ? 'pt-mate-backup.json' : String(fileNameArg);

      // 1) 先落沙箱：Dart 侧 exportBackup 期望拿到可被 File(path) 操作的路径
      sandboxPath = `${ctx.filesDir}/${fileName}`;
      const bytes = this.toArrayBuffer(call.argument('bytes'));
      const sandboxFile = fileIo.openSync(
        sandboxPath,
        fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC,
      );
      try {
        if (bytes != null && bytes.byteLength > 0) {
          fileIo.writeSync(sandboxFile.fd, bytes);
        }
      } finally {
        fileIo.closeSync(sandboxFile);
      }

      // 2) 让用户选保存位置，再把沙箱文件拷过去
      const options = new picker.DocumentSaveOptions();
      options.newFileNames = [fileName];
      const choices = this.suffixFilters(call);
      if (choices.length > 0) {
        options.fileSuffixChoices = choices;
      }

      const documentPicker = new picker.DocumentViewPicker(ctx);
      const uris: Array<string> = await documentPicker.save(options);
      Log.i(TAG, 'save dialog returned ' + uris.length + ' uri(s)');
      if (uris.length > 0) {
        const dstFile = fileIo.openSync(
          uris[0],
          fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC,
        );
        const srcFile = fileIo.openSync(sandboxPath, fileIo.OpenMode.READ_ONLY);
        try {
          fileIo.copyFileSync(srcFile.fd, dstFile.fd);
        } finally {
          fileIo.closeSync(srcFile);
          fileIo.closeSync(dstFile);
        }
        Log.i(TAG, `saved backup to user location`);
      } else {
        Log.w(TAG, 'save dialog dismissed; sandbox copy retained');
      }

      result.success(sandboxPath);
    } catch (e) {
      const msg = this.errMsg(e);
      Log.e(TAG, `saveFile failed: ${msg}`);
      result.error(TAG, msg, null);
    }
  }

  // ------------------------------------------------------------ 工具方法

  /** allowedExtensions(['json']) → fileSuffixFilters(['.json']) */
  private suffixFilters(call: MethodCall): Array<string> {
    const out: Array<string> = [];
    const raw: Any = call.argument('allowedExtensions');
    if (!(raw instanceof Array)) {
      return out;
    }
    const list = raw as Array<Object>;
    for (let i = 0; i < list.length; i++) {
      const item = list[i];
      if (item == null) {
        continue;
      }
      const text = String(item);
      out.push(text.startsWith('.') ? text : `.${text}`);
    }
    return out;
  }

  /** 从 Picker 返回的 URI 里取文件名。 */
  private baseName(uri: string): string {
    const slash = uri.lastIndexOf('/');
    let raw = slash >= 0 ? uri.substring(slash + 1) : uri;
    const query = raw.indexOf('?');
    if (query >= 0) {
      raw = raw.substring(0, query);
    }
    try {
      return decodeURIComponent(raw);
    } catch (e) {
      return raw;
    }
  }

  /** Dart 的 Uint8List 经 StandardMessageCodec 解码为 Uint8Array。 */
  private toArrayBuffer(value: Any): ArrayBuffer | null {
    if (value instanceof Uint8Array) {
      return value.buffer as ArrayBuffer;
    }
    if (value instanceof ArrayBuffer) {
      return value as ArrayBuffer;
    }
    return null;
  }

  private errMsg(e: Object): string {
    return e instanceof Error ? (e.message ?? 'unknown error') : String(e);
  }
}
