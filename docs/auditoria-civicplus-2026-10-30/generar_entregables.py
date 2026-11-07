from pathlib import Path
import html
import re
import json
import textwrap
from xml.etree import ElementTree

from reportlab.lib import colors
from reportlab.lib.enums import TA_LEFT
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.utils import ImageReader
from reportlab.platypus import (
    SimpleDocTemplate, Paragraph, Spacer, Table, TableStyle,
    PageBreak, Preformatted, Image, KeepTogether, Flowable,
)
from pypdf import PdfReader

BASE = Path(__file__).resolve().parent
ROOT = BASE.parent.parent
SKILL = Path('E:/CODEX ChatGPT/CodexData/skills/identidad-diagonales/assets')
PDF_DIR = ROOT / 'output/pdf'
PDF_DIR.mkdir(parents=True, exist_ok=True)
(BASE / 'pdf').mkdir(exist_ok=True)


def blocks(text):
    lines = text.splitlines()
    result = []
    i = 0
    while i < len(lines):
        line = lines[i].strip()
        if not line:
            i += 1
            continue
        if line.startswith('```'):
            language = line[3:]
            i += 1
            code = []
            while i < len(lines) and not lines[i].strip().startswith('```'):
                code.append(lines[i])
                i += 1
            result.append(('code', '\n'.join(code), language))
            i += 1
            continue
        if line.startswith('|'):
            rows = []
            while i < len(lines) and lines[i].strip().startswith('|'):
                cells = [c.strip() for c in lines[i].strip().strip('|').split('|')]
                if not all(re.fullmatch(r':?-+:?', c) for c in cells):
                    rows.append(cells)
                i += 1
            result.append(('table', rows))
            continue
        heading = re.match(r'^(#{1,6})\s+(.+)', line)
        if heading:
            result.append(('heading', len(heading[1]), heading[2]))
            i += 1
            continue
        picture = re.fullmatch(r'!\[(.*?)\]\((.*?)\)', line)
        if picture:
            result.append(('image', picture[1], picture[2]))
            i += 1
            continue
        if re.match(r'^[-*] ', line):
            items = []
            while i < len(lines) and re.match(r'^[-*] ', lines[i].strip()):
                items.append(lines[i].strip()[2:])
                i += 1
            result.append(('list', items))
            continue
        paragraph = [line]
        i += 1
        while i < len(lines) and lines[i].strip() and not re.match(r'^(#{1,6}\s|\||```|[-*] |!\[)', lines[i].strip()):
            paragraph.append(lines[i].strip())
            i += 1
        result.append(('paragraph', ' '.join(paragraph)))
    return result


def inline_html(text):
    text = html.escape(text)
    text = re.sub(r'\[([^\]]+)\]\((https?://[^\s)]+)\)', r'<a href="\2" target="_blank" rel="noopener">\1</a>', text)
    text = re.sub(r'`([^`]+)`', r'<code>\1</code>', text)
    text = re.sub(r'\*\*([^*]+)\*\*', r'<strong>\1</strong>', text)
    return text


def inline_pdf(text):
    text = html.escape(text).replace('→', '-&gt;').replace('←', '&lt;-').replace('–', '-').replace('—', '-')
    text = re.sub(r'\[([^\]]+)\]\((https?://[^\s)]+)\)', r'<link href="\2" color="#003A90"><u>\1</u></link>', text)
    text = re.sub(r'`([^`]+)`', r'<font name="Consolas">\1</font>', text)
    return re.sub(r'\*\*([^*]+)\*\*', r'<b>\1</b>', text)


