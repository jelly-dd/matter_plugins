package com.example.matter_control

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.annotation.NonNull
import chip.devicecontroller.ChipClusters
import chip.devicecontroller.ChipDeviceController
import chip.devicecontroller.ControllerParams
import chip.devicecontroller.GetConnectedDeviceCallbackJni
import chip.devicecontroller.NetworkCredentials
import chip.devicecontroller.UnpairDeviceCallback
import chip.platform.AndroidBleManager
import chip.platform.AndroidChipPlatform
import chip.platform.ChipMdnsCallbackImpl
import chip.platform.DiagnosticDataProviderImpl
import chip.platform.NsdManagerServiceBrowser
import chip.platform.NsdManagerServiceResolver
import chip.platform.PreferencesConfigurationManager
import chip.platform.PreferencesKeyValueStoreManager
import matter.onboardingpayload.ManualOnboardingPayloadParser
import matter.onboardingpayload.QRCodeOnboardingPayloadParser
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

/**
 * Matter 控制模块的 Android 原生入口。
 *
 * 当前为「桩实现」：所有方法返回内存中的假数据，用于在接入真实
 * connectedhomeip（Matter C++ 协议栈）之前先跑通端到端流程。
 *
 * 接入真实库时，只需把下面各 handler 内的假逻辑替换为对
 * ChipDeviceController 的调用，Flutter 侧代码无需改动。
 */
class MatterControlPlugin : FlutterPlugin, MethodCallHandler {

    private lateinit var channel: MethodChannel
    private var appContext: Context? = null

    // 内存中的假设备表：key = deviceId
    private val devices = LinkedHashMap<String, HashMap<String, Any?>>()
    private var counter = 0

    // AndroidChipPlatform 只需初始化一次，持有引用避免被 GC 回收。
    private var chipPlatform: AndroidChipPlatform? = null

    // Matter 控制器，配网/控制/自检共用同一个实例，只创建一次。
    private var chipDeviceController: ChipDeviceController? = null

    private val mainHandler = Handler(Looper.getMainLooper())

