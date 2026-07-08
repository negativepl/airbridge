# Add project specific ProGuard rules here.
# By default, the flags in this file are appended to flags specified in the AGP.
# You can control the set of applied configuration files using the
# proguardFiles setting in build.gradle.kts.

# Keep protocol model classes
-keep class com.airbridge.protocol.** { *; }

# ML Kit component registrars (e.g. BarcodeRegistrar, CommonComponentRegistrar)
# are instantiated by reflection during MlKitComponentDiscovery. The consumer
# rule shipped by firebase-components keeps the class but, under R8 full mode,
# their no-arg <init>() is stripped as unreferenced — so discovery fails and
# BarcodeScanning.getClient() throws NPE in release builds only (QR pairing scan).
# Keep the reflectively-invoked constructor so component discovery succeeds.
-keep class * implements com.google.firebase.components.ComponentRegistrar {
    <init>();
}

# OkHttp
-dontwarn okhttp3.**
-dontwarn okio.**
