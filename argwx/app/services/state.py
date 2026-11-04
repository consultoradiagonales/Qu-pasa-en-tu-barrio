"""Estado actual del motor: consenso por partido + alertas SMN + observaciones -> alerta final."""
from collections import defaultdict
from datetime import timedelta

from sqlalchemy import func, select

from app.config import get_settings
from app.engine.consensus import consensus
from app.engine.levels import LABEL, idx, info, max_level
from app.engine.thresholds import level_for
from app.models import Alert, Forecast, Observation
from app.services.municipalities import SECCION_NOMBRE, load_municipalities
from app.services.runs import latest_run, run_info
from app.util import iso, utcnow

WINDOWS = {24: "Próximas 24 h", 48: "De 24 a 48 h", 72: "De 48 a 72 h"}
HAZARD_VERB = {"lluvia": "lluvia", "tormenta": "tormentas", "viento": "viento", "calor": "calor"}
_cache: dict = {"key": None, "value": None}


def weather_level(notes: str | None) -> str:
    """Estado del tiempo observado (texto de la estación): granizo -> Naranja, tormenta -> Amarilla."""
    t = (notes or "").lower()
    return "ORANGE" if "granizo" in t else "YELLOW" if "tormenta" in t else "GREEN"


def observed_level(o: Observation) -> str:
    return max_level(level_for("rain_mm", o.rain_mm_24h), level_for("gust_kmh", o.gust_kmh),
                     level_for("tmax_c", o.temp_c), weather_level(o.notes))


def _overlaps(a: Alert, wf, wt, window: int) -> bool:
    if wf is None or (a.valid_from is None and a.valid_to is None):
        return window == 24
    start_ok = a.valid_from is None or a.valid_from < wt
    end_ok = a.valid_to is None or a.valid_to > wf
    return start_ok and end_ok


def _fmt_values(stats: dict) -> str:
    parts = []
    if "rain_mm" in stats:
        parts.append(f"lluvia {stats['rain_mm']['median']} mm")
    if "gust_kmh" in stats:
        parts.append(f"ráfagas {stats['gust_kmh']['median']} km/h")
    if "tmax_c" in stats:
        parts.append(f"máxima {stats['tmax_c']['median']} °C")
    return ", ".join(parts)


def _entry(m, window, per_model, smn_items, obs, wf, wt, min_agreeing) -> dict:
    cons = consensus(per_model, min_agreeing)
    smn_level = max_level(*(a.level for a in smn_items))
    obs_level = observed_level(obs) if obs is not None else "GREEN"
    final = max_level(cons["level"], smn_level, obs_level)

    basis, drivers = [], []
    if cons["models_analyzed"]:
        n_ag, n = len(cons["agreeing_models"]), cons["models_analyzed"]
        what = HAZARD_VERB.get(cons["hazard"], cons["hazard"]) if cons["hazard"] else "sin fenómenos significativos"
        drivers.append(f"Consenso ARGWX: {LABEL[cons['level']]} ({what}); coinciden {n_ag} de {n} modelos. "
                       f"Mediana: {_fmt_values(cons['stats'])}.")
        if cons["unconfirmed_signal"]:
            s = cons["unconfirmed_signal"]
            drivers.append(f"Señal no confirmada: {LABEL[s['level']]} según {', '.join(s['models'])}.")
    for a in smn_items:
        drivers.append(f"SMN oficial: {a.title}")
    if obs is not None:
        detail = obs.notes if obs.notes and obs.rain_mm_24h is None else f"lluvia 24 h {obs.rain_mm_24h} mm, ráfaga {obs.gust_kmh} km/h"
        drivers.append(f"Observación ({obs.source}): {detail} -> {LABEL[obs_level]}. La observación prevalece sobre el modelo.")
    if obs is not None and obs_level == final and final != "GREEN":
        basis.append("observación")
    if smn_level == final and final != "GREEN":
        basis.append("SMN oficial")
    if cons["level"] == final:
        basis.append("consenso ARGWX")

    if "observación" in basis:
        confidence, conf_label = 1.0, "Observado"
        observed = {"tormenta": weather_level(obs.notes), "lluvia": level_for("rain_mm", obs.rain_mm_24h),
                    "viento": level_for("gust_kmh", obs.gust_kmh), "calor": level_for("tmax_c", obs.temp_c)}
        hazard = max(observed, key=lambda h: idx(observed[h]))
    elif "consenso ARGWX" in basis:
        confidence, conf_label, hazard = cons["consensus"], cons["confidence_label"], cons["hazard"]
    else:
        confidence, conf_label = None, "Oficial SMN"
        hazard = next((a.hazard for a in smn_items if a.level == final), None)

    return {
        "id": m["id"], "name": m["name"], "seccion": m["seccion"], "seccion_nombre": SECCION_NOMBRE[m["seccion"]],
        "conurbano": m["conurbano"], "lat": m["lat"], "lon": m["lon"], **info(final), "hazard": hazard,
        "confidence": confidence, "confidence_label": conf_label,
        "consensus": f"{len(cons['agreeing_models'])}/{cons['models_analyzed']}", "basis": basis,
        "drivers": drivers, "window": WINDOWS[window], "valid_from": iso(wf), "valid_to": iso(wt),
        "values": cons["stats"],
        "argwx": {k: cons[k] for k in ("level", "consensus", "confidence_label", "hazard", "agreeing_models",
                                        "models_analyzed", "unconfirmed_signal", "note")},
        "models": {mod: {**per_model[mod], "level": v["level"], "hazard": v["hazard"]}
                   for mod, v in cons["votes"].items()},
        "smn": [{"level": a.level, "title": a.title, "hazard": a.hazard, "valid_from": iso(a.valid_from),
                 "valid_to": iso(a.valid_to)} for a in smn_items],
        "observation": None if obs is None else {
            "source": obs.source, "observed_at": iso(obs.observed_at), "rain_mm_24h": obs.rain_mm_24h,
            "gust_kmh": obs.gust_kmh, "temp_c": obs.temp_c, "level": obs_level, "notes": obs.notes},
    }


