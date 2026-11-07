"""Ajusta los grises tenues y comprueba la paleta común de los accesos."""
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def luminance(value):
    rgb = [int(value[i:i + 2], 16) / 255 for i in (1, 3, 5)]
    rgb = [v / 12.92 if v <= .04045 else ((v + .055) / 1.055) ** 2.4 for v in rgb]
    return sum(v * w for v, w in zip(rgb, (.2126, .7152, .0722)))


def contrast(a, b):
    lo, hi = sorted((luminance(a), luminance(b)))
    return (hi + .05) / (lo + .05)


css = ROOT / 'web' / 'admin' / 'styles.css'
replaced = set()


def improve(match):
    color = match[1].lower()
    rgb = [int(color[i:i + 2], 16) for i in (1, 3, 5)]
    if max(rgb) < 180 and max(rgb) - min(rgb) < 80 and contrast(color, '#ffffff') < 4.5:
        replaced.add(color)
        return 'color: #465971'
    return match[0]


text = css.read_text(encoding='utf-8')
updated = re.sub(r'(?<![-\w])color:\s*(#[0-9a-fA-F]{6})(?![0-9a-fA-F])', improve, text)
if text != updated:
    css.write_text(updated, encoding='utf-8')
pairs = [('#14283f', '#f8fafc'), ('#41556b', '#f8fafc'), ('#465971', '#edf6ff'),
         ('#ffffff', '#155bc0'), ('#ffffff', '#1565c0'), ('#ffffff', '#b54708'),
         ('#344b65', '#f1f6fc'), ('#123e77', '#dceafb'), ('#052910', '#2e9d4f'),
         ('#3a1b00', '#f07c00')]
result = [{'texto': a, 'fondo': b, 'contraste': round(contrast(a, b), 2)} for a, b in pairs]
assert all(row['contraste'] >= 4.5 for row in result), result
out = ROOT / 'output' / 'fondos-claros-2026-11-05'
out.mkdir(parents=True, exist_ok=True)
(out / 'contraste.json').write_text(json.dumps(result, indent=2), encoding='utf-8')
print(json.dumps({'grises_corregidos': sorted(replaced), 'contrastes': result}, ensure_ascii=True))
