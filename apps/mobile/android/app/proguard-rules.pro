# Add project specific ProGuard rules here.
# By default, the flags in this file are appended to flags specified
# in /usr/local/Cellar/android-sdk/24.3.3/tools/proguard/proguard-android.txt
# You can edit the include path and order by changing the proguardFiles
# directive in build.gradle.
#
# For more details, see
#   http://developer.android.com/guide/developing/tools/proguard.html

# react-native-reanimated
-keep class com.swmansion.reanimated.** { *; }
-keep class com.facebook.react.turbomodule.** { *; }

# React Native and Expo reflection/JNI entry points
-keep class com.facebook.react.** { *; }
-keep class expo.modules.** { *; }
-keep class expo.modules.kotlin.** { *; }
-keep class com.swmansion.gesturehandler.** { *; }
-keep class com.swmansion.reanimated.** { *; }
-keep class com.swmansion.worklets.** { *; }
-keep class com.th3rdwave.safeareacontext.** { *; }
-keep class com.swmansion.rnscreens.** { *; }

# Firebase, Google Sign-In, OCR, and SMS native integrations
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
-keep class com.google.mlkit.** { *; }
-keep class com.reactnativegooglesignin.** { *; }
-keep class com.reactnativegooglesignin.google_sign_in.** { *; }
-keep class com.tkporter.sendsms.** { *; }
-keep class com.centaurwarchief.smslistener.** { *; }
-keep class com.joelpjoji.one.wallet.** { *; }

-dontwarn com.google.firebase.**
-dontwarn com.google.android.gms.**
-dontwarn com.google.mlkit.**
-dontwarn com.reactnativegooglesignin.**
-dontwarn com.tkporter.sendsms.**
-dontwarn com.centaurwarchief.smslistener.**
