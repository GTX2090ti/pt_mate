
import { FlutterAbility, FlutterEngine } from '@ohos/flutter_ohos';
import { GeneratedPluginRegistrant } from '../plugins/GeneratedPluginRegistrant';
import { ManualPluginRegistrant } from '../plugins/ManualPluginRegistrant';
import { OhosPluginContext } from '../plugins/OhosPluginContext';

export default class EntryAbility extends FlutterAbility {
  configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    // [移植适配-OHOS] picker.DocumentViewPicker 等系统 API 只接受 UIAbilityContext，
    // 而 FlutterPluginBinding.getApplicationContext() 给到的是 ApplicationContext。
    // 在这里注入真正的 UIAbilityContext，插件在真正呼起 Picker 时再惰性读取。
    OhosPluginContext.set(this.context);
    GeneratedPluginRegistrant.registerWith(flutterEngine)
    // [移植适配-OHOS] 手写桥接插件（shared_preferences / secure_storage /
    // path_provider / package_info / file_picker）不进入生成的 registrant，
    // 必须手工挂载，否则 Dart 侧 MethodChannel 无接收端。
    ManualPluginRegistrant.registerWith(flutterEngine)
  }
}
