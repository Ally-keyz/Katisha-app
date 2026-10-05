# Katisha release ProGuard/R8 rules
-keep class rw.katisha.today.** { *; }

# Keep Flutter plugins' entry points (Flutter loader reflects on them)
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.embedding.** { *; }

# OkHttp (used transitively by dio) — keep platform/logging interfaces
-dontwarn okhttp3.**
-dontwarn okio.**
-keep class okhttp3.** { *; }

# Socket.IO engine client reflection
-keep class io.socket.** { *; }
-dontwarn io.socket.**

# Play Core Deferred Components (referenced by Flutter embedding only when deferred APKs used)
-dontwarn com.google.android.play.core.splitcompat.SplitCompatApplication
-dontwarn com.google.android.play.core.splitinstall.*
-dontwarn com.google.android.play.core.tasks.*

# Gson/JSON reflection used by some plugins
-keepattributes Signature
-keepattributes *Annotation*
