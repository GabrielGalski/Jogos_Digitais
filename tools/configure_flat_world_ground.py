"""Give Room_2 a solid lowest layer while retaining its river and walkable cells."""
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
COLOUR = "#533048"
TEXTURE = "assets/tiles/floor/ground_base.png"


def convert(data: dict) -> dict:
    before = deepcopy(data)
    levels = all_levels(data)
    main = next(l for l in levels if l["identifier"] == "Room_2")
    art = next(l for l in levels if l["identifier"] == "Room_2_Cenario")
    if any(l["__identifier"] == "GroundBase" for l in art["layerInstances"]):
        return {"changed": False, "reason": "Solid base already authored; preserving manual edits."}
    original_floor = deepcopy(next(l for l in art["layerInstances"] if l["__identifier"] == "Floor"))
    width, height = art["pxWid"], art["pxHei"]
    columns, rows = width // 16, height // 16

    def uid() -> int:
        number = data["nextUid"]
        data["nextUid"] += 1
        return number

    source = deepcopy(next(t for t in data["defs"]["tilesets"] if t["identifier"] == "ForestBase_16"))
    source.update(identifier="GroundBase_16", uid=uid(), relPath=TEXTURE, tags=["scenery", "ground", "solid_colour"],
        customData=[], savedSelections=[], cachedPixelData=None)
    data["defs"]["tilesets"].append(source)
    definition = deepcopy(next(l for l in data["defs"]["layers"] if l["identifier"] == "ForestBase"))
    definition.update(identifier="GroundBase", uid=uid(), tilesetDefUid=source["uid"],
        doc="FUNDO / Base uniforme #533048 cobrindo todo o mapa. Camada inferior, Z=-90: abaixo da agua. Nao define piso caminhavel ou colisoes. As sombras das arvores sao geradas na Godot.")
    # Remove the dark band completely, including its empty paired instances.
    data["defs"]["layers"] = [l for l in data["defs"]["layers"] if l["identifier"] != "ForestBase"]
    data["defs"]["tilesets"] = [t for t in data["defs"]["tilesets"] if t["identifier"] != "ForestBase_16"]
    data["defs"]["layers"].append(definition)
    for level in levels:
        template = deepcopy(next(l for l in level["layerInstances"] if l["__identifier"] == "ForestBase"))
        level["layerInstances"] = [l for l in level["layerInstances"] if l["__identifier"] != "ForestBase"]
        template.update(__identifier="GroundBase", __tilesetDefUid=source["uid"], __tilesetRelPath=TEXTURE,
            layerDefUid=definition["uid"], iid=str(uuid.uuid5(uuid.UUID(level["iid"]), "ground_base")),
            visible=level is art, gridTiles=[], autoLayerTiles=[], overrideTilesetUid=None)
        if level is art:
            template["gridTiles"] = [{"px": [x * 16, y * 16], "src": [0, 0], "f": 0, "t": 0,
                "d": [x + y * columns], "a": 1} for y in range(rows) for x in range(columns)]
        level["layerInstances"].append(template)
    for level in (main, art):
        level["__bgColor"] = COLOUR
        level["bgColor"] = COLOUR
    floor = next(l for l in art["layerInstances"] if l["__identifier"] == "Floor")
    floor.update(__tilesetDefUid=source["uid"], __tilesetRelPath=TEXTURE, overrideTilesetUid=source["uid"])
    for tile in floor["gridTiles"] + floor["autoLayerTiles"]:
        tile.update(src=[0, 0], f=0, t=0)
    castle = next(l for l in art["layerInstances"] if l["__identifier"] == "Floor_Castle")
    assert {tuple(t["px"]) for t in castle["gridTiles"]} <= {tuple(t["px"]) for t in floor["gridTiles"]}
    castle["visible"] = False  # Covered by the same elevated Floor; retain the old paint for reference.
    assert [t["px"] for t in floor["gridTiles"]] == [t["px"] for t in original_floor["gridTiles"]]
    for old in all_levels(before):
        new = next(l for l in levels if l["iid"] == old["iid"])
        for old_layer in old["layerInstances"]:
            name = old_layer["__identifier"]
            if name == "ForestBase" or (old["identifier"] == "Room_2_Cenario" and name in {"Floor", "Floor_Castle"}): continue
            assert old_layer == next(l for l in new["layerInstances"] if l["__identifier"] == name), name
        if old["identifier"] not in {"Room_2", "Room_2_Cenario"}:
            stripped = deepcopy(new)
            stripped["layerInstances"] = [l for l in stripped["layerInstances"] if l["__identifier"] != "GroundBase"]
            stripped_old = deepcopy(old)
            stripped_old["layerInstances"] = [l for l in old["layerInstances"] if l["__identifier"] != "ForestBase"]
            assert stripped == stripped_old
    composed_layers(data, main)
    return {"changed": True, "base_tiles": columns * rows, "land_tiles": len(floor["gridTiles"]),
        "colour": COLOUR, "size": [width, height], "walkable_geometry_preserved": True,
        "trees_and_entities_preserved": True, "dark_band_removed": True}


def apply(project: Path, dry_run: bool) -> dict:
    original = project.read_bytes()
    data = json.loads(original.decode("utf-8-sig"))
    report = convert(data)
    if dry_run or not report["changed"]: return report
    if editor_busy() or project.read_bytes() != original:
        raise RuntimeError("LDtk aberto ou mapa modificado; nenhum mapa sobrescrito.")
    backup_root = project.parent / "ldtk_backups"
    backup_root.mkdir(exist_ok=True)
    backup = backup_root / f"before_flat_ground_{datetime.now():%Y%m%d_%H%M%S}_{hashlib.sha256(original).hexdigest()[:12]}.ldtk"
    backup.write_bytes(original)
    image_path = project.parent / TEXTURE
    if image_path.exists():
        with Image.open(image_path) as image:
            assert image.size == (16, 16) and set(image.convert("RGBA").getdata()) == {(83, 48, 72, 255)}
    else:
        Image.new("RGBA", (16, 16), COLOUR).save(image_path)
    content = json.dumps(data, ensure_ascii=False, indent=2) + "\n"
    if b"\r\n" in original: content = content.replace("\n", "\r\n")
    with tempfile.NamedTemporaryFile(mode="wb", dir=project.parent, prefix=".flat_ground_", suffix=".tmp", delete=False) as stream:
        temporary = Path(stream.name)
        stream.write(content.encode("utf-8"))
    try:
        if editor_busy() or project.read_bytes() != original:
            raise RuntimeError("LDtk abriu ou mapa mudou; mapa preservado.")
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