def render_html(content, prefix):
    parts, nav = [], []
    opened = False
    for block in blocks(content):
        kind = block[0]
        if kind == 'heading':
            level, title = block[1:]
            if level == 1:
                continue
            if level == 2:
                if opened:
                    parts.append('</div></section>')
                n = len(nav) + 1
                anchor = f'{prefix}-{n}'
                label = re.sub(r'^\d+\.\s*', '', title)
                nav.append((anchor, label))
                parts.append(f'<section class="s" id="{anchor}"><div class="wrap"><h3><span class="num">{n:02}</span>{inline_html(label)}</h3>')
                opened = True
                if prefix == 'audit' and n == 1:
                    parts.append(NETWORK)
            else:
                parts.append(f'<h4>{inline_html(title)}</h4>')
        elif kind == 'paragraph':
            if not opened:
                continue
            parts.append('<p>' + inline_html(block[1]) + '</p>')
        elif kind == 'list':
            parts.append('<ul>' + ''.join('<li>' + inline_html(t) + '</li>' for t in block[1]) + '</ul>')
        elif kind == 'code':
            parts.append('<pre tabindex="0"><code>' + html.escape(block[1]) + '</code></pre>')
        elif kind == 'table':
            rows = block[1]
            parts.append('<div class="table-wrap" tabindex="0" role="region" aria-label="Tabla desplazable"><table><thead><tr>' + ''.join('<th scope="col">' + inline_html(c) + '</th>' for c in rows[0]) + '</tr></thead><tbody>')
            for row in rows[1:]:
                parts.append('<tr>' + ''.join('<td>' + inline_html(c) + '</td>' for c in row) + '</tr>')
            parts.append('</tbody></table></div>')
        elif kind == 'image':
            if block[2].endswith('.svg'):
                parts.append('<figure class="chart-card"><h4>Arquitectura evolutiva <span class="stamp">Modelo propuesto</span></h4>' + (BASE / block[2]).read_text(encoding='utf-8') + '<figcaption>Diseño para ConDi. No implementado; no representa infraestructura privada de CivicPlus.</figcaption></figure>')
    if opened:
        parts.append('</div></section>')
    return '\n'.join(parts), nav


NETWORK = '''<div class="actor-network-card"><h4>El circuito de responsabilidad <span class="stamp">Modelo</span></h4><div class="sub">Relaciones funcionales propuestas; nodos de tamaño uniforme, sin métrica cuantitativa.</div><div class="net-wrap" id="redActoresWrap" role="img" aria-label="Vecinos, municipio y cuadrillas conectan solicitudes, compromisos y evidencia"></div><div class="net-legend"><span>Actores: vecinos y equipos</span><span>Ámbito: municipio</span><span>Temas: solicitud, plazo y evidencia</span></div><div class="footer">Arrastrá para mover y usá + / - para ampliar. El detalle accesible está en las tablas de arquitectura.</div></div>'''


