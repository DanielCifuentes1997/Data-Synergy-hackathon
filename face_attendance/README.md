# Asistencia Facial (Flutter)

Aplicación Flutter para registrar ingreso/salida mediante reconocimiento facial offline con MobileFaceNet (TFLite).

## Requisitos
- Flutter SDK instalado y en PATH
- Dispositivo Android (iOS requiere configuración adicional de permisos)

## Configuración inicial (si aún no existen plataformas)
Desde la carpeta `face_attendance`:

```bash
flutter create .
```

Esto generará las carpetas de `android/`, `ios/`, etc.

## Instalación y ejecución
1. Coloca el modelo en: `assets/models/mobilefacenet.tflite` (respeta el nombre/minúsculas).
2. Instala dependencias y ejecuta:
```bash
flutter pub get
flutter run
```

### Android
1. Si no existen las carpetas de plataforma, crea con `flutter create .`.
2. Abre `android/app/build.gradle` y fija `minSdkVersion 24` (ver `platform_templates/android/build.gradle.append.md`).
3. Asegura permisos en `AndroidManifest.xml` (ejemplo en `platform_templates/android/AndroidManifest.xml`).

### iOS
1. Si no existen plataformas, ejecuta `flutter create .`.
2. Añade `NSCameraUsageDescription` en `ios/Runner/Info.plist` (ver `platform_templates/ios/Info.plist`).
3. En `ios/Podfile`, fija `platform :ios, '13.0'` si es necesario (ver `platform_templates/ios/Podfile.append.md`).

## Permisos
- Android: tras crear plataformas, abre `android/app/src/main/AndroidManifest.xml` y asegúrate de incluir:
```xml
<uses-permission android:name="android.permission.CAMERA" />
```
- iOS: añade descripciones de uso de cámara en `Info.plist`.

## Características
- Detección de rostros con ML Kit
- Embeddings con MobileFaceNet (TFLite)
- Matching local (sin conexión)
- UI primario (92, 9, 9) con blanco
- Botones: "Registrar ingreso" y "Registrar salida"
- Pantalla de Configuración con flujo de enrolamiento de usuarios

## Estructura relevante
- `lib/src/services/` detector, embedding, reconocimiento y asistencia
- `lib/src/screens/` home, configuración y enrolamiento
- `assets/models/` modelo TFLite (coloca aquí tu `mobilefacenet.tflite`)

## Notas de modelo y preproceso
- Entrada esperada: 112x112 RGB normalizado a rango [-1, 1]. Ajusta si tu variante de MobileFaceNet difiere.
- Umbral de matching por defecto: ~1.05 (ajústalo según tus pruebas).

## Flujo de uso
1. Abre Configuración → Enrolar usuario y captura el rostro; asigna un identificador (ej. nombre).
2. En la pantalla principal, la app detecta el rostro y si encuentra coincidencia mostrará el ID.
3. Usa "Registrar ingreso" o "Registrar salida" para guardar el evento localmente.
