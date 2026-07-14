/// Matter 设备配网与控制插件 —— 功能 API 入口。
///
/// 这是一个仅 Android 的 Flutter 插件，只提供**功能能力**（配网、控制、设备管理），
/// 不包含任何界面。与 `mobile_scanner`、`permission_handler` 等功能型插件一样，
/// UI 由主 App 自行实现——本插件只把方法与数据流暴露出来。
///
/// 用法示例：
/// ```dart
/// final matter = MatterControl(backend: PlatformMatterBackend());
/// await matter.selfTest();
/// final device = await matter.commissionOnNetwork(
///   ipAddress: '192.168.1.20', port: 5540,
///   setupPinCode: 20202021, discriminator: 3840,
/// );
/// await matter.setOnOff(device.id, true);
/// matter.devices.listen((list) => print(list));
/// ```
library;

// 门面：对外唯一的功能入口。
export 'src/matter_control_base.dart';

// 后端：抽象接口 + 真实平台实现 + 假数据实现（便于无设备时联调）。
export 'src/backend/matter_backend.dart';
export 'src/backend/fake_matter_backend.dart';
export 'src/backend/platform_matter_backend.dart';

// 数据模型：设备、设备状态、异常。
export 'src/models/matter_device.dart';
export 'src/models/device_state.dart';
export 'src/models/matter_exception.dart';

// 权限：BLE 配网前的运行时权限申请工具。
export 'src/matter_permissions.dart';
