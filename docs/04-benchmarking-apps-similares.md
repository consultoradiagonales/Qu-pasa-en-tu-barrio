# Módulo 4 — Benchmarking: apps que ya hacen esto

## Apps globales

### 1. SeeClickFix (EE.UU.) — el referente más completo
- **Web/iOS/Android**
- **Flujo:** Ciudadano sube foto + GPS → el reporte llega al servidor del municipio → staff de atención al cliente lo despacha al equipo de campo (integración con sistemas GIS de órdenes de trabajo).
- **Puntos clave para copiar:**
  - El reporte incluye: tipo de problema, foto, GPS, descripción
  - El municipio tiene un panel interno con todos los reportes
  - El ciudadano puede ver el estado en tiempo real
  - Integración con sistemas GIS municipales (Esri, etc.)
- **Debilidad para nosotros:** no tiene flujo nativo de foto del "antes/después" por el equipo de campo. Eso es lo que nos diferencia.
- **Link:** https://seeclickfix.com

---

### 2. SnapSendSolve (Australia/NZ) — flujo ciudadano limpio
- **iOS/Android**
- **Flujo más relevante:** Snap (foto) → Send (GPS automático + tipo) → Solve (el municipio recibe, asigna, cierra)
- **Clave:** identifica automáticamente qué municipio es responsable según el GPS. Envía el reporte directamente al área correcta.
- **Función de campo:** alertas SMS a oficiales de campo (parking, inspectores), pueden priorizar y solicitar más info al vecino.
- **El "Solve":** el municipio cierra el ticket y el ciudadano recibe confirmación.
- **Debilidad:** no hay foto del "después" como parte del flujo estándar.
- **Referencia:** ciudad de Perth → 2.848 reportes resueltos en un año (+229% vs 2023).
- **Link:** https://snapsendsolve.com

---

### 3. FixMyStreet (Reino Unido) — open source
- **Web + PWA (sin app nativa activa)**
- **Stack:** Perl/Catalyst + PostgreSQL + PostGIS + OpenStreetMap
- **Código fuente:** https://github.com/mysociety/fixmystreet (AGPL-3.0)
- **Flujo:** Web → mapea el problema → lo envía al concejo/municipio → el ciudadano ve el estado
- **Lo que se puede tomar:** el modelo de datos (body/category/state), el sistema de envío automático al área responsable según coordenadas.
- **Limitación:** plataforma web, no móvil nativa moderna. No tiene modo de campo.

---

### 4. Citimon — más cercano conceptualmente
- **iOS/Android**
- **Funcionalidades:** foto + GPS + descripción → panel municipal → ciudadano ve estado
- **Diferencial:** comunicación directa entre ciudadano y administración dentro de la app.
- **Funciona solo en municipios que se suscriben al servicio.**
- **Link:** https://apps.apple.com/en/app/citimon/id6499262969

---

### 5. Improve My City (Grecia) — open source
- **Extrae GPS automáticamente del teléfono**
- **Funciona offline** (guarda y sube cuando hay conexión)
- **Código fuente disponible**
- **Link:** http://smartcityapps.urenio.org/improve-my-city_en.html

---

## Apps argentinas

### 6. BA Colaborativa / BA 147 (GCABA) — referente local
- **Flujo:**
  1. Ciudadano carga solicitud + foto + dirección
  2. Recibe número de trámite por mail
  3. Puede compartir para que otros vecinos la "apoyen" (priorización por votos)
  4. A más apoyo, más prioridad de atención
  5. Recibe mails sobre el avance
  6. Al cierre puede calificar el servicio
- **Punto clave para copiar:** la **priorización por apoyo ciudadano** (crowdsourcing de urgencia). Cuantos más vecinos reportan o apoyan un problema, sube en la cola.
- **Debilidad:** calificación 2.5/5 en App Store. Interfaz obsoleta.
- **Link:** https://apps.apple.com/us/app/id731052976

### 7. App Ciudadana de Córdoba
- **111.868 incidentes resueltos** desde 2021
- Cubre: postes caídos, cables sueltos, veredas, alumbrado, calles, cloacas, espacios verdes
- **Referencia de escala:** funciona a nivel municipio grande sin colapsar
- **Link:** https://grupoclarin-la-voz-prod.cdn.arcpublishing.com/ciudadanos/se-resolvieron-mas-de-100000-incidentes-con-la-app-ciudadana-como-reportar-problemas

---

## Síntesis: qué copiar y qué mejorar

| Feature | De quién copiarlo |
|---------|------------------|
| GPS automático + foto al reportar | SnapSendSolve (flujo más limpio) |
| Priorización por apoyo ciudadano | BA Colaborativa |
| Panel municipal con filtros y asignación | SeeClickFix |
| Foto del ANTES registrada al reportar | Todos lo tienen |
| **Foto del DESPUÉS in situ por el equipo** | ⭐ Ninguno lo hace bien — nuestro diferencial |
| **Modo campo: el técnico navega al GPS** | ⭐ Ninguno lo hace nativamente |
| Notificación al ciudadano cuando se resuelve | SeeClickFix + SnapSendSolve |
| Historial antes/después visible para todos | ⭐ Ninguno lo expone públicamente |
| Open source base para adaptar | FixMyStreet (AGPL) |

---

## Flujo ideal basado en el benchmarking

```
CIUDADANO
1. Abre app → toca "Reportar"
2. Foto del problema (cámara) → GPS automático
3. Categoría + descripción breve
4. Enviar → el reporte aparece en el mapa para todos
5. Otros vecinos pueden "apoyar" (sube prioridad)

COORDINADOR (panel web o tablet)
6. Ve el mapa con todos los reportes
7. Filtra por zona/categoría/prioridad
8. Asigna al equipo de campo disponible

EQUIPO DE CAMPO (app en celular)
9. Recibe notificación push con ubicación
10. Navega con GPS al punto exacto
11. Foto del "antes" al llegar (documenta la situación)
12. Trabaja
13. Foto del "después" (documenta la resolución)
14. Marca como resuelto + nota opcional

CIUDADANO (notificación)
15. Recibe push "Tu reporte fue atendido"
16. Ve el antes/después en el detalle del reporte
17. Puede calificar la atención (1-5 estrellas)
```

---

## Decisión de arquitectura basada en benchmarking

| Decisión | Elección |
|----------|----------|
| Stack | Flutter (mismo app, distintos roles) |
| Asignación | Manual por coordinador (como SeeClickFix) — automática es fase 3 |
| Priorización | Botón "Apoyo" de vecinos (como BA Colaborativa) |
| Panel coordinador | Vista dentro de la misma app, rol "coordinator" |
| Diferencial único | Flujo foto antes/después por equipo de campo |
