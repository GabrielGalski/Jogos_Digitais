"""Separate Room_2 gameplay/effects from tiles, preserving their local coordinates.

The optional editor reference is a rendering of authored tiles, not runtime art.
Reapplying preserves both levels; --refresh-reference updates only the guide PNG.
"""
from __future__ import annotations

import argparse
from copy import deepcopy
from datetime import datetime
import hashlib
from io import BytesIO
import json
import os
from pathlib import Path
import tempfile
import uuid

from PIL import Image
from configure_ldtk_water import all_levels, editor_busy
from ldtk_field_values import set_value

ROOT = Path(__file__).resolve().parents[1]
PRIMARY = "Room_2"
SCENERY = "Room_2_Cenario"
REFERENCE = "assets/tiles/editor/room_2_cenario_reference.png"
TILE_TYPES = {"Tiles", "AutoLayer"}


def scenery_name(level: dict) -> str:
    return next((str(f.get("__value") or "").strip() for f in level.get("fieldInstances", [])
                 if f["__identifier"] == "SceneryLevel"), "")


def has_content(layer: dict) -> bool:
    return bool(layer.get("entityInstances") or layer.get("gridTiles") or layer.get("autoLayerTiles") or any(layer.get("intGridCsv", [])))


def composed_layers(data: dict, primary: dict) -> list[dict]:
    name = scenery_name(primary)
    if not name:
        return primary["layerInstances"]
    scenery = next((l for l in all_levels(data) if l["identifier"] == name), None)
    if scenery is None:
        raise ValueError("Cenario ausente: " + name)
    if scenery_name(scenery) or (primary["pxWid"], primary["pxHei"]) != (scenery["pxWid"], scenery["pxHei"]):
        raise ValueError("Cenario encadeado ou dimensoes divergentes: " + name)
    art = {l["__identifier"]: l for l in scenery["layerInstances"] if l["__type"] in TILE_TYPES}
    if any(has_content(l) for l in scenery["layerInstances"] if l["__type"] not in TILE_TYPES):
        raise ValueError("Entidades e IntGrid devem ficar no level de gameplay.")
    result = []
    for layer in primary["layerInstances"]:
        if layer["__type"] in TILE_TYPES:
            if has_content(layer):
                raise ValueError("Tiles devem ficar no level de cenario: " + layer["__identifier"])
            source = art.pop(layer["__identifier"])
            if source["__gridSize"] != layer["__gridSize"]:
                raise ValueError("Grades divergentes: " + layer["__identifier"])
            result.append(source)
        else:
            result.append(layer)
    if art:
        raise ValueError("Camadas sem par no gameplay: " + ", ".join(art))
    return result


