/// Matter 设备配网与控制插件。
///
/// 这是一个可整体迁移的 Flutter 插件（仅 Android）：在宿主 App 的 pubspec.yaml
/// 中以 path 或 git 依赖引入即可使用。
///
/// 用法示例：
/// ```dart
/// final matter = MatterControl(backend: PlatformMatterBackend());
/// final device = await matter.commissionOnNetwork(...);
/// await matter.setOnOff(device.id, true);
/// ```
library;

export 'src/matter_control_base.dart';
export 'src/backend/matter_backend.dart';
export 'src/backend/fake_matter_backend.dart';
export 'src/backend/platform_matter_backend.dart';
export 'src/models/matter_device.dart';
export 'src/models/device_state.dart';
export 'src/models/matter_exception.dart';
export 'src/ui/matter_devices_page.dart';
export 'src/ui/add_device_page.dart';
export 'src/ui/device_control_page.dart';
