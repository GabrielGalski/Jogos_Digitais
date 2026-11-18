"""Undo only the generated river bake, preserving later manual edits.

Also register barrier.png and an EMPTY collision-enabled painting layer.
Never place the barrier or restore the removed stone shoreline.
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
import zipfile

from PIL import Image
from configure_ldtk_water import all_levels, editor_busy
from ldtk_editor_coordinates import synchronize
from split_ldtk_room2 import REFERENCE, reference_bytes, validate

ROOT = Path(__file__).resolve().parents[1]
ART = "assets/tiles/floor/barrier.png"
RETIRED_ATLAS = "assets/tiles/floor/river_ground_atlas.png"
PREVIEW = "RiverWaterPreview"


def level(data: dict, name: str) -> dict:
    return next(l for l in all_levels(data) if l["identifier"] == name)


def layer(room: dict, name: str) -> dict:
    return next(l for l in room["layerInstances"] if l["__identifier"] == name)


def tiles(instance: dict) -> dict:
    return {tuple(t["px"]): t for t in instance["gridTiles"]}


def semantic(tile: dict | None) -> tuple | None:
    if tile is None: return None
    return (tuple(tile["src"]), tile.get("f", 0), tile.get("a", 1), tile.get("t"))


def rollback(data: dict) -> dict:
    scenery = level(data, "Room_2_Cenario")
    current_floor = layer(scenery, "Floor")
    if current_floor["__tilesetRelPath"] != RETIRED_ATLAS:
        return {"river_reverted": False, "already_reverted": True}
    # Reconstruct our own exact generated delta; current-vs-generated is the artist's delta.
    from round_room_2_river import convert as reconstruct_bake
    migration = json.loads((ROOT / "output/rounded_river/migration.json").read_text(encoding="utf-8"))
    original = json.loads(Path(migration["backup"]).read_text(encoding="utf-8-sig"))
    generated = deepcopy(original)
    reconstruct_bake(generated)
    base_room, expected_room = level(original, "Room_2_Cenario"), level(generated, "Room_2_Cenario")
    base = tiles(layer(base_room, "Floor"))
    expected = tiles(layer(expected_room, "Floor"))
    current = tiles(current_floor)
    manual = {p for p in current.keys() | expected.keys() if semantic(current.get(p)) != semantic(expected.get(p))}
    result = deepcopy(current)
    for point in base.keys() | expected.keys():
        if point in manual: continue
        if point in base: result[point] = deepcopy(base[point])
        else: result.pop(point, None)
    # Convert the retained manual painting back to the ordinary solid source.
    for tile in result.values():
        tile.update(src=[0, 0], t=0)
    for key in ["__tilesetDefUid", "__tilesetRelPath", "overrideTilesetUid"]:
        current_floor[key] = layer(base_room, "Floor")[key]
    current_floor["gridTiles"] = [result[p] for p in sorted(result, key=lambda p: (p[1], p[0]))]
    synchronize(scenery, current_floor)
    assert all((p in result) == (p in current) for p in manual), "A manual addition/deletion was overwritten."
    grass = layer(scenery, "Floor_Grass")
    base_grass = tiles(layer(base_room, "Floor_Grass"))
    expected_grass = tiles(layer(expected_room, "Floor_Grass"))
    current_grass = tiles(grass)
    restored_grass = 0
    for point in base_grass.keys() - expected_grass.keys():
        if point not in current_grass and point in result:
            current_grass[point] = deepcopy(base_grass[point])
            restored_grass += 1
    grass["gridTiles"] = [current_grass[p] for p in sorted(current_grass, key=lambda p: (p[1], p[0]))]
    synchronize(scenery, grass)
    data["defs"]["layers"] = [d for d in data["defs"]["layers"] if d["identifier"] != PREVIEW]
    for room in all_levels(data):
        room["layerInstances"] = [l for l in room["layerInstances"] if l["__identifier"] != PREVIEW]
    retired = {t["uid"] for t in data["defs"]["tilesets"] if t["relPath"] == RETIRED_ATLAS}
    assert not any(l.get("__tilesetDefUid") in retired for room in all_levels(data) for l in room["layerInstances"]), "Retired atlas still has authored references."
    data["defs"]["tilesets"] = [t for t in data["defs"]["tilesets"] if t["uid"] not in retired]
    return {"river_reverted": True, "manual_floor_delta_preserved": len(manual),
            "manual_floor_additions_preserved": len(current.keys() - expected.keys()),
            "manual_floor_deletions_preserved": len(expected.keys() - current.keys()),
            "restored_grass": restored_grass, "source_backup": migration["backup"]}


def register_barrier(data: dict) -> dict:
    with Image.open(ROOT / ART) as image:
        width, height = image.size
        bounds = image.convert("RGBA").getbbox()
    assert (width, height) == (112, 32)
    atlas = next((t for t in data["defs"]["tilesets"] if t.get("relPath") == ART), None)
    if atlas is None:
        atlas = deepcopy(next(t for t in data["defs"]["tilesets"] if t["identifier"] == "GroundBase_16"))
        atlas.update(identifier="Barrier_16", uid=data["nextUid"], relPath=ART,
                     pxWid=width, pxHei=height, __cWid=7, __cHei=2, tileGridSize=16,
                     spacing=0, padding=0, cachedPixelData=None, tags=["scenery", "barrier", "solid"],
                     savedSelections=[{"ids": list(range(14)), "mode": "Stamp"},
                                      {"ids": [2, 3, 4, 5, 9, 10, 11, 12], "mode": "Stamp"}],
                     customData=[{"tileId": 0, "data": json.dumps({"piece": "barreira_completa", "stamp_px": [0,0,112,32],
                                   "visible_px": [bounds[0], bounds[1], bounds[2]-bounds[0], bounds[3]-bounds[1]],
                                   "collision": "opaque_alpha", "layer": "Barriers", "placed": False})}])
        data["nextUid"] += 1
        data["defs"]["tilesets"].append(atlas)
    definition = next((l for l in data["defs"]["layers"] if l["identifier"] == "Barriers"), None)
    if definition is None:
        definition = deepcopy(next(l for l in data["defs"]["layers"] if l["identifier"] == "Borders"))
        definition.update(identifier="Barriers", uid=data["nextUid"], gridSize=16, tilesetDefUid=atlas["uid"],
                          doc="LIMITES / Barreira de regioes. barrier.png 112x32; grade 16; carimbo completo 7x2. Pintar em Room_2_Cenario bloqueia Nox por alpha opaco na layer de mundo 1, inclusive dash. Sem duplicar em Gameplay. Cadastro somente: nenhum tile colocado.")
        data["nextUid"] += 1
        i = next(i for i,l in enumerate(data["defs"]["layers"]) if l["identifier"] == "Borders")
        data["defs"]["layers"].insert(i+1, definition)
    for room in all_levels(data):
        instance = next((l for l in room["layerInstances"] if l["__identifier"] == "Barriers"), None)
        if instance is None:
            instance = deepcopy(layer(room, "GroundBase"))
            instance.update(__identifier="Barriers", __gridSize=16, __opacity=1,
                            __pxTotalOffsetX=0, __pxTotalOffsetY=0, pxOffsetX=0, pxOffsetY=0,
                            __tilesetDefUid=atlas["uid"], __tilesetRelPath=ART,
                            layerDefUid=definition["uid"], iid=str(uuid.uuid5(uuid.UUID(room["iid"]), "barriers")),
                            overrideTilesetUid=None, gridTiles=[], autoLayerTiles=[], intGridCsv=[], entityInstances=[],
                            visible=room["identifier"] == "Room_2_Cenario")
            i = next(i for i,l in enumerate(room["layerInstances"]) if l["__identifier"] == "Borders")
            room["layerInstances"].insert(i+1, instance)
            synchronize(room, instance)
        assert not instance["gridTiles"] and not instance["autoLayerTiles"], "Registration must not place a barrier."
    return {"barrier_tileset": atlas["identifier"], "barrier_size": [width,height],
            "barrier_visible_rect": [bounds[0],bounds[1],bounds[2]-bounds[0],bounds[3]-bounds[1]],
            "barrier_grid": 16, "barrier_placed_tiles": 0}


def convert(data: dict) -> dict:
    before = deepcopy(data)
    report = rollback(data)
    report.update(register_barrier(data))
    for old in all_levels(before):
        current = next(l for l in all_levels(data) if l["iid"] == old["iid"])
        for source in old["layerInstances"]:
            name = source["__identifier"]
            if name == PREVIEW or old["identifier"] == "Room_2_Cenario" and name in ["Floor", "Floor_Grass"]: continue
            assert layer(current,name) == source, "Unrelated artist work was modified: " + name
        for key in old:
            if key != "layerInstances": assert current[key] == old[key], "Level metadata or dimensions changed."
    assert all(e["__identifier"] != "RiverBankControl" for r in all_levels(data) for l in r["layerInstances"] for e in l["entityInstances"])
    report.update(validate(data))
    report["stone_tiles"] = len(layer(level(data,"Room_2_Cenario"),"WaterBanks")["gridTiles"])
    report["new_river_proposal_implemented"] = False
    return report


def apply(project: Path, dry_run: bool = False) -> dict:
    original = project.read_bytes()
    before = json.loads(original.decode("utf-8-sig")); after = deepcopy(before)
    report = convert(after)
    repeat = deepcopy(after); convert(repeat); assert repeat == after, "Not idempotent."
    report.update(changed=before != after, dry_run=dry_run, idempotent=True)
    output = ROOT / "output/river_revision"; output.mkdir(exist_ok=True, parents=True)
    if report["changed"] and not dry_run:
        if editor_busy() or project.read_bytes() != original: raise RuntimeError("LDtk aberto ou mapa alterado; original preservado.")
        backup = ROOT / "ldtk_backups" / f"before_river_rollback_barrier_{datetime.now():%Y%m%d_%H%M%S}_{hashlib.sha256(original).hexdigest()[:12]}.ldtk"
        backup.write_bytes(original)
        archive = output / "retired_model.zip"
        names = [RETIRED_ATLAS, RETIRED_ATLAS+".import", "scripts/dungeon/ldtk_river_ground.gd",
                 "scripts/dungeon/ldtk_river_ground.gd.uid", "tools/round_room_2_river.py", "tools/rounded_river_regression.gd",
                 "tools/rounded_river_regression.gd.uid", "docs/RIO_ARREDONDADO.md"]
        with zipfile.ZipFile(archive,"w",compression=zipfile.ZIP_DEFLATED) as stream:
            for name in names:
                if (ROOT/name).exists(): stream.write(ROOT/name,name)
        guide = reference_bytes(after, ROOT)
        content = json.dumps(after,ensure_ascii=False,indent=2)+"\n"
        if b"\r\n" in original: content=content.replace("\n","\r\n")
        with tempfile.NamedTemporaryFile(mode="wb",dir=ROOT,prefix=".river_rollback_",suffix=".tmp",delete=False) as stream:
            temporary=Path(stream.name);stream.write(content.encode("utf-8"))
        try:
            if editor_busy() or project.read_bytes()!=original: raise RuntimeError("Projeto mudou durante a preparacao; original preservado.")
            os.replace(temporary,project)
        finally: temporary.unlink(missing_ok=True)
        (ROOT/REFERENCE).write_bytes(guide)
        report.update(backup=str(backup), retired_model_archive=str(archive))
    (output/("preview.json" if dry_run else "migration.json")).write_text(json.dumps(report,indent=2)+"\n",encoding="utf-8")
    return report


if __name__ == "__main__":
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument("--dry-run",action="store_true")
    args=parser.parse_args();print(json.dumps(apply(ROOT/"monster_booster.ldtk",args.dry_run),indent=2))