def make_html():
    audit, nav_a = render_html((BASE / 'auditoria.md').read_text(encoding='utf-8'), 'audit')
    arch, nav_b = render_html((BASE / 'arquitectura.md').read_text(encoding='utf-8'), 'arch')
    logo = (SKILL / 'logo_cd_base64.txt').read_text(encoding='utf-8').strip()
    logo = logo.removeprefix('data:image/png;base64,')
    css = (SKILL / 'identidad.css').read_text(encoding='utf-8')
    ui = (SKILL / 'ui.js').read_text(encoding='utf-8')
    template = (SKILL / 'plantilla.html').read_text(encoding='utf-8')
    template = template.replace('<script src="https://cdn.jsdelivr.net/npm/chart.js@4.4.1/dist/chart.umd.min.js"></script>', '')
    template = template.replace('/* === INSERTAR AQUÍ EL CONTENIDO COMPLETO DE assets/identidad.css === */', css + EXTRA_CSS)
    start, end = template.index('<main>'), template.index('</main>') + len('</main>')
    main = '''<main><section class="cover"><div class="wrap"><div class="kicker">Auditoría de producto y diseño de arquitectura</div><h2>De reportar problemas a gestionar compromisos</h2><div class="meta"><b>ConDi frente a SeeClickFix 311 CRM</b><br>30 de octubre de 2026 · Consultora Diagonales<br>Fuentes oficiales, inspección en Chrome y código local.</div><div class="downloads"><a href="pdf/auditoria-condi-civicplus.pdf" download>Descargar auditoría PDF</a><a href="pdf/arquitectura-condi-crm.pdf" download>Descargar arquitectura PDF</a><a href="backlog.csv" download>Backlog CSV</a></div><div class="nota"><span class="lbl">Alcance de esta entrega</span><p>Revisión pública y diseño propuesto. No se envió el formulario de la demo ni se modificó la aplicación.</p></div></div></section>''' + audit + '''<section class="cover" id="arquitectura"><div class="wrap"><div class="kicker">Segundo documento</div><h2>Arquitectura evolutiva para ConDi</h2><div class="meta">Flutter + Firebase · catálogo, SLA, eventos y ejecución</div></div></section>''' + arch + '''<section class="s" id="anexos"><div class="wrap"><h3><span class="num">+</span>Evidencia y anexos</h3><p><a href="inspeccion-condi.md">Inspección del código con rutas y líneas</a> · <a href="fuentes-civicplus.md">Registro de fuentes oficiales</a> · <a href="arquitectura.mmd">Diagrama editable Mermaid</a></p><figure class="chart-card"><h4>Vista de la demo en Chrome</h4><img alt="La página comercial de SeeClickFix pide datos para abrir la demo" src="evidencia/civicplus-demo.jpg"><figcaption>Captura del 30/10/2026. No se completó el formulario.</figcaption></figure></div></section></main>'''
    # Embed screenshot to keep the HTML portable as one file.
    import base64
    shot = base64.b64encode((BASE / 'evidencia/civicplus-demo.jpg').read_bytes()).decode()
    main = main.replace('src="evidencia/civicplus-demo.jpg"', 'src="data:image/jpeg;base64,' + shot + '"')
    template = template[:start] + main + template[end:]
    nav_html = '<p class="nav-title">Auditoría</p>' + ''.join(f'<a href="#{a}"><span class="n">{i+1}</span>{html.escape(t)}</a>' for i, (a,t) in enumerate(nav_a))
    nav_html += '<p class="nav-title">Arquitectura</p>' + ''.join(f'<a href="#{a}"><span class="n">{i+1}</span>{html.escape(t)}</a>' for i, (a,t) in enumerate(nav_b))
    template = re.sub(r'<nav>.*?</nav>', '<nav>' + nav_html + '</nav>', template, flags=re.S)
    template = template.replace('{{TITULO_DOCUMENTO}}', 'ConDi · auditoría CivicPlus y arquitectura').replace('{{TITULO_CORTO}}', 'ConDi · auditoría y arquitectura')
    template = template.replace('{{LOGO_BASE64}}', logo)
    template = template.replace('/* === INSERTAR AQUÍ assets/ui.js (drawer, progress, top-btn, TTS, Chart defaults, canvas nodos, renderRedActores) === */', ui)
    script_start = template.index('/* Al final, definir los datos reales')
    script_end = template.index('</script>', script_start)
    extra_js = '''
window.RED_ACTORES={nodes:[{id:'v',label:'Vecinos',group:'actor',size:0},{id:'m',label:'Municipio',group:'territorio',size:0},{id:'q',label:'Cuadrillas',group:'actor',size:0},{id:'s',label:'Solicitud',group:'tema',size:0},{id:'p',label:'Plazo',group:'tema',size:0},{id:'e',label:'Evidencia',group:'tema',size:0}],links:[{source:'v',target:'s'},{source:'m',target:'s'},{source:'m',target:'q'},{source:'q',target:'e'},{source:'s',target:'p'},{source:'s',target:'e'}]};
renderRedActores('redActoresWrap',window.RED_ACTORES);
const netWrap=document.getElementById('redActoresWrap'); let netWidth=netWrap.clientWidth; let netResize;
new ResizeObserver(()=>{if(Math.abs(netWrap.clientWidth-netWidth)>1){netWidth=netWrap.clientWidth;clearTimeout(netResize);netResize=setTimeout(()=>{netWrap.replaceChildren();renderRedActores('redActoresWrap',window.RED_ACTORES);},100);}}).observe(netWrap);
document.addEventListener('keydown',e=>{if(e.key==='Escape'){closeMenu();menuBtn.focus();}});
menuBtn.setAttribute('aria-controls','drawer');
const updateDrawer=()=>{const open=drawer.classList.contains('open'); menuBtn.setAttribute('aria-expanded',String(open)); drawer.setAttribute('aria-hidden',String(!open)); drawer.inert=!open;};
new MutationObserver(updateDrawer).observe(drawer,{attributes:true,attributeFilter:['class']}); updateDrawer();
menuBtn.addEventListener('click',()=>{if(drawer.classList.contains('open')){drawer.querySelector('a')?.focus();}});
if(matchMedia('(prefers-reduced-motion: reduce)').matches){document.documentElement.style.scrollBehavior='auto';}
'''
    template = template[:script_start] + extra_js + template[script_end:]
    (BASE / 'informe-condi-civicplus.html').write_text(template, encoding='utf-8')


