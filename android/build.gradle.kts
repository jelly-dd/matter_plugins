plugins {
    id("com.android.library")
    id("org.jetbrains.kotlin.android")
}

group = "com.example.matter_control"
version = "0.0.1"

android {
    namespace = "com.example.matter_control"
    compileSdk = 34

    defaultConfig {
        minSdk = 21
    }

    sourceSets {
        getByName("main") {
            jniLibs.srcDirs("src/main/jniLibs")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }
}

dependencies {
    // 编译出的 Matter 控制器 Java 库。
    // 注意：在 Android library 模块里，本地 jar 必须用 api(files(...)) 显式声明，
    // 这样才能作为「传递依赖」被上层 app 模块打包进最终 APK。
    // 若用 implementation(fileTree(...))，class 只参与编译、不会进 APK，
    // 运行时会 NoClassDefFoundError（一调用 ChipDeviceController 就崩）。
    api(files(
        "libs/CHIPController.jar",
        "libs/AndroidPlatform.jar",
        "libs/CHIPClusters.jar",
        "libs/CHIPClusterID.jar",
        "libs/OnboardingPayload.jar",
        "libs/libMatterJson.jar",
        "libs/libMatterTlv.jar",
    ))
    // Matter Java 库依赖 annotation 与 json
    implementation("androidx.annotation:annotation:1.7.0")
}
