plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

import com.android.build.gradle.AppExtension

// libc++_shared.so para el ffmpeg integrado (Android): se copia del NDK al
// empaquetar, una por ABI, sin guardar binarios en git. El motor la sirve a
// los procesos hijo vía LD_LIBRARY_PATH (ver process.rs).
val abiTriples = mapOf(
    "arm64-v8a" to "aarch64-linux-android",
    "armeabi-v7a" to "arm-linux-androideabi",
    "x86_64" to "x86_64-linux-android",
)
// Respeta el buildDir remapeado por el root (flutter/build/app).
val stlLibsDir = project.buildDir.resolve("generated/stlLibs")

tasks.register("copyStlLibs") {
    outputs.dir(stlLibsDir)
    doLast {
        val ndk = project.extensions.getByType(AppExtension::class.java).ndkDirectory
        val sysroots = ndk.resolve("toolchains/llvm/prebuilt").listFiles()
            ?.map { it.resolve("sysroot") }
            ?.filter { it.isDirectory } ?: emptyList()
        if (sysroots.isEmpty()) {
            throw GradleException("NDK sin sysroot en $ndk; instala el NDK ${flutter.ndkVersion}")
        }
        for ((abi, triple) in abiTriples) {
            val src = sysroots
                .map { it.resolve("usr/lib/$triple/libc++_shared.so") }
                .firstOrNull { it.isFile }
                ?: throw GradleException("libc++_shared.so no encontrado para $abi en $ndk")
            val dst = stlLibsDir.resolve(abi)
            dst.mkdirs()
            src.copyTo(dst.resolve("libc++_shared.so"), overwrite = true)
        }
    }
}

tasks.configureEach {
    if (name.startsWith("merge") && name.endsWith("JniLibFolders")) {
        dependsOn("copyStlLibs")
    }
}

android {
    namespace = "com.offlineaudio.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.offlineaudio.app"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    sourceSets {
        getByName("main") {
            jniLibs.srcDir(stlLibsDir)
        }
    }

    // Nativas extraídas al instalar (legado): el motor localiza su carpeta
    // vía /proc/self/maps para servir libc++_shared.so a los hijos.
    packagingOptions {
        jniLibs {
            useLegacyPackaging = true
        }
    }

    signingConfigs {
        // Release signing comes from environment/property secrets (CI) or falls
        // back to debug keys so `flutter build apk --release` works locally.
        create("release") {
            val keystorePath = System.getenv("KEYSTORE_PATH")
            if (keystorePath != null && file(keystorePath).exists()) {
                storeFile = file(keystorePath)
                storePassword = System.getenv("KEYSTORE_PASSWORD")
                keyAlias = System.getenv("KEY_ALIAS")
                keyPassword = System.getenv("KEY_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            val release = signingConfigs.getByName("release")
            signingConfig = if (release.storeFile != null) release else signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}