"""Register new 16px floor/scenery atlases in LDtk, preserving authored levels.

By default adds definitions only. --with-layers also creates dedicated empty
painting layers, paired between gameplay/scenery. Never repaints existing layers.
Reapplying is a no-op. A backup precedes the atomic map replacement.
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

ROOT = Path(__file__).resolve().parents[1]
ATLASES = (
    ("Grass_16", "assets/tiles/floor/grass_tileset.png", ["floor", "grass"]),
    ("GrassBorder_16", "assets/tiles/floor/grass_border_tileset.png", ["floor", "grass", "border"]),
    ("Path_16", "assets/tiles/floor/path_tileset.png", ["floor", "path"]),
    ("Tree_16", "assets/tiles/floor/tree.png", ["scenery", "tree"]),
)


def add_painting_layers(data: dict) -> list[int]:
    added = []
    definitions = data["defs"]["layers"]
    template = next(l for l in definitions if l["identifier"] == "Floor")
    for name, source_name, description in (
        ("Floor_StonePaths", "Path_16", "PISO / Caminhos de pedra novos, grade 16px. Pintar em Room_2_Cenario. Z=-17."),
        ("Floor_GrassBorders", "GrassBorder_16", "PISO / Bordas e transicoes de grama, grade 16px. Pintar em Room_2_Cenario. Z=-18."),
        ("Floor_Grass", "Grass_16", "PISO / Grama e variacoes do chao, grade 16px. Pintar em Room_2_Cenario. Z=-19."),
        ("Trees", "Tree_16", "CENARIO / Arvores 80x80, carimbo 5x5 em grade 16px. Pintar em Room_2_Cenario. Godot: base fisica 24x12 em (40,70), copa livre e ordem Y pela base (40,74)."),
    ):
        tileset = next(t for t in data["defs"]["tilesets"] if t["identifier"] == source_name)
        existing = next((l for l in definitions if l["identifier"] == name), None)
        if existing:
            if existing["tilesetDefUid"] != tileset["uid"]:
                raise ValueError("Existing painting layer uses another authored tileset: " + name)
            continue
        definition = deepcopy(template)
        definition.update(identifier=name, uid=data["nextUid"], tilesetDefUid=tileset["uid"],
                          doc=description, hideInList=False, gridSize=16)
        data["nextUid"] += 1
        anchor = "Leaves" if name == "Trees" else "Floor_Paths"
        index = next(i for i, l in enumerate(definitions) if l["identifier"] == anchor)
        definitions.insert(index, definition)
        added.append(definition["uid"])
        for level in all_levels(data):
            floor = next(l for l in level["layerInstances"] if l["__identifier"] == "Floor")
            layer = deepcopy(floor)
            layer.update(__identifier=name, __tilesetDefUid=tileset["uid"],
                         __tilesetRelPath=tileset["relPath"], layerDefUid=definition["uid"],
                         iid=str(uuid.uuid5(uuid.UUID(level["iid"]), "floor_painting:" + name)),
                         overrideTilesetUid=None, gridTiles=[], autoLayerTiles=[],
                         entityInstances=[], intGridCsv=[], optionalRules=[],
                         visible=level["identifier"] == "Room_2_Cenario")
            index = next(i for i, l in enumerate(level["layerInstances"]) if l["__identifier"] == anchor)
            level["layerInstances"].insert(index, layer)
    return added


def convert(data: dict, with_layers: bool = False) -> dict:
    original = deepcopy(data)
    definitions = data["defs"]["tilesets"]
    added = []
    registered = []
    for name, relative, tags in ATLASES:
        with Image.open(ROOT / relative) as image:
            width, height = image.size
            image.verify()
        if width % 16 or height % 16:
            raise ValueError("Atlas is not aligned to 16px: " + relative)
        matches = [t for t in definitions if str(t.get("relPath", "")).replace("\\", "/").casefold() == relative.casefold()]
        if len(matches) > 1:
            raise ValueError("Duplicate atlas definitions: " + relative)
        if matches:
            entry = matches[0]
            if (entry["pxWid"], entry["pxHei"], entry["tileGridSize"]) != (width, height, 16):
                raise ValueError("Existing atlas has authored settings; not replacing: " + relative)
        else:
            if any(t["identifier"] == name for t in definitions):
                raise ValueError("Tileset name belongs to another file: " + name)
            entry = deepcopy(next(t for t in definitions if t["identifier"] == "MonsterShiftTrail_16"))
            entry.update(identifier=name, uid=data["nextUid"], relPath=relative,
                         pxWid=width, pxHei=height, __cWid=width // 16, __cHei=height // 16,
                         tileGridSize=16, padding=0, spacing=0, embedAtlas=None,
                         tags=tags, tagsSourceEnumUid=None, enumTags=[], customData=[],
                         savedSelections=[], cachedPixelData=None)
            if name == "Tree_16":
                entry["savedSelections"] = [{"ids": list(range((width // 16) * (height // 16))), "mode": "Stamp"}]
            data["nextUid"] += 1
            definitions.append(entry)
            added.append(entry["uid"])
        registered.append(dict(name=entry["identifier"], uid=entry["uid"], path=relative,
                               size=[width, height], grid=16, cells=[width // 16, height // 16]))
    new_layers = add_painting_layers(data) if with_layers else []
    stripped = deepcopy(data)
    stripped["defs"]["tilesets"] = [t for t in stripped["defs"]["tilesets"] if t["uid"] not in added]
    stripped["defs"]["layers"] = [l for l in stripped["defs"]["layers"] if l["uid"] not in new_layers]
    for level in all_levels(stripped):
        level["layerInstances"] = [l for l in level["layerInstances"] if l["layerDefUid"] not in new_layers]
    stripped["nextUid"] = original["nextUid"]
    if stripped != original:
        raise AssertionError("Registration altered existing authored data")
    return dict(changed=bool(added or new_layers), added=added, added_layers=new_layers,
                tilesets=registered, authored_levels_preserved=True)


def register(project: Path, dry_run: bool = False, with_layers: bool = False) -> dict:
    original = project.read_bytes()
    data = json.loads(original.decode("utf-8-sig"))
    report = convert(data, with_layers)
    report["dry_run"] = dry_run
    if dry_run or not report["changed"]:
        return report
    if editor_busy() or project.read_bytes() != original:
        raise RuntimeError("LDtk open or map changed; no map overwritten")
    folder = project.parent / "ldtk_backups"
    folder.mkdir(exist_ok=True)
    backup = folder / f"before_floor_tilesets_{datetime.now():%Y%m%d_%H%M%S}_{hashlib.sha256(original).hexdigest()[:12]}.ldtk"
    backup.write_bytes(original)
    content = json.dumps(data, ensure_ascii=False, indent=2) + "\n"
    if b"\r\n" in original:
        content = content.replace("\n", "\r\n")
    with tempfile.NamedTemporaryFile(mode="wb", dir=project.parent, prefix=".floor_tilesets_", suffix=".tmp", delete=False) as stream:
        temporary = Path(stream.name)
        stream.write(content.encode("utf-8"))
    try:
        if editor_busy() or project.read_bytes() != original:
            raise RuntimeError("LDtk opened or map changed while preparing registration")
        os.replace(temporary, project)
    finally:
        temporary.unlink(missing_ok=True)
    report["backup"] = str(backup)
    return report


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", type=Path, default=ROOT / "monster_booster.ldtk")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--with-layers", action="store_true")
    args = parser.parse_args()
    print(json.dumps(register(args.project, args.dry_run, args.with_layers), ensure_ascii=False))
