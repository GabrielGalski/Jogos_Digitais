"""Register the authored bridge atlas and assemble two independent river spans.

Bridge decorations never supply Floor support. The command integrates the road
widening and grass fringe in one backed-up, atomic LDtk update.
"""
from __future__ import annotations

import argparse
from copy import deepcopy
from datetime import datetime
import hashlib
import json
import os
from pathlib import Path
import tempfile
import uuid

from PIL import Image
from configure_ldtk_water import all_levels, editor_busy
from split_ldtk_room2 import composed_layers, reference_bytes, REFERENCE

ROOT = Path(__file__).resolve().parents[1]
ART = "assets/bridge/bridge_all.png"
PARTS = {
    "Bridge_BackRail": "CENARIO / Ponte: guarda-corpo de tras. Ordenacao Y e colisao longitudinal na Godot; entradas laterais abertas.",
    "Bridge_FrontRail": "CENARIO / Ponte: guarda-corpo frontal sobre os atores; ordenacao Y e colisao longitudinal na Godot.",
    "Bridge_Facade": "CENARIO / Ponte: arco e pilares sobre a agua. Apenas visual, sem suporte de chao; bases recebem submersao animada na Godot.",
}
SPANS = ((2544, 1392, 288, 64), (2464, 2224, 320, 80))


def painted_spans(layers: dict) -> list[tuple[int, int, int, int]]:
    remaining = {tuple(t["px"]) for t in layers["Floor_Bridges"]["gridTiles"]}
    result = []
    while remaining:
        pending = [remaining.pop()]
        component = set(pending)
        while pending:
            x, y = pending.pop()
            for dx, dy in ((0, 16), (0, -16), (16, 0), (-16, 0)):
                point = (x + dx, y + dy)
                if point in remaining:
                    remaining.remove(point)
                    component.add(point)
                    pending.append(point)
        left, top = min(x for x, _ in component), min(y for _, y in component)
        width, height = max(x for x, _ in component) - left + 16, max(y for _, y in component) - top + 16
        if len(component) != width // 16 * height // 16:
            raise ValueError("As pontes deste atlas precisam de um deck retangular completo.")
        result.append((left, top, width, height))
    return sorted(result, key=lambda bounds: bounds[1])


