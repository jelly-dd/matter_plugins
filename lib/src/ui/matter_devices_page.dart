import 'package:flutter/material.dart';

import '../matter_control_base.dart';
import '../models/matter_device.dart';
import 'add_device_page.dart';
import 'device_control_page.dart';

/// 设备列表页：展示所有已绑定的 Matter 设备，支持进入控制页、添加新设备。
///
/// 这是模块 UI 的入口页。正式 App 可直接把它作为某个 Tab 页嵌入。
class MatterDevicesPage extends StatefulWidget {
  const MatterDevicesPage({super.key, required this.controller});

  /// 共享的控制器实例。
  final MatterControl controller;

  @override
  State<MatterDevicesPage> createState() => _MatterDevicesPageState();
}

class _MatterDevicesPageState extends State<MatterDevicesPage> {
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    await widget.controller.refresh();
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _openAddDevice() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AddDevicePage(controller: widget.controller),
      ),
    );
    if (mounted) _load();
  }

  Future<void> _openControl(MatterDevice device) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DeviceControlPage(
          controller: widget.controller,
          deviceId: device.id,
        ),
      ),
    );
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('我的 Matter 设备'),
        actions: [
          IconButton(
            onPressed: _load,
            icon: const Icon(Icons.refresh),
            tooltip: '刷新',
          ),
        ],
      ),
      body: StreamBuilder<List<MatterDevice>>(
        stream: widget.controller.devices,
        initialData: widget.controller.currentDevices,
        builder: (context, snapshot) {
          if (_loading && (snapshot.data?.isEmpty ?? true)) {
            return const Center(child: CircularProgressIndicator());
          }
          final devices = snapshot.data ?? const [];
          if (devices.isEmpty) {
            return _EmptyState(onAdd: _openAddDevice);
          }
          return RefreshIndicator(
            onRefresh: _load,
            child: ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: devices.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final d = devices[index];
                return _DeviceTile(
                  device: d,
                  onTap: () => _openControl(d),
                  onToggle: d.type.supportsOnOff
                      ? (v) => widget.controller.setOnOff(d.id, v)
                      : null,
                );
              },
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openAddDevice,
        icon: const Icon(Icons.add),
        label: const Text('添加设备'),
      ),
    );
  }
}

class _DeviceTile extends StatelessWidget {
  const _DeviceTile({required this.device, required this.onTap, this.onToggle});

  final MatterDevice device;
  final VoidCallback onTap;
  final ValueChanged<bool>? onToggle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          backgroundColor: device.state.on
              ? scheme.primaryContainer
              : scheme.surfaceContainerHighest,
          child: Icon(
            _iconFor(device.type),
            color: device.state.on ? scheme.primary : scheme.outline,
          ),
        ),
        title: Text(device.name),
        subtitle: Text(
          device.online ? device.type.label : '${device.type.label} · 离线',
          style: TextStyle(color: device.online ? null : scheme.error),
        ),
        trailing: onToggle == null
            ? const Icon(Icons.chevron_right)
            : Switch(
                value: device.state.on,
                onChanged: device.online ? onToggle : null,
              ),
      ),
    );
  }

  IconData _iconFor(MatterDeviceType type) {
    switch (type) {
      case MatterDeviceType.onOffLight:
      case MatterDeviceType.dimmableLight:
        return Icons.lightbulb_outline;
      case MatterDeviceType.onOffPlug:
        return Icons.power_outlined;
      case MatterDeviceType.contactSensor:
        return Icons.sensor_door_outlined;
      case MatterDeviceType.temperatureSensor:
        return Icons.thermostat_outlined;
      case MatterDeviceType.unknown:
        return Icons.devices_other_outlined;
    }
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.home_outlined,
            size: 72,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 16),
          const Text('还没有绑定任何设备'),
          const SizedBox(height: 8),
          const Text(
            '点击下方按钮，扫码添加你的第一个 Matter 设备',
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.qr_code_scanner),
            label: const Text('扫码添加设备'),
          ),
        ],
      ),
    );
  }
}
