"""Author the first Room_2 blockout, preserving other levels and the seven altar IIDs.

Reapplying to an already authored Room_2 only validates it: never repaint later edits.
"""
from __future__ import annotations

import argparse
from collections import deque
from copy import deepcopy
from datetime import datetime
import hashlib
import json
import math
import os
from pathlib import Path
import tempfile
import uuid

from PIL import Image
from configure_ldtk_water import all_levels, editor_busy
from ldtk_field_values import set_value
from configure_pedestal_arenas import convert_data as configure_arenas
from split_ldtk_room2 import composed_layers

ROOT = Path(__file__).resolve().parents[1]
NAMESPACE = uuid.UUID("fb93a010-bde0-11f1-87bb-9be959d73132")
GRID = 16
BRIDGES = ((1136, 96), (1808, 96))
RAMPS = ((256, 928, 128, 96), (1088, 928, 160, 96), (1888, 928, 128, 96))


def identity(label: str) -> str:
    return str(uuid.uuid5(NAMESPACE, label))


def fields(entity: dict) -> dict:
    return {f["__identifier"]: f["__value"] for f in entity["fieldInstances"]}


def river_at(y: float) -> tuple[int, int]:
    """Smooth meanders sampled onto the existing 16px grid, across both map ends."""
    axis = 2304 + 68 * math.sin(y / 330) + 36 * math.sin(y / 170 + 0.5)
    width = 224 + 32 * math.sin(y / 430 + 0.8)
    return math.floor((axis - width / 2) / GRID), math.ceil((axis + width / 2) / GRID)


def in_bridge(y: int) -> bool:
    return any(top <= y < top + height for top, height in BRIDGES)


