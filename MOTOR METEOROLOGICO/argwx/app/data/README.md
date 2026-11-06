# Datos de los 135 partidos

Generados con `scripts/build_municipios.py` (reproducible).

| Archivo | Contenido |
|---|---|
| `municipios_pba.json` | id, nombre, sección electoral, código de partido electoral, conurbano, punto de pronóstico (lat/lon) |
| `municipios_pba.geojson` | Límites simplificados (tolerancia ~300 m) para el mapa |

## Fuentes

- **Geometría:** circuitos electorales 2025 de la Provincia de Buenos Aires, repositorio
  [tartagalensis/circuitos_electorales_AR](https://github.com/tartagalensis/circuitos_electorales_AR),
  licencia **CC BY 4.0**. Los circuitos se unen por código de partido (`coddepto`, 001-135), que se conserva
  como `codigo_electoral`.
- **Nombres:** departamentos del IGN (SIG 250) en
  [mgaitan/departamentos_argentina](https://github.com/mgaitan/departamentos_argentina), asignados por
  superposición de polígonos. Esa capa es anterior a la creación de Lezama (2009): el código 135 es el segundo
  polígono dentro del antiguo Chascomús, ubicado al sur, y se asignó a Lezama.

## Criterios y advertencias

- **Punto de pronóstico:** centroide geométrico del partido (o un punto interior si el centroide cae fuera).
  En partidos con mucha superficie rural o de islas (por ejemplo San Fernando, con el Delta) el punto puede
  quedar lejos del casco urbano.
- **Secciones electorales** (1ra a 7ma y Sección Capital) y los **24 partidos del conurbano** (definición INDEC)
  se cargaron a mano en el script. Los totales coinciden con los oficiales (24, 15, 19, 19, 27, 22, 8 y 1),
  pero conviene validarlos contra la Junta Electoral bonaerense.
- No se incluyen todavía los códigos INDEC/Georef de cada partido: se pueden agregar consultando
  `https://apis.datos.gob.ar/georef/api/departamentos?provincia=06&max=200`.

## Límites provinciales (`provincias_ar.geojson`)

Unión de los circuitos electorales 2025 de cada distrito (misma fuente, CC BY 4.0), sin huecos internos y
simplificada (~4 km). Generado con `scripts/build_provincias.py`. Se usa solo como fondo del mapa nacional.
