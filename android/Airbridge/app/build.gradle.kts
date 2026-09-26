plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.plugin.compose")
}

android {
    namespace = "com.airbridge"
    compileSdk = 37
    defaultConfig {
        applicationId = "com.airbridge"
        minSdk = 29
        targetSdk = 36
        versionCode = 30200
        versionName = "3.2.0"
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
    implementation(platform("androidx.compose:compose-bom:2026.08.00"))
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.foundation:foundation")
    // Nadpisuje BOM: komponenty M3 Expressive (LoadingIndicator, WavyProgress, ButtonGroup,
    // FAB menu, MaterialShapes) istnieją dopiero w linii 1.5.0-alpha.
    implementation("androidx.compose.material3:material3:1.5.0-alpha27")
    implementation("androidx.compose.material:material-icons-extended")
    implementation("androidx.compose.ui:ui-tooling-preview")
    implementation("androidx.activity:activity-compose:1.13.0")
    implementation("com.google.android.material:material:1.14.0")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.11.0")
    // Image loading
    implementation("io.coil-kt.coil3:coil-compose:3.6.0")
    // Networking
    implementation("com.squareup.okhttp3:okhttp:5.5.0")
    // QR scanning — versions bumped for 16 KB page-size alignment of bundled
    // native libs (libbarhopper_v3.so, libimage_processing_util_jni.so):
    // ML Kit 17.3.0 + CameraX 1.4.x are the first 16 KB-aligned releases.
    implementation("com.google.mlkit:barcode-scanning:17.3.0")
    implementation("androidx.camera:camera-camera2:1.6.2")
    implementation("androidx.camera:camera-lifecycle:1.6.2")
    implementation("androidx.camera:camera-view:1.6.2")
    // Launch splash held until the Mac is connected and its info has arrived.
    implementation("androidx.core:core-splashscreen:1.2.0")
    // Glass bars: the top bar and the dock blur the content passing under them.
    implementation("dev.chrisbanes.haze:haze:2.0.0")
    implementation("dev.chrisbanes.haze:haze-blur:2.0.0")
    // Testing
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.jetbrains.kotlinx:kotlinx-coroutines-test:1.11.0")
    testImplementation("org.json:json:20260814")
    testImplementation("com.squareup.okhttp3:mockwebserver:5.5.0")
    // TLS test fixtures (HeldCertificate/HandshakeCertificates) for pinned-TLS tests
    testImplementation("com.squareup.okhttp3:okhttp-tls:5.5.0")
}