EXTRA_CSS = '''
.s .wrap>p{font-size:14px;color:#2C4054;margin:13px 0;overflow-wrap:anywhere}
.s .wrap>h4{font-size:17px;color:#003A90;margin:25px 0 12px}
.s ul{padding-left:22px;margin:15px 0;font-size:14px}.s li{margin:8px 0}
a{color:#003A90}code{overflow-wrap:anywhere;font-size:.9em}
pre{overflow:auto;background:#08364A;color:#fff;padding:18px;border-radius:10px;font-size:12px;line-height:1.55;margin:18px 0;max-width:100%}
pre code{white-space:pre;overflow-wrap:normal}
.downloads{display:flex;flex-wrap:wrap;gap:10px;margin:22px 0}
.downloads a{background:#003A90;color:#fff;padding:12px 16px;border-radius:8px;text-decoration:none;font-size:13px;font-weight:700}
.nav-title{padding:14px 22px 5px;font-size:12px;font-weight:800;color:#157A9E}
.stamp{display:inline-block;font-size:10px;vertical-align:middle;color:#fff;background:#C1432A;border-radius:4px;padding:3px 6px;margin-left:5px}
.chart-card svg{width:100%;height:auto;display:block}.chart-card figcaption{font-size:11px;color:#546a80;margin-top:12px}
.s{min-width:0}.s .wrap{min-width:0}.table-wrap{max-width:100%}.table-wrap table{min-width:760px}td{vertical-align:top;overflow-wrap:anywhere}
.table-wrap:focus-visible,a:focus-visible,button:focus-visible{outline:3px solid #157A9E;outline-offset:3px}
@media(max-width:700px){header.cd-header img{height:30px}header.cd-header .wrap{gap:10px;padding:10px 14px}.wrap{padding:0 16px}.actor-network-card{padding:14px 12px}.net-wrap{height:320px!important}.scene{padding-bottom:70px}.cover h2{font-size:29px}}
@media print{#nodos-cv{display:none!important}.scene{background:#fff;padding:0}.report-shell{width:100%;border:0;box-shadow:none;background:white}.report-shell:before,.downloads{display:none}.s{break-inside:auto}.table-wrap{overflow:visible}table{min-width:0!important;font-size:9px}pre{white-space:pre-wrap}.actor-network-card{display:none}}
'''


from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
for name, file in [('Arial','arial.ttf'),('Arial-Bold','arialbd.ttf'),('Arial-Italic','ariali.ttf'),('Consolas','consola.ttf')]:
    pdfmetrics.registerFont(TTFont(name, str(Path('C:/Windows/Fonts') / file)))
pdfmetrics.registerFontFamily('Arial', normal='Arial', bold='Arial-Bold', italic='Arial-Italic', boldItalic='Arial-Bold')

BODY = ParagraphStyle('body',fontName='Arial',fontSize=9.1,leading=13.2,textColor=colors.HexColor('#092743'),spaceAfter=8)
H2 = ParagraphStyle('h2',parent=BODY,fontName='Arial-Bold',fontSize=16,leading=20,spaceBefore=18,spaceAfter=11,keepWithNext=True,textColor=colors.HexColor('#003A90'))
H3 = ParagraphStyle('h3',parent=BODY,fontName='Arial-Bold',fontSize=11.3,leading=15,spaceBefore=13,spaceAfter=7,keepWithNext=True)
CELL = ParagraphStyle('cell',parent=BODY,fontSize=7.4,leading=10.1,spaceAfter=0,splitLongWords=True)
HEAD = ParagraphStyle('head',parent=CELL,fontName='Arial-Bold',textColor=colors.white)
CODE = ParagraphStyle('code',fontName='Consolas',fontSize=7.3,leading=10,textColor=colors.HexColor('#08364A'),spaceAfter=10)


class Diagram(Flowable):
    def __init__(self, path, width):
        Flowable.__init__(self)
        self.path = path
        self.width = width
        self.height = width * 960 / 1200
    def draw(self):
        image = ImageReader(str(self.path))
        iw, ih = image.getSize()
        scale = self.width / 1200
        self.canv.saveState()
        clip = self.canv.beginPath()
        clip.rect(0, 0, self.width, self.height)
        self.canv.clipPath(clip, stroke=0)
        self.canv.drawImage(image, 0, self.height-ih*scale, width=iw*scale, height=ih*scale)
        self.canv.restoreState()


def footer(canvas, doc):
    canvas.saveState()
    w,h=A4
    canvas.setFillColor(colors.HexColor('#003A90'))
    canvas.rect(0,h-9,w,9,fill=1,stroke=0)
    canvas.setFont('Arial',7.5)
    canvas.setFillColor(colors.HexColor('#526a80'))
    canvas.drawString(44,28,'Consultora Diagonales | ConDi | 30/10/2026')
    canvas.drawRightString(w-44,28,str(doc.page))
    canvas.restoreState()


