"""Apply the MonsterShift ground to Room_2 without changing gameplay or footprints.

Decoration is hidden, not deleted. Runtime images are copied byte for byte into a
separate source folder so Room_1 and its existing atlases remain independent.
"""
from __future__ import annotations

import argparse
from copy import deepcopy
from datetime import datetime
import hashlib
import json
import os
from pathlib import Path
import shutil
import tempfile

from configure_ldtk_water import all_levels, editor_busy
from split_ldtk_room2 import composed_layers, reference_bytes, REFERENCE

ROOT = Path(__file__).resolve().parents[1]
SOURCE = Path("C:/Projetos/MonsterShift")
ASSETS = "assets/tiles/floor/monstershift"
SOIL = ASSETS + "/texturized_floor_atlas.png"
RIMS = ASSETS + "/floor_tileset2.png"
GROUND_LAYERS = {"Floor", "Floor_Castle", "Floor_Paths", "Floor_Bridges", "TerrainStairs", "TerrainFaces"}


def path_tile(point: tuple[int, int], cells: set[tuple[int, int]]) -> tuple[int, int, int]:
    """Continuous 16 px trail: dark outside rims and small concave corners."""
    x, y = point
    up, right, down, left = ((x, y - 16) in cells, (x + 16, y) in cells,
                             (x, y + 16) in cells, (x - 16, y) in cells)
    if not up and not left: return 0, 0, 0
    if not up and not right: return 6, 0, 0
    if not down and not left: return 0, 2, 0
    if not down and not right: return 6, 2, 0
    if not up: return 1, 0, 0
    if not down: return 1, 2, 0
    if not left: return 0, 1, 0
    if not right: return 6, 1, 0
    for dx, dy, flip in [(-16, -16, 0), (16, -16, 1), (-16, 16, 2), (16, 16, 3)]:
        if (x + dx, y + dy) not in cells:
            return 1, 1, flip
    return 8, 2, 0


