import 'package:flutter/material.dart';

import '../matter_control_base.dart';
import '../models/matter_device.dart';

/// 设备控制页：根据设备类型显示对应的控制项（开关、亮度等）。
class DeviceControlPage extends StatelessWidget {
  const DeviceControlPage({
    super.key,
    required this.controller,
    required this.deviceId,
  });

  final MatterControl controller;
  final String deviceId;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<MatterDevice>>(
      stream: controller.devices,
      initialData: controller.currentDevices,
      builder: (context, snapshot) {
        final devices = snapshot.data ?? const [];
        final device = devices.where((d) => d.id == deviceId).firstOrNull;

        if (device == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const Center(child: Text('设备已被移除')),
          );
        }

        return Scaffold(
          appBar: AppBar(
            title: Text(device.name),
            actions: [
              IconButton(
                tooltip: '解绑设备',
                icon: const Icon(Icons.delete_outline),
                onPressed: () => _confirmRemove(context),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _StatusHeader(device: device),
              const SizedBox(height: 24),
              if (device.type.supportsOnOff)
                _OnOffControl(
                  value: device.state.on,
                  enabled: device.online,
                  onChanged: (v) => controller.setOnOff(device.id, v),
                ),
              if (device.type.supportsBrightness) ...[
                const SizedBox(height: 16),
                _BrightnessControl(
                  value: device.state.brightness,
                  enabled: device.online && device.state.on,
                  onChanged: (v) => controller.setBrightness(device.id, v),
                ),
              ],
              if (!device.type.supportsOnOff)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('该设备类型暂无可用的控制项（如传感器为只读）。'),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _confirmRemove(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('解绑设备'),
        content: const Text('确定要从 App 中移除该设备吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('解绑'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await controller.removeDevice(deviceId);
      if (context.mounted) Navigator.of(context).pop();
    }
  }
}

class _StatusHeader extends StatelessWidget {
  const _StatusHeader({required this.device});

  final MatterDevice device;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: device.state.on
                  ? scheme.primaryContainer
                  : scheme.surfaceContainerHighest,
              child: Icon(
                device.state.on
                    ? Icons.lightbulb
                    : Icons.lightbulb_outline,
                color: device.state.on ? scheme.primary : scheme.outline,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(device.type.label,
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    'ID: ${device.id}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  Text(
                    device.online ? '在线' : '离线',
                    style: TextStyle(
                      color: device.online ? Colors.green : scheme.error,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OnOffControl extends StatelessWidget {
  const _OnOffControl({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: SwitchListTile(
        title: const Text('电源'),
        subtitle: Text(value ? '已开启' : '已关闭'),
        value: value,
        onChanged: enabled ? onChanged : null,
        secondary: const Icon(Icons.power_settings_new),
      ),
    );
  }
}

class _BrightnessControl extends StatefulWidget {
  const _BrightnessControl({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final int value;
  final bool enabled;
  final ValueChanged<int> onChanged;

  @override
  State<_BrightnessControl> createState() => _BrightnessControlState();
}

class _BrightnessControlState extends State<_BrightnessControl> {
  late double _local = widget.value.toDouble();

  @override
  void didUpdateWidget(covariant _BrightnessControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _local = widget.value.toDouble();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.brightness_6_outlined),
                const SizedBox(width: 12),
                const Text('亮度'),
                const Spacer(),
                Text('${_local.round()}%'),
              ],
            ),
            Slider(
              value: _local,
              min: 0,
              max: 100,
              divisions: 100,
              label: '${_local.round()}%',
              onChanged: widget.enabled
                  ? (v) => setState(() => _local = v)
                  : null,
              onChangeEnd:
                  widget.enabled ? (v) => widget.onChanged(v.round()) : null,
            ),
          ],
        ),
      ),
    );
  }
}
