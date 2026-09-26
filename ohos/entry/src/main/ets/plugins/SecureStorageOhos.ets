/*
 * [移植适配-OHOS] flutter_secure_storage 鸿蒙实现
 *
 * 上游 flutter_secure_storage 没有 ohos 平台实现，GeneratedPluginRegistrant 为空，
 * Dart 侧 _secure.read() 的 MethodChannel 调用既无接收端也不抛 MissingPluginException，
 * 会永久挂起，导致启动链路卡死白屏。
 *
 * 本实现：
 *  - 数据落盘 filesDir/ptmate_secure_storage.bin
 *  - 先用 @kit.CryptoArchitectureKit 的 AES-256-GCM 加密；如设备能力不可用，
 *    退化为明文存储（仍保持接口语义，不阻塞启动），并在日志中明确告警
 *  - 覆盖 flutter_secure_storage 10.x 的全部 channel 方法
 *
 * channel: plugins.it_nomads.com/flutter_secure_storage
 */

import common from '@ohos.app.ability.common';
import { fileIo } from '@kit.CoreFileKit';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { util } from '@kit.ArkTS';
import { MethodChannel, MethodCall, MethodResult, Any } from '@ohos/flutter_ohos';
import { FlutterPlugin, FlutterPluginBinding } from '@ohos/flutter_ohos';
import Log from '@ohos/flutter_ohos/src/main/ets/util/Log';

const TAG = 'SecureStorageOhos';
const CHANNEL_NAME = 'plugins.it_nomads.com/flutter_secure_storage';
const STORE_FILE = 'ptmate_secure_storage.bin';
const KEY_FILE = 'ptmate_secure_storage.key';
const MAGIC = 'PTMS1:';
const KEY_LEN = 32;
/** GCM 认证标签长度。加密输出为「密文 + 追加的 TAG_LEN 字节 tag」（见 decryptText）。 */
const TAG_LEN = 16;

export default class SecureStorageOhos implements FlutterPlugin {
  private channel: MethodChannel | null = null;
  private context: common.Context | null = null;
  private store: Map<string, string> = new Map<string, string>();
  private loaded = false;
  private key: Uint8Array | null = null;
  private cryptoAvailable = true;

