plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.plugin.compose")
    id("org.jetbrains.kotlin.plugin.serialization")
}

android {
    namespace = "com.airbridge"
    compileSdk = 37
    defaultConfig {
        applicationId = "com.airbridge"
        minSdk = 29
        targetSdk = 36
        versionCode = 30402
        versionName = "3.4.2"
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }
    signingConfigs {
        create("release") {
            storeFile = file(System.getProperty("user.home") + "/.android/debug.keystore")
            storePassword = "android"
            keyAlias = "androiddebugkey"
            keyPassword = "android"
        }
    }
    buildTypes {
        release {
            isMinifyEnabled = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            signingConfig = signingConfigs.getByName("release")
        }
    }
    buildFeatures { compose = true; buildConfig = true }
    testOptions {
        // android.util.Log w czystych unit testach: no-op zamiast "not mocked".
        unitTests.isReturnDefaultValues = true
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
        freeCompilerArgs.add("-opt-in=androidx.compose.material3.ExperimentalMaterial3ExpressiveApi")
    }
}

dependencies {
    // Compose BOM
    implementation(platform("androidx.compose:compose-bom:2026.09.00"))
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.foundation:foundation")
    // Nadpisuje BOM: komponenty M3 Expressive (LoadingIndicator, WavyProgress, ButtonGroup,
    // FAB menu, MaterialShapes) istnieją dopiero w linii 1.5.0 (BOM wciąż daje 1.4).
    implementation("androidx.compose.material3:material3:1.5.0-rc01")
    // Navigation 3: back stack of serializable keys, predictive back.
    implementation("androidx.navigation3:navigation3-runtime:1.2.1")
    implementation("androidx.navigation3:navigation3-ui:1.2.1")
    implementation("androidx.lifecycle:lifecycle-viewmodel-navigation3:2.11.0")
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-core:1.12.0")
    implementation("androidx.compose.material:material-icons-extended")
    implementation("androidx.compose.ui:ui-tooling-preview")
    implementation("androidx.activity:activity-compose:1.13.0")
    implementation("com.google.android.material:material:1.14.0")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.11.0")
    // Image loading
    implementation("io.coil-kt.coil3:coil-compose:3.6.3")
    // Networking
    implementation("com.squareup.okhttp3:okhttp:5.5.1")
    // QR scanning — versions bumped for 16 KB page-size alignment of bundled
    // native libs (libbarhopper_v3.so, libimage_processing_util_jni.so):
    // ML Kit 17.3.0 + CameraX 1.4.x are the first 16 KB-aligned releases.
    implementation("com.google.mlkit:barcode-scanning:17.3.0")
    // Document scanner for "Scan Document with Phone" on the Mac: Google's own
    // scanner UI (edge detection, cropping, multi-page PDF) via Play services.
    implementation("com.google.android.gms:play-services-mlkit-document-scanner:16.0.0")
    implementation("androidx.camera:camera-camera2:1.6.2")
    implementation("androidx.camera:camera-lifecycle:1.6.2")
    implementation("androidx.camera:camera-view:1.6.2")
    // Launch splash held until the Mac is connected and its info has arrived.
    implementation("androidx.core:core-splashscreen:1.2.0")
    // Home screen widget (quick actions in the Expressive Toolbar layout).
    implementation("androidx.glance:glance-appwidget:1.2.0")
    implementation("androidx.glance:glance-material3:1.2.0")
    // Glance only asks for WorkManager 2.7 (Room 2.2), whose R8 rules predate
    // full mode: release builds lost WorkDatabase_Impl's constructor and the
    // app crashed at start-up. A current WorkManager brings Room with rules
    // that keep it.
    implementation("androidx.work:work-runtime:2.12.0")
    // Window metrics without the deprecated Display APIs (mirror stream sizing).
    implementation("androidx.window:window:1.5.1")
    // Testing
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.jetbrains.kotlinx:kotlinx-coroutines-test:1.11.0")
    testImplementation("org.json:json:20260814")
    testImplementation("com.squareup.okhttp3:mockwebserver:5.5.0")
    // TLS test fixtures (HeldCertificate/HandshakeCertificates) for pinned-TLS tests
    testImplementation("com.squareup.okhttp3:okhttp-tls:5.5.0")
}
