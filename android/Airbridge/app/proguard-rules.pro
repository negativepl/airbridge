# Add project specific ProGuard rules here.
# By default, the flags in this file are appended to flags specified in the AGP.
# You can control the set of applied configuration files using the
# proguardFiles setting in build.gradle.kts.

# Keep protocol model classes
-keep class com.airbridge.protocol.** { *; }

# OkHttp
-dontwarn okhttp3.**
-dontwarn okio.**