def convert_data(data: dict) -> dict:
    levels = all_levels(data)
    primary = next(l for l in levels if l["identifier"] == PRIMARY)
    if scenery_name(primary):
        return validate(data)
    if any(l["identifier"] == SCENERY for l in levels):
        raise ValueError("Ja existe Room_2_Cenario sem vinculo; nao sobrescrever.")
    original_layers = deepcopy(primary["layerInstances"])
    original_entities = [deepcopy(e) for l in original_layers for e in l["entityInstances"]]
    original_tiles = {l["__identifier"]: deepcopy((l["gridTiles"], l["autoLayerTiles"])) for l in original_layers if l["__type"] in TILE_TYPES}

    def allocate() -> int:
        value = data["nextUid"]
        data["nextUid"] += 1
        return value

    field = next((f for f in data["defs"]["levelFields"] if f["identifier"] == "SceneryLevel"), None)
    if field is None:
        field = deepcopy(next(f for e in data["defs"]["entities"] for f in e["fieldDefs"] if f["__type"] == "String"))
        field.update(identifier="SceneryLevel", uid=allocate(), __type="String", type="F_String",
            defaultOverride={"id": "V_String", "params": [""]},
            doc="COMPOSICAO / Nome do level que fornece os tiles deste mapa. Gameplay/Entities/IntGrid ficam aqui. "
                "Os dois levels precisam das mesmas dimensoes e grade. Origem usada no jogo: coordenadas locais (0,0). "
                "Vazio mantem o carregamento de um unico level.",
            min=None, max=None, editorDisplayMode="NameAndValue", editorAlwaysShow=True)
        data["defs"]["levelFields"].append(field)
    for level in levels:
        instance = next((f for f in level["fieldInstances"] if f["__identifier"] == "SceneryLevel"), None)
        if instance is None:
            instance = {"__identifier": "SceneryLevel", "__type": "String", "defUid": field["uid"], "__tile": None}
            set_value(instance, "")
            level["fieldInstances"].append(instance)
    set_value(next(f for f in primary["fieldInstances"] if f["__identifier"] == "SceneryLevel"), SCENERY)
    scenery = deepcopy(primary)
    scenery_uid = allocate()
    scenery_iid = str(uuid.uuid5(uuid.UUID(primary["iid"]), "scenery_level"))
    scenery.update(identifier=SCENERY, uid=scenery_uid, iid=scenery_iid, useAutoIdentifier=False,
        worldX=primary["worldX"] + primary["pxWid"] + 320, __smartColor="#816A86", __neighbours=[],
        bgRelPath=None, bgPos=None, __bgPos=None)
    set_value(next(f for f in scenery["fieldInstances"] if f["__identifier"] == "SceneryLevel"), "")
    primary_layers, scenery_layers = [], []
    for layer in primary["layerInstances"]:
        if layer["__type"] in TILE_TYPES:
            # Move the authored tile-layer identity along with its content.
            art = deepcopy(layer)
            art["levelId"] = scenery_uid
            scenery_layers.append(art)
            empty = deepcopy(layer)
            empty.update(iid=str(uuid.uuid5(uuid.UUID(primary["iid"]), "empty:" + layer["__identifier"])),
                         gridTiles=[], autoLayerTiles=[], entityInstances=[], intGridCsv=[], visible=False)
            primary_layers.append(empty)
        else:
            primary_layers.append(layer)
            empty = deepcopy(layer)
            empty.update(iid=str(uuid.uuid5(uuid.UUID(scenery_iid), layer["__identifier"])),
                         levelId=scenery_uid, entityInstances=[], gridTiles=[], autoLayerTiles=[], visible=False)
            if empty["intGridCsv"]:
                empty["intGridCsv"] = [0] * len(empty["intGridCsv"])
            scenery_layers.append(empty)
    primary["layerInstances"] = primary_layers
    scenery["layerInstances"] = scenery_layers
    primary.update(useAutoIdentifier=False, bgRelPath=REFERENCE, bgPos="Unscaled", bgPivotX=0.0, bgPivotY=0.0,
                   __bgPos={"topLeftPx": [0, 0], "scale": [1, 1], "cropRect": [0, 0, primary["pxWid"], primary["pxHei"]]})
    collection = data["levels"]
    if primary not in collection:
        collection = next(w["levels"] for w in data["worlds"] if primary in w["levels"])
    collection.insert(collection.index(primary) + 1, scenery)
    assert [e for l in primary_layers for e in l["entityInstances"]] == original_entities
    assert {l["__identifier"]: (l["gridTiles"], l["autoLayerTiles"]) for l in scenery_layers if l["__type"] in TILE_TYPES} == original_tiles
    for old, composed in zip(original_layers, composed_layers(data, primary), strict=True):
        normalized = deepcopy(composed)
        normalized["levelId"] = old["levelId"]
        assert normalized == old
    return validate(data)


def validate(data: dict) -> dict:
    primary = next(l for l in all_levels(data) if l["identifier"] == PRIMARY)
    layers = composed_layers(data, primary)
    if scenery_name(primary) != SCENERY:
        raise ValueError("Room_2 precisa apontar para Room_2_Cenario.")
    scenery = next(l for l in all_levels(data) if l["identifier"] == SCENERY)
    return {"gameplay_level": PRIMARY, "scenery_level": SCENERY,
            "size": [primary["pxWid"], primary["pxHei"]],
            "entities": sum(len(l["entityInstances"]) for l in primary["layerInstances"]),
            "tiles": sum(len(l["gridTiles"]) + len(l["autoLayerTiles"]) for l in scenery["layerInstances"]),
            "composed_layers": len(layers), "reference": primary.get("bgRelPath")}


