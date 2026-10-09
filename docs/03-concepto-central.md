# Concepto central — Rastreador de problemas urbanos

## Qué hace la app

1. **Ciudadano reporta** → ubica el problema en el mapa, describe, sube fotos.
2. **Equipo de campo recibe** → ve el problema geolocalizdo en su mapa, acepta la tarea.
3. **Equipo va al lugar** → llega, trabaja, documenta con fotos desde el sitio.
4. **Cierra el caso** → sube foto del "después", marca como resuelto.
5. **Ciudadano es notificado** → ve el resultado con las fotos del antes/después.

## Actores revisados

| Actor | Rol |
|-------|-----|
| Ciudadano | Reporta problemas desde su barrio |
| Coordinador / Legislador | Asigna el problema a un equipo, hace seguimiento |
| Equipo de campo | Va al sitio, trata el problema, sube fotos del resultado |

## Flujo principal

```
Ciudadano reporta
       ↓
Coordinador recibe alerta
       ↓
Asigna a equipo de campo
       ↓
Equipo acepta → navega al punto GPS
       ↓
Trabaja en el sitio → sube fotos del proceso
       ↓
Marca como "Resuelto" + foto del resultado
       ↓
Ciudadano recibe notificación + ve el antes/después
```

## Datos clave del reporte

- Título + descripción
- Categoría
- Fotos del PROBLEMA (ciudadano, al reportar)
- Ubicación GPS exacta
- Equipo asignado
- Fotos de la RESOLUCIÓN (equipo de campo, in situ)
- Fecha de resolución

## Diferencial vs apps similares

- Fotos del ANTES y DESPUÉS visibles para todos
- El equipo de campo trabaja desde la misma app (modo campo)
- Mapa en tiempo real con estado de cada problema
- Sin intermediarios: el ciudadano ve quién fue y qué hizo
