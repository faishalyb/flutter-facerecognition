plugins {
    id("com.android.application")
    id("kotlin-android")
    // Flutter Gradle Plugin harus setelah Android & Kotlin
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.lkt.presence.presensi"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    androidResources {
        // Biar model .tflite tidak dikompres (lebih aman untuk load)
        noCompress += "tflite"
    }

    defaultConfig {
        applicationId = "com.lkt.presence.presensi"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = "11"
    }

    buildTypes {
    release {
        signingConfig = signingConfigs.getByName("debug")
        isMinifyEnabled = true
        isShrinkResources = true
        proguardFiles(
            getDefaultProguardFile("proguard-android-optimize.txt"),
            "proguard-rules.pro")
        }    
    }

}

dependencies {
    // ✅ Wajib untuk Kotlin native spoof detector (org.tensorflow.lite.Interpreter)
    implementation("org.tensorflow:tensorflow-lite:2.14.0")

    // Optional (aman kalau suatu saat butuh helper ops)
    // implementation("org.tensorflow:tensorflow-lite-support:0.4.4")

    // Optional GPU (tidak wajib untuk spoof)
    implementation("org.tensorflow:tensorflow-lite-gpu:2.14.0")
}

flutter {
    source = "../.."
}