def convert_data(data: dict) -> dict:
    room = next(l for l in all_levels(data) if l["identifier"] == "Room_2")
    scenery = next(l for l in all_levels(data) if l["identifier"] == "Room_2_Cenario")
    layers = {l["__identifier"]: l for l in scenery["layerInstances"]}
    definitions = data["defs"]["tilesets"]

    def register(identifier: str, relative: str, width: int, height: int) -> dict:
        found = next((t for t in definitions if t["relPath"] == relative), None)
        if found is not None:
            return found
        found = deepcopy(next(t for t in definitions if t["uid"] == 603))
        found.update(identifier=identifier, uid=data["nextUid"], relPath=relative,
                     pxWid=width, pxHei=height, __cWid=width // 16, __cHei=height // 16,
                     cachedPixelData=None, savedSelections=[], enumTags=[], customData=[])
        data["nextUid"] += 1
        definitions.append(found)
        return found

    soil = register("MonsterShiftSoil_16", SOIL, 512, 512)
    rims = register("MonsterShiftTrail_16", RIMS, 256, 48)
    network = {tuple(t["px"]) for name in ("Floor_Paths", "Floor_Bridges", "TerrainStairs")
               for t in layers[name]["gridTiles"]}
    hidden = []
    for name, layer in layers.items():
        if layer["__type"] not in ("Tiles", "AutoLayer"):
            continue
        if name not in GROUND_LAYERS:
            if layer["gridTiles"] or layer["autoLayerTiles"]:
                hidden.append(name)
            layer["visible"] = False
            continue
        target = soil if name in ("Floor", "Floor_Castle") else rims
        layer.update(__tilesetDefUid=target["uid"], __tilesetRelPath=target["relPath"],
                     overrideTilesetUid=target["uid"], visible=True)
        for tile in layer["gridTiles"] + layer["autoLayerTiles"]:
            x, y = tile["px"]
            flip = 0
            if target is soil:
                # One complete texture repeat per 512 px, with no random tile flips.
                sx, sy = (x // 16) % 32, (y // 16) % 32
            elif name == "TerrainFaces":
                # Structural cliff face: same purple soil palette and dark rim.
                sx, sy = 9 + (x // 16) % 4, 1
            elif name == "TerrainStairs":
                sx, sy, flip = path_tile((x, y), network)
                if sx == 8 and (y // 16) % 2 == 0:
                    sx, sy = 1, 0
            else:
                sx, sy, flip = path_tile((x, y), network)
            tile.update(src=[sx * 16, sy * 16], t=sy * target["__cWid"] + sx, f=flip)

    # Same source palette in the LDtk room model; its authored props remain intact.
    template = next(l for l in all_levels(data) if l["identifier"] == "RoomTemplate_30x16")
    floor = next(l for l in template["layerInstances"] if l["__identifier"] == "Floor")
    floor.update(__tilesetDefUid=soil["uid"], __tilesetRelPath=SOIL, overrideTilesetUid=soil["uid"])
    for tile in floor["gridTiles"] + floor["autoLayerTiles"]:
        x, y = tile["px"]
        sx, sy = (x // 16) % 32, (y // 16) % 32
        tile.update(src=[sx * 16, sy * 16], t=sy * 32 + sx, f=0)
    composed_layers(data, room)
    return {"hidden_decoration_layers": hidden, "soil_tileset": soil["uid"], "trail_tileset": rims["uid"],
            "path_cells": len(network), "ground_layers": sorted(GROUND_LAYERS)}


def apply(source: Path, dry_run: bool = False) -> dict:
    project = ROOT / "monster_booster.ldtk"
    original = project.read_bytes()
    before = json.loads(original.decode("utf-8-sig"))
    after = deepcopy(before)
    result = convert_data(after)
    for old in all_levels(before):
        new = next(l for l in all_levels(after) if l["iid"] == old["iid"])
        if old["identifier"] not in ("Room_2_Cenario", "RoomTemplate_30x16"):
            assert old == new, "Gameplay and unrelated rooms must remain byte-equivalent as JSON."
        for old_layer, new_layer in zip(old["layerInstances"], new["layerInstances"], strict=True):
            assert old_layer["entityInstances"] == new_layer["entityInstances"]
            assert old_layer["intGridCsv"] == new_layer["intGridCsv"]
            assert [t["px"] for t in old_layer["gridTiles"]] == [t["px"] for t in new_layer["gridTiles"]]
    result.update(changed=before != after, dry_run=dry_run)
    if dry_run:
        return result
    if editor_busy() or project.read_bytes() != original:
        raise RuntimeError("LDtk aberto ou mapa alterado: mapa preservado.")
    folder = ROOT / ASSETS
    folder.mkdir(parents=True, exist_ok=True)
    copied = []
    for name in ("texturized_floor.png", "texturized_floor_atlas.png", "floor_tileset2.png", "floor_tileset3.png", "floor_tileset_2.png", "floor_tileset2.ase"):
        source_file = source / "assets/tiles/floor" / name
        target = folder / name
        if target.exists() and target.read_bytes() != source_file.read_bytes():
            raise ValueError("A copia local foi alterada: preservar antes de substituir " + str(target))
        if not target.exists():
            shutil.copyfile(source_file, target)
        copied.append(name)
    if result["changed"]:
        backup_root = ROOT / "ldtk_backups"
        backup_root.mkdir(exist_ok=True)
        backup = backup_root / f"before_monstershift_ground_{datetime.now():%Y%m%d_%H%M%S}_{hashlib.sha256(original).hexdigest()[:12]}.ldtk"
        backup.write_bytes(original)
        content = (json.dumps(after, ensure_ascii=False, indent=2) + "\n").encode("utf-8")
        with tempfile.NamedTemporaryFile(mode="wb", dir=ROOT, prefix=".ground_", suffix=".tmp", delete=False) as file:
            temporary = Path(file.name)
            file.write(content)
        try:
            if editor_busy() or project.read_bytes() != original:
                raise RuntimeError("LDtk abriu ou mapa mudou: mapa preservado.")
            os.replace(temporary, project)
        finally:
            temporary.unlink(missing_ok=True)
        result["backup"] = str(backup)
    reference = reference_bytes(after, ROOT)
    (ROOT / REFERENCE).write_bytes(reference)
    result["copied"] = copied
    return result


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=SOURCE)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    print(json.dumps(apply(args.source, args.dry_run), ensure_ascii=False))
