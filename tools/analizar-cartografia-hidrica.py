import pathlib,xml.etree.ElementTree as ET,collections,json,re,importlib.util
root=pathlib.Path(__file__).resolve().parents[1]/'output'/'red-hidrica-2026-11-05'
ns={'k':'http://www.opengis.net/kml/2.2'}
doc=ET.parse(root/'hidraulica-cuencas.kml')
print('DOCUMENTO',doc.findtext('.//k:Document/k:name',namespaces=ns))
for folder in doc.findall('.//k:Folder',ns):
 marks=folder.findall('.//k:Placemark',ns)
 print(json.dumps({'folder':folder.findtext('k:name',namespaces=ns),'count':len(marks),'names':[m.findtext('k:name',namespaces=ns) for m in marks[:9]],'geometries':dict(collections.Counter(g.tag.split('}')[-1] for m in marks for g in m.iter() if g.tag.split('}')[-1] in ['Polygon','LineString','Point']))},ensure_ascii=False))
html=(root/'capas-ign.html').read_text('utf8')
for name in ['Corriente de agua perenne','Corriente de agua intermitente','Corriente de agua','Acequia, zanja','<script src=']:
 idx=html.find(name)
 print(name, html[max(0,idx-350):idx+1600] if idx>=0 else 'NO')
print('PAQUETES', {p:importlib.util.find_spec(p) is not None for p in ['httpx','sqlalchemy','pydantic_settings','fastapi','pytest','shapely']})
