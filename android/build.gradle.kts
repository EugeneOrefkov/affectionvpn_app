allprojects {
    repositories {
        // Local override of dev.tfox.fluttervless:xray-android produced by
        // scripts/build_xray_android.sh. Must come before mavenCentral so the
        // pinned version resolves even before the plugin author publishes it.
        maven(url = uri("${rootProject.projectDir}/xray-maven"))
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
