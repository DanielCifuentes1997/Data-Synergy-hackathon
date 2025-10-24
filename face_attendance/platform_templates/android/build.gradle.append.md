En `android/app/build.gradle`, asegúrate de:

```gradle
android {
    defaultConfig {
        minSdkVersion 24 // requerido por camera/tflite
    }
    compileOptions {
        sourceCompatibility JavaVersion.VERSION_17
        targetCompatibility JavaVersion.VERSION_17
    }
}
```


