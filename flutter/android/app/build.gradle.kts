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
        // targetSdk 36 (Requerido Play Store). El motor usa youtubedl-android +
        // ffmpeg-kit que manejan la ejecución interna, evitando la restricción
        // W^X de execve() en el directorio privado de Android 10+.
        targetSdk = 36
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
            // youtubedl-android empaqueta Python como `libpython.zip.so`
            // (zip renombrado para que el APK lo trate como lib nativa).
            // AGP intenta strip-earlo y falla: lo excluimos.
            keepDebugSymbols += listOf(
                "**/libpython.zip.so",
            )
        }
    }

    // targetSdk 28 es deliberado (ver defaultConfig): lint lo marca como
    // caducado por la política de Play, que no aplica a esta app sideload.
    lint {
        disable += "ExpiredTargetSdkVersion"
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
            // R8 minificación deshabilitada: ffmpeg-kit y youtubedl-android
            // usan reflexión JNI y requieren reglas keep complejas. Para uso
            // sideload sin Play, el tamaño del APK no es crítico.
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

// youtubedl-android (GPL-3.0) provee Python + yt-dlp embebidos como libs
// nativas, permitiendo ejecución in-process compatible con targetSdk >= 29.
// ffmpeg-kit maintained fork (LGPL-3.0) reemplaza al arthenica original
// (archivado julio 2026) con la misma API drop-in.
dependencies {
    implementation("io.github.junkfood02.youtubedl-android:library:0.18.1")
    implementation("dev.ffmpegkit-maintained:ffmpeg-kit-full:8.1.7")
}

flutter {
    source = "../.."
}