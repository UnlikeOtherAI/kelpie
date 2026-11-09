plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jlleitschuh.gradle.ktlint")
}

ktlint {
    version.set("1.5.0")
    android.set(true)
}

android {
    namespace = "com.unlikeotherai.kelpie.app"
    compileSdk = 34
    defaultConfig {
        applicationId = "com.unlikeotherai.kelpie.updateverification"
        minSdk = 28
        targetSdk = 34
        versionCode = 1
        versionName = "0.2.2"
    }
    buildFeatures { buildConfig = true }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = "17" }
}

kotlin.sourceSets["main"].kotlin.apply {
    srcDir("../../android/app/src/main/java")
    exclude("**/MainActivity.kt", "**/KelpieApp.kt")
}

dependencies {
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.7.3")
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    implementation("com.squareup.okhttp3:mockwebserver:4.12.0")
}
