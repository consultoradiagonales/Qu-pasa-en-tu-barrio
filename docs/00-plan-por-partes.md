# Qué pasa en tu barrio: plan por partes

App ciudadana para reportar problemas urbanos (infraestructura, salud, seguridad, etc.) con ubicación en mapa, fotos y comentarios. Los legisladores pueden ver los reportes, responder y marcarlos como resueltos.

Se trabaja por módulos independientes. Cada módulo tiene su propio prompt y su entregable, y al final se integran en una sola app lista para Google Play.

## Decisiones por defecto (cambiar si no están de acuerdo)

- Stack: Flutter (Android e iOS), Firebase (Auth, Firestore, Storage, Cloud Messaging), Google Maps SDK.
- MVP: registro con correo y Google, mapa con incidencias, carga de problemas con título, descripción, categoría, fotos y ubicación. El panel del legislador y las notificaciones push entran en la fase 2.
- Login con Facebook: fuera del MVP. Suma complejidad y requisitos extra en Play Store.
- Interfaz en español.
- ASTRA: pendiente de definir. No se incorpora hasta tener la app maquetada.

## Partes

| # | Módulo | Entregable | Depende de |
|---|--------|------------|-----------|
| 1 | Especificación funcional | Pantallas, flujos de usuario, reglas de negocio, estados de un reporte (pendiente, en revisión, resuelto) | — |
| 2 | Modelo de datos y seguridad | Esquema Firestore, reglas de seguridad, estructura de Storage | 1 |
| 3 | Autenticación | Registro, login con correo y Google, recuperación de contraseña | 2 |
| 4 | Mapa y geolocalización | Mapa con incidencias, GPS, selección manual de punto | 2 |
| 5 | Reporte de problemas | Formulario, subida de fotos, comentarios, guardado | 2, 4 |
| 6 | Panel del legislador (web) | Listado con filtros por zona, categoría y estado; marcar como resuelto | 2 |
| 7 | Notificaciones push | Aviso al ciudadano cuando cambia el estado | 5, 6 |
| 8 | Cumplimiento Play Store | Política de privacidad, formulario Data Safety, moderación de contenido, eliminación de cuenta, justificación de permisos (ubicación, cámara, fotos), SDK objetivo vigente | Transversal, se revisa en cada módulo |
| 9 | Integración y release | App unificada, pruebas de punta a punta, AAB firmado, ficha de Play Console | Todos |

## Restricciones de Play Store a tener en cuenta desde el inicio

- Contenido generado por usuarios: hace falta un mecanismo para reportar contenido y moderarlo. Sin eso, la app puede ser rechazada.
- Eliminación de cuenta: el usuario debe poder borrar su cuenta y sus datos dentro de la app.
- Permisos de ubicación y cámara: deben justificarse en la ficha y pedirse solo en el momento de uso.
- Política de privacidad pública y enlazada en la ficha.
- Data Safety: declarar qué datos se recogen (ubicación, fotos, correo).
- Datos de un municipio o de un legislador: no publicar datos personales de terceros sin base. Los reportes deben ocultar datos sensibles de quien reporta.

## Orden de trabajo sugerido

1. Módulo 1 y 2 (base común).
2. Módulos 3, 4 y 5 (ciudadano).
3. Módulo 6 (legislador).
4. Módulo 7 (push).
5. Módulo 8 transversal y revisión final.
6. Módulo 9 con build de release.

## Pendiente de respuesta

- ¿Qué es ASTRA y en qué momento entra?
- ¿Se confirma el stack propuesto y el alcance del MVP?
- ¿El primer entregable se hace con GPT-5.6 Luna o con otra herramienta?
