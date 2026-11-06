import urllib.request,json,pathlib,datetime,hashlib
root=pathlib.Path(__file__).resolve().parents[1]/'output'/'red-hidrica-2026-11-05'
root.mkdir(parents=True,exist_ok=True)
sources={
 'catalogo-cursos.json':'https://catalogo.datos.gba.gov.ar/api/3/action/package_show?id=cursos-agua',
 'hidraulica-cuencas.kml':'https://www.google.com/maps/d/kml?mid=1Jvk6CoOUiGDAdeMl0aM8v6oCvcCzlG8P&forcekml=1',
 'capas-ign.html':'https://www.ign.gob.ar/NuestrasActividades/InformacionGeoespacial/CapasSIG',
}
for name,url in sources.items():
 try:
  req=urllib.request.Request(url,headers={'User-Agent':'ConDi/1.0 (info.consultoradiagonales@gmail.com)'})
  with urllib.request.urlopen(req,timeout=45) as r:
   content=r.read(40*1024*1024);ctype=r.headers.get('Content-Type')
  (root/name).write_bytes(content)
  print(json.dumps({'file':name,'bytes':len(content),'type':ctype,'sha256':hashlib.sha256(content).hexdigest()}))
  if name.endswith('.json'):
   data=json.loads(content)
   print(json.dumps({'resources':[{k:x.get(k) for k in ['id','name','url','format']} for x in data.get('result',{}).get('resources',[])]},ensure_ascii=False))
 except Exception as e:print(json.dumps({'file':name,'error':str(e)}))
