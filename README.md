# Lapsus

Agenda y recordatorios para Android. Cada evento o tarea tiene una importancia que decide cómo avisa:

| Importancia | Avisos |
|---|---|
| Crítico | El día antes, 1 h antes y a la hora, con sonido de alarma. Se repite cada pocos minutos hasta marcarlo como hecho. |
| Importante | 1 h antes y a la hora. En tareas, un recordatorio más si no está hecha. |
| Normal | A la hora. |
| Sin aviso | Solo aparece en la agenda. |

Además:

- Eventos (pasan a una hora) y tareas (si no se hacen, siguen pendientes los días siguientes).
- Repeticiones diarias, semanales, mensuales, anuales y personalizadas (cada 2 semanas, lunes y jueves, último viernes del mes…). Al editar una serie se puede cambiar solo una vez, desde esa fecha o todas.
- Categorías editables, cada una con su importancia por defecto.
- Resumen diario por la mañana.
- Botones "Hecho" y "Posponer" en las notificaciones.
- Cinco temas de color con modo claro y oscuro.
- Todo se guarda en el móvil. Exportar/importar desde Ajustes.

## Instalar

1. Desde el móvil, abre la última versión en [Releases](../../releases/latest) y descarga el `.apk`.
2. Ábrelo. Android pedirá permitir la instalación desde el navegador: acéptalo.
3. Al abrir Lapsus por primera vez, acepta los permisos de notificaciones y batería.

Para recibir las actualizaciones sin estar pendiente, se puede usar [Obtainium](https://github.com/ImranR98/Obtainium) añadiendo la URL de este repositorio.

Requiere Android 8.0 o superior.

## Desarrollo

Hecho con Flutter. Cada push compila el APK en GitHub Actions (`.github/workflows/build.yml`); en la rama principal además se publica una Release.

```bash
flutter pub get
flutter analyze
flutter test
flutter run
```

Capturas de las pantallas con datos de ejemplo (se guardan en `tool/goldens/`):

```bash
flutter test tool/screenshots_test.dart --update-goldens
```

### Firma del APK

La clave de firma está cifrada en `android/keystore/lapsus.jks.enc`. Para que GitHub Actions pueda firmar y publicar, hay que crear el secreto `LAPSUS_SIGNING_PASSWORD` en *Settings → Secrets and variables → Actions*. Sin él, el APK se compila con una clave temporal y no se publica.

Esa contraseña no se puede recuperar: si se pierde, las actualizaciones no se podrán instalar encima de la versión anterior.

### Estructura

```
lib/
  models/     datos: eventos, repeticiones, categorías, ajustes
  logic/      cálculo de repeticiones y de qué avisos programar
  data/       base de datos SQLite
  services/   notificaciones de Android
  state/      estado de la app
  ui/         pantallas
```
