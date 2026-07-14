# matter_plugins

一个**仅 Android** 的 Flutter 插件，封装 Matter 协议的设备配网与控制能力。

本插件**只提供功能 API，不包含任何界面**——和 `mobile_scanner`、`permission_handler` 一样，UI 完全由主 App 自行实现。插件负责扫码/输入码配网、IP 直连配网、设备开关调光、设备列表与实时状态推送。

---

## 一、功能一览

所有能力都通过门面类 `MatterControl` 暴露：

| 分类 | 方法 | 说明 |
| --- | --- | --- |
| 配网 | `commissionDevice(setupPayload, wifiSsid, wifiPassword)` | 通过扫码二维码 / 11 位配对码走 **BLE 配网**：蓝牙连上设备 → 下发 WiFi 凭据 → 入网 |
| 配网 | `commissionOnNetwork(ipAddress, port, setupPinCode, discriminator)` | **IP 直连配网**，连接已在局域网内的设备（如电脑上的虚拟灯 chip-lighting-app） |
| 控制 | `setOnOff(deviceId, on)` | 开 / 关（灯、插座） |
| 控制 | `setBrightness(deviceId, 0-100)` | 调光（可调光灯） |
| 管理 | `refresh()` / `currentDevices` | 拉取 / 读取已绑定设备列表 |
| 管理 | `devices` (Stream) | 设备列表实时流，状态变化自动推送，配合 `StreamBuilder` 使用 |
| 管理 | `removeDevice(deviceId)` | 解绑设备 |
| 自检 | `selfTest()` | 验证原生 Matter 库（`.so`/`.jar`）能否正常加载，返回 `{ok, version, error}` |
| 生命周期 | `dispose()` | 释放资源（关闭内部 Stream） |

支持的设备类型（`MatterDeviceType`）：灯、可调光灯、插座、门窗传感器、温度传感器。

---

## 二、接入步骤

### 1. 添加依赖

在主 App 的 `pubspec.yaml` 中用 `path` 或 `git` 引入：

```yaml
dependencies:
  # 本地相对路径（推荐用于同仓库开发）
  matter_plugins:
    path: ../matter_plugins

  # 或者 Git 依赖
  # matter_plugins:
  #   git:
  #     url: https://your.git/matter_plugins.git
  #     ref: main
```

然后执行 `flutter pub get`。

### 2. 配置 Android 权限

插件自带的 `AndroidManifest.xml` 已声明蓝牙 / WiFi 权限，会自动合并到主 App。但以下权限**属于主 App 的职责**，需你在 `android/app/src/main/AndroidManifest.xml` 的 `<manifest>` 内补充：

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:tools="http://schemas.android.com/tools">

    <!-- 若使用扫码配网，需相机权限（扫码 UI 由你自己用 mobile_scanner 等实现） -->
    <uses-permission android:name="android.permission.CAMERA" />
    <uses-feature android:name="android.hardware.camera" android:required="false" />

    <!-- BLE 配网所需 -->
    <uses-permission android:name="android.permission.BLUETOOTH_SCAN"
        android:usesPermissionFlags="neverForLocation" tools:targetApi="s" />
    <uses-permission android:name="android.permission.BLUETOOTH_CONNECT" tools:targetApi="s" />
    <uses-permission android:name="android.permission.BLUETOOTH" android:maxSdkVersion="30" />
    <uses-permission android:name="android.permission.BLUETOOTH_ADMIN" android:maxSdkVersion="30" />
    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />

    <!-- WiFi + mDNS 发现所需 -->
    <uses-permission android:name="android.permission.INTERNET" />
    <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
    <uses-permission android:name="android.permission.ACCESS_WIFI_STATE" />
    <uses-permission android:name="android.permission.CHANGE_WIFI_STATE" />
    <uses-permission android:name="android.permission.NEARBY_WIFI_DEVICES"
        android:usesPermissionFlags="neverForLocation" tools:targetApi="tiramisu" />

    <application ...>
