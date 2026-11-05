"""Niveles de alerta. La alerta expresa riesgo, no certeza."""
LEVELS = ("GREEN", "YELLOW", "ORANGE", "RED", "PURPLE")
LABEL = {"GREEN": "Verde", "YELLOW": "Amarilla", "ORANGE": "Naranja", "RED": "Roja", "PURPLE": "Púrpura"}
MEANING = {
    "GREEN": "Sin fenómenos significativos",
    "YELLOW": "Posibles inconvenientes puntuales",
    "ORANGE": "Fenómenos potencialmente peligrosos",
    "RED": "Fenómenos severos",
    "PURPLE": "Evento extremo (granizo severo, inundaciones excepcionales, fenómenos destructivos)",
}
COLOR = {"GREEN": "#2e9d4f", "YELLOW": "#f2c200", "ORANGE": "#f07c00", "RED": "#d62828", "PURPLE": "#7b2cbf"}


def idx(level: str | None) -> int:
    return LEVELS.index(level) if level in LEVELS else 0


def max_level(*levels: str | None) -> str:
    return max((lv for lv in levels if lv in LEVELS), key=idx, default="GREEN")


def parse_level(text: str | None) -> str:
    """Acepta GREEN/YELLOW/... o verde/amarilla/... ."""
    if not text:
        return "GREEN"
    t = text.strip().upper()
    if t in LEVELS:
        return t
    es = {v.upper(): k for k, v in LABEL.items()} | {"AMARILLO": "YELLOW", "ROJO": "RED", "PURPURA": "PURPLE",
                                                    "VIOLETA": "PURPLE"}
    if t in es:
        return es[t]
    raise ValueError(f"Nivel desconocido: {text}")


def info(level: str) -> dict:
    return {"alert_level": level, "alert_label": LABEL[level], "color": COLOR[level], "meaning": MEANING[level]}
