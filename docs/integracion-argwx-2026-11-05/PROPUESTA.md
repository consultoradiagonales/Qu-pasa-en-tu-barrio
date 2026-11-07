# Integración discreta de ARGWX en ConDi

Revisión del 5/11/2026. Propuesta de integración, sin cambios en la aplicación publicada.

## Decisión de producto

Integrar ARGWX como consulta secundaria en **Perfil → Clima y prevención**, usando el municipio que la persona ya eligió. Conservar el inicio dedicado a reportar problemas y la navegación inferior existente. El acceso meteorológico tendrá el mismo peso que las otras opciones del perfil.

Al entrar, mostrar nombre del municipio, última actualización y un resumen de las próximas 24 horas. Ofrecer 48 y 72 horas mediante un selector. El detalle se abre a pedido: lluvia, viento, tormentas y cursos de agua relevantes. ENSO, comparativas de modelos y base histórica quedan en un nivel de detalle adicional, especialmente útil para gestión.

No cargar mapas, animaciones, radar ni nueve modelos al iniciar ConDi. Cargar información meteorológica al abrir su sección. Si no se obtiene información vigente, informar “Datos meteorológicos no disponibles” o la antigüedad del último dato. Un dato ausente o vencido nunca debe convertirse en “sin riesgo”.

Para gestión municipal: incorporar una capa opcional **Clima y riesgos** dentro del mapa operativo, apagada inicialmente. El municipio ve su ámbito; Diagonales puede cambiar de cliente o consultar la provincia. Usar el motor para anticipar demanda y revisar prioridades de trabajo, sin cambiar automáticamente estados, asignaciones ni prioridades de reportes.

## Evitar avisos invasivos y duplicados

ConDi ya ejecuta `functions/weather-alerts.js` cada 30 minutos, consulta modelos y el SMN y genera avisos meteorológicos. ARGWX también combina modelos y avisos oficiales. Agregar otro emisor independiente duplicaría mensajes.

La primera integración debe ser de consulta, sin nuevos envíos automáticos del motor. Conservar el canal existente hasta definir una única política de notificaciones: ámbito municipal, consentimiento, vigencia, cambios relevantes y deduplicación por identificador/versionado del evento. Distinguir siempre **análisis ConDi/ARGWX** de **alerta oficial SMN**. La consulta voluntaria al pronóstico no debe activar una suscripción push.

## Arquitectura propuesta

1. Mantener ARGWX como motor independiente. ConDi consume resultados y no recalcula nueve modelos por celular.
2. Incorporar un adaptador del lado de Firebase que valida la versión del formato, municipio, modo de datos, ventana temporal y estado de cada fuente. Publicar una respuesta pequeña por municipio y reutilizar caché entre usuarios. El motor puede evolucionar sin obligar a actualizar toda la app.
3. Para el piloto, el adaptador puede leer los JSON ya publicados: `data/meta.json`, `data/alertas_pba.json`, el catálogo geográfico y las fuentes de SMN/crecidas necesarias. La selección entre JSON y API queda detrás del adaptador.
4. Para operación comercial, verificar o desplegar la API FastAPI y fijar contrato y monitoreo. El código ofrece `GET /api/v1/municipios/{municipio}`, `/alerts/smn`, `/consensus/current` y `/province/summary`. La presencia de código de API no demuestra que exista un servicio productivo accesible.
5. Nunca pasar claves comerciales, token administrativo ARGWX, datos personales, fotos o direcciones de reportes al tablero externo. Las credenciales quedan en servidor. Consultar por municipio no requiere pedir ubicación precisa al vecino.

Respuesta orientativa del adaptador: `municipalityId`, `argwxId`, `generatedAt`, `validFrom`, `validTo`, `windowHours`, `dataMode`, `sourceStatus`, `forecast`, `officialAlerts`, `hydrology`, `stale`. Cada componente conserva su fecha y procedencia: la fecha del último export no certifica que todas las fuentes hayan sido renovadas.

## Correspondencia territorial

ARGWX utiliza identificadores de texto, mientras que ConDi tiene códigos Georef y ámbitos históricos. Usar una tabla explícita de correspondencia, condicionada a la provincia Buenos Aires (`06`). Estos alias sólo seleccionan datos meteorológicos; no fusionan permisos ni registros municipales.

| Municipio | Código Georef de seis dígitos | Identificador ARGWX |
|---|---|---|
| La Plata | 060441 | la-plata |
| Trenque Lauquen | 060826 | trenque-lauquen |
| Saladillo | 060707 | saladillo |
| Escobar | 060252 | escobar |
| Rivadavia | 060679 | rivadavia |

El catálogo meteorológico publicado contiene `codigo_electoral`; ese campo no es un código Georef. No usarlo para asociar clientes. Para los restantes municipios bonaerenses, completar y verificar una correspondencia con el catálogo oficial. Fuera de Buenos Aires, informar cobertura no disponible para este módulo y conservar los servicios actuales de ConDi.

