# Flutter特定规则
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }
-keep class io.flutter.embedding.** { *; }

# Google Play Core库（Flutter内部使用）
-keep class com.google.android.play.core.** { *; }
-dontwarn com.google.android.play.core.**

# 腾讯云相关
-keep class com.tencentcloudapi.** { *; }
-keep class com.tencent.** { *; }

# 网络请求 - 保留 http 包相关类
-keep class okhttp3.** { *; }
-keep class okio.** { *; }
-keep class java.net.** { *; }
-keep class java.io.** { *; }

# JSON解析
-keepattributes Signature
-keepattributes *Annotation*
-keepattributes RuntimeVisibleAnnotations
-keepattributes RuntimeInvisibleAnnotations
-keepattributes EnclosingMethod
-keepattributes InnerClasses
-keep class com.alibaba.fastjson.** { *; }

# 保持Flutter引擎
-keep class com.tencent.bugly.** { *; }

# 保持数据模型类不被混淆（重要！）
-keep class com.example.env_inspection_new.models.** { *; }
-keep class * extends java.lang.Object { *; }
-keepclassmembers class * {
    @com.google.gson.annotations.SerializedName <fields>;
}

# 移除日志（release模式）
-assumenosideeffects class android.util.Log {
    public static *** d(...);
    public static *** v(...);
    public static *** i(...);
    public static *** w(...);
    public static *** e(...);
}

# R8缺失规则
-keepattributes SourceFile,LineNumberTable
-renamesourcefileattribute SourceFile
-repackageclasses ''
