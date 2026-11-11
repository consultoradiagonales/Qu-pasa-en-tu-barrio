from pathlib import Path
from docx import Document
from docx.enum.section import WD_SECTION
from docx.enum.table import WD_CELL_VERTICAL_ALIGNMENT
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.oxml import OxmlElement
from docx.oxml.ns import qn
from docx.shared import Inches, Pt, RGBColor

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'dist' / 'ConDi-Cierre-1.0.26+27' / 'Producto' / 'Manual_de_Uso_ConDi_1.0.26.docx'
LOGO = ROOT / 'assets' / 'images' / 'condi_logo.png'

BLUE = '123A6D'
PALE = 'EDF4FA'
GRAY = 'D9D9D9'

def shade(cell, fill):
    tcPr = cell._tc.get_or_add_tcPr()
    shd = tcPr.find(qn('w:shd'))
    if shd is None:
        shd = OxmlElement('w:shd')
        tcPr.append(shd)
    shd.set(qn('w:fill'), fill)

def set_cell_margins(cell, top=110, start=120, bottom=110, end=120):
    tc = cell._tc
    tcPr = tc.get_or_add_tcPr()
    tcMar = tcPr.first_child_found_in('w:tcMar')
    if tcMar is None:
        tcMar = OxmlElement('w:tcMar')
        tcPr.append(tcMar)
    for m, v in [('top', top), ('start', start), ('bottom', bottom), ('end', end)]:
        node = tcMar.find(qn('w:' + m))
        if node is None:
            node = OxmlElement('w:' + m)
            tcMar.append(node)
        node.set(qn('w:w'), str(v))
        node.set(qn('w:type'), 'dxa')

def set_table_borders(table):
    tblPr = table._tbl.tblPr
    borders = tblPr.first_child_found_in('w:tblBorders')
    if borders is None:
        borders = OxmlElement('w:tblBorders')
        tblPr.append(borders)
    for edge in ('top', 'left', 'bottom', 'right', 'insideH', 'insideV'):
        tag = 'w:' + edge
        el = borders.find(qn(tag))
        if el is None:
            el = OxmlElement(tag)
            borders.append(el)
        el.set(qn('w:val'), 'single')
        el.set(qn('w:sz'), '6')
        el.set(qn('w:color'), GRAY)

def hyperlink(paragraph, text, url):
    part = paragraph.part
    rel_id = part.relate_to(url, 'http://schemas.openxmlformats.org/officeDocument/2006/relationships/hyperlink', is_external=True)
    link = OxmlElement('w:hyperlink')
    link.set(qn('r:id'), rel_id)
    run = OxmlElement('w:r')
    rPr = OxmlElement('w:rPr')
    color = OxmlElement('w:color')
    color.set(qn('w:val'), '0563C1')
    underline = OxmlElement('w:u')
    underline.set(qn('w:val'), 'single')
    rPr.extend([color, underline])
    run.append(rPr)
    text_node = OxmlElement('w:t')
    text_node.text = text
    run.append(text_node)
    link.append(run)
    paragraph._p.append(link)

def add_heading(doc, text, level=1):
    p = doc.add_heading(text, level=level)
    p.paragraph_format.keep_with_next = True
    return p

def add_bullets(doc, items):
    for item in items:
        p = doc.add_paragraph(style='List Bullet')
        p.add_run(item)

def add_steps(doc, items):
    for number, item in enumerate(items, 1):
        p = doc.add_paragraph()
        p.paragraph_format.left_indent = Inches(0.28)
        p.paragraph_format.first_line_indent = Inches(-0.28)
        p.add_run(f'{number}.').bold = True
        p.add_run('  ' + item)

def add_link_line(doc, label, url):
    p = doc.add_paragraph()
    p.paragraph_format.space_after = Pt(5)
    r = p.add_run(label + ': ')
    r.bold = True
    hyperlink(p, url, url)

def add_footer(section):
    p = section.footer.paragraphs[0]
    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    r = p.add_run('ConDi 1.0.26  |  Manual operativo  |  10 de noviembre de 2026')
    r.font.name = 'Aptos'
    r.font.size = Pt(9)
    r.font.color.rgb = RGBColor(90, 90, 90)

