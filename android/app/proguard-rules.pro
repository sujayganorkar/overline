# Flutter Wrapper
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }

# Flutter Rust Bridge & JNI native entrypoints
-keepclasseswithmembernames class * {
    native <methods>;
}
-keep class app.overline.pdf.** { *; }
-keep class com.pdfcraft.pdfcraft_mobile.** { *; }

# Preserve Line Numbers and Source Attributes for Crash Telemetry Symbolication
-keepattributes SourceFile,LineNumberTable
-renamesourcefileattribute SourceFile

# Suppress warnings for optional Play Core deferred components
-dontwarn com.google.android.play.core.**

