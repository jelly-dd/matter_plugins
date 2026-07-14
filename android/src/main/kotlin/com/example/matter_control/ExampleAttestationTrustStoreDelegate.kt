package com.example.matter_control

import android.util.Base64
import chip.devicecontroller.AttestationTrustStoreDelegate
import chip.devicecontroller.ChipDeviceController
import chip.devicecontroller.DeviceAttestation
import java.util.Arrays

/**
 * 设备认证信任库（PAA 根证书）委托。
 *
 * 直接采用官方 connectedhomeip Android 示例（CHIPTool）的实现：
 * 配网时设备会出示制造商的 DAC 证书，SDK 需要用对应的 PAA 根证书验证其真伪。
 * 这里内置的是 Matter「测试用 PAA」，可验证测试/开发类设备。
 *
 * 正式上架、需要验证正规厂商设备时，应替换/追加真实的 PAA 根证书列表
 * （或对接 DCL 分布式合规账本）。届时配网主流程无需改动。
 */
class ExampleAttestationTrustStoreDelegate(
    val chipDeviceController: ChipDeviceController
) : AttestationTrustStoreDelegate {

    private val paaCerts = arrayListOf(TEST_PAA_FFF1_Cert, TEST_PAA_NOVID_CERT)

    override fun getProductAttestationAuthorityCert(skid: ByteArray): ByteArray? {
        return paaCerts
            .map { Base64.decode(it, Base64.DEFAULT) }
            .firstOrNull { cert ->
                Arrays.equals(DeviceAttestation.extractSkidFromPaaCert(cert), skid)
            }
    }

    companion object {
        const val TEST_PAA_FFF1_Cert =
            "MIIBvTCCAWSgAwIBAgIITqjoMYLUHBwwCgYIKoZIzj0EAwIwMDEYMBYGA1UEAwwP\n" +
                "TWF0dGVyIFRlc3QgUEFBMRQwEgYKKwYBBAGConwCAQwERkZGMTAgFw0yMTA2Mjgx\n" +
                "NDIzNDNaGA85OTk5MTIzMTIzNTk1OVowMDEYMBYGA1UEAwwPTWF0dGVyIFRlc3Qg\n" +
                "UEFBMRQwEgYKKwYBBAGConwCAQwERkZGMTBZMBMGByqGSM49AgEGCCqGSM49AwEH\n" +
                "A0IABLbLY3KIfyko9brIGqnZOuJDHK2p154kL2UXfvnO2TKijs0Duq9qj8oYShpQ\n" +
                "NUKWDUU/MD8fGUIddR6Pjxqam3WjZjBkMBIGA1UdEwEB/wQIMAYBAf8CAQEwDgYD\n" +
                "VR0PAQH/BAQDAgEGMB0GA1UdDgQWBBRq/SJ3H1Ef7L8WQZdnENzcMaFxfjAfBgNV\n" +
                "HSMEGDAWgBRq/SJ3H1Ef7L8WQZdnENzcMaFxfjAKBggqhkjOPQQDAgNHADBEAiBQ\n" +
                "qoAC9NkyqaAFOPZTaK0P/8jvu8m+t9pWmDXPmqdRDgIgI7rI/g8j51RFtlM5CBpH\n" +
                "mUkpxyqvChVI1A0DTVFLJd4="

        const val TEST_PAA_NOVID_CERT =
            "MIIBkTCCATegAwIBAgIHC4+6qN2G7jAKBggqhkjOPQQDAjAaMRgwFgYDVQQDDA9N\n" +
                "YXR0ZXIgVGVzdCBQQUEwIBcNMjEwNjI4MTQyMzQzWhgPOTk5OTEyMzEyMzU5NTla\n" +
                "MBoxGDAWBgNVBAMMD01hdHRlciBUZXN0IFBBQTBZMBMGByqGSM49AgEGCCqGSM49\n" +
                "AwEHA0IABBDvAqgah7aBIfuo0xl4+AejF+UKqKgoRGgokUuTPejt1KXDnJ/3Gkzj\n" +
                "ZH/X9iZTt9JJX8ukwPR/h2iAA54HIEqjZjBkMBIGA1UdEwEB/wQIMAYBAf8CAQEw\n" +
                "DgYDVR0PAQH/BAQDAgEGMB0GA1UdDgQWBBR4XOcFuGuPTm/Hk6pgy0PqaWiC1TAf\n" +
                "BgNVHSMEGDAWgBR4XOcFuGuPTm/Hk6pgy0PqaWiC1TAKBggqhkjOPQQDAgNIADBF\n" +
                "AiEAue/bPqBqUuwL8B5h2u0sLRVt22zwFBAdq3mPrAX6R+UCIGAGHT411g2dSw1E\n" +
                "ja12EvfoXFguP8MS3Bh5TdNzcV5d"
    }
}
