plugins {
    id("com.android.application") version "8.3.0" apply false
    id("org.jetbrains.kotlin.android") version "1.9.22" apply false
    id("org.jetbrains.kotlin.plugin.serialization") version "1.9.22" apply false
    id("org.jlleitschuh.gradle.ktlint") version "12.1.2"
}

val scopedBuildRoot = providers.environmentVariable("KELPIE_ANDROID_BUILD_ROOT").orNull
if (scopedBuildRoot != null) {
    allprojects {
        layout.buildDirectory.set(file(scopedBuildRoot + "/" + project.name))
    }
}
