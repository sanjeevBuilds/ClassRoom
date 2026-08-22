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
subprojects {
    project.evaluationDependsOn(":app")
    
    project.configurations.all {
        resolutionStrategy {
            force("androidx.concurrent:concurrent-futures:1.1.0")
            force("com.google.guava:guava:31.1-android")
        }
        // Exclude listenablefuture if guava is used, or just force concurrent-futures
        exclude(group = "com.google.guava", module = "listenablefuture")
    }
}
tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