def pdf_table(rows, width):
    n=len(rows[0])
    weights = {2:[.3,.7],3:[.26,.39,.35],4:[.2,.29,.27,.24],6:[.06,.19,.10,.17,.14,.34]}.get(n,[1/n]*n)
    data=[]
    for ri,row in enumerate(rows):
        row=row+['']*(n-len(row))
        data.append([Paragraph(inline_pdf(c),HEAD if ri==0 else CELL) for c in row])
    t=Table(data,colWidths=[width*x for x in weights],repeatRows=1,hAlign='LEFT')
    t.setStyle(TableStyle([('BACKGROUND',(0,0),(-1,0),colors.HexColor('#003A90')),('ROWBACKGROUNDS',(0,1),(-1,-1),[colors.white,colors.HexColor('#F1F7FC')]),('VALIGN',(0,0),(-1,-1),'TOP'),('LEFTPADDING',(0,0),(-1,-1),7),('RIGHTPADDING',(0,0),(-1,-1),7),('TOPPADDING',(0,0),(-1,-1),7),('BOTTOMPADDING',(0,0),(-1,-1),7),('LINEBELOW',(0,0),(-1,0),1,colors.HexColor('#009AFE')),('LINEBELOW',(0,1),(-1,-1),.3,colors.HexColor('#DDE7F0'))]))
    return t


def make_pdf(source, filename, subtitle):
    content=(BASE/source).read_text(encoding='utf-8')
    title=blocks(content)[0][2]
    path=PDF_DIR/filename
    doc=SimpleDocTemplate(str(path),pagesize=A4,rightMargin=44,leftMargin=44,topMargin=42,bottomMargin=47,title=title,author='Consultora Diagonales')
    width=A4[0]-88
    story=[Spacer(1,38),Image(str(SKILL/'logo_cd.png'),width=194,height=74),Spacer(1,35),Paragraph('CONDI · GESTIÓN MUNICIPAL',ParagraphStyle('kicker',parent=BODY,fontName='Arial-Bold',fontSize=10,textColor=colors.HexColor('#157A9E'))),Paragraph(inline_pdf(title),ParagraphStyle('title',parent=BODY,fontName='Arial-Bold',fontSize=27,leading=34,spaceAfter=23)),Paragraph(subtitle,ParagraphStyle('sub',parent=BODY,fontSize=13,leading=20)),Spacer(1,25),Paragraph('30 de octubre de 2026<br/>Consultora Diagonales<br/>Versión 1.0',BODY),Spacer(1,24),Paragraph('Documento basado en fuentes públicas oficiales e inspección estática local. Las mejoras y la arquitectura son propuestas; no se modificó ni desplegó la aplicación.',BODY),Spacer(1,20),Paragraph('Paquete complementario: informe HTML navegable, fuentes, evidencia técnica, diagrama editable y backlog.',BODY),PageBreak()]
    started=False
    for b in blocks(content):
        kind=b[0]
        if kind=='heading':
            level,title=b[1:]
            if level==1:continue
            started=True
            story.append(Paragraph(inline_pdf(title),H2 if level==2 else H3))
        elif not started:continue
        elif kind=='paragraph':story.append(Paragraph(inline_pdf(b[1]),BODY))
        elif kind=='list':
            for item in b[1]:story.append(Paragraph('- '+inline_pdf(item),BODY))
        elif kind=='table':story.extend([pdf_table(b[1],width),Spacer(1,12)])
        elif kind=='code':
            lines=[]
            for line in b[1].splitlines():
                lines.extend(textwrap.wrap(line,width=94,replace_whitespace=False,drop_whitespace=False) or [''])
            story.append(Preformatted('\n'.join(lines).replace('→','->').replace('←','<-'),CODE))
        elif kind=='image':
            png=BASE/'evidencia/arquitectura.jpg'
            if png.exists():
                story.append(Diagram(png,width))
                story.append(Paragraph('Modelo propuesto para ConDi. No representa un despliegue existente.',CELL))
            else:story.append(Paragraph('Diagrama editable incluido en arquitectura.svg y arquitectura.mmd.',BODY))
    doc.build(story,onFirstPage=footer,onLaterPages=footer)
    (BASE/'pdf'/filename).write_bytes(path.read_bytes())
    reader=PdfReader(str(path))
    txt='\n'.join(p.extract_text() or '' for p in reader.pages)
    if len(txt)<len(content)*.65:raise RuntimeError(f'Texto incompleto: {filename}')
    print(json.dumps({'pdf':str(path),'pages':len(reader.pages),'characters':len(txt)},ensure_ascii=True))


if __name__=='__main__':
    make_html()
    make_pdf('auditoria.md','auditoria-condi-civicplus.pdf','Comparación funcional, hallazgos y prioridades para evolucionar ConDi hacia un CRM municipal.')
    make_pdf('arquitectura.md','arquitectura-condi-crm.pdf','Modelo de datos, comandos, SLA, permisos, sincronización y plan de migración gradual.')
