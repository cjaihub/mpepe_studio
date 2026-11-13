# Filament / gltfio are reached through JNI: keep their Java side intact.
-keep class com.google.android.filament.** { *; }
-dontwarn com.google.android.filament.**
