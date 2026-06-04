# Flutter
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Firebase
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }

# Groq / OkHttp
-dontwarn okhttp3.**
-dontwarn okio.**

# Keep notification service
-keep class com.dexterous.** { *; }