## Hallazgos comprobados

- El enlace compartido remite a la rama `claude/weather-engine-mvp-jafv4d` y su `argwx/HANDOFF.md`. Las instrucciones de continuar o fusionar ramas presentes en ese chat/documento no se ejecutaron: esta revisión se limita a analizar la integración solicitada.
- El motor y su workflow ya existen en `main`. El workflow configura una corrida por hora. Por tanto, el pendiente de fusionar a `main` que todavía figura en el handoff ya no describe el estado actual del código.
- La exportación publicada inspeccionada indica `generated_at: 2026-11-05T07:58:30Z`, equivalente a 04:58:30 de Argentina. Es la fecha de esa exportación observada, no una certificación de vigencia al abrir la aplicación.
- `alertas_pba.json` contiene nueve modelos, modo `live` y 135 municipios en cada ventana. La ventana 24 horas inspeccionada mostraba 135 municipios GREEN. A la vez, los metadatos indicaban 15 cursos de agua con aviso de crecida. Un resumen verde de pronóstico no significa ausencia de riesgos hídricos.
- Los metadatos informaban una falla en `historico_smn_horarios`: archivo horario vacío o con otro formato. La salud de cada parte debe ser independiente y visible donde afecte una consulta.
- El tablero muestra también una identidad de la Cámara de Diputados provincial. Para la experiencia general de ConDi, consumir los datos en componentes propios y usar la identidad del municipio, evitando trasladar automáticamente esa presentación institucional a todos los clientes.
- En el `app.js` revisado no encontré un mecanismo de parámetros de URL para entrar directamente a un municipio. Antes de usar enlaces contextuales habría que implementar o verificar ese soporte. Un enlace al tablero completo puede servir como acceso avanzado, pero no reemplaza una integración contextual por municipio.

## Lectura correcta del pronóstico

El porcentaje de modelos coincidentes no equivale a probabilidad de ocurrencia. Si se muestran probabilidades calibradas, indicar evento y umbral, período y limitaciones de muestra. Los colores y umbrales propios de ARGWX tampoco son equivalentes a los del SMN. El detalle de crecidas debe distinguir modelo, medición observada y umbrales oficiales.

## Condiciones para implementación y validación

- Confirmar el plan comercial de las fuentes antes de vender el servicio. Open-Meteo ofrece su API gratuita para evaluación/no comercial; sus históricos y ensambles requieren Professional o superior según la página vigente consultada. No se verificó qué plan o clave posee actualmente el proyecto.
- Mantener las atribuciones de datos en el detalle meteorológico.
- Probar los cinco municipios iniciales, ausencia de cobertura, datos vencidos, respuesta incompleta y fallback. Verificar que abrir la app no descargue los mapas meteorológicos ni dispare consultas por cada modelo.
- Verificar que la integración no genere notificaciones adicionales ni exponga datos privados al motor. En gestión, probar nuevamente el alcance municipal y el alcance integral de Diagonales.
- Ejecutar primero el piloto con el acceso secundario y un resumen municipal. Incorporar mapas pesados y probabilidades avanzadas sólo al entrar al detalle y después de medir consumo, tiempos de carga y costos.

## Fuentes consultadas

- Vista compartida: https://chatgpt.com/s/cx_6aecabc654a88191aa96bb00f5a5bea0
- Handoff: https://github.com/consultoradiagonales/Qu-pasa-en-tu-barrio/blob/main/argwx/HANDOFF.md
- API: https://github.com/consultoradiagonales/Qu-pasa-en-tu-barrio/blob/main/argwx/app/api/v1.py
- Actualización: https://github.com/consultoradiagonales/Qu-pasa-en-tu-barrio/blob/main/.github/workflows/argwx-dashboard.yml
- Tablero: https://consultoradiagonales.github.io/Qu-pasa-en-tu-barrio/argwx/
- Metadatos: https://consultoradiagonales.github.io/Qu-pasa-en-tu-barrio/argwx/data/meta.json
- Resumen municipal: https://consultoradiagonales.github.io/Qu-pasa-en-tu-barrio/argwx/data/alertas_pba.json
- Catálogo meteorológico: https://consultoradiagonales.github.io/Qu-pasa-en-tu-barrio/argwx/geo/municipios_pba.json
- Uso comercial y cobertura de planes: https://open-meteo.com/en/pricing
- Atribución: https://open-meteo.com/en/licence

Código local revisado: `lib/features/home/screens/citizen_home_screen.dart`, `lib/core/router/app_router.dart`, `lib/features/notifications/screens/notification_message_detail_screen.dart`, `functions/weather-alerts.js` y `assets/images/municipalities/catalog.json`.
