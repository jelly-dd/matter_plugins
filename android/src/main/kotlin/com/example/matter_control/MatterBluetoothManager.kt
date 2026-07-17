package com.example.matter_control

import android.annotation.SuppressLint
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCallback
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattDescriptor
import android.bluetooth.BluetoothProfile
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanFilter
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.os.ParcelUuid
import android.util.Log
import chip.platform.AndroidChipPlatform
import chip.platform.BleCallback
import java.util.UUID

/**
 * Matter BLE 扫描 + 连接管理器（无协程版）。
 *
 * 逻辑照搬官方 connectedhomeip Android 示例（CHIPTool）的 BluetoothManager，
 * 但改为普通回调，避免引入 kotlinx-coroutines。
 *
 * 职责：
 * 1. 按 discriminator 扫描 Matter 设备的 BLE 广播。
 * 2. 连接 GATT，把这条 GATT 通道注册进 native 的 AndroidBleManager，
 *    并拿到 connectionId 供 pairDevice 使用。
 */
@SuppressLint("MissingPermission")
class MatterBluetoothManager(
    private val chipPlatform: AndroidChipPlatform
) : BleCallback {

    private val bluetoothAdapter = BluetoothAdapter.getDefaultAdapter()
    private val mainHandler = Handler(Looper.getMainLooper())

    private var bleGatt: BluetoothGatt? = null
    var connectionId = 0
        private set

    /** Matter 设备 BLE 广播里携带的 service data，用 discriminator 匹配。 */
    private fun getServiceData(discriminator: Int): ByteArray {
        val opcode = 0
        val version = 0
        val versionDiscriminator = ((version and 0xf) shl 12) or (discriminator and 0xfff)
        return intArrayOf(opcode, versionDiscriminator, versionDiscriminator shr 8)
            .map { it.toByte() }
            .toByteArray()
    }

    private fun getServiceDataMask(isShortDiscriminator: Boolean): ByteArray {
        val shortDiscriminatorMask = if (isShortDiscriminator) 0x00 else 0xff
        return intArrayOf(0xff, shortDiscriminatorMask, 0xff).map { it.toByte() }.toByteArray()
    }

    /**
     * 按 discriminator 扫描设备，超时或找到时回调。
     * 找到返回设备；超时返回 null。
     */
    fun scanForDevice(
        discriminator: Int,
        isShortDiscriminator: Boolean,
        timeoutMs: Long,
        onResult: (BluetoothDevice?) -> Unit
    ) {
        val scanner = bluetoothAdapter?.bluetoothLeScanner
        if (scanner == null) {
            Log.e(TAG, "No bluetooth scanner found")
            onResult(null)
            return
        }

        var finished = false
        lateinit var scanCallback: ScanCallback

        val timeoutRunnable = Runnable {
            if (!finished) {
                finished = true
                scanner.stopScan(scanCallback)
                Log.w(TAG, "BLE 扫描超时，未找到设备")
                onResult(null)
            }
        }

        scanCallback = object : ScanCallback() {
            override fun onScanResult(callbackType: Int, result: ScanResult) {
                if (finished) return
                val device = result.device
                Log.i(TAG, "扫描到设备 Addr=${device.address}, Name=${device.name}")
                finished = true
                mainHandler.removeCallbacks(timeoutRunnable)
                scanner.stopScan(this)
                onResult(device)
            }

            override fun onScanFailed(errorCode: Int) {
                if (finished) return
                finished = true
                mainHandler.removeCallbacks(timeoutRunnable)
                Log.e(TAG, "BLE 扫描失败 errorCode=$errorCode")
                onResult(null)
            }
        }

        val scanFilter = ScanFilter.Builder()
            .setServiceData(
                ParcelUuid(UUID.fromString(CHIP_UUID)),
                getServiceData(discriminator),
                getServiceDataMask(isShortDiscriminator)
            )
            .build()
        val scanSettings = ScanSettings.Builder()
            .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY)
            .build()

        Log.i(TAG, "开始 BLE 扫描 discriminator=$discriminator")
        scanner.startScan(listOf(scanFilter), scanSettings, scanCallback)
        mainHandler.postDelayed(timeoutRunnable, timeoutMs)
    }

    /**
     * 连接设备的 GATT，服务发现 + MTU 协商完成后回调 gatt。
     * 失败回调 null。连接成功后 [connectionId] 可用。
     */
    fun connect(
        context: Context,
        device: BluetoothDevice,
        onConnected: (BluetoothGatt?) -> Unit
    ) {
        var resolved = false
        fun finishOnce(gatt: BluetoothGatt?) {
            if (resolved) return
            resolved = true
            onConnected(gatt)
        }

        val gattCallback = object : BluetoothGattCallback() {
            private val wrapped = chipPlatform.bleManager.callback

            override fun onConnectionStateChange(gatt: BluetoothGatt?, status: Int, newState: Int) {
                super.onConnectionStateChange(gatt, status, newState)
                Log.i(FLOW, "[GATT] onConnectionStateChange status=$status newState=$newState")
                wrapped.onConnectionStateChange(gatt, status, newState)
                if (newState == BluetoothProfile.STATE_CONNECTED &&
                    status == BluetoothGatt.GATT_SUCCESS
                ) {
                    Log.i(FLOW, "[GATT] 已连接，开始发现服务 discoverServices()")
                    gatt?.discoverServices()
                } else if (newState == BluetoothProfile.STATE_DISCONNECTED) {
                    Log.w(FLOW, "[GATT] 连接断开 status=$status（配网中途断开通常意味着上一步失败）")
                    // 断开时必须释放 GATT client，否则句柄泄漏，
                    // 下次连同一设备会报 "BLE already in use" 并被 status=8 踢掉。
                    cleanup()
                    finishOnce(null)
                }
            }

            override fun onServicesDiscovered(gatt: BluetoothGatt?, status: Int) {
                Log.i(FLOW, "[GATT] onServicesDiscovered status=$status ${gattStatus(status)}")
                wrapped.onServicesDiscovered(gatt, status)
                Log.i(FLOW, "[GATT] 发起 requestMtu(247)")
                gatt?.requestMtu(247)
            }

            override fun onMtuChanged(gatt: BluetoothGatt?, mtu: Int, status: Int) {
                super.onMtuChanged(gatt, mtu, status)
                Log.i(FLOW, "[GATT] onMtuChanged mtu=$mtu status=$status ${gattStatus(status)} -> 判定 GATT 就绪")
                wrapped.onMtuChanged(gatt, mtu, status)
                finishOnce(gatt)
            }

            override fun onCharacteristicChanged(
                gatt: BluetoothGatt,
                characteristic: BluetoothGattCharacteristic
            ) {
                Log.d(FLOW, "[GATT] onCharacteristicChanged uuid=${characteristic.uuid}")
                wrapped.onCharacteristicChanged(gatt, characteristic)
            }

            override fun onCharacteristicRead(
                gatt: BluetoothGatt,
                characteristic: BluetoothGattCharacteristic,
                status: Int
            ) {
                Log.d(FLOW, "[GATT] onCharacteristicRead uuid=${characteristic.uuid} status=$status ${gattStatus(status)}")
                wrapped.onCharacteristicRead(gatt, characteristic, status)
            }

            override fun onCharacteristicWrite(
                gatt: BluetoothGatt,
                characteristic: BluetoothGattCharacteristic,
                status: Int
            ) {
                Log.i(FLOW, "[GATT] onCharacteristicWrite uuid=${characteristic.uuid} status=$status ${gattStatus(status)}")
                wrapped.onCharacteristicWrite(gatt, characteristic, status)
            }

            override fun onDescriptorRead(
                gatt: BluetoothGatt,
                descriptor: BluetoothGattDescriptor,
                status: Int
            ) {
                Log.d(FLOW, "[GATT] onDescriptorRead uuid=${descriptor.uuid} status=$status ${gattStatus(status)}")
                wrapped.onDescriptorRead(gatt, descriptor, status)
            }

            override fun onDescriptorWrite(
                gatt: BluetoothGatt,
                descriptor: BluetoothGattDescriptor,
                status: Int
            ) {
                // 这一步是 BTP 订阅 CHIP 特征通知（写 CCCD）。status!=0 即订阅失败，
                // 是 0xAC Internal error 的高度可疑点。
                Log.i(
                    FLOW,
                    "[GATT] onDescriptorWrite descUuid=${descriptor.uuid} " +
                        "charUuid=${descriptor.characteristic?.uuid} " +
                        "status=$status ${gattStatus(status)}"
                )
                wrapped.onDescriptorWrite(gatt, descriptor, status)
            }

            override fun onReadRemoteRssi(gatt: BluetoothGatt, rssi: Int, status: Int) {
                wrapped.onReadRemoteRssi(gatt, rssi, status)
            }

            override fun onReliableWriteCompleted(gatt: BluetoothGatt, status: Int) {
                wrapped.onReliableWriteCompleted(gatt, status)
            }
        }

        Log.i(FLOW, "[GATT] 开始 GATT 连接 device=${device.address}")
        bleGatt = device.connectGatt(context, false, gattCallback)
        connectionId = chipPlatform.bleManager.addConnection(bleGatt)
        Log.i(FLOW, "[GATT] addConnection -> connectionId=$connectionId")
        chipPlatform.bleManager.setBleCallback(this)
    }

    override fun onCloseBleComplete(connId: Int) {
        connectionId = 0
        Log.d(TAG, "onCloseBleComplete")
    }

    override fun onNotifyChipConnectionClosed(connId: Int) {
        Log.d(FLOW, "[GATT] onNotifyChipConnectionClosed connId=$connId")
        cleanup()
    }

    /**
     * 释放本次配网持有的 BLE 资源。可重复调用（幂等）。
     *
     * 必须在所有终止路径调用：连接断开、配网失败、配网成功后。
     * 否则 [BluetoothGatt] client 句柄泄漏，累积到系统上限后再连同一设备
     * 会报 "BLE already in use"，MTU 就绪后立即被 status=8(GATT_CONN_TIMEOUT) 踢掉。
     */
    fun cleanup() {
        val gatt = bleGatt ?: run {
            if (connectionId != 0) {
                chipPlatform.bleManager.removeConnection(connectionId)
                connectionId = 0
            }
            return
        }
        Log.i(FLOW, "[GATT] cleanup: 关闭 GATT 并移除 connection=$connectionId")
        try {
            gatt.disconnect()
            gatt.close()
        } catch (t: Throwable) {
            Log.w(FLOW, "[GATT] cleanup 关闭异常: ${t.message}")
        }
        if (connectionId != 0) {
            chipPlatform.bleManager.removeConnection(connectionId)
        }
        bleGatt = null
        connectionId = 0
    }

    companion object {
        private const val TAG = "MatterBluetoothManager"
        /** 统一日志标头，logcat 用 `grep MATTER_FLOW` 即可只看配网关键流程。 */
        private const val FLOW = "MATTER_FLOW"
        private const val CHIP_UUID = "0000FFF6-0000-1000-8000-00805F9B34FB"

        /** 把 GATT status 数字翻译成可读提示。 */
        private fun gattStatus(status: Int): String =
            if (status == BluetoothGatt.GATT_SUCCESS) "(SUCCESS)" else "(FAILED code=$status)"
    }
}