</manifest>
```

### 3. 确认 Gradle 配置

主 App 的 `android/app/build.gradle.kts` 需满足：

- **`minSdk >= 21`**（Matter 原生库要求，Flutter 默认的 `flutter.minSdkVersion` 通常已满足）
- **Java 17**（`sourceCompatibility` / `targetCompatibility` = `JavaVersion.VERSION_17`）

> 打包相关的资源合并冲突（多个 Matter jar 都含 `META-INF/*.kotlin_module`）已在**插件内部**的 `build.gradle.kts` 用 `packaging.resources.excludes` 处理，主 App 无需额外配置。

### 4. 运行时权限

BLE 配网前需动态申请蓝牙 / 定位权限。插件已内置工具类，直接调用即可：

```dart
final granted = await MatterPermissions.requestForCommissioning();
if (!granted) {
  // 提示用户去系统设置授予权限
}
```

---

## 三、使用方法

### 3.1 初始化

```dart
import 'package:matter_plugins/matter_plugins.dart';

// 真实设备用 PlatformMatterBackend（走原生 Matter 库）
final matter = MatterControl(backend: PlatformMatterBackend());

// 无设备联调 UI 时可用假后端，返回模拟数据
// final matter = MatterControl(backend: FakeMatterBackend());
```

记得在页面/应用销毁时释放：

```dart
@override
void dispose() {
  matter.dispose();
  super.dispose();
}
```

### 3.2 自检（验证原生库）

```dart
final result = await matter.selfTest();
if (result['ok'] == true) {
  print('原生库加载成功: ${result['version']}');
} else {
  print('加载失败: ${result['error']}');
}
```

### 3.3 配网

**方式一：扫码 / 输入 11 位码（BLE 配网）**

扫码 UI 由你自己实现（例如用 `mobile_scanner` 拿到二维码字符串），拿到 `payload` 后：

```dart
final granted = await MatterPermissions.requestForCommissioning();
if (!granted) return;

final device = await matter.commissionDevice(
  setupPayload: payload,       // 二维码内容或 11 位配对码
  wifiSsid: 'your-wifi',       // 下发给设备的 WiFi
  wifiPassword: 'your-pass',
);
print('已添加: ${device.name}');
```

**方式二：IP 直连（连接电脑虚拟灯测试）**

```dart
final device = await matter.commissionOnNetwork(
  ipAddress: '192.168.1.20',   // 设备局域网 IP
  port: 5540,                  // 虚拟灯默认端口
  setupPinCode: 20202021,      // 虚拟灯默认 PIN
  discriminator: 3840,         // 虚拟灯默认识别码
);
```

### 3.4 控制设备

```dart
await matter.setOnOff(device.id, true);      // 开
await matter.setBrightness(device.id, 60);   // 调光到 60%
await matter.removeDevice(device.id);        // 解绑
```

### 3.5 展示设备列表（自己写 UI）

用 `devices` 流驱动界面，状态变化会自动刷新：

```dart
StreamBuilder<List<MatterDevice>>(
  stream: matter.devices,
  initialData: matter.currentDevices,
  builder: (context, snapshot) {
    final devices = snapshot.data ?? const [];
    return ListView(
      children: [
        for (final d in devices)
          ListTile(
            title: Text(d.name),
            subtitle: Text(d.online ? d.type.label : '离线'),
            trailing: d.type.supportsOnOff
                ? Switch(
                    value: d.state.on,
                    onChanged: d.online
                        ? (v) => matter.setOnOff(d.id, v)
                        : null,
                  )
                : null,
          ),
      ],
    );
  },
)
```

> 完整可运行示例见同仓库的 `matter` App（`matter/lib/main.dart`）。

---

## 四、错误处理

配网/控制失败会抛出 `MatterException`（含 `code` 和 `message`）：

```dart
try {
  await matter.commissionOnNetwork(...);
} on MatterException catch (e) {
  print('配网失败[${e.code}]: ${e.message}');
} catch (e) {
  print('未知错误: $e');
}
```

---

## 五、注意事项

- **仅支持 Android**，且当前仅打包了 `arm64-v8a` 原生库（真机需为 arm64 设备）。
- 插件不含任何 UI 与扫码库；如需扫码，请在主 App 自行引入 `mobile_scanner` 等。
- 私有插件，`publish_to: none`，不发布到 pub.dev。
