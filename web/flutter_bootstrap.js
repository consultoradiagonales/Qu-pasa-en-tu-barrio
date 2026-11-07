{{flutter_js}}
{{flutter_build_config}}

// Los recursos gráficos se sirven junto a la app para que el inicio no dependa
// de que una CDN externa permita descargar el motor de esta versión de Flutter.
_flutter.loader.load({
  config: {
    canvasKitBaseUrl: new URL('canvaskit/', document.baseURI).href,
  },
});
