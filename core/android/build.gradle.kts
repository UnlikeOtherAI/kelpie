plugins {
    id("com.android.library")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.serialization")
    id("org.jlleitschuh.gradle.ktlint")
}

group = "com.unlikeotherai.kelpie"
version = "0.2.2"

ktlint {
    version.set("1.5.0")
    android.set(true)
    verbose.set(true)
    outputToConsole.set(true)
}

android {
    namespace = "com.kelpie.browser"
    compileSdk = 34

    defaultConfig {
        minSdk = 28
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        buildConfigField("int", "LOCAL_HTTP_PORT", "8420")
        ndk { abiFilters += listOf("arm64-v8a", "x86_64") }

        externalNativeBuild {
            cmake {
                cppFlags += "-std=c++17"
            }
        }
    }

    buildTypes {
        debug {
            if (providers.gradleProperty("kelpieEmbeddingVerificationProfile").orNull == "true") {
                buildConfigField("int", "LOCAL_HTTP_PORT", "18431")
            } else if (providers.gradleProperty("kelpieVerificationProfile").orNull == "true") {
                buildConfigField("int", "LOCAL_HTTP_PORT", "18420")
            }
        }
        release {
            isMinifyEnabled = false
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    buildFeatures {
        compose = true
        buildConfig = true
    }

    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
        }
    }

    sourceSets {
        getByName("main") {
            assets.srcDir("../../assets")
            assets.srcDir("../native/licenses")
        }
        // Cookie sync test doubles (fake UOA, memory store, loopback discovery) serve JVM and device tests.
        getByName("test") { java.srcDir("src/sharedTest/java") }
        getByName("androidTest") { java.srcDir("src/sharedTest/java") }
    }

    composeOptions {
        kotlinCompilerExtensionVersion = "1.5.10"
    }

    packaging {
        resources {
            excludes +=
                setOf(
                    "META-INF/INDEX.LIST",
                    "META-INF/io.netty.versions.properties",
                    "META-INF/DEPENDENCIES",
                    "META-INF/LICENSE.md",
                    "META-INF/NOTICE.md",
                )
        }
    }
}

dependencies {
    // Compose
    implementation(platform("androidx.compose:compose-bom:2024.02.00"))
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material:material-icons-extended")
    api("androidx.compose.ui:ui")
    implementation("androidx.compose.ui:ui-tooling-preview")
    api("androidx.activity:activity-compose:1.8.2")
    implementation("androidx.lifecycle:lifecycle-runtime-compose:2.7.0")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.7.0")
    debugImplementation("androidx.compose.ui:ui-tooling")

    // Core
    implementation("androidx.core:core-ktx:1.12.0")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.7.0")
    implementation("androidx.webkit:webkit:1.18.0")

    // Encrypted credential storage (HF token etc.)
    implementation("androidx.security:security-crypto:1.1.0-alpha06")

    // HTTP Server (Ktor)
    api("com.squareup.okhttp3:okhttp:4.12.0")
    implementation("io.ktor:ktor-server-netty:2.3.8")
    implementation("io.ktor:ktor-server-content-negotiation:2.3.8")
    implementation("io.ktor:ktor-serialization-kotlinx-json:2.3.8")
    implementation("io.ktor:ktor-server-cors:2.3.8")

    // Serialization
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.6.3")
    api("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.8.0")

    // Gemini Nano (AI Edge) — accessed via reflection in PlatformAIEngine to avoid hard dependency.
    // Uncomment when the SDK stabilizes: implementation("com.google.ai.edge.aicore:aicore:0.0.1-exp02")

    // Unit tests (plain JVM, no Android runtime)
    testImplementation("junit:junit:4.13.2")
    androidTestImplementation("androidx.test:runner:1.5.2")
    androidTestImplementation("androidx.test.ext:junit:1.1.5")
    androidTestImplementation(platform("androidx.compose:compose-bom:2024.02.00"))
    androidTestImplementation("androidx.compose.ui:ui-test-junit4")
    androidTestImplementation("com.squareup.okhttp3:mockwebserver:4.12.0")
}

// JVM unit tests run the real core-sync through a host build of the same JNI
// bridge (src/test/cpp). Needs CMake and a host C++17 compiler; CMake comes from
// PATH or the Android SDK.
val hostSyncJniBuild = layout.buildDirectory.dir("host-sync-jni/build")
val hostSyncJniOutput = layout.buildDirectory.dir("host-sync-jni/lib")
val hostSyncJniLibrary = hostSyncJniOutput.map { it.file(System.mapLibraryName("kelpie_sync_host_jni")) }

fun hostCmake(): String {
    val sdkCmake = android.sdkDirectory.resolve("cmake/3.22.1/bin/" + if (System.getProperty("os.name").startsWith("Windows")) "cmake.exe" else "cmake")
    val onPath =
        System
            .getenv("PATH")
            .orEmpty()
            .split(File.pathSeparator)
            .map { File(it, if (System.getProperty("os.name").startsWith("Windows")) "cmake.exe" else "cmake") }
    return (onPath.firstOrNull { it.canExecute() } ?: sdkCmake).absolutePath
}

val configureHostSyncJni by tasks.registering(Exec::class) {
    description = "Configures the host build of the cookie-sync JNI bridge used by unit tests."
    val include = File(System.getProperty("java.home")).resolve("include")
    val os = System.getProperty("os.name").lowercase()
    val platform =
        include.resolve(
            if (os.startsWith("windows")) {
                "win32"
            } else if (os.contains("mac")) {
                "darwin"
            } else {
                "linux"
            },
        )
    inputs.file("src/test/cpp/CMakeLists.txt")
    outputs.file(hostSyncJniBuild.map { it.file("CMakeCache.txt") })
    commandLine(
        hostCmake(),
        "-S",
        file("src/test/cpp").absolutePath,
        "-B",
        hostSyncJniBuild.get().asFile.absolutePath,
        "-DCMAKE_BUILD_TYPE=Release",
        "-DKELPIE_JNI_INCLUDE=${include.absolutePath}",
        "-DKELPIE_JNI_PLATFORM_INCLUDE=${platform.absolutePath}",
        "-DKELPIE_JNI_OUTPUT=${hostSyncJniOutput.get().asFile.absolutePath}",
    )
}

val buildHostSyncJni by tasks.registering(Exec::class) {
    description = "Builds the cookie-sync JNI bridge for the host JVM used by unit tests."
    dependsOn(configureHostSyncJni)
    inputs.file("src/main/cpp/cookie_sync_jni.cpp")
    inputs.dir("../native/core-sync/src")
    inputs.dir("../native/core-sync/include")
    outputs.file(hostSyncJniLibrary)
    commandLine(hostCmake(), "--build", hostSyncJniBuild.get().asFile.absolutePath, "--config", "Release", "--target", "kelpie_sync_host_jni")
}

tasks.withType<Test>().configureEach {
    dependsOn(buildHostSyncJni)
    systemProperty("kelpie.sync.jni", hostSyncJniLibrary.get().asFile.absolutePath)
    systemProperty("kelpie.sync.vectors", file("../native/core-sync/tests/vectors/handshake-v1.json").absolutePath)
}