doc = Document()
sec = doc.sections[0]
sec.page_width = Inches(8.5)
sec.page_height = Inches(11)
sec.top_margin = Inches(0.7)
sec.bottom_margin = Inches(0.65)
sec.left_margin = Inches(0.78)
sec.right_margin = Inches(0.78)
add_footer(sec)

styles = doc.styles
normal = styles['Normal']
normal.font.name = 'Aptos'
normal.font.size = Pt(11)
normal.font.color.rgb = RGBColor(25, 35, 45)
normal.paragraph_format.space_after = Pt(7)
normal.paragraph_format.line_spacing = 1.08
for name, size in [('Title', 27), ('Heading 1', 19), ('Heading 2', 14)]:
    st = styles[name]
    st.font.name = 'Aptos Display' if name != 'Normal' else 'Aptos'
    st.font.size = Pt(size)
    st.font.bold = True
    st.font.color.rgb = RGBColor(0, 0, 0)
    st.paragraph_format.space_before = Pt(10 if name != 'Title' else 0)
    st.paragraph_format.space_after = Pt(8)
title_ppr = styles['Title']._element.get_or_add_pPr()
title_border = title_ppr.find(qn('w:pBdr'))
if title_border is not None:
    title_ppr.remove(title_border)

# Cover
p = doc.add_paragraph()
p.alignment = WD_ALIGN_PARAGRAPH.CENTER
p.add_run().add_picture(str(LOGO), width=Inches(3.9))
p = doc.add_paragraph('Manual de uso y puesta en marcha de ConDi', style='Title')
p.alignment = WD_ALIGN_PARAGRAPH.CENTER
p = doc.add_paragraph('Aplicación ciudadana y central de monitoreo')
p.alignment = WD_ALIGN_PARAGRAPH.CENTER
p.runs[0].font.size = Pt(15)
p.runs[0].font.bold = True
p = doc.add_paragraph('Versión 1.0.26  |  Compilación 27  |  Noviembre de 2026')
p.alignment = WD_ALIGN_PARAGRAPH.CENTER
p.runs[0].font.color.rgb = RGBColor(70, 90, 110)
doc.add_paragraph('')
p = doc.add_paragraph()
p.alignment = WD_ALIGN_PARAGRAPH.CENTER
r = p.add_run('Este manual permite instalar, operar y verificar ConDi. Incluye el uso ciudadano, el municipio habitual, el reporte desde otra localidad, el pronóstico a 48 horas y la central de monitoreo.')
r.font.size = Pt(12)
p.paragraph_format.left_indent = Inches(0.65)
p.paragraph_format.right_indent = Inches(0.65)
doc.add_paragraph('')
p = doc.add_paragraph('Consultora Diagonales')
p.alignment = WD_ALIGN_PARAGRAPH.CENTER
p.runs[0].bold = True

doc.add_page_break()
add_heading(doc, 'Puesta en marcha rápida')
doc.add_paragraph('La entrega está dividida en un paquete técnico y un paquete comercial independiente. Para operar el sistema se utiliza únicamente el paquete técnico.')
add_heading(doc, 'Componentes del paquete técnico', 2)
table = doc.add_table(rows=1, cols=3)
table.autofit = False
table.columns[0].width = Inches(1.8)
table.columns[1].width = Inches(3.8)
table.columns[2].width = Inches(1.2)
headers = ['Componente', 'Uso', 'Estado']
for i, text in enumerate(headers):
    c = table.rows[0].cells[i]
    c.text = text
    shade(c, BLUE)
    for run in c.paragraphs[0].runs:
        run.font.color.rgb = RGBColor(255,255,255); run.bold = True
rows = [
    ('Aplicación Android', 'Reportes ciudadanos, alertas y clima.', 'Firmada'),
    ('Central de monitoreo', 'Acceso operativo para equipos municipales.', 'Ejecutable'),
    ('Backend', 'Autenticación, datos, notificaciones y reglas.', 'Funcional'),
    ('Manual', 'Instalación, operación y contingencias.', 'Incluido'),
]
for idx, row in enumerate(rows):
    cells = table.add_row().cells
    for i, value in enumerate(row):
        cells[i].text = value
        cells[i].vertical_alignment = WD_CELL_VERTICAL_ALIGNMENT.CENTER
        set_cell_margins(cells[i])
        if idx % 2: shade(cells[i], PALE)
