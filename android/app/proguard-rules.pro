-dontwarn com.google.firebase.perf.network.FirebasePerfUrlConnection
-dontwarn com.google.firebase.perf.network.FirebasePerfOkHttpClient

# Live Studio v2: LiveKit / flutter_webrtc are reached through JNI; R8 must not
# strip or rename them in minified release builds.
-keep class org.webrtc.** { *; }
-keep class io.livekit.** { *; }
-keep class com.cloudwebrtc.webrtc.** { *; }