def compute_state(session) -> dict:
    settings = get_settings()
    now = utcnow()
    mrun = latest_run(session, "models")
    mode = mrun.data_mode if mrun else None
    srun = latest_run(session, "smn", mode) if mode else None
    since = now - timedelta(hours=settings.observation_max_age_h)
    obs_filter = [Observation.observed_at >= since] + ([Observation.data_mode == mode] if mode else [])
    obs_max, obs_n = session.execute(select(func.max(Observation.id), func.count(Observation.id))
                                     .where(*obs_filter)).one()
    key = (mrun and mrun.id, srun and srun.id, obs_max, obs_n, now.strftime("%Y%m%d%H") + str(now.minute // 10))
    if _cache["key"] == key:
        return _cache["value"]

    per = defaultdict(lambda: defaultdict(dict))
    valid, models = {}, set()
    if mrun:
        for f in session.scalars(select(Forecast).where(Forecast.run_id == mrun.id)):
            per[f.municipality_id][f.window_h][f.model] = {
                "rain_mm": f.rain_mm, "gust_kmh": f.gust_kmh, "tmax_c": f.tmax_c, "tmin_c": f.tmin_c,
                "weather_code": f.weather_code}
            valid.setdefault(f.window_h, (f.valid_from, f.valid_to))
            models.add(f.model)
    smn_by = defaultdict(list)
    if srun:
        for a in session.scalars(select(Alert).where(Alert.run_id == srun.id)):
            if a.municipality_id:
                smn_by[a.municipality_id].append(a)
    obs_by = {}
    for o in session.scalars(select(Observation).where(*obs_filter).order_by(Observation.observed_at)):
        prev = obs_by.get(o.municipality_id)
        if prev is None or idx(observed_level(o)) >= idx(observed_level(prev)):
            obs_by[o.municipality_id] = o

    windows = {}
    for w, label in WINDOWS.items():
        wf, wt = valid.get(w, (None, None))
        entries = {}
        for m in load_municipalities():
            smn_items = [a for a in smn_by.get(m["id"], []) if _overlaps(a, wf, wt, w)]
            obs = obs_by.get(m["id"]) if w == 24 else None
            entries[m["id"]] = _entry(m, w, per[m["id"]][w], smn_items, obs, wf, wt, settings.min_agreeing_models)
        windows[w] = {"label": label, "valid_from": iso(wf), "valid_to": iso(wt), "municipalities": entries}

    state = {"generated_at": iso(now), "data_mode": mode or "sin_datos", "models": sorted(models),
             "models_run": run_info(mrun), "smn_run": run_info(srun), "windows": windows}
    _cache.update(key=key, value=state)
    return state


def summary(entries: list[dict]) -> dict:
    out = {lv: 0 for lv in ("GREEN", "YELLOW", "ORANGE", "RED", "PURPLE")}
    for e in entries:
        out[e["alert_level"]] += 1
    return out


def zones(state: dict, window: int) -> list[dict]:
    entries = list(state["windows"][window]["municipalities"].values())
    out = []
    for s, name in SECCION_NOMBRE.items():
        es = [e for e in entries if e["seccion"] == s]
        top = max_level(*(e["alert_level"] for e in es))
        out.append({"seccion": s, "nombre": name, "municipios": len(es), **info(top), "por_nivel": summary(es),
                    "en_alerta": sorted(({"id": e["id"], "name": e["name"], "alert_level": e["alert_level"]}
                                         for e in es if e["alert_level"] != "GREEN"),
                                        key=lambda e: (-idx(e["alert_level"]), e["name"]))})
    return out
