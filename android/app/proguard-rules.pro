# Flutter plugin entry points and application classes
-keep class io.flutter.plugins.** { *; }
-keep class com.example.mx_player_clone.** { *; }

# AndroidX Room
-keep class androidx.room.** { *; }
-dontwarn androidx.room.**

# Media & fvp / mdk
-keep class com.mediadevkit.** { *; }
-keep class mdk.** { *; }
-keep class com.ryanheise.just_audio.** { *; }