  getUniqueClassName(): string {
    return 'SecureStorageOhos';
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.context = binding.getApplicationContext();
    this.channel = new MethodChannel(binding.getBinaryMessenger(), CHANNEL_NAME);
    this.channel.setMethodCallHandler({
      onMethodCall: (call: MethodCall, result: MethodResult): void => {
        this.handle(call, result);
      },
    });
    Log.i(TAG, 'flutter_secure_storage ohos implementation attached');
  }

  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    if (this.channel != null) {
      this.channel.setMethodCallHandler(null);
      this.channel = null;
    }
    this.context = null;
    this.key = null;
  }

  // ------------------------------------------------------------ channel 分发

  private handle(call: MethodCall, result: MethodResult): void {
    // 先加载已落盘的数据。否则 read 取不到旧值，且 write 会用「空映射 + 新值」
    // 覆盖写回文件，造成已存密码丢失。
    this.ensureLoaded();
    try {
      switch (call.method) {
        case 'read':
          this.sendMaybe(result, this.store.get(this.arg(call, 'key')));
          break;

        case 'containsKey':
          result.success(this.store.has(this.arg(call, 'key')));
          break;

        case 'readAll':
        case 'readAllWithOptions':
        case 'readAllWithParameters':
          result.success(this.dumpAll());
          break;

        case 'write': {
          const key = this.arg(call, 'key');
          const value: Any = this.argOrNull(call, 'value');
          if (value === null || value === undefined) {
            this.store.delete(key);
          } else {
            this.store.set(key, String(value));
          }
          this.persist();
          result.success(null);
          break;
        }

        case 'delete': {
          this.store.delete(this.arg(call, 'key'));
          this.persist();
          result.success(null);
          break;
        }

        case 'deleteAll':
          this.store.clear();
          this.persist();
          result.success(null);
          break;

        default:
          Log.w(TAG, `unhandled method ${call.method}`);
          result.notImplemented();
          break;
      }
    } catch (e) {
      const msg = e instanceof Error ? (e.message ?? '') : String(e);
      Log.e(TAG, `${call.method} failed: ${msg}`);
      result.error('secure_storage_error', msg, null);
    }
  }

  private sendMaybe(result: MethodResult, value: string | undefined): void {
    result.success(value === undefined ? null : value);
  }

  private dumpAll(): Record<string, string> {
    const out: Record<string, string> = {};
    this.store.forEach((v: string, k: string) => {
      out[k] = v;
    });
    return out;
  }

  /**
   * 提取字符串参数。
   *
   * 【必须走 call.argument()】引擎 StandardMessageCodec 把 Dart 的 Map 解码为
   * ArkTS 原生 Map（见 readValueOfType 的 `new Map()` 分支），不是普通对象。
   * 直接 `args['key']` 索引在 Map 上恒为 undefined，会误报 "missing argument"。
   * 引擎的 argument() 内部已兼容 Map / Object 两种情况。
   */
  private arg(call: MethodCall, name: string): string {
    const v: Any = call.argument(name);
    if (v === null || v === undefined) {
      throw new Error(`missing argument "${name}"`);
    }
    return String(v);
  }

  private argOrNull(call: MethodCall, name: string): Any {
    return call.argument(name);
  }

  // ---------------------------------------------------------------- 持久化

  private storePath(): string {
    const ctx = this.context;
    if (ctx == null) {
      throw new Error('application context unavailable');
    }
    return `${ctx.filesDir}/${STORE_FILE}`;
  }

  private keyPath(): string {
    const ctx = this.context as common.Context;
    return `${ctx.filesDir}/${KEY_FILE}`;
  }

  private ensureLoaded(): void {
    if (this.loaded) {
      return;
    }
    this.loaded = true;
    try {
      const path = this.storePath();
      if (!fileIo.accessSync(path)) {
        return;
      }
      const raw = this.readFileText(path);
      if (raw.startsWith(MAGIC)) {
        const body = raw.substring(MAGIC.length);
        // decryptText 直接读 this.key，这里先触发密钥加载，否则永远解不开旧数据。
        this.ensureKey();
        const plain = this.decryptText(body);
        if (plain != null) {
          this.mergeJson(plain);
          return;
        }
        // 解不开就把原文件另存一份，避免被后续 persist 无痕覆盖，便于事后排查。
        this.preserveCorrupt(path, raw);
        Log.w(TAG, 'store decrypt failed, start with empty map');
        return;
      }
      // 兼容早期未加密格式
      this.mergeJson(raw);
    } catch (e) {
      const msg = e instanceof Error ? (e.message ?? '') : String(e);
      Log.e(TAG, `load store failed, start with empty map: ${msg}`);
      this.store.clear();
    }
  }

  private mergeJson(text: string): void {
    const parsed = JSON.parse(text) as Record<string, string>;
    for (const k of Object.keys(parsed)) {
      this.store.set(k, parsed[k]);
    }
  }

  private persist(): void {
    const json = JSON.stringify(this.dumpAll());
    const enc = this.encryptText(json);
    // 密钥不可用时刻意退化为明文：写出「下次解不开的密文」等于直接丢数据。
    const content = enc == null ? json : MAGIC + enc;
    const path = this.storePath();

    const bytes = new Uint8Array(util.TextEncoder.create('utf-8').encodeInto(content));
    const written = this.writeBytes(path, bytes);
    if (written !== bytes.byteLength) {
      throw new Error(`short write on store: ${written}/${bytes.byteLength}`);
    }
  }

  /** 把无法解密的历史文件另存为 .corrupt，不阻断启动，也避免被无痕覆盖。 */
  private preserveCorrupt(path: string, raw: string): void {
    try {
      const target = `${path}.corrupt`;
      if (fileIo.accessSync(target)) {
        return;
      }
      const bytes = new Uint8Array(util.TextEncoder.create('utf-8').encodeInto(raw));
      this.writeBytes(target, bytes);
      Log.w(TAG, `corrupt store preserved at ${target}`);
    } catch (e) {
      const msg = e instanceof Error ? (e.message ?? '') : String(e);
      Log.w(TAG, `preserve corrupt store failed: ${msg}`);
    }
  }

  private readFileText(path: string): string {
    const file = fileIo.openSync(path, fileIo.OpenMode.READ_ONLY);
    try {
      const stat = fileIo.statSync(path);
      const buf = new ArrayBuffer(stat.size);
      const n = fileIo.readSync(file.fd, buf);
      return util.TextDecoder.create('utf-8').decodeToString(new Uint8Array(buf, 0, n));
    } finally {
      fileIo.closeSync(file);
    }
  }

  // --------------------------------------------------------- AES-256-GCM

  /**
   * 取（或首次生成）256 位密钥，并【确保它真的落盘了】才返回。
   *
   * 【历史 bug —— 这是「装新版后 Cookie/密码全丢」的直接原因】
   * 旧实现末尾是 `fileIo.writeSync(file.fd, this.key)`，而 this.key 是 Uint8Array。
   * SDK 签名是：
   *   writeSync(fd: number, buffer: ArrayBuffer | string, options?: WriteOptions): number
   * 只接受 ArrayBuffer / string —— 传 Uint8Array 不抛异常，但实际写入 0 字节。
   * 后果链：
   *   内存里密钥有效 → 本次运行加解密一切正常（用户看不出问题）
   *   磁盘上密钥文件恒为 0 字节 → 下次启动读不到密钥 → 重新生成新密钥
   *   → 旧密文（Cookie、下载器密码）用新密钥解不开 → 永久丢失
   * 由于「启动应用」必然触发这条路径，用户感知就是「一重启/一升级，数据就没了」。
   *
   * 现在的做法：写 ArrayBuffer + 回读比对；只要校验不过就降级为明文存储。
   * 明文换不来机密性，但**绝不丢数据** —— 对用户而言后者重要得多。
   */
  private ensureKey(): Uint8Array | null {
    if (this.key != null) {
      return this.key;
    }
    if (!this.cryptoAvailable) {
      return null;
    }
    try {
      const path = this.keyPath();

      // 1) 复用已落盘的密钥
      const stored = this.readBytes(path);
      if (stored != null && stored.byteLength === KEY_LEN) {
        this.key = stored;
        return this.key;
      }
      if (stored != null) {
        Log.w(TAG, `stored key has wrong length (${stored.byteLength}), regenerating`);
      }

      // 2) 生成新密钥
      const symKey = cryptoFramework.createSymKeyGenerator('AES256');
      const material = symKey.generateSymKeySync().getEncoded();
      const fresh = material.data;
      if (fresh.byteLength !== KEY_LEN) {
        throw new Error(`unexpected generated key length ${fresh.byteLength}`);
      }

      // 3) 落盘并回读校验 —— 不通过就说明加密数据下次必然读不回来
      const written = this.writeBytes(path, fresh);
      const back = this.readBytes(path);
      if (written !== KEY_LEN || back == null || back.byteLength !== KEY_LEN
        || !this.sameBytes(fresh, back)) {
        const got = back == null ? -1 : back.byteLength;
        throw new Error(`key persist verification failed (written=${written}, reread=${got})`);
      }

      this.key = fresh;
      Log.i(TAG, `AES-256 key generated and persisted (${KEY_LEN} bytes)`);
      return this.key;
    } catch (e) {
      const msg = e instanceof Error ? (e.message ?? '') : String(e);
      Log.e(TAG, `AES key unavailable, falling back to plaintext storage: ${msg}`);
      this.cryptoAvailable = false;
      this.key = null;
      return null;
    }
  }

  /**
   * 写字节数组。
   *
   * 【必须包成 ArrayBuffer】fileIo.writeSync 只接受 ArrayBuffer | string，
   * 直接传 Uint8Array 会静默写入 0 字节（见 ensureKey 的注释）。
   */
  private writeBytes(path: string, bytes: Uint8Array): number {
    const buf = new ArrayBuffer(bytes.byteLength);
    new Uint8Array(buf).set(bytes);
    const file = fileIo.openSync(
      path,
      fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC,
    );
    try {
      const written = fileIo.writeSync(file.fd, buf);
      fileIo.fsyncSync(file.fd);
      return written;
    } finally {
      fileIo.closeSync(file);
    }
  }

  /** 读整个文件为字节数组；不存在或空文件返回 null。 */
  private readBytes(path: string): Uint8Array | null {
    if (!fileIo.accessSync(path)) {
      return null;
    }
    const file = fileIo.openSync(path, fileIo.OpenMode.READ_ONLY);
    try {
      const size = fileIo.statSync(path).size;
      if (size <= 0) {
        return null;
      }
      const buf = new ArrayBuffer(size);
      const n = fileIo.readSync(file.fd, buf);
      if (n <= 0) {
        return null;
      }
      return new Uint8Array(buf, 0, n);
    } finally {
      fileIo.closeSync(file);
    }
  }

  private sameBytes(a: Uint8Array, b: Uint8Array): boolean {
    if (a.byteLength !== b.byteLength) {
      return false;
    }
    for (let i = 0; i < a.byteLength; i++) {
      if (a[i] !== b[i]) {
        return false;
      }
    }
    return true;
  }

  /** 加密：base64(nonce(12) || cipher+tag)。返回 null 表示回退明文。 */
  private encryptText(plain: string): string | null {
    const keyBytes = this.ensureKey();
    if (keyBytes == null) {
      return null;
    }
    try {
      const symKey = cryptoFramework
        .createSymKeyGenerator('AES256')
        .convertKeySync({ data: keyBytes });
      const gcm = cryptoFramework.createCipher('AES256|GCM|NoPadding');
      const nonce = cryptoFramework.createRandom().generateRandomSync(12).data;
      const params: cryptoFramework.GcmParamsSpec = {
        algName: 'GcmParamsSpec',
        iv: { data: nonce },
        aad: { data: new Uint8Array(0) },
        authTag: { data: new Uint8Array(16) },
      };
      gcm.initSync(cryptoFramework.CryptoMode.ENCRYPT_MODE, symKey, params);
      const input = new Uint8Array(util.TextEncoder.create('utf-8').encodeInto(plain));
      const out = gcm.doFinalSync({ data: input });
      const cipher = out.data;

      const combined = new Uint8Array(nonce.length + cipher.length);
      combined.set(nonce, 0);
      combined.set(cipher, nonce.length);
      return this.toBase64(combined);
    } catch (e) {
      const msg = e instanceof Error ? (e.message ?? '') : String(e);
      Log.e(TAG, `encrypt failed, storing plaintext for this write: ${msg}`);
      return null;
    }
  }

  /**
   * 解密 base64(nonce(12) || cipher || authTag(16))，失败返回 null。
   *
   * 【历史 bug —— 这是「冷启动后 Cookie / 下载器密码 / CookieCloud 配置全丢」的根因】
   * 鸿蒙 cryptoFramework 在 GCM 模式下，`doFinalSync` 的加密输出是
   * **密文 + 追加在末尾的 16 字节 authTag**（不是只输出密文、tag 另给）。
   *
   * 旧实现解密时把 `raw.slice(12)`（密文 + tag 整体）当作密文传给 doFinalSync，
   * 同时 authTag 填的是全 0 的 16 字节 —— GCM 认证必然失败，decryptText 恒返回
   * null，于是 ensureLoaded() 判定「文件损坏」→ 清空 store → 原文件另存 .corrupt。
   *
   * 后果链（与用户反馈完全一致）：
   *   写入   → 加密正常、落盘正常（所以数据在文件里，用正确格式能解开）
   *   冷启动 → 解密恒失败 → store 为空 → 所有 read 返回 null
   *          → 表现为「Cookie 过期 / 密码没保存 / CookieCloud 配置丢失」
   *   用户重填 → 本次会话内存里有效 → 下次冷启动再丢
   *
   * 正确做法：末尾 16 字节是 authTag，必须切出来单独传给 GcmParamsSpec.authTag。
   */
  private decryptText(payload: string): string | null {
    const keyBytes = this.key;
    if (keyBytes == null) {
      return null;
    }
    try {
      const raw = this.fromBase64(payload);
      // 至少要有 1 字节密文 + 16 字节 tag
      if (raw.length <= 12 + TAG_LEN) {
        return null;
      }
      const nonce = raw.slice(0, 12);
      const body = raw.slice(12);
      const cipher = body.slice(0, body.length - TAG_LEN);
      const authTag = body.slice(body.length - TAG_LEN);

      const symKey = cryptoFramework
        .createSymKeyGenerator('AES256')
        .convertKeySync({ data: keyBytes });
      const gcm = cryptoFramework.createCipher('AES256|GCM|NoPadding');
      const params: cryptoFramework.GcmParamsSpec = {
        algName: 'GcmParamsSpec',
        iv: { data: nonce },
        aad: { data: new Uint8Array(0) },
        authTag: { data: authTag }, // ← 末尾 16 字节，不是全 0
      };
      gcm.initSync(cryptoFramework.CryptoMode.DECRYPT_MODE, symKey, params);
      const out = gcm.doFinalSync({ data: cipher });
      return util.TextDecoder.create('utf-8').decodeToString(out.data);
    } catch (e) {
      const msg = e instanceof Error ? (e.message ?? '') : String(e);
      Log.e(TAG, `decrypt failed: ${msg}`);
      return null;
    }
  }

  private toBase64(data: Uint8Array): string {
    return new util.Base64Helper().encodeToStringSync(data);
  }

  private fromBase64(text: string): Uint8Array {
    return new util.Base64Helper().decodeSync(text);
  }
}