    override fun onAttachedToEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        appContext = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, CHANNEL_NAME)
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    override fun onMethodCall(@NonNull call: MethodCall, @NonNull result: Result) {
        when (call.method) {
            "selfTest" -> selfTest(result)
            "commissionDevice" -> commissionDevice(call, result)
            "commissionOnNetwork" -> commissionOnNetwork(call, result)
            "getDevices" -> result.success(devices.values.toList())
            "setOnOff" -> setOnOff(call, result)
            "setBrightness" -> setBrightness(call, result)
            "removeDevice" -> removeDevice(call, result)
            else -> result.notImplemented()
        }
    }

    /**
     * 阶段 1 库加载自检：验证编译出的 libCHIPController.so / CHIPController.jar
     * 能在真机上正常加载并创建 ChipDeviceController，不做任何配网。
     * 返回 map: { ok: Boolean, version: String?, error: String? }
     */
    private fun selfTest(result: Result) {
        try {
            // 强制加载 JNI 原生库（libCHIPController.so + libc++_shared.so）
            ChipDeviceController.loadJni()
            // 初始化 AndroidChipPlatform：向 native 层注入 KeyValueStore、
            // ConfigurationManager、mDNS 等后端。缺这一步会导致
            // KeyValueStoreManagerImpl.cpp error 0x03 (INCORRECT_STATE)。
            ensureChipPlatform()
            // 创建（或复用）controller，验证 native 层可用
            val controller = ensureController()
            Log.i(TAG, "selfTest: ChipDeviceController 就绪 -> $controller")
            result.success(
                hashMapOf<String, Any?>(
                    "ok" to true,
                    "version" to "connectedhomeip v1.3.0.0 (arm64)",
                    "error" to null
                )
            )
        } catch (t: Throwable) {
            Log.e(TAG, "selfTest 失败：原生库加载/初始化异常", t)
            result.success(
                hashMapOf<String, Any?>(
                    "ok" to false,
                    "version" to null,
                    "error" to (t.message ?: t.toString())
                )
            )
        }
    }

    /**
     * 初始化 Matter 平台层（只做一次）。
     *
     * AndroidChipPlatform 构造时会把 KeyValueStore / ConfigurationManager /
     * mDNS 等 Java 后端注入 native，并调用 initChipStack()。这是 native 层
     * 读写持久化存储的前提，缺失会报 KeyValueStoreManagerImpl error 0x03。
     */
    private fun ensureChipPlatform() {
        if (chipPlatform != null) return
        val context = appContext
            ?: throw IllegalStateException("appContext 为空，插件未正确 attach")
        val nsdResolver = NsdManagerServiceResolver(context)
        chipPlatform = AndroidChipPlatform(
            AndroidBleManager(context),
            PreferencesKeyValueStoreManager(context),
            PreferencesConfigurationManager(context),
            nsdResolver,
            NsdManagerServiceBrowser(context),
            ChipMdnsCallbackImpl(),
            DiagnosticDataProviderImpl(context)
        )
        Log.i(TAG, "ensureChipPlatform: AndroidChipPlatform 初始化完成")
    }

    /**
     * 创建（或复用）Matter 控制器。
     *
     * 做法与官方 connectedhomeip Android 示例（CHIPTool）一致：
     * - 不向 ControllerParams 传任何证书 → native 内置测试 CA 会自动生成
     *   本 Fabric 的 root/NOC 证书。（正式上架时改为传入生产证书即可，
     *   配网/控制主流程无需改动。）
     * - setEnableServerInteractions(true)：允许作为 commissioner 与设备交互。
     * - setAttestationTrustStoreDelegate：注入 PAA 根证书用于校验设备真伪。
     */
    private fun ensureController(): ChipDeviceController {
        chipDeviceController?.let { return it }
        // 确保平台层已初始化。
        ensureChipPlatform()
        val controller = ChipDeviceController(
            ControllerParams.newBuilder()
                .setControllerVendorId(TEST_VENDOR_ID)
                .setEnableServerInteractions(true)
                .build()
        )
        controller.setAttestationTrustStoreDelegate(
            ExampleAttestationTrustStoreDelegate(controller)
        )
        chipDeviceController = controller
        Log.i(TAG, "ensureController: ChipDeviceController 创建完成")
        return controller
    }

    private fun commissionDevice(call: MethodCall, result: Result) {
        val payload = call.argument<String>("setupPayload")
        if (payload.isNullOrBlank()) {
            result.error("invalid_payload", "配对码为空", null)
            return
        }
        val wifiSsid = call.argument<String>("wifiSsid")
        val wifiPassword = call.argument<String>("wifiPassword")

        // Result 只能回调一次，且需在主线程；用包装保证安全。
        val safeResult = SafeResult(result, mainHandler)

        try {
            val context = appContext
                ?: throw IllegalStateException("appContext 为空")
            val controller = ensureController()
            val platform = chipPlatform
                ?: throw IllegalStateException("chipPlatform 未初始化")

            // 1) 解析配对码，拿到 discriminator + setupPinCode。
            val payloadInfo = parsePayload(payload.trim())
            Log.i(
                TAG,
                "配网开始 discriminator=${payloadInfo.discriminator} " +
                    "short=${payloadInfo.isShortDiscriminator}"
            )

            // 2) 组装 WiFi 网络凭据（若提供）。
            val network: NetworkCredentials? =
                if (!wifiSsid.isNullOrBlank()) {
                    NetworkCredentials.forWiFi(
                        NetworkCredentials.WiFiCredentials(wifiSsid, wifiPassword ?: "")
                    )
                } else {
                    null
                }

            val deviceId = nextDeviceId()
            val bleManager = MatterBluetoothManager(platform)

            // 3) 设置配网结果监听。
            controller.setCompletionListener(object : BaseCompletionListener() {
                override fun onCommissioningComplete(nodeId: Long, errorCode: Int) {
                    if (errorCode == 0) {
                        Log.i(TAG, "配网成功 nodeId=$nodeId")
                        // pairDevice 传入的 deviceId 即设备被分配的 nodeId，
                        // 后续控制命令用它取回设备指针。
                        val device = buildDevice(deviceId, nodeId)
                        safeResult.success(device)
                    } else {
                        Log.e(TAG, "配网失败 errorCode=$errorCode")
                        safeResult.error(
                            "commissioning_failed",
                            "配网失败，错误码=$errorCode",
                            null
                        )
                    }
                }

                override fun onError(error: Throwable) {
                    Log.e(TAG, "配网过程出错", error)
                    safeResult.error("commissioning_error", error.message ?: "配网异常", null)
                }
            })

            // 4) 扫描 -> 连接 -> pairDevice。
            bleManager.scanForDevice(
                payloadInfo.discriminator,
                payloadInfo.isShortDiscriminator,
                BLE_SCAN_TIMEOUT_MS
            ) { device ->
                if (device == null) {
                    safeResult.error("device_not_found", "未扫描到目标 Matter 设备（BLE）", null)
                    return@scanForDevice
                }
                bleManager.connect(context, device) { gatt ->
                    if (gatt == null) {
                        safeResult.error("ble_connect_failed", "BLE 连接失败", null)
                        return@connect
                    }
                    try {
                        Log.i(TAG, "GATT 就绪，调用 pairDevice deviceId=$deviceId")
                        controller.pairDevice(
                            gatt,
                            bleManager.connectionId,
                            deviceId,
                            payloadInfo.setupPinCode,
                            network
                        )
                    } catch (t: Throwable) {
                        Log.e(TAG, "pairDevice 调用异常", t)
                        safeResult.error("pair_device_error", t.message ?: "pairDevice 异常", null)
                    }
                }
            }
        } catch (t: Throwable) {
            Log.e(TAG, "commissionDevice 初始化异常", t)
            safeResult.error("commission_init_error", t.message ?: "配网初始化失败", null)
        }
    }

    /**
     * On-Network(IP 直连) 配网：直接用已知 IP + 端口 + 配对参数建立 PASE
     * 通道并入网，不走 BLE、不下发 WiFi 凭据。用于连接电脑上运行的虚拟灯
     * (chip-lighting-app)，等价于 chip-tool 的 `pairing already-discovered`。
     */
    private fun commissionOnNetwork(call: MethodCall, result: Result) {
        val ipAddress = call.argument<String>("ipAddress")
        if (ipAddress.isNullOrBlank()) {
            result.error("invalid_address", "IP 地址为空", null)
            return
        }
        val port = call.argument<Int>("port") ?: 5540
        // Flutter int 过通道可能是 Int 或 Long，做兼容取值。
        val setupPinCode =
            (call.argument<Number>("setupPinCode")?.toLong()) ?: 20202021L
        val discriminator = call.argument<Int>("discriminator") ?: 3840

        val safeResult = SafeResult(result, mainHandler)
        try {
            val controller = ensureController()
            val deviceId = nextDeviceId()

            controller.setCompletionListener(object : BaseCompletionListener() {
                override fun onCommissioningComplete(nodeId: Long, errorCode: Int) {
                    if (errorCode == 0) {
                        Log.i(TAG, "On-Network 配网成功 nodeId=$nodeId")
                        safeResult.success(buildDevice(deviceId, nodeId))
                    } else {
                        Log.e(TAG, "On-Network 配网失败 errorCode=$errorCode")
                        safeResult.error(
                            "commissioning_failed",
                            "配网失败，错误码=$errorCode",
                            null
                        )
                    }
                }

                override fun onError(error: Throwable) {
                    Log.e(TAG, "On-Network 配网出错", error)
                    safeResult.error(
                        "commissioning_error",
                        error.message ?: "配网异常",
                        null
                    )
                }
            })

            Log.i(
                TAG,
                "On-Network 配网开始 ip=$ipAddress port=$port " +
                    "discriminator=$discriminator deviceId=$deviceId"
            )
            // 配网无响应时（如 IP 不可达、设备不在配网模式）native 层不会回调，
            // 这里加超时兜底，避免 Flutter 侧无限等待。
            safeResult.scheduleTimeout(
                COMMISSION_TIMEOUT_MS,
                "commissioning_timeout",
                "配网超时：$COMMISSION_TIMEOUT_MS ms 内未完成，请检查设备 IP、" +
                    "端口是否正确，以及设备是否处于可配网状态。"
            )
            // pairDeviceWithAddress(nodeId, address, port, discriminator,
            //   pinCode, csrNonce=null)
            controller.pairDeviceWithAddress(
                deviceId,
                ipAddress,
                port,
                discriminator,
                setupPinCode,
                null
            )
        } catch (t: Throwable) {
            Log.e(TAG, "commissionOnNetwork 初始化异常", t)
            safeResult.error(
                "commission_init_error",
                t.message ?: "配网初始化失败",
                null
            )
        }
    }

    /** 解析二维码（MT: 开头）或手动配对码，返回配网所需信息。 */
    private fun parsePayload(payload: String): PayloadInfo {
        val onboarding = if (payload.startsWith("MT:")) {
            QRCodeOnboardingPayloadParser(payload).populatePayload()
        } else {
            ManualOnboardingPayloadParser(payload).populatePayload()
        }
        return PayloadInfo(
            discriminator = onboarding.discriminator,
            isShortDiscriminator = onboarding.hasShortDiscriminator,
            setupPinCode = onboarding.setupPinCode
        )
    }

    private fun buildDevice(deviceId: Long, nodeId: Long): HashMap<String, Any?> {
        val id = "android-node-$deviceId"
        val device = hashMapOf<String, Any?>(
            "id" to id,
            "name" to "Matter 设备 $deviceId",
            "type" to "dimmable_light",
            "online" to true,
            // 记录 Matter nodeId，控制命令据此取回设备指针（不回传给 Flutter）。
            "_nodeId" to nodeId,
            "state" to hashMapOf<String, Any?>(
                "on" to false,
                "brightness" to 80
            )
        )
        devices[id] = device
        return device
    }

    private fun nextDeviceId(): Long {
        counter += 1
        return counter.toLong()
    }

    private fun setOnOff(call: MethodCall, result: Result) {
        val id = call.argument<String>("deviceId")
        val on = call.argument<Boolean>("on") ?: false
        val device = devices[id]
        if (device == null) {
            result.error("device_not_found", "找不到设备: $id", null)
            return
        }
        val nodeId = (device["_nodeId"] as? Long)
        if (nodeId == null) {
            result.error("no_node_id", "设备缺少 nodeId，无法控制", null)
            return
        }
        val safeResult = SafeResult(result, mainHandler)

        withConnectedDevice(nodeId, safeResult) { devicePtr ->
            val cluster = ChipClusters.OnOffCluster(devicePtr, DEFAULT_ENDPOINT)
            val cb = object : ChipClusters.DefaultClusterCallback {
                override fun onSuccess() {
                    @Suppress("UNCHECKED_CAST")
                    val state = device["state"] as HashMap<String, Any?>
                    state["on"] = on
                    safeResult.success(device)
                }

                override fun onError(error: Exception) {
                    Log.e(TAG, "setOnOff 失败", error)
                    safeResult.error("onoff_failed", error.message ?: "OnOff 命令失败", null)
                }
            }
            if (on) cluster.on(cb) else cluster.off(cb)
        }
    }

    private fun setBrightness(call: MethodCall, result: Result) {
        val id = call.argument<String>("deviceId")
        val brightness = (call.argument<Int>("brightness") ?: 0).coerceIn(0, 100)
        val device = devices[id]
        if (device == null) {
            result.error("device_not_found", "找不到设备: $id", null)
            return
        }
        val nodeId = (device["_nodeId"] as? Long)
        if (nodeId == null) {
            result.error("no_node_id", "设备缺少 nodeId，无法控制", null)
            return
        }
        val safeResult = SafeResult(result, mainHandler)
        // Matter LevelControl 的 level 范围是 0..254，这里从 0..100 百分比换算。
        val level = (brightness * 254 / 100).coerceIn(0, 254)

        withConnectedDevice(nodeId, safeResult) { devicePtr ->
            val cluster = ChipClusters.LevelControlCluster(devicePtr, DEFAULT_ENDPOINT)
            val cb = object : ChipClusters.DefaultClusterCallback {
                override fun onSuccess() {
                    @Suppress("UNCHECKED_CAST")
                    val state = device["state"] as HashMap<String, Any?>
                    state["brightness"] = brightness
                    state["on"] = brightness > 0
                    safeResult.success(device)
                }

                override fun onError(error: Exception) {
                    Log.e(TAG, "setBrightness 失败", error)
                    safeResult.error("level_failed", error.message ?: "LevelControl 命令失败", null)
                }
            }
            // moveToLevel(callback, level, transitionTime, optionsMask, optionsOverride)
            cluster.moveToLevel(cb, level, 0, 0, 0)
        }
    }

    private fun removeDevice(call: MethodCall, result: Result) {
        val id = call.argument<String>("deviceId")
        val device = devices[id]
        if (device == null) {
            // 本地没有记录，直接当作已删除。
            result.success(null)
            return
        }
        val nodeId = (device["_nodeId"] as? Long)
        val safeResult = SafeResult(result, mainHandler)

        if (nodeId == null) {
            devices.remove(id)
            safeResult.success(null)
            return
        }

        try {
            val controller = ensureController()
            controller.unpairDeviceCallback(nodeId, object : UnpairDeviceCallback {
                override fun onSuccess(nodeId: Long) {
                    Log.i(TAG, "unpair 成功 nodeId=$nodeId")
                    devices.remove(id)
                    safeResult.success(null)
                }

                override fun onError(errorCode: Int, nodeId: Long) {
                    Log.e(TAG, "unpair 失败 errorCode=$errorCode")
                    // 即使 native 端失败，本地也移除，避免残留。
                    devices.remove(id)
                    safeResult.success(null)
                }
            })
        } catch (t: Throwable) {
            Log.e(TAG, "removeDevice 异常", t)
            devices.remove(id)
            safeResult.success(null)
        }
    }

    /**
     * 取回已配网设备的 native 指针，再执行控制命令。
     *
     * Matter 控制命令需要一个「已建立 CASE 会话的设备指针」，
     * getConnectedDevicePointer 会（必要时）自动建立会话后回调指针。
     */
    private fun withConnectedDevice(
        nodeId: Long,
        safeResult: SafeResult,
        action: (devicePtr: Long) -> Unit
    ) {
        try {
            val controller = ensureController()
            controller.getConnectedDevicePointer(
                nodeId,
                object : GetConnectedDeviceCallbackJni.GetConnectedDeviceCallback {
                    override fun onDeviceConnected(devicePointer: Long) {
                        try {
                            action(devicePointer)
                        } catch (t: Throwable) {
                            Log.e(TAG, "控制命令执行异常", t)
                            safeResult.error("command_error", t.message ?: "命令执行失败", null)
                        }
                    }

                    override fun onConnectionFailure(devicePointer: Long, error: Exception) {
                        Log.e(TAG, "连接设备失败 nodeId=$nodeId", error)
                        safeResult.error(
                            "device_unreachable",
                            "无法连接设备（可能离线）：${error.message}",
                            null
                        )
                    }
                }
            )
        } catch (t: Throwable) {
            Log.e(TAG, "withConnectedDevice 异常", t)
            safeResult.error("connect_error", t.message ?: "取回设备失败", null)
        }
    }

    companion object {
        private const val CHANNEL_NAME = "matter_control/methods"
        private const val TAG = "MatterControlPlugin"
        // 0xFFF4 为测试用 Vendor ID，正式量产需替换为分配到的公司 ID
        private const val TEST_VENDOR_ID = 0xFFF4
        // BLE 扫描超时（毫秒）
        private const val BLE_SCAN_TIMEOUT_MS = 15_000L
        // 配网整体超时（毫秒）：无响应时兜底，避免上层无限等待。
        private const val COMMISSION_TIMEOUT_MS = 60_000L
        // 灯泡类设备的应用功能通常挂在 endpoint 1（endpoint 0 是根节点）
        private const val DEFAULT_ENDPOINT = 1
    }
}