set_table_borders(table)
add_heading(doc, 'Secuencia recomendada', 2)
add_steps(doc, [
    'Abrir ConDi Central de Monitoreo.exe en una computadora con Internet y Microsoft Edge.',
    'Ingresar con la cuenta operativa habilitada para el municipio u organismo.',
    'Instalar la aplicación desde la prueba interna de Google Play o mediante los APK firmados del paquete.',
    'Crear una cuenta ciudadana, seleccionar el municipio habitual y habilitar las notificaciones.',
    'Realizar un reporte de prueba y confirmar su recepción en la central.',
])

doc.add_page_break()
add_heading(doc, 'Uso de la aplicación ciudadana')
add_heading(doc, 'Municipio habitual', 2)
doc.add_paragraph('El municipio seleccionado se guarda como municipio habitual. No cambia por desplazarse físicamente ni por crear un reporte en otra localidad. Este dato organiza las alertas, el clima y la experiencia principal del usuario.')
add_steps(doc, [
    'Ingresar a Perfil y abrir Municipio habitual y alertas climáticas.',
    'Buscar el municipio por nombre y seleccionar la opción correcta.',
    'Confirmar el cambio. El nuevo municipio queda guardado hasta que el usuario decida modificarlo.',
])
add_heading(doc, 'Reportar desde otro municipio', 2)
doc.add_paragraph('Si la ubicación del reporte pertenece a otro municipio, ConDi ofrece reportar allí sin modificar el municipio habitual. La central recibe el caso en la jurisdicción seleccionada y conserva el municipio habitual como referencia del perfil.')
add_steps(doc, [
    'Tomar la fotografía o cargar la evidencia solicitada.',
    'Confirmar la ubicación o elegir una dirección válida.',
    'Cuando ConDi detecte otra jurisdicción, seleccionar Reportar en el municipio detectado.',
    'Revisar la categoría y enviar. El municipio habitual permanece sin cambios.',
])
add_heading(doc, 'Estados y seguimiento', 2)
add_bullets(doc, [
    'Enviado: el reporte fue recibido.',
    'En revisión: el equipo operativo inició el análisis.',
    'En proceso: existe una acción municipal en curso.',
    'Resuelto: el caso se cerró y puede incluir evidencia final.',
])

doc.add_page_break()
add_heading(doc, 'Clima y prevención')
doc.add_paragraph('La sección combina fuentes meteorológicas y oficiales para ofrecer contexto preventivo. No reemplaza las instrucciones del Servicio Meteorológico Nacional, Defensa Civil ni otras autoridades competentes.')
add_heading(doc, 'Pronóstico a 48 horas', 2)
add_bullets(doc, [
    'Muestra precipitación estimada y probabilidad de superar umbrales relevantes.',
    'Utiliza el municipio habitual como referencia territorial.',
    'Integra varios modelos cuando existe disponibilidad y señala la fecha de actualización.',
    'Permite consultar cursos de agua, alertas oficiales y el tablero ampliado.',
])
add_heading(doc, 'Lectura de flechas y colores', 2)
table = doc.add_table(rows=1, cols=3)
table.autofit = False
for i, text in enumerate(['Color', 'Lectura', 'Acción sugerida']):
    c = table.rows[0].cells[i]; c.text = text; shade(c, BLUE)
    for run in c.paragraphs[0].runs: run.font.color.rgb = RGBColor(255,255,255); run.bold=True
for idx, row in enumerate([
    ('Verde', 'Condición estable o tendencia favorable.', 'Seguimiento normal.'),
    ('Amarillo', 'Atención preventiva o cambio moderado.', 'Revisar actualizaciones.'),
    ('Naranja', 'Riesgo significativo o evolución adversa.', 'Preparar respuesta.'),
    ('Rojo', 'Situación crítica o alerta alta.', 'Seguir a la autoridad competente.'),
    ('Azul', 'Información hidrológica o referencia.', 'Consultar el detalle.'),
]):
    cells=table.add_row().cells
    for i,v in enumerate(row):
        cells[i].text=v; set_cell_margins(cells[i]); cells[i].vertical_alignment=WD_CELL_VERTICAL_ALIGNMENT.CENTER
        if idx%2: shade(cells[i], PALE)
