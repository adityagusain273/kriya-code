// Offline engine mirror, used only when it has actually been built.
//
// The Flutter engine artifacts (`io.flutter:<abi>_debug`) are published only to
// storage.googleapis.com. On a machine that cannot reach it, and with those jars
// absent from the Gradle cache, every build hangs mid-resolve rather than failing
// fast. `tool/make-local-engine-repo.sh` assembles the same coordinates from the
// jars already inside the Flutter SDK, so the build works with no network.
//
// Skipped when the directory is absent, which is the case on any normal machine and
// in CI, so the published repository is used there as normal.
val localEngineRepo = file(System.getenv("BCODE_LOCAL_ENGINE_REPO") ?: "local-engine-repo")

allprojects {
    repositories {
        if (localEngineRepo.isDirectory) {
            maven { url = uri(localEngineRepo) }
        }
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
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
