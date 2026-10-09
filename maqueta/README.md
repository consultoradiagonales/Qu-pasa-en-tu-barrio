# Maqueta móvil y demo para inversores

## Demo sin infraestructura

Abrir [demo-inversores.html](demo-inversores.html) directamente en un navegador, o enviarlo como archivo único. Funciona sin servidor, Firebase ni conexión; incluye datos ficticios, cambio entre Vecino, Coordinación y Cuadrilla, y el recorrido de reporte, asignación, resolución y comparación antes/después. Los cambios se guardan en el navegador del dispositivo y se pueden borrar con **Reiniciar demo**. Para actualizar el archivo después de editar la maqueta, ejecutar `node build_investor_demo.js`.

Esta demo es una presentación interactiva responsive, no un APK/IPA ni una instalación nativa.
El generador también deja `dist/index.html` listo para publicar en Firebase Hosting cuando haya un proyecto disponible.

## Backend local para desarrollo

Requiere Node.js 22.13 o posterior. Desde esta carpeta:

```powershell
node server.js
```

Abrir `http://127.0.0.1:4173`. El servidor guarda los reportes y avisos en `data/maqueta.sqlite`. **Reiniciar demo** restaura los datos de ejemplo. `node --test test_backend.js` verifica el flujo y el canal de eventos.

La interfaz se adapta a Android y iPhone y tiene manifiesto PWA. Para verla en otro dispositivo de la misma red, iniciar el servidor en PowerShell con `$env:HOST='0.0.0.0'; node server.js` y abrir `http://IP-DE-LA-PC:4173`. Esta modalidad de demostración no incluye cuentas ni permisos por rol: usar solamente datos ficticios y una red de confianza. La instalación PWA fuera de `localhost` requiere servirla mediante HTTPS.

El tablero de Coordinación consume `/api/analytics`, calculado con consultas SQL. `/api/events` usa Server-Sent Events para actualizar todas las pantallas abiertas cuando cambia un reporte, voto o aviso. `/api/bootstrap` entrega el estado inicial y `/api/actions` valida y guarda las transiciones.

Recorrido sugerido: crear un reporte como **Vecino**, asignarlo como **Coordinación**, elegir la cuadrilla correspondiente en **Cuadrilla**, registrar llegada y resolución y volver a **Vecino** para comparar el antes y después y calificar.

Las imágenes y la cámara siguen simuladas. El backend SQLite es para probar funcionalidades y estética; la app Flutter usa Firebase. El proyecto Firebase real sigue sin configurar.