def reference_bytes(data: dict, project_root: Path) -> bytes:
    primary = next(l for l in all_levels(data) if l["identifier"] == PRIMARY)
    scenery = next(l for l in all_levels(data) if l["identifier"] == scenery_name(primary))
    definitions = {d["uid"]: d for d in data["defs"]["tilesets"]}
    images = {}
    stamps = {}
    canvas = Image.new("RGBA", (primary["pxWid"], primary["pxHei"]), primary["__bgColor"])
    for layer in reversed(scenery["layerInstances"]):
        if not layer.get("visible", True) or layer["__type"] not in TILE_TYPES:
            continue
        source_uid = layer["__tilesetDefUid"]
        if source_uid is None:
            continue
        definition = definitions[source_uid]
        if source_uid not in images:
            path = (project_root / definition["relPath"]).resolve()
            if not path.is_relative_to(project_root.resolve()):
                raise ValueError("PNG fora do projeto")
            images[source_uid] = Image.open(path).convert("RGBA")
        grid = definition["tileGridSize"]
        for tile in layer["autoLayerTiles"] + layer["gridTiles"]:
            sx, sy = tile["src"]
            flip = int(tile.get("f", 0))
            opacity = float(layer.get("__opacity", 1)) * float(tile.get("a", 1))
            key = (source_uid, sx, sy, flip, opacity)
            if key not in stamps:
                stamp = images[source_uid].crop((sx, sy, sx + grid, sy + grid))
                if flip & 1: stamp = stamp.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
                if flip & 2: stamp = stamp.transpose(Image.Transpose.FLIP_TOP_BOTTOM)
                if opacity < 1: stamp.putalpha(stamp.getchannel("A").point(lambda value: round(value * opacity)))
                stamps[key] = stamp
            x, y = tile["px"]
            x += int(layer.get("__pxTotalOffsetX", 0))
            y += int(layer.get("__pxTotalOffsetY", 0))
            canvas.alpha_composite(stamps[key], (x, y))
    output = BytesIO()
    canvas.save(output, format="PNG", optimize=True)
    return output.getvalue()


def split(project: Path, dry_run: bool = False, refresh_reference: bool = False) -> dict:
    original = project.read_bytes()
    before = json.loads(original.decode("utf-8-sig"))
    data = deepcopy(before)
    report = convert_data(data)
    changed = data != before
    # Other levels keep every authored layer and entity; only a default empty field is added.
    for old in all_levels(before):
        if old["identifier"] == PRIMARY:
            continue
        new = next(l for l in all_levels(data) if l["iid"] == old["iid"])
        stripped = deepcopy(new)
        old_fields = {f["defUid"] for f in old["fieldInstances"]}
        stripped["fieldInstances"] = [f for f in new["fieldInstances"] if f["defUid"] in old_fields]
        if stripped != old:
            raise ValueError("A divisao tentou alterar outro level: " + old["identifier"])
    report.update(changed=changed, dry_run=dry_run)
    if dry_run:
        return report
    reference_path = project.parent / REFERENCE
    write_reference = changed or refresh_reference or not reference_path.is_file()
    if not changed and not write_reference:
        return report
    if editor_busy() or project.read_bytes() != original:
        raise RuntimeError("LDtk aberto ou mapa alterado; nenhum arquivo sobrescrito.")
    png = reference_bytes(data, project.parent) if write_reference else None
    if changed:
        backup_root = project.parent / "ldtk_backups"
        backup_root.mkdir(exist_ok=True)
        backup = backup_root / f"before_room2_split_{datetime.now():%Y%m%d_%H%M%S}_{hashlib.sha256(original).hexdigest()[:12]}.ldtk"
        backup.write_bytes(original)
        with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", dir=project.parent, prefix=".room2_split_", suffix=".tmp", delete=False) as stream:
            temporary = Path(stream.name)
            json.dump(data, stream, ensure_ascii=False, indent=2)
            stream.write("\n")
        try:
            if editor_busy() or project.read_bytes() != original:
                raise RuntimeError("LDtk abriu ou mapa mudou durante a divisao; mapa preservado.")
            reference_path.parent.mkdir(exist_ok=True, parents=True)
            if png is not None:
                reference_path.write_bytes(png)
            os.replace(temporary, project)
        finally:
            temporary.unlink(missing_ok=True)
        report["backup"] = str(backup)
    elif png is not None:
        reference_path.parent.mkdir(exist_ok=True, parents=True)
        reference_path.write_bytes(png)
    report["reference_updated"] = write_reference
    return report


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", type=Path, default=ROOT / "monster_booster.ldtk")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--refresh-reference", action="store_true")
    args = parser.parse_args()
    print(json.dumps(split(args.project, args.dry_run, args.refresh_reference), ensure_ascii=False))