def connect_approaches(data: dict) -> dict:
    """Join the existing horizontal road paint to the resized bridge end caps."""
    room = next(l for l in all_levels(data) if l["identifier"] == "Room_2")
    layers = {l["__identifier"]: l for l in composed_layers(data, room)}
    roads = {tuple(t["px"]) for t in layers["Floor_Paths"]["gridTiles"]}
    floor = {tuple(t["px"]) for t in layers["Floor"]["gridTiles"]}
    added = set()
    for x, y, width, height in painted_spans(layers):
        for cy in range(y, y + min(height, 64), 16):
            for direction, edge in ((-1, x), (1, x + width - 16)):
                nearby = next((edge + direction * distance for distance in range(16, 81, 16)
                               if (edge + direction * distance, cy) in roads), None)
                if nearby is None:
                    raise ValueError("A ponte precisa de uma aproximacao existente em cada margem.")
                first, last = sorted((edge + direction * 16, nearby))
                for cx in range(first, last + 16, 16):
                    point = (cx, cy)
                    if point in roads:
                        continue
                    if point not in floor:
                        raise ValueError("A aproximacao da ponte invadiu agua sem piso autoral.")
                    added.add(point)
    layer = layers["Floor_Paths"]
    source = next(s for s in data["defs"]["tilesets"] if s["uid"] == layer["__tilesetDefUid"])
    for x, y in sorted(added, key=lambda p: (p[1], p[0])):
        layer["gridTiles"].append({"px": [x, y], "src": [128, 32], "f": 0,
                                  "t": 2 * source["__cWid"] + 8,
                                  "d": [y // 16 * layer["__cWid"] + x // 16], "a": 1})
    return {"added_land_cells": len(added), "no_new_river_support": True}


def clear_road_bushes(data: dict) -> dict:
    """Move only a lower bush footprint hit by the new road edge, by one tile."""
    room = next(l for l in all_levels(data) if l["identifier"] == "Room_2")
    layers = composed_layers(data, room)
    roads = {tuple(t["px"]) for l in layers if l["__identifier"] == "Floor_Paths" for t in l["gridTiles"]}
    floor = {tuple(t["px"]) for l in layers if l["__identifier"] == "Floor" for t in l["gridTiles"]}
    sources = {s["uid"] for s in data["defs"]["tilesets"] if s.get("relPath", "").endswith("/bush.png")}

    def obstructed(x: int, y: int) -> bool:
        return any(x + 2 < cx + 16 and cx < x + 30 and y + 8 < cy + 16 and cy < y + 32
                   for cx, cy in roads)

    moved = []
    for layer in layers:
        if layer["__tilesetDefUid"] not in sources or not layer.get("visible", True):
            continue
        stamps = {}
        for part in layer["gridTiles"]:
            sx, sy = part["src"]
            flip = part.get("f", 0)
            ox = part["px"][0] - (16 - sx if flip & 1 else sx)
            oy = part["px"][1] - (16 - sy if flip & 2 else sy)
            stamps.setdefault((ox, oy, flip), []).append(part)
        occupied = {tuple(t["px"]) for t in layer["gridTiles"]}
        for (x, y, _flip), parts in stamps.items():
            if not obstructed(x, y):
                continue
            if len(parts) != 4:
                raise ValueError("Revisar manualmente arbusto parcial junto ao novo caminho.")
            old_cells = {tuple(p["px"]) for p in parts}
            target = next(((x + dx, y + dy, dx, dy) for dx, dy in ((0, 16), (16, 0), (-16, 0), (0, -16))
                           if not obstructed(x + dx, y + dy)
                           and {(px + dx, py + dy) for px, py in old_cells} <= floor
                           and not ({(px + dx, py + dy) for px, py in old_cells} & (occupied - old_cells))), None)
            if target is None:
                raise ValueError("Arbusto bloqueando caminho precisa de revisao de distribuicao.")
            nx, ny, dx, dy = target
            for part in parts:
                part["px"][0] += dx
                part["px"][1] += dy
                part["d"] = [part["px"][1] // 16 * layer["__cWid"] + part["px"][0] // 16]
            occupied.difference_update(old_cells)
            occupied.update((px + dx, py + dy) for px, py in old_cells)
            moved.append({"before": [x, y], "after": [nx, ny], "reason": "lower footprint intersects widened road"})
    return {"moved": moved, "all_other_paint_preserved": True}


def tile(layer: dict, x: int, y: int, sx: int, sy: int) -> dict:
    return {"px": [x, y], "src": [sx, sy], "f": 0, "t": sy // 16 * 9 + sx // 16,
            "d": [y // 16 * layer["__cWid"] + x // 16], "a": 1}


def convert(data: dict, root: Path = ROOT) -> dict:
    levels = all_levels(data)
    scenery = next(l for l in levels if l["identifier"] == "Room_2_Cenario")
    layers = {l["__identifier"]: l for l in scenery["layerInstances"]}
    definitions = data["defs"]
    with Image.open(root / ART) as image:
        if image.size != (144, 112):
            raise ValueError("bridge_all precisa conservar o atlas autoral 144x112, sem reescala.")
    source = next((s for s in definitions["tilesets"] if s.get("relPath") == ART), None)
    if source and layers["Floor_Bridges"]["__tilesetDefUid"] == source["uid"] and all(n in layers for n in PARTS):
        return {"changed": False, "reason": "Atlas already applied; retaining later authored bridge edits."}
    if source is None:
        source = deepcopy(next(s for s in definitions["tilesets"] if s["identifier"] == "Bush_16"))
        source.update(identifier="Bridge_All_16", uid=data["nextUid"], relPath=ART,
                      pxWid=144, pxHei=112, __cWid=9, __cHei=7, tileGridSize=16,
                      tags=["scenery", "bridge"], enumTags=[], customData=[], cachedPixelData=None,
                      savedSelections=[{"ids": list(range(9, 63)), "mode": "Stamp"},
                                       {"ids": list(range(18, 36)), "mode": "Stamp"},
                                       {"ids": list(range(45, 63)), "mode": "Stamp"}])
        data["nextUid"] += 1
        definitions["tilesets"].append(source)
    deck_definition = next(d for d in definitions["layers"] if d["identifier"] == "Floor_Bridges")
    previous_uid = deck_definition["tilesetDefUid"]
    deck_definition.update(tilesetDefUid=source["uid"], doc="CENARIO / Ponte: somente piso caminhavel, com atlas Bridge_All_16. Guarda-corpos e apoios usam camadas Bridge_ separadas.")
    for level in levels:
        deck = next(l for l in level["layerInstances"] if l["__identifier"] == "Floor_Bridges")
        if level is not scenery and (deck["gridTiles"] or deck["autoLayerTiles"]):
            deck["overrideTilesetUid"] = deck["__tilesetDefUid"] or previous_uid
        else:
            deck.update(__tilesetDefUid=source["uid"], __tilesetRelPath=ART, overrideTilesetUid=None)
    template = next(d for d in definitions["layers"] if d["identifier"] == "Trees")
    for name, description in PARTS.items():
        definition = next((d for d in definitions["layers"] if d["identifier"] == name), None)
        if definition is None:
            definition = deepcopy(template)
            definition.update(identifier=name, uid=data["nextUid"], tilesetDefUid=source["uid"], doc=description)
            data["nextUid"] += 1
            index = definitions["layers"].index(deck_definition)
            definitions["layers"].insert(index, definition)
            for level in levels:
                instance = deepcopy(next(l for l in level["layerInstances"] if l["__identifier"] == "Trees"))
                instance.update(__identifier=name, __tilesetDefUid=source["uid"], __tilesetRelPath=ART,
                                layerDefUid=definition["uid"], iid=str(uuid.uuid5(uuid.UUID(level["iid"]), name)),
                                gridTiles=[], autoLayerTiles=[], entityInstances=[], intGridCsv=[], overrideTilesetUid=None,
                                visible=level is scenery)
                index = next(i for i, l in enumerate(level["layerInstances"]) if l["__identifier"] == "Floor_Bridges")
                level["layerInstances"].insert(index, instance)
        layers[name] = next(l for l in scenery["layerInstances"] if l["__identifier"] == name)
    deck = layers["Floor_Bridges"]
    deck.update(gridTiles=[], autoLayerTiles=[])
    for name in PARTS:
        layers[name].update(gridTiles=[], autoLayerTiles=[])
    report = []
    for x, y, width, height in SPANS:
        columns, rows = width // 16, height // 16
        facade_columns = [0, 1, 2, 3] + [4] * (columns - 8) + [5, 6, 7, 8]
        for col in range(columns):
            wx = x + col * 16
            cap = 0 if col == 0 else 8 if col == columns - 1 else 1 + (col - 1) % 7
            rail = 0 if col == 0 else 8 if col == columns - 1 else 1 if col % 2 else 2
            for row in range(rows):
                deck["gridTiles"].append(tile(deck, wx, y + row * 16, cap * 16, 32 + row % 2 * 16))
            for name, wy, sy in (("Bridge_BackRail", y - 16, 16), ("Bridge_FrontRail", y + height, 64)):
                layers[name]["gridTiles"].append(tile(layers[name], wx, wy, rail * 16, sy))
            for row in range(2):
                layers["Bridge_Facade"]["gridTiles"].append(tile(layers["Bridge_Facade"], wx, y + height + 16 + row * 16,
                                                                 facade_columns[col] * 16, 80 + row * 16))
        report.append({"deck_rect": [x, y, width, height], "walkable_rows": rows,
                       "art_rect": [x, y - 16, width, height + 64], "facade_waterline_y": y + height + 32})
    return {"changed": True, "atlas": ART, "atlas_grid": [9, 7], "bridges": report,
            "decorations_supply_floor": False, "source_png_unchanged": True}


def apply(project: Path, dry_run: bool) -> dict:
    from widen_room_2_paths import convert as widen
    from complete_room_2_grass_borders import convert as fringe
    original = project.read_bytes()
    before = json.loads(original.decode("utf-8-sig"))
    data = deepcopy(before)
    report = {"paths": widen(data, project.parent, rebuild_borders=False), "bridges": convert(data, project.parent)}
    report["approaches"] = connect_approaches(data)
    report["road_bushes"] = clear_road_bushes(data)
    report["grass_fringe"] = fringe(data, project.parent)
    report.update(changed=data != before, dry_run=dry_run)
    # Floor, unrelated scenery and every other room's old content stay authored.
    for old_level in all_levels(before):
        new_level = next(l for l in all_levels(data) if l["iid"] == old_level["iid"])
        if old_level["identifier"] != "Room_2":
            if old_level["fieldInstances"] != new_level["fieldInstances"]:
                raise AssertionError("Unexpected level field change")
        for old_layer in old_level["layerInstances"]:
            if old_level["identifier"] == "Room_2_Cenario" and old_layer["__identifier"] in ("Floor_Paths", "Floor_GrassBorders", "Floor_Bridges", "Bushes"):
                continue
            if old_level["identifier"] == "Room_2" and old_layer["__type"] == "Entities":
                continue
            new_layer = next(l for l in new_level["layerInstances"] if l["iid"] == old_layer["iid"])
            for key in ("gridTiles", "autoLayerTiles", "entityInstances", "intGridCsv"):
                if new_layer[key] != old_layer[key]:
                    raise AssertionError((old_level["identifier"], old_layer["__identifier"], key))
    if dry_run or not report["changed"]:
        return report
    if editor_busy() or project.read_bytes() != original:
        raise RuntimeError("LDtk aberto ou arquivo alterado durante a operacao; nada sobrescrito.")
    backup_dir = project.parent / "ldtk_backups"
    backup_dir.mkdir(exist_ok=True)
    backup = backup_dir / f"before_bridges_paths_{datetime.now():%Y%m%d_%H%M%S}_{hashlib.sha256(original).hexdigest()[:12]}.ldtk"
    backup.write_bytes(original)
    content = json.dumps(data, ensure_ascii=False, indent=2) + "\n"
    if b"\r\n" in original:
        content = content.replace("\n", "\r\n")
    reference = reference_bytes(data, project.parent)
    with tempfile.NamedTemporaryFile(dir=project.parent, prefix=".bridges_", suffix=".tmp", delete=False) as stream:
        stream.write(content.encode("utf-8"))
        pending = Path(stream.name)
    os.replace(pending, project)
    (project.parent / REFERENCE).write_bytes(reference)
    report["backup"] = str(backup)
    return report


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    result = apply(ROOT / "monster_booster.ldtk", args.dry_run)
    output = ROOT / "output" / "pontes"
    output.mkdir(parents=True, exist_ok=True)
    (output / ("preview.json" if args.dry_run else "aplicacao.json")).write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(result, ensure_ascii=False, indent=2))
