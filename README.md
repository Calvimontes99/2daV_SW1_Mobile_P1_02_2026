# Diagramador UML — app móvil

App Flutter informativa del Diagramador UML (segundo parcial de Software 1). Pensada para quien
está fuera de la computadora:

- muestra el diagrama de la sala actualizándose en vivo (Socket.IO), con zoom, búsqueda de clases y detalle;
- el chat del equipo y el de la IA compartida;
- quién hizo cada cambio;
- notificaciones cuando hay novedades.

Backend y frontend web:

- https://github.com/Calvimontes99/2daV_SW1_Backend_P1_02_2026
- https://github.com/Calvimontes99/2daV_SW1_Frontend_P1_02_2026

## Ejecutar

```bash
flutter pub get
flutter run --dart-define=API_URL=https://ficctuagrmbolivia.online
```

Sin `API_URL`, la app apunta a `http://127.0.0.1:8083`. El servidor también se puede cambiar en la
pantalla de inicio.

## Notificaciones push

Se activan solas si existe `android/app/google-services.json` (proyecto de Firebase gratuito, con
Firebase Cloud Messaging). Sin ese archivo, la app sigue avisando con notificaciones locales
mientras está abierta o en segundo plano.

## Pruebas

```bash
flutter test
```
