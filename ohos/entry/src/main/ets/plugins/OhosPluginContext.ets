/*
 * [移植适配-OHOS] UIAbilityContext 共享单例
 *
 * 某些系统 API 只接受 UIAbilityContext，典型代表：
 *   picker.DocumentViewPicker(context)  —— 注释明确 "only UIAbilityContext is supported"
 * 而 FlutterPluginBinding.getApplicationContext() 给到的是 ApplicationContext，
 * 拿它去构造 Picker 会失败。
 *
 * 由 EntryAbility 在 onCreate 时注入真正的 UIAbilityContext，
 * 插件在「真正发起点选」时惰性读取（不能在建插件时就取，那时 Ability 可能还没建好）。
 */

import common from '@ohos.app.ability.common';

export class OhosPluginContext {
  private static abilityContext: common.UIAbilityContext | null = null;

  static set(context: common.UIAbilityContext): void {
    OhosPluginContext.abilityContext = context;
  }

  static get(): common.UIAbilityContext | null {
    return OhosPluginContext.abilityContext;
  }
}
