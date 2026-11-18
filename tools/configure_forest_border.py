"""Author an irregular outer forest in Room_2_Cenario, preserving the artist's Trees.

Trees_Border holds the new, editable stamps; ForestBase widens the dark ground
under both old and new crowns. Terrain, events, river and other rooms are retained.
"""
from __future__ import annotations

import argparse
from copy import deepcopy
from datetime import datetime
import hashlib
import json
import math
import os
from pathlib import Path
import random
import tempfile
import uuid

from PIL import Image
from configure_ldtk_water import all_levels, editor_busy
from split_ldtk_room2 import composed_layers, reference_bytes, REFERENCE

ROOT = Path(__file__).resolve().parents[1]
BASE_PATH = "assets/tiles/floor/forest_base.png"
BASE_COLOUR = "#25131a"
GENERATED = {"Trees_Border", "ForestBase"}


def stamp_origins(layer: dict) -> list[tuple[int, int, int]]:
    stamps = set()
    for tile in layer["gridTiles"] + layer["autoLayerTiles"]:
        sx, sy = tile["src"]
        flip = int(tile.get("f", 0))
        if flip & 1: sx = 64 - sx
        if flip & 2: sy = 64 - sy
        stamps.add((tile["px"][0] - sx, tile["px"][1] - sy, flip))
    return sorted(stamps, key=lambda p: (p[1] + (10 if p[2] & 2 else 70), p[0]))


def right_depth(y: float) -> float:
    return 176 + 32 * math.sin(y / 241) + 20 * math.cos(y / 97)


def bottom_depth(x: float) -> float:
    return 152 + 32 * math.sin(x / 197) + 24 * math.cos(x / 83)


def register(data: dict, scenery: dict) -> None:
    def uid() -> int:
        number = data["nextUid"]
        data["nextUid"] += 1
        return number

    tree_source = next(t for t in data["defs"]["tilesets"] if t["identifier"] == "Tree_16")
    base_source = next((t for t in data["defs"]["tilesets"] if t["identifier"] == "ForestBase_16"), None)
    if base_source is None:
        base_source = deepcopy(tree_source)
        base_source.update(identifier="ForestBase_16", uid=uid(), relPath=BASE_PATH,
            pxWid=16, pxHei=16, __cWid=1, __cHei=1, tags=["scenery", "forest", "base"],
            savedSelections=[], cachedPixelData=None, customData=[], enumTags=[])
        data["defs"]["tilesets"].append(base_source)
    for name, source, anchor, description in (
        ("ForestBase", base_source, "Leaves", "CENARIO / Base escura da floresta de borda. Grade 16px, Z=-13. Nao cria chao, agua ou colisao; preservar caminhos e acessos."),
        ("Trees_Border", tree_source, "Trees", "CENARIO / Floresta externa, carimbos 80x80. Distribuicao irregular na direita e embaixo ate o rio. Copas completas alem do mapa na Godot; tronco fisico e ordem Y iguais a Trees."),
    ):
        if any(l["identifier"] == name for l in data["defs"]["layers"]):
            raise ValueError("Existing forest layer must be edited manually: " + name)
        definition = deepcopy(next(l for l in data["defs"]["layers"] if l["identifier"] == "Trees"))
        definition.update(identifier=name, uid=uid(), tilesetDefUid=source["uid"], doc=description)
        index = next(i for i, l in enumerate(data["defs"]["layers"]) if l["identifier"] == anchor)
        data["defs"]["layers"].insert(index, definition)
        for level in all_levels(data):
            layer = deepcopy(next(l for l in level["layerInstances"] if l["__identifier"] == "Trees"))
            layer.update(__identifier=name, __tilesetDefUid=source["uid"],
                __tilesetRelPath=source["relPath"], layerDefUid=definition["uid"],
                iid=str(uuid.uuid5(uuid.UUID(level["iid"]), "forest_border:" + name)),
                overrideTilesetUid=None, gridTiles=[], autoLayerTiles=[], intGridCsv=[], entityInstances=[],
                visible=level is scenery)
            index = next(i for i, l in enumerate(level["layerInstances"]) if l["__identifier"] == anchor)
            level["layerInstances"].insert(index, layer)


