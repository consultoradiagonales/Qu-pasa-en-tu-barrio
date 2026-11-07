import urllib.request,urllib.parse,pathlib,json
root=pathlib.Path(__file__).resolve().parents[1]/'output'/'red-hidrica-2026-11-05'
urls={
'red-osm-anterior.json':'https://raw.githubusercontent.com/consultoradiagonales/Qu-pasa-en-tu-barrio/gh-pages/argwx/data/red_hidrica.json',
'ign-agua-muestra.json':'https://wms.ign.gob.ar/geoserver/ign/ows?'+urllib.parse.urlencode({'service':'WFS','version':'1.0.0','request':'GetFeature','typeName':'ign:areas_de_aguas_continentales_BH140','outputFormat':'application/json','srsName':'EPSG:4326','maxFeatures':3,'bbox':'-63.5,-41.2,-56.3,-33.1,EPSG:4326'}),
}
for name,url in urls.items():
 try:
  with urllib.request.urlopen(urllib.request.Request(url,headers={'User-Agent':'ConDi-ARGWX/1.0'}),timeout=90) as r: b=r.read(40*1024*1024)
  (root/name).write_bytes(b)
  j=json.loads(b)
  print(json.dumps({'file':name,'bytes':len(b),'keys':list(j),'sample':[{'id':f.get('id'),'properties':f.get('properties')} for f in j.get('features',[])],'courses':len(j.get('cursos',[]))},ensure_ascii=True))
 except Exception as e: print(json.dumps({'file':name,'error':str(e)}))
