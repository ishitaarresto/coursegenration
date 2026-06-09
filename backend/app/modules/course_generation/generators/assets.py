"""Free illustration/icon fetcher using the Iconify API.

Iconify hosts 200k+ vector icons. We bias toward COLORFUL flat-illustration
sets so scenes look like professional explainer videos (Renderforest-style).
SVGs are cached locally and embedded inline into the animation HTML, so the
Playwright recording never depends on the network mid-render.
"""
from __future__ import annotations

import json
import urllib.parse
import urllib.request
from pathlib import Path

# Colorful illustration sets, in priority order (best-looking first).
COLOR_SETS = [
    "streamline-kameleon-color",
    "streamline-plump-color",
    "fluent-emoji",
    "fluent-emoji-flat",
    "noto",
    "openmoji",
    "flat-color-icons",
    "twemoji",
    "streamline-color",
    "emojione",
]

# Line/outline sets for the whiteboard style (drawable strokes).
LINE_SETS = [
    "streamline",
    "tabler",
    "mdi-light",
    "ph",
    "ic",  # material outline
]

_CACHE = Path("media") / "assets"
_CACHE.mkdir(parents=True, exist_ok=True)

_UA = {"User-Agent": "Mozilla/5.0 (LMS asset fetcher)"}


def _http_json(url: str, timeout: int = 20):
    req = urllib.request.Request(url, headers=_UA)
    return json.loads(urllib.request.urlopen(req, timeout=timeout).read())


def _http_text(url: str, timeout: int = 20) -> str:
    req = urllib.request.Request(url, headers=_UA)
    return urllib.request.urlopen(req, timeout=timeout).read().decode("utf-8")


def search_icon(query: str, prefer_color: bool = True) -> str | None:
    """Return the best Iconify icon id (e.g. 'fluent-emoji:fire') for a query."""
    sets = COLOR_SETS if prefer_color else LINE_SETS
    try:
        url = "https://api.iconify.design/search?query=" + urllib.parse.quote(query) + "&limit=60"
        data = _http_json(url)
    except Exception:
        return None
    icons = data.get("icons", [])
    # Prefer icons from our nice sets, in set-priority order.
    for s in sets:
        for ic in icons:
            if ic.startswith(s + ":"):
                return ic
    # Fallback: any colorful-looking result, else first result.
    return icons[0] if icons else None


def fetch_svg(icon_id: str, color: str | None = None) -> str | None:
    """Fetch an icon's SVG markup (cached).

    Iconify applies `color` only to monochrome icons; multicolor illustration
    sets ignore it. So it's always safe to pass a theme color.
    """
    if not icon_id:
        return None
    safe = icon_id.replace(":", "__") + (f"__{color.lstrip('#')}" if color else "")
    cache_file = _CACHE / f"{safe}.svg"
    if cache_file.exists():
        return cache_file.read_text(encoding="utf-8")

    prefix, _, name = icon_id.partition(":")
    url = f"https://api.iconify.design/{prefix}/{name}.svg?height=400"
    if color:
        url += "&color=" + urllib.parse.quote(color)
    try:
        svg = _http_text(url)
        if "<svg" not in svg:
            return None
        cache_file.write_text(svg, encoding="utf-8")
        return svg
    except Exception:
        return None


def get_illustration(query: str, color: str = "#2563eb", line: bool = False) -> str:
    """Search + fetch SVG for a topic. Tries the phrase, then the last word.

    Monochrome icons get recolored with `color`; colorful sets keep their art.
    Returns '' if nothing found (caller should show an emoji fallback).
    """
    for q in (query, query.split()[-1] if query.split() else query):
        icon_id = search_icon(q, prefer_color=not line)
        if icon_id:
            svg = fetch_svg(icon_id, color=color)
            if svg:
                return svg
    return ""
