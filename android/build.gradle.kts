allprojects {
    repositories {
        // The Xray core is the dev.tfox.fluttervless:xray-android AAR
        // published on Maven Central by the flutter_vless plugin author.
        // The pinned version must exist there; experimental cores built from
        // Xray-core sources are installed at runtime via CoreUpdateService.
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
