import pathlib,xml.etree.ElementTree as ET,json,collections
base=pathlib.Path(__file__).resolve().parents[1]/'output'/'red-hidrica-2026-11-05'
ns={'k':'http://www.opengis.net/kml/2.2'}
doc=ET.parse(base/'hidraulica-cuencas.kml')
for folder in doc.findall('.//k:Folder',ns):
 name=folder.findtext('k:name',namespaces=ns)
 if name not in ['Rios','Arroyos','Canales','CUENCAS']:continue
 marks=folder.findall('k:Placemark',ns)
 print(name)
 for m in marks[:2]:
  print(ET.tostring(m,encoding='unicode')[:1700])
 print('NOMBRES',json.dumps([m.findtext('k:name',namespaces=ns) for m in marks],ensure_ascii=True)[:1500])
