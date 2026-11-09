pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}

rootProject.name = "Kelpie"
include(":app")

include(":kelpie-browser")
project(":kelpie-browser").projectDir = file("../../core/android")

// A separate app identity and simulated Update action; excluded from ordinary builds.
if (providers.gradleProperty("updateVerification").orNull == "true") {
    include(":update-verification")
    project(":update-verification").projectDir = file("../updates/android-verification")
}