def convert(data: dict) -> dict:
    levels = all_levels(data)
    room = next(l for l in levels if l["identifier"] == "Room_2")
    if any(e["__identifier"] in ("ExplorationRegion", "PedestalArena") for l in room["layerInstances"] for e in l["entityInstances"]):
        configure_arenas(data)
        return validate(data)
    if any(l["gridTiles"] or l["autoLayerTiles"] or any(l["intGridCsv"]) for l in room["layerInstances"]):
        raise ValueError("Room_2 ja possui pintura: esta ferramenta nao sobrescreve autoria posterior.")
    old_altars = [e for l in room["layerInstances"] for e in l["entityInstances"] if e["__identifier"] == "HordePedestal"]
    if len(old_altars) != 7:
        raise ValueError("Esperados os seis altares e o altar central autorais.")
    defs = data["defs"]

    def allocate() -> int:
        value = data["nextUid"]
        data["nextUid"] += 1
        return value

    field_template = deepcopy(defs["entities"][0]["fieldDefs"][0])

    def entity_definition(name: str, color: str, doc: str, specs: list[tuple]) -> dict:
        existing = next((d for d in defs["entities"] if d["identifier"] == name), None)
        if existing:
            return existing
        result = deepcopy(next(d for d in defs["entities"] if d["identifier"] == "SpiritHordeArea"))
        result.update(identifier=name, uid=allocate(), color=color, doc=doc, width=160, height=160,
                      tags=["gameplay"], fieldDefs=[], tileOpacity=0, fillOpacity=0.12, lineOpacity=0.8)
        for key, kind, default, description in specs:
            field = deepcopy(field_template)
            field.update(identifier=key, uid=allocate(), __type=kind, type="F_" + kind,
                         defaultOverride={"id": "V_" + kind, "params": [default]}, doc=description,
                         min=0 if kind in ("Int", "Float") else None, max=None,
                         editorDisplayMode="NameAndValue", editorAlwaysShow=key in ("RegionId", "MonsterCount", "HeightPx"))
            result["fieldDefs"].append(field)
        defs["entities"].append(result)
        return result

    entity_definition("ElevationArea", "#B192D6",
        "TERRENO / Plano elevado. Projeta piso, ator, arma e sombra em HeightPx. Colisao fica em Gameplay.", [
            ("HeightPx", "Int", 24, "Altura visual acima do plano base, em pixels."),
            ("Enabled", "Bool", True, "Habilita este plano elevado."),
        ])
    entity_definition("ElevationRamp", "#E9CF6A",
        "TERRENO / Rampa de 0 ate HeightPx. Tem prioridade sobre ElevationArea. "
        "Direction indica a direcao de SUBIDA; abra a passagem na colisao Gameplay.", [
            ("HeightPx", "Int", 24, "Altura no fim da subida."),
            ("Direction", "String", "North", "North, South, East ou West."),
            ("Enabled", "Bool", True, "Habilita esta transicao de altura."),
        ])

    def tileset(name: str, path: str) -> dict:
        existing = next((d for d in defs["tilesets"] if d["identifier"] == name), None)
        if existing:
            return existing
        with Image.open(ROOT / path) as image:
            width, height = image.size
        entry = deepcopy(defs["tilesets"][0])
        entry.update(identifier=name, uid=allocate(), relPath=path, pxWid=width, pxHei=height,
                     __cWid=width // 16, __cHei=height // 16, tileGridSize=16,
                     cachedPixelData=None, savedSelections=[], customData=[], enumTags=[])
        defs["tilesets"].append(entry)
        return entry

    natural = tileset("NaturalFloor_16", "assets/tiles/floor/floor_tileset3.png")
    castle = tileset("CastleFloor_16", "assets/tiles/floor/floor_tileset2.png")
    stairs = tileset("TerrainStair_16", "assets/tiles/wall/decor/stair.png")
    underside = next(d for d in defs["tilesets"] if d["identifier"] == "PlatformUnderside_16")
    floor_definition = next(d for d in defs["layers"] if d["identifier"] == "Floor")
    layers_to_add = (
        ("TerrainStairs", stairs, "TERRENO / Escadas do relevo, arte existente em cortes de 16px. Z=-15."),
        ("Floor_Bridges", natural, "PISO / Exatamente duas travessias do rio. As celulas sustentam o jogador, Z=-16."),
        ("TerrainFaces", underside, "TERRENO / Face do patamar do castelo; sem suporte caminhavel, Z=-17."),
        ("Floor_Paths", natural, "PISO / Caminhos de pedra ligam os sete altares, rampas e pontes, Z=-18."),
        ("Floor_Castle", castle, "PISO / Castelo superior. HeightPx vem de ElevationArea, Z=-19."),
    )
    for name, source, doc in layers_to_add:
        if any(d["identifier"] == name for d in defs["layers"]):
            continue
        definition = deepcopy(floor_definition)
        definition.update(identifier=name, uid=allocate(), tilesetDefUid=source["uid"], doc=doc)
        defs["layers"].insert(defs["layers"].index(floor_definition), definition)
        for level in levels:
            floor = next(l for l in level["layerInstances"] if l["__identifier"] == "Floor")
            layer = deepcopy(floor)
            layer.update(__identifier=name, __tilesetDefUid=source["uid"], __tilesetRelPath=source["relPath"],
                         layerDefUid=definition["uid"], iid=identity(level["iid"] + ":" + name),
                         overrideTilesetUid=None, gridTiles=[], autoLayerTiles=[], entityInstances=[], intGridCsv=[])
            level["layerInstances"].insert(level["layerInstances"].index(floor), layer)

    gameplay_def = next(d for d in defs["layers"] if d["identifier"] == "GameplayAreas")
    gameplay_def["doc"] += " ElevationArea/ElevationRamp: altura do terreno e acessos."
    layer_by_name = {l["__identifier"]: l for l in room["layerInstances"]}
    by_entity = {d["identifier"]: d for d in defs["entities"]}

    def entity(kind: str, label: str, rect: tuple, values: dict) -> dict:
        definition = by_entity[kind]
        x, y, width, height = rect
        result = {"__identifier": kind, "__grid": [x // GRID, y // GRID],
                  "__pivot": [definition["pivotX"], definition["pivotY"]], "__tags": definition["tags"],
                  "__tile": deepcopy(definition["tileRect"]), "__smartColor": definition["color"],
                  "__worldX": room["worldX"] + x, "__worldY": room["worldY"] + y,
                  "iid": identity(label), "width": width, "height": height, "defUid": definition["uid"],
                  "px": [x, y], "fieldInstances": []}
        for field in definition["fieldDefs"]:
            instance = {"__identifier": field["identifier"], "__type": field["__type"], "defUid": field["uid"], "__tile": None}
            default = field["defaultOverride"]["params"][0]
            set_value(instance, values.get(field["identifier"], default))
            result["fieldInstances"].append(instance)
        return result

    gameplay_areas = layer_by_name["GameplayAreas"]["entityInstances"]
    # Preserve the user's seven instances; only their schematic positions and ambiguous IDs change.
    positions = {
        "17d11640-bde0-11f1-87bb-15c67deeabfb": (1576, 1416, "final_center"),
        "1e345f10-bde0-11f1-87bb-fd6693cc8786": (1448, 2512, "forest_east"),
        "2008d0f0-bde0-11f1-87bb-11ebc5ef8338": (248, 2592, "forest_west"),
        "24462c80-bde0-11f1-87bb-c9fea3b3f526": (2760, 2304, "river_south"),
        "3b18eab0-bde0-11f1-87bb-fdb30d4bbe25": (1240, 376, "castle_east"),
        "3df1ad30-bde0-11f1-87bb-f9a133cc86b4": (2776, 568, "river_north"),
        "419e6180-bde0-11f1-87bb-77024abbd0e6": (312, 392, "castle_west"),
    }
    for altar in old_altars:
        if altar["iid"] not in positions:
            raise ValueError("IID de altar inesperado: preservar alteracao autoral antes de converter.")
        x, y, name = positions[altar["iid"]]
        altar.update(px=[x, y], __grid=[x // GRID, y // GRID], __worldX=room["worldX"] + x, __worldY=room["worldY"] + y)
        for field in altar["fieldInstances"]:
            if field["__identifier"] == "EncounterId":
                set_value(field, "room_2_" + name)
    gameplay_areas.append(entity("Warp", "center_arrival", (1576, 1528, 48, 48),
        {"WarpId": "room_2_center", "IsEntrance": True, "Interact": False, "WhiteRing": False,
         "RequiredCondition": "", "TargetLevel": "", "TargetScene": "", "TargetWarp": "", "RestartGame": False}))
    gameplay_areas.append(entity("ElevationArea", "castle_height", (0, 0, 2304, 960), {"HeightPx": 24}))
    for index, rect in enumerate(RAMPS):
        gameplay_areas.append(entity("ElevationRamp", "castle_ramp_" + str(index), rect, {"HeightPx": 24, "Direction": "North"}))
    layer_by_name["WaterAreas"]["entityInstances"].append(entity("WaterArea", "main_river", (2048, -32, 608, room["pxHei"] + 64),
        {"Preset": "River", "MaskId": "Rectangle", "SurfaceId": "room_2_river"}))

    width = room["pxWid"] // GRID
    height = room["pxHei"] // GRID
    gameplay = layer_by_name["Gameplay"]["intGridCsv"]
    floor = layer_by_name["Floor"]
    floor.update(__tilesetDefUid=natural["uid"], __tilesetRelPath=natural["relPath"], overrideTilesetUid=natural["uid"])
    sources = {t["uid"]: t for t in defs["tilesets"]}
    safe = set()

    def paint(name: str, x: int, y: int, sx: int, sy: int, flip: int = 0):
        layer = layer_by_name[name]
        source = sources[layer["__tilesetDefUid"]]
        grid = source["tileGridSize"]
        layer["gridTiles"].append({"px": [x, y], "src": [sx, sy], "f": flip,
            "t": (sy // grid) * source["__cWid"] + sx // grid, "d": [x // grid + y // grid * layer["__cWid"]]})

    for y in range(3, height - 3):
        left, right = river_at(y * GRID + 8)
        for x in range(3, width - 3):
            if left <= x < right:
                continue
            if x < left and y < 6:
                continue  # Top castle wall; no trapped walkable strip behind it.
            safe.add((x, y))
            selector = (x * 73856093 ^ y * 19349663) & 63
            paint("Floor", x * GRID, y * GRID, (selector % 8) * GRID, (selector // 8) * GRID)
            if y < 60 and x < left:
                paint("Floor_Castle", x * GRID, y * GRID, 32, 16)
            if 60 <= y < 62 and x < left and not any(rx <= x * GRID < rx + rw for rx, ry, rw, rh in RAMPS):
                gameplay[y * width + x] = 6
    # Two and only two decks: wide enough for movement, protected by edge collisions.
    for top, deck_height in BRIDGES:
        for y in range(top // GRID, (top + deck_height) // GRID):
            left, right = river_at(y * GRID + 8)
            for x in range(left - 2, right + 2):
                safe.add((x, y))
                paint("Floor_Bridges", x * GRID, y * GRID, (x % 3) * GRID, 144)
        left = min(river_at(y)[0] for y in range(top, top + deck_height, GRID)) - 1
        right = max(river_at(y)[1] for y in range(top, top + deck_height, GRID)) + 1
        for x in range(left * GRID, right * GRID, 8):
            paint("Borders", x, top - 8, 8, 8)
            paint("Borders", x, top + deck_height, 8, 8)
    # South face of the plateau and its three projected stairways.
    for x in range(3, river_at(968)[0]):
        if any(rx <= x * GRID < rx + rw for rx, ry, rw, rh in RAMPS):
            continue
        paint("TerrainFaces", x * GRID, 936, 32 + (x % 4) * GRID, 0)
        paint("TerrainFaces", x * GRID, 952, 32 + (x % 4) * GRID, 16)
    for rx, ry, rw, rh in RAMPS:
        for row in range(rh // GRID):
            for col in range(rw // GRID):
                sx = 16 if col == 0 else 96 if col == rw // GRID - 1 else 48
                sy = 48 if row == 0 else 96 if row == rh // GRID - 1 else 64 + (row % 2) * GRID
                paint("TerrainStairs", rx + col * GRID, ry + row * GRID, sx, sy)
    # Top castle facade, using the current wall source and physical footprint.
    for x in range(64, 2080, GRID):
        for sy in range(128, 176, 8):
            for sx in (16, 24):
                paint("WallsBack", x + sx - 16, 48 + sy - 128, sx, sy)
        gameplay[5 * width + x // GRID] = 6

    path_cells = set()

    def path(points: list[tuple[int, int]], radius: int = 2):
        for first, last in zip(points, points[1:]):
            distance = math.dist(first, last)
            for step in range(max(1, math.ceil(distance / 8)) + 1):
                t = min(1.0, step * 8 / max(distance, 1))
                cx = round((first[0] + (last[0] - first[0]) * t) / GRID)
                cy = round((first[1] + (last[1] - first[1]) * t) / GRID)
                for dy in range(-radius, radius + 1):
                    for dx in range(-radius, radius + 1):
                        cell = (cx + dx, cy + dy)
                        if cell in safe and (dx * dx + dy * dy <= radius * radius + 1):
                            path_cells.add(cell)

    path([(1576, 1528), (1576, 1416), (1472, 1248), (1168, 1040), (1168, 928), (1240, 376)])
    path([(312, 392), (440, 672), (1168, 752), (1240, 376)])
    path([(440, 672), (320, 928), (320, 1104), (688, 1376), (1576, 1416)])
    path([(1240, 376), (1744, 704), (1952, 928), (1952, 1120), (2180, 1184)])
    path([(1576, 1416), (1904, 1376), (2144, 1184), (2528, 1184), (2720, 944), (2776, 568)])
    path([(1576, 1416), (1680, 1664), (2176, 1856), (2544, 1856), (2760, 2304)])
    path([(1576, 1528), (1344, 1856), (1520, 2176), (1448, 2512)])
    path([(1344, 1856), (944, 2144), (560, 2304), (248, 2592)])
    path([(2776, 568), (2928, 1328), (2832, 1904), (2760, 2304)], 1)
    for x, y in sorted(path_cells, key=lambda c: (c[1], c[0])):
        paint("Floor_Paths", x * GRID, y * GRID, (x % 3) * GRID, 144)
    # Existing foliage establishes the forest silhouette; leave broad traversal lanes.
    for x, y in [(96, 1920), (560, 1936), (992, 2336), (480, 2640), (1824, 2400), (1840, 2704),
                 (2880, 800), (2816, 1568), (2880, 2528), (160, 2240), (736, 2624), (1760, 1936)]:
        for row in range(5):
            for col in range(6):
                px, py = x + col * GRID, y + row * GRID
                if (px // GRID, py // GRID) not in safe or (px // GRID, py // GRID) in path_cells:
                    continue
                paint("Leaves", px, py, 96 + col * GRID, 160 + row * GRID)
    gameplay[(1528 // GRID) * width + 1576 // GRID] = 4
    configure_arenas(data)
    return validate(data)


def validate(data: dict) -> dict:
    room = next(l for l in all_levels(data) if l["identifier"] == "Room_2")
    layers = {l["__identifier"]: l for l in composed_layers(data, room)}
    entities = [e for l in room["layerInstances"] for e in l["entityInstances"]]
    altars = [e for e in entities if e["__identifier"] == "HordePedestal"]
    if len(altars) != 7 or len({fields(e)["EncounterId"] for e in altars}) != 7:
        raise ValueError("Os sete altares precisam de IDs distintos.")
    width = room["pxWid"] // GRID
    solids = { (i % width, i // width) for i, v in enumerate(layers["Gameplay"]["intGridCsv"]) if v in (1, 2, 3, 6, 7) }
    land = {(t["px"][0] // GRID, t["px"][1] // GRID) for name, l in layers.items() if name == "Floor" or name.startswith("Floor_") for t in l["gridTiles"]} - solids
    bridges = {(t["px"][0] // GRID, t["px"][1] // GRID) for t in layers["Floor_Bridges"]["gridTiles"]}

    def reachable(cells: set, start: tuple) -> set:
        found = {start}
        queue = deque([start])
        while queue:
            x, y = queue.popleft()
            for point in ((x-1, y), (x+1, y), (x, y-1), (x, y+1)):
                if point in cells and point not in found:
                    found.add(point)
                    queue.append(point)
        return found

    entrance = next(e for e in entities if e["__identifier"] == "Warp" and fields(e).get("WarpId") == "room_2_center")
    spawn = (entrance["px"][0] // GRID, entrance["px"][1] // GRID)
    connected = reachable(land, spawn)
    if any((e["px"][0] // GRID, e["px"][1] // GRID) not in connected for e in altars):
        raise ValueError("Um altar nao pode ser alcancado a partir do centro.")
    no_bridges = reachable(land - bridges, spawn)
    east = [e for e in altars if fields(e)["EncounterId"] in ("room_2_river_north", "room_2_river_south")]
    if any((e["px"][0] // GRID, e["px"][1] // GRID) in no_bridges for e in east):
        raise ValueError("Existe acesso a margem direita fora das duas pontes.")
    bridge_rows = sorted({y for x, y in bridges})
    groups = []
    for row in bridge_rows:
        if not groups or row != groups[-1][-1] + 1:
            groups.append([])
        groups[-1].append(row)
    if len(groups) != 2:
        raise ValueError("Esperadas exatamente duas pontes separadas.")
    # Either bridge alone must connect all altars; neither may be decorative only.
    for group in groups:
        allowed = (land - bridges) | {(x, y) for x, y in bridges if y in group}
        reached = reachable(allowed, spawn)
        if any((e["px"][0] // GRID, e["px"][1] // GRID) not in reached for e in altars):
            raise ValueError("Uma das pontes nao conecta as duas margens.")
    source_defs = {s["uid"]: s for s in data["defs"]["tilesets"]}
    for layer in layers.values():
        for tile in layer["gridTiles"]:
            source = source_defs[layer["__tilesetDefUid"]]
            x, y = tile["src"]
            if min(x, y) < 0 or x >= source["pxWid"] or y >= source["pxHei"]:
                raise ValueError("Tile fora da fonte: " + layer["__identifier"])
    return {"level": "Room_2", "size": [room["pxWid"], room["pxHei"]], "altars": 7,
            "bridges": len(groups), "ramps": len([e for e in entities if e["__identifier"] == "ElevationRamp"]),
            "arenas": len([e for e in entities if e["__identifier"] == "PedestalArena"]),
            "walkable_cells": len(land), "connected_altars": True, "right_bank_requires_bridge": True}


def configure(project: Path, dry_run: bool = False) -> dict:
    original = project.read_bytes()
    before = json.loads(original.decode("utf-8-sig"))
    after = deepcopy(before)
    report = convert(after)
    changed = after != before
    # Every existing layer/entity/tile outside Room_2 must stay byte-for-byte equivalent as data.
    for old, new in zip(all_levels(before), all_levels(after), strict=True):
        if old["identifier"] == "Room_2":
            continue
        old_layers = {l["iid"]: l for l in old["layerInstances"]}
        if any(l != old_layers[l["iid"]] for l in new["layerInstances"] if l["iid"] in old_layers):
            raise ValueError("Conteudo fora da Room_2 foi alterado.")
    report.update(changed=changed, dry_run=dry_run)
    if not changed or dry_run:
        return report
    if editor_busy() or project.read_bytes() != original:
        raise RuntimeError("LDtk aberto ou mapa alterado durante a autoria; arquivo preservado.")
    backup_root = project.parent / "ldtk_backups"
    backup_root.mkdir(exist_ok=True)
    backup = backup_root / f"before_room_2_{datetime.now():%Y%m%d_%H%M%S}_{hashlib.sha256(original).hexdigest()[:12]}.ldtk"
    backup.write_bytes(original)
    with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", dir=project.parent, prefix=".room2_", suffix=".tmp", delete=False) as stream:
        temporary = Path(stream.name)
        json.dump(after, stream, ensure_ascii=False, indent=2)
        stream.write("\n")
    try:
        if editor_busy() or project.read_bytes() != original:
            raise RuntimeError("Mapa mudou durante a autoria; arquivo preservado.")
        os.replace(temporary, project)
    finally:
        temporary.unlink(missing_ok=True)
    report["backup"] = str(backup)
    return report


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", type=Path, default=ROOT / "monster_booster.ldtk")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    print(json.dumps(configure(args.project, args.dry_run), ensure_ascii=False))
