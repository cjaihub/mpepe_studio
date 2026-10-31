allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
// flutter_pcm_sound (Gemini Live audio playback) still pins compileSdk 33,
// but its AndroidX dependencies require 34+.
subprojects {
    if (project.name == "flutter_pcm_sound") {
        afterEvaluate {
            extensions.configure<com.android.build.gradle.LibraryExtension> {
                compileSdk = 36
            }
        }
    }
}
// stripe_android's release lint classpath pulls Google's private tapandpay
// artifact (push provisioning, unused here), which isn't on public Maven, so
// its lintVital task can't resolve and fails every release build.
subprojects {
    if (project.name == "stripe_android") {
        tasks.matching { it.name.startsWith("lintVital") }.configureEach { enabled = false }
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

