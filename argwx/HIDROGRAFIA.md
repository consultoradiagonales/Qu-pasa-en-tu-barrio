# Red hídrica bonaerense

El inventario conserva los **1.271 registros cartográficos** del mapa DPH (79 de
ríos, 774 de arroyos y 418 de canales), sus **84 cuencas**, 18 registros urbanos
del catálogo GCBA, el estuario del Río de la Plata del IGN y un complemento OSM.
Son tramos, no ríos únicos. Incluye cauces sin nombre y no descarta los cortos.
La cobertura responde a esas fuentes: no acredita exhaustividad física.

## Uso

En **Crecidas**, buscar por curso, alias, partido, cuenca, localidad o jurisdicción.
«Todos» muestra el inventario; «Sin evaluación» identifica falta de datos aplicables.
En el mapa, **Red hídrica** y **Cuencas DPH** son capas opcionales. Los cauces menores
se dibujan desde zoom 8; se pueden abrir individualmente desde el buscador.
El gris discontinuo indica ausencia de evaluación, nunca riesgo verde.

La pertenencia municipal se determina por intersección geométrica con los 135
partidos del proyecto, sin asignación al centroide más cercano. Esas geometrías
son simplificadas: la asignación es orientativa, no una delimitación catastral.
Los tramos GCBA se identifican como CABA. Maldonado de La Plata y Maldonado de CABA
se mantienen separados; no se fusionan cursos por coincidencia de nombre.

## Datos y actualización

- DPH: https://www.gba.gob.ar/hidraulica/cuencas_hidricas/mapa
  El KML del mapa público se consulta mensualmente; si falla, se conserva el
  respaldo fechado y se registra una advertencia. Se leen `refname` y los campos
  originales cuando `<name>` está vacío. Se preservan registros e identificadores.
- FUENTE: Instituto Geográfico Nacional de la República Argentina.
  Capa `ign:areas_de_aguas_continentales_BH140`, Río de la Plata, campo original
  `fdc: Esri-World_Imagery 2010`. Condiciones: https://www.ign.gob.ar/descargas/tyc1.html
- GCBA: https://data.buenosaires.gob.ar/dataset/arroyos
  Geometrías WKT de la tabla pública del recurso; actualización de catálogo
  6/7/2026. Incluye conductos y emisarios. La descarga CSV respondió 503 al importar.
- © colaboradores de OpenStreetMap, ODbL. Complemento de la red anterior,
  cuya fecha y checksum quedan en el manifiesto. No reemplaza registros DPH.

Los archivos públicos `data/red_hidrica.json` y `data/cuencas_hidricas.json`
permiten descargar el inventario y su procedencia. El manifiesto conserva URLs,
SHA-256, fecha de descarga y fecha original cuando la fuente la informa. La fecha
de descarga no implica que la geometría se haya relevado ese día. El KML DPH no
declara una licencia específica: no se le atribuye una licencia inventada.

Para regenerar el respaldo:

```sh
python scripts/download_hydro_sources.py hydro-sources
python scripts/import_hydrography.py hydro-sources
pytest -q
```

## Evaluación y límites

El inventario y el monitoreo son independientes. Se mantiene el límite de 400
puntos GloFAS por corrida, con hasta cuatro por tramo de río elegible. Los arroyos
y canales nuevos no reciben caudal ficticio de una grilla fluvial gruesa.
La lluvia sobre partidos del trazado es una aproximación territorial, no una
integración hidrológica de la cuenca ni un mapa de inundación. Las cuencas DPH
se muestran como contexto cartográfico y no cambian esos umbrales.

El estuario se evalúa únicamente con escalas costeras aplicables y umbrales
conocidos; no con lluvia municipal ni GloFAS fluvial. Los registros urbanos GCBA
no estiman capacidad de conductos. Sin lluvia aplicable, caudal representado,
referencia o escala con umbral, el estado es `nivel: null`, `evaluado: false`.

Pruebas: conservación de todos los registros y nombres solicitados, cauces
cortos y anónimos, homónimos, jurisdicción, cruces sin vértices dentro del partido,
huecos de polígonos, respaldo ante fallo DPH y ausencia de falsas alertas/verdes.