def convert(data: dict) -> dict:
    before = deepcopy(data)
    levels = all_levels(data)
    primary = next(l for l in levels if l["identifier"] == "Room_2")
    scenery = next(l for l in levels if l["identifier"] == "Room_2_Cenario")
    if any(l["__identifier"] in GENERATED for l in scenery["layerInstances"]):
        return {"changed": False, "reason": "Forest already authored; preserving manual edits."}
    width, height = scenery["pxWid"], scenery["pxHei"]
    columns = width // 16
    art = {l["__identifier"]: l for l in scenery["layerInstances"]}
    original_stamps = stamp_origins(art["Trees"])
    floor = {tuple(t["px"]) for name, layer in art.items()
             if layer["visible"] and (name == "Floor" or name.startswith("Floor_"))
             for t in layer["gridTiles"] + layer["autoLayerTiles"]}
    # Preserve circulation and altar approaches, including the two bridges.
    protected = set()
    for name in ("Floor_Paths", "Floor_Bridges", "TerrainStairs"):
        for tile in art[name]["gridTiles"]:
            x, y = tile["px"]
            for dy in (-16, 0, 16):
                for dx in (-16, 0, 16): protected.add((x + dx, y + dy))
    for layer in primary["layerInstances"]:
        for entity in layer["entityInstances"]:
            if entity["__identifier"] not in {"HordePedestal", "Warp"}: continue
            x = entity["px"][0] - entity["width"] * entity["__pivot"][0]
            y = entity["px"][1] - entity["height"] * entity["__pivot"][1]
            for yy in range(math.floor((y - 24) / 16) * 16, math.ceil((y + entity["height"] + 24) / 16) * 16, 16):
                for xx in range(math.floor((x - 24) / 16) * 16, math.ceil((x + entity["width"] + 24) / 16) * 16, 16):
                    protected.add((xx, yy))

    rng = random.Random(28102026)
    origins = []
    roots = [(x + 40, y + (10 if f & 2 else 70)) for x, y, f in original_stamps]
    for _ in range(22000):
        if rng.random() < 0.48:
            x = rng.randrange((width - 256) // 16, width // 16) * 16
            y = rng.randrange(-4, height // 16) * 16
        else:
            x = rng.randrange(-3, width // 16) * 16
            y = rng.randrange((height - 288) // 16, height // 16) * 16
        rx, ry = x + 40, y + 70
        in_right = rx >= width - right_depth(ry) and ry >= 6
        in_bottom = ry >= height - bottom_depth(rx)
        if not (in_right or in_bottom): continue
        # Project exterior trunks back to the bank to avoid filling the river mouth.
        inland_x = max(64, min(width - 64, rx)) // 16 * 16
        inland_y = max(64, min(height - 64, ry)) // 16 * 16
        if (inland_x, inland_y) not in floor: continue
        if any((xx, yy) in protected for yy in range(y - 16, y + 96, 16) for xx in range(x - 16, x + 96, 16)): continue
        if any((rx - px) ** 2 + (ry - py) ** 2 < 64 ** 2 for px, py in roots): continue
        roots.append((rx, ry))
        origins.append((x, y, rng.randrange(2)))
    origins.sort(key=lambda p: (p[1], p[0]))

    register(data, scenery)
    art = {l["__identifier"]: l for l in scenery["layerInstances"]}
    for x, y, flip in origins:
        for sy in range(0, 80, 16):
            for sx in range(0, 80, 16):
                px, py = x + (64 - sx if flip & 1 else sx), y + sy
                if not (0 <= px < width and 0 <= py < height): continue
                art["Trees_Border"]["gridTiles"].append({"px": [px, py], "src": [sx, sy],
                    "f": flip, "t": sx // 16 + sy // 16 * 5, "d": [px // 16 + py // 16 * columns], "a": 1})

    dark = {(x, y) for x, y in floor if
            (x >= width - right_depth(y) - 48 or y >= height - bottom_depth(x) - 80)}
    # Include the user's existing irregular lower corner, preserving every stamp.
    for x, y, _ in original_stamps + origins:
        for yy in range(y - 16, y + 96, 16):
            for xx in range(x - 16, x + 96, 16):
                if (xx, yy) in floor: dark.add((xx, yy))
    dark.difference_update(protected)
    art["ForestBase"]["gridTiles"] = [{"px": [x, y], "src": [0, 0], "f": 0, "t": 0,
        "d": [x // 16 + y // 16 * columns], "a": 1} for x, y in sorted(dark, key=lambda p: (p[1], p[0]))]

    # Strip the intentional additions: all original authored data must match.
    stripped = deepcopy(data)
    stripped["nextUid"] = before["nextUid"]
    stripped["defs"]["layers"] = [l for l in stripped["defs"]["layers"] if l["identifier"] not in GENERATED]
    stripped["defs"]["tilesets"] = [t for t in stripped["defs"]["tilesets"] if t["identifier"] != "ForestBase_16"]
    for level in all_levels(stripped):
        level["layerInstances"] = [l for l in level["layerInstances"] if l["__identifier"] not in GENERATED]
    assert stripped == before, "Existing authored map changed"
    assert len(stamp_origins(art["Trees_Border"])) == len(origins)
    assert not (dark & protected)
    composed_layers(data, primary)
    return {"changed": True, "new_trees": len(origins), "original_trees": len(original_stamps),
        "exterior_stamps": sum(x < 0 or y < 0 or x + 80 > width or y + 80 > height for x, y, _ in origins),
        "dark_tiles": len(dark), "colour": BASE_COLOUR, "size": [width, height],
        "preserved": "All original layers, entities, river, crossings and rooms"}


def apply(project: Path, dry_run: bool = False) -> dict:
    original = project.read_bytes()
    data = json.loads(original.decode("utf-8-sig"))
    report = convert(data)
    if dry_run or not report["changed"]: return report
    if editor_busy() or project.read_bytes() != original:
        raise RuntimeError("LDtk aberto ou mapa modificado; nenhum mapa sobrescrito.")
    backup_root = project.parent / "ldtk_backups"
    backup_root.mkdir(exist_ok=True)
    backup = backup_root / f"before_forest_border_{datetime.now():%Y%m%d_%H%M%S}_{hashlib.sha256(original).hexdigest()[:12]}.ldtk"
    backup.write_bytes(original)
    image_path = project.parent / BASE_PATH
    if image_path.exists():
        with Image.open(image_path) as existing:
            if existing.size != (16, 16) or set(existing.convert("RGBA").getdata()) != {(37, 19, 26, 255)}:
                raise ValueError("Existing forest base has manual artwork; not overwriting it")
    else:
        Image.new("RGBA", (16, 16), BASE_COLOUR).save(image_path)
    content = json.dumps(data, ensure_ascii=False, indent=2) + "\n"
    if b"\r\n" in original: content = content.replace("\n", "\r\n")
    with tempfile.NamedTemporaryFile(mode="wb", dir=project.parent, prefix=".forest_border_", suffix=".tmp", delete=False) as stream:
        temporary = Path(stream.name)
        stream.write(content.encode("utf-8"))
    try:
        if editor_busy() or project.read_bytes() != original:
            raise RuntimeError("LDtk abriu ou mapa foi modificado durante a preparacao; mapa preservado.")
        os.replace(temporary, project)
    finally:
        temporary.unlink(missing_ok=True)
    (project.parent / REFERENCE).write_bytes(reference_bytes(data, project.parent))
    report["backup"] = str(backup)
    return report


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", type=Path, default=ROOT / "monster_booster.ldtk")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    print(json.dumps(apply(args.project, args.dry_run), ensure_ascii=False))