set_table_borders(table)
doc.add_paragraph('La referencia exacta debe leerse junto con la leyenda visible en cada mapa o tablero. Una flecha representa dirección o evolución; su color representa el nivel asociado a esa capa.')

doc.add_page_break()
add_heading(doc, 'Central de monitoreo')
doc.add_paragraph('El ejecutable abre el panel web operativo en modo aplicación. Requiere Windows, conexión a Internet, Microsoft Edge actualizado y una cuenta autorizada.')
add_heading(doc, 'Instalación y acceso', 2)
add_steps(doc, [
    'Copiar la carpeta Producto en una ubicación estable de la computadora.',
    'Ejecutar ConDi Central de Monitoreo.exe. Si Windows muestra una advertencia, comprobar que el archivo provenga del paquete oficial.',
    'Iniciar sesión con la cuenta asignada. No compartir credenciales entre operadores.',
    'Fijar la ventana en la barra de tareas si se requiere acceso permanente.',
])
add_heading(doc, 'Operación diaria', 2)
add_bullets(doc, [
    'Revisar reportes nuevos y priorizar casos urgentes.',
    'Validar evidencia y jurisdicción antes de asignar.',
    'Actualizar estados con información verificable y sin datos personales innecesarios.',
    'Registrar avances y cierre con trazabilidad.',
    'Revisar alertas climáticas y territoriales vigentes.',
])
add_heading(doc, 'Roles', 2)
doc.add_paragraph('El acceso depende de la organización, el rol y el estado habilitado de la cuenta. El personal municipal opera únicamente su ámbito; las cuentas centrales autorizadas pueden administrar más de una jurisdicción.')

doc.add_page_break()
add_heading(doc, 'Conectividad y servicios')
doc.add_paragraph('La aplicación utiliza servicios públicos y privados. La validación de cierre comprobó la disponibilidad de la web, la central, GeoRef, Open Meteo, MET Norway, SMN CAP, ARGWX y sus datos de alertas y crecidas.')
add_heading(doc, 'Servicios principales', 2)
table=doc.add_table(rows=1, cols=3)
for i,t in enumerate(['Servicio','Finalidad','Contingencia']):
    c=table.rows[0].cells[i]; c.text=t; shade(c,BLUE)
    for run in c.paragraphs[0].runs: run.font.color.rgb=RGBColor(255,255,255); run.bold=True
for idx,row in enumerate([
    ('Firebase', 'Identidad, datos, funciones y notificaciones.', 'Reintentar y verificar estado del servicio.'),
    ('GeoRef', 'Municipios y jurisdicciones.', 'Conservar la selección previa y reintentar.'),
    ('Open Meteo y MET Norway', 'Pronóstico y comparación de modelos.', 'Mostrar las fuentes disponibles.'),
    ('SMN CAP', 'Alertas oficiales.', 'Mantener aviso de fuente oficial y reintentar.'),
    ('ARGWX', 'Tablero territorial y datos hídricos.', 'Usar la última información publicada.'),
]):
    cells=table.add_row().cells
    for i,v in enumerate(row):
        cells[i].text=v; set_cell_margins(cells[i]); cells[i].vertical_alignment=WD_CELL_VERTICAL_ALIGNMENT.CENTER
        if idx%2: shade(cells[i],PALE)
set_table_borders(table)
add_heading(doc, 'Verificación rápida', 2)
add_steps(doc, [
    'Abrir la aplicación y confirmar que carga Inicio.',
    'Consultar el municipio habitual y la vista de 48 horas.',
    'Abrir la central y confirmar la carga de reportes.',
    'Enviar un reporte controlado y verificar su recepción.',
    'Confirmar la notificación o el seguimiento del estado.',
])

