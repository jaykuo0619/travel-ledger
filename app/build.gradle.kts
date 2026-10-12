import java.security.KeyStore
import java.security.MessageDigest
import java.util.Base64
import java.util.Properties

plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.ksp)
    alias(libs.plugins.paparazzi)
}

/*
 * Release signing. The key is NOT in this (public) repository. It is read from either
 *   - env TRAVEL_LEDGER_KEYSTORE_B64 (base64 of the keystore file), or
 *   - local.properties: travelLedger.keystore=/path/to/travel-ledger-release.keystore
 * Installed copies of the app only accept updates signed with this exact key, so the build
 * checks its fingerprint and refuses to produce a release APK with any other key.
 */
val releaseKeyFingerprint = "661000B556FC151FEC6D13B75D77D1FC5552265B796F7E733610AA42AAC730F4"
val releaseKeystore: File? = run {
    val b64 = System.getenv("TRAVEL_LEDGER_KEYSTORE_B64")
    if (!b64.isNullOrBlank()) {
        layout.buildDirectory.file("signing/release.keystore").get().asFile.apply {
            parentFile.mkdirs()
            writeBytes(Base64.getMimeDecoder().decode(b64))
        }
    } else {
        val props = Properties().apply {
            rootProject.file("local.properties").takeIf { it.exists() }?.inputStream()?.use { load(it) }
        }
        props.getProperty("travelLedger.keystore")?.let { file(it) }?.takeIf { it.exists() }
    }
}
val releaseStorePassword = System.getenv("TRAVEL_LEDGER_KEYSTORE_PASSWORD") ?: "android"

fun keystoreFingerprint(f: File): String {
    val ks = KeyStore.getInstance(KeyStore.getDefaultType()).apply { f.inputStream().use { load(it, releaseStorePassword.toCharArray()) } }
    val cert = ks.getCertificate(ks.aliases().nextElement())
    return MessageDigest.getInstance("SHA-256").digest(cert.encoded).joinToString("") { "%02X".format(it) }
}

android {
    namespace = "com.archiekuo.travelledger"
    compileSdk = 35

    defaultConfig {
        applicationId = "com.archiekuo.travelledger"
        minSdk = 29
        targetSdk = 35
        // Personal phone is 64-bit ARM; keeps the bundled OCR native libraries small.
        ndk { abiFilters += "arm64-v8a" }
        versionCode = 24
        versionName = "0.10.6"
    }

    signingConfigs {
        create("release") {
            if (releaseKeystore != null) {
                storeFile = releaseKeystore
                storePassword = releaseStorePassword
                keyAlias = "androiddebugkey"
                keyPassword = releaseStorePassword
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            signingConfig = signingConfigs.getByName("release")
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions {
        jvmTarget = "17"
    }
    testOptions {
        unitTests.isIncludeAndroidResources = true
    }
    sourceSets {
        // Exported Room schemas for the migration tests (Robolectric reads the debug assets).
        getByName("debug").assets.srcDir("$projectDir/schemas")
    }
    buildFeatures {
        compose = true
        buildConfig = true
    }
}

ksp {
    arg("room.schemaLocation", "$projectDir/schemas")
}

dependencies {
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.activity.compose)
    implementation(libs.androidx.lifecycle.runtime.compose)
    implementation(libs.androidx.lifecycle.viewmodel.compose)
    implementation(libs.androidx.navigation.compose)

    implementation(platform(libs.androidx.compose.bom))
    implementation(libs.androidx.compose.ui)
    implementation(libs.androidx.compose.ui.tooling.preview)
    implementation(libs.androidx.compose.material3)
    implementation(libs.androidx.compose.material.icons)
    debugImplementation(libs.androidx.compose.ui.tooling)

    // On-device text recognition, models bundled in the APK.
    implementation("com.google.mlkit:text-recognition:16.0.1")
    implementation("com.google.mlkit:text-recognition-chinese:16.0.1")
    implementation("com.google.mlkit:text-recognition-japanese:16.0.1")
    implementation("com.google.mlkit:text-recognition-korean:16.0.1")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-play-services:1.9.0")
    implementation("androidx.exifinterface:exifinterface:1.3.7")

    implementation(libs.androidx.room.runtime)
    implementation(libs.androidx.room.ktx)
    ksp(libs.androidx.room.compiler)

    testImplementation("junit:junit:4.13.2")
    testImplementation("org.robolectric:robolectric:4.14.1")
    testImplementation("androidx.test:core-ktx:1.6.1")
    testImplementation("androidx.test.ext:junit-ktx:1.2.1")
    testImplementation("androidx.room:room-testing:2.6.1")
    testImplementation("org.jetbrains.kotlinx:kotlinx-coroutines-test:1.9.0")
    testImplementation(platform(libs.androidx.compose.bom))
    testImplementation("androidx.compose.ui:ui-test-junit4")
    debugImplementation("androidx.compose.ui:ui-test-manifest")
}

// Robolectric's own downloader ignores the build proxy, so Gradle fetches the Android runtime jar
// and the tests run Robolectric in offline mode against it.
val robolectricRuntime: Configuration by configurations.creating
dependencies {
    robolectricRuntime("org.robolectric:android-all-instrumented:15-robolectric-12650502-i7")
}
val robolectricDepsDir = layout.buildDirectory.dir("robolectric-deps")
val copyRobolectricRuntime by tasks.registering(Copy::class) {
    from(robolectricRuntime)
    into(robolectricDepsDir)
}
tasks.withType<Test>().configureEach {
    dependsOn(copyRobolectricRuntime)
    systemProperty("robolectric.offline", "true")
    systemProperty("robolectric.dependency.dir", robolectricDepsDir.get().asFile.absolutePath)
}

// Refuse to build a release APK that phones with the app installed could not update to.
tasks.matching { it.name == "assembleRelease" || it.name == "packageRelease" }.configureEach {
    doFirst {
        val ks = releaseKeystore ?: throw GradleException(
            "缺少正式簽章金鑰:設定環境變數 TRAVEL_LEDGER_KEYSTORE_B64,或在 local.properties 加上 travelLedger.keystore=<路徑>",
        )
        val fp = keystoreFingerprint(ks)
        if (fp != releaseKeyFingerprint) throw GradleException("簽章金鑰不符(指紋 $fp),已安裝的 App 無法用它更新")
    }
}
