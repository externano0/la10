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
// Forzamos compileSdk 36 en cada submódulo Android (los plugins externos).
// flutter_ringtone_player viene compilado contra 33 y sus transitive deps
// (androidx.core 1.17, exifinterface 1.4.1) requieren compileSdk >= 34.
// IMPORTANTE: este bloque tiene que ir ANTES del `evaluationDependsOn(":app")`
// para que el afterEvaluate se registre antes de que se evalúen los proyectos.
subprojects {
    afterEvaluate {
        if (project.extensions.findByName("android") != null) {
            project.extensions.configure<com.android.build.gradle.BaseExtension>("android") {
                compileSdkVersion(36)
            }
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