doc.add_page_break()
add_heading(doc, 'Seguridad y resolución de problemas')
add_heading(doc, 'Prácticas obligatorias', 2)
add_bullets(doc, [
    'Usar cuentas personales de operador y revocar accesos al finalizar una función.',
    'No copiar bases, fotografías ni datos personales fuera del sistema.',
    'No publicar claves, archivos de firma ni credenciales técnicas.',
    'Mantener Windows, Edge y Android actualizados.',
    'Escalar incidentes con fecha, usuario afectado y captura sin datos sensibles.',
])
add_heading(doc, 'Problemas frecuentes', 2)
table=doc.add_table(rows=1, cols=2)
for i,t in enumerate(['Situación','Resolución']):
    c=table.rows[0].cells[i]; c.text=t; shade(c,BLUE)
    for run in c.paragraphs[0].runs: run.font.color.rgb=RGBColor(255,255,255); run.bold=True
for idx,row in enumerate([
    ('La central no abre', 'Comprobar Internet, abrir nuevamente el ejecutable y probar el enlace web directo.'),
    ('No permite ingresar', 'Verificar correo, contraseña, rol y estado habilitado de la cuenta.'),
    ('No carga el clima', 'Actualizar la pantalla y confirmar la conectividad; las fuentes pueden responder de forma parcial.'),
    ('El municipio no coincide', 'Corregir el punto o elegir reportar en el municipio detectado sin cambiar el habitual.'),
    ('No llegan avisos', 'Revisar permisos de notificación, ahorro de batería y sesión iniciada.'),
]):
    cells=table.add_row().cells
    for i,v in enumerate(row):
        cells[i].text=v; set_cell_margins(cells[i]); cells[i].vertical_alignment=WD_CELL_VERTICAL_ALIGNMENT.CENTER
        if idx%2: shade(cells[i],PALE)
set_table_borders(table)

doc.add_page_break()
add_heading(doc, 'Enlaces de acceso y estado de publicación')
add_link_line(doc, 'Aplicación web', 'https://project-5fc9024a-e961-42b7-9ee.web.app/')
add_link_line(doc, 'Central de monitoreo', 'https://project-5fc9024a-e961-42b7-9ee.web.app/admin/')
add_link_line(doc, 'Prueba interna de Google Play', 'https://play.google.com/apps/internaltest/4701647237677047143')
add_link_line(doc, 'Ficha pública prevista', 'https://play.google.com/store/apps/details?id=ar.com.consultoradiagonales.condi')
add_link_line(doc, 'Sitio de Consultora Diagonales', 'https://consultoradiagonales.com.ar/')
add_link_line(doc, 'Tablero ARGWX', 'https://consultoradiagonales.github.io/Qu-pasa-en-tu-barrio/argwx/')
add_heading(doc, 'Estado de Google Play', 2)
doc.add_paragraph('La versión firmada está preparada para Google Play y existe un canal de prueba interna operativo. La ficha pública todavía no está disponible. La publicación de producción depende de completar los requisitos de prueba cerrada y de la aprobación de Google Play Console; no puede considerarse pública hasta que la ficha responda correctamente.')
add_heading(doc, 'Cierre de aceptación', 2)
add_bullets(doc, [
    'Aplicación instalada y sesión iniciada.',
    'Municipio habitual guardado y persistente.',
    'Reporte en otra jurisdicción probado sin alterar el municipio habitual.',
    'Pronóstico a 48 horas visible.',
    'Central abierta desde el ejecutable.',
    'Reporte de prueba recibido y actualizado.',
    'Operadores, responsables y canales de soporte definidos.',
])
p=doc.add_paragraph()
p.paragraph_format.space_before=Pt(18)
r=p.add_run('Soporte operativo')
r.bold=True
p.add_run('  Consultora Diagonales  |  consultoradiagonales.com.ar')

OUT.parent.mkdir(parents=True, exist_ok=True)
doc.core_properties.title = 'Manual de uso y puesta en marcha de ConDi'
doc.core_properties.subject = 'Aplicación ciudadana y central de monitoreo'
doc.core_properties.author = 'Consultora Diagonales'
doc.save(OUT)
print('Manual DOCX generado')