/** 从配对码解析出的配网关键信息。 */
private data class PayloadInfo(
    val discriminator: Int,
    val isShortDiscriminator: Boolean,
    val setupPinCode: Long
)

/**
 * 包装 Flutter [Result]，保证：
 * 1. 只回调一次（配网是异步多回调，避免重复 success/error 崩溃）。
 * 2. 始终在主线程回调（Flutter 要求）。
 */
private class SafeResult(
    private val result: Result,
    private val handler: Handler
) {
    private var done = false
    private var timeoutRunnable: Runnable? = null

    /**
     * 安排一个超时：若在 [timeoutMs] 内未收到 success/error，则自动以
     * [code]/[message] 回一次 error，避免上层无限等待（如配网无响应）。
     * 成功或失败先到达时会取消该超时。
     */
    fun scheduleTimeout(timeoutMs: Long, code: String, message: String) {
        val runnable = Runnable { error(code, message, null) }
        timeoutRunnable = runnable
        handler.postDelayed(runnable, timeoutMs)
    }

    private fun cancelTimeout() {
        timeoutRunnable?.let { handler.removeCallbacks(it) }
        timeoutRunnable = null
    }

    fun success(value: Any?) {
        if (done) return
        done = true
        cancelTimeout()
        handler.post { result.success(value) }
    }

    fun error(code: String, message: String?, details: Any?) {
        if (done) return
        done = true
        cancelTimeout()
        handler.post { result.error(code, message, details) }
    }
}

/**
 * [ChipDeviceController.CompletionListener] 的空实现基类，
 * 让调用方只需覆写关心的回调（onCommissioningComplete / onError）。
 */
private open class BaseCompletionListener :
    ChipDeviceController.CompletionListener {
    override fun onConnectDeviceComplete() {}
    override fun onStatusUpdate(status: Int) {}
    override fun onPairingComplete(errorCode: Int) {}
    override fun onPairingDeleted(errorCode: Int) {}
    override fun onCommissioningComplete(nodeId: Long, errorCode: Int) {}
    override fun onReadCommissioningInfo(
        vendorId: Int,
        productId: Int,
        wifiEndpointId: Int,
        threadEndpointId: Int
    ) {}
    override fun onCommissioningStatusUpdate(nodeId: Long, stage: String?, errorCode: Int) {}
    override fun onNotifyChipConnectionClosed() {}
    override fun onCloseBleComplete() {}
    override fun onError(error: Throwable) {}
    override fun onOpCSRGenerationComplete(csr: ByteArray?) {}
    override fun onICDRegistrationInfoRequired() {}
    override fun onICDRegistrationComplete(
        errorCode: Int,
        icdDeviceInfo: chip.devicecontroller.ICDDeviceInfo?
    ) {}
}
