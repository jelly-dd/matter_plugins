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
                Log.i(TAG, "onConnectionStateChange status=$status newState=$newState")
                wrapped.onConnectionStateChange(gatt, status, newState)
                if (newState == BluetoothProfile.STATE_CONNECTED &&
                    status == BluetoothGatt.GATT_SUCCESS
                ) {
                    Log.i(TAG, "已连接，开始发现服务")
                    gatt?.discoverServices()
                } else if (newState == BluetoothProfile.STATE_DISCONNECTED) {
                    finishOnce(null)
                }
            }

            override fun onServicesDiscovered(gatt: BluetoothGatt?, status: Int) {
                Log.d(TAG, "onServicesDiscovered status=$status")
                wrapped.onServicesDiscovered(gatt, status)
                gatt?.requestMtu(247)
            }

            override fun onMtuChanged(gatt: BluetoothGatt?, mtu: Int, status: Int) {
                super.onMtuChanged(gatt, mtu, status)
                Log.d(TAG, "onMtuChanged mtu=$mtu status=$status")
                wrapped.onMtuChanged(gatt, mtu, status)
                finishOnce(gatt)
            }

            override fun onCharacteristicChanged(
                gatt: BluetoothGatt,
                characteristic: BluetoothGattCharacteristic
            ) {
                wrapped.onCharacteristicChanged(gatt, characteristic)
            }

            override fun onCharacteristicRead(
                gatt: BluetoothGatt,
                characteristic: BluetoothGattCharacteristic,
                status: Int
            ) {
                wrapped.onCharacteristicRead(gatt, characteristic, status)
            }

            override fun onCharacteristicWrite(
                gatt: BluetoothGatt,
                characteristic: BluetoothGattCharacteristic,
                status: Int
            ) {
                wrapped.onCharacteristicWrite(gatt, characteristic, status)
            }

            override fun onDescriptorRead(
                gatt: BluetoothGatt,
                descriptor: BluetoothGattDescriptor,
                status: Int
            ) {
                wrapped.onDescriptorRead(gatt, descriptor, status)
            }

            override fun onDescriptorWrite(
                gatt: BluetoothGatt,
                descriptor: BluetoothGattDescriptor,
                status: Int
            ) {
                wrapped.onDescriptorWrite(gatt, descriptor, status)
            }

            override fun onReadRemoteRssi(gatt: BluetoothGatt, rssi: Int, status: Int) {
                wrapped.onReadRemoteRssi(gatt, rssi, status)
            }

            override fun onReliableWriteCompleted(gatt: BluetoothGatt, status: Int) {
                wrapped.onReliableWriteCompleted(gatt, status)
            }
        }

        Log.i(TAG, "开始 GATT 连接")
        bleGatt = device.connectGatt(context, false, gattCallback)
        connectionId = chipPlatform.bleManager.addConnection(bleGatt)
        chipPlatform.bleManager.setBleCallback(this)
    }

    override fun onCloseBleComplete(connId: Int) {
        connectionId = 0
        Log.d(TAG, "onCloseBleComplete")
    }

    override fun onNotifyChipConnectionClosed(connId: Int) {
        bleGatt?.close()
        connectionId = 0
        Log.d(TAG, "onNotifyChipConnectionClosed")
    }

    companion object {
        private const val TAG = "MatterBluetoothManager"
        private const val CHIP_UUID = "0000FFF6-0000-1000-8000-00805F9B34FB"
    }
}
