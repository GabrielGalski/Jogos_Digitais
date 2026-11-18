"""Replace Room_2_Cenario art with the saved Room_2 art, then clear source tiles.

Entities and IntGrid in Room_2 remain exact. Source art is copied verbatim,
including opacity, visibility, offsets and atlas choice. No terrain is repainted.
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

from configure_ldtk_water import all_levels, editor_busy
from ldtk_field_values import set_value
from split_ldtk_room2 import REFERENCE, reference_bytes, validate

ROOT = Path(__file__).resolve().parents[1]
ART_TYPES = {"Tiles", "AutoLayer"}


def convert(data: dict) -> dict:
    primary = next(level for level in all_levels(data) if level["identifier"] == "Room_2")
    scenery = next(level for level in all_levels(data) if level["identifier"] == "Room_2_Cenario")
    source_art = [layer for layer in primary["layerInstances"] if layer["__type"] in ART_TYPES]
    total = sum(len(layer["gridTiles"]) + len(layer["autoLayerTiles"]) for layer in source_art)
    support = sum(len(layer["gridTiles"]) + len(layer["autoLayerTiles"]) for layer in source_art
                  if layer["__identifier"] == "Floor" or layer["__identifier"].startswith("Floor_"))
    if total == 0:
        raise ValueError("Room_2 ainda tem zero tiles no arquivo salvo. Nenhuma camada foi apagada.")
    if support == 0:
        raise ValueError("Room_2 ainda nao tem as camadas de piso. Fonte incompleta; nada apagado.")
    expected = deepcopy(source_art)
    gameplay_before = deepcopy([layer for layer in primary["layerInstances"] if layer["__type"] not in ART_TYPES])
    old_art = {layer["layerDefUid"]: layer for layer in scenery["layerInstances"] if layer["__type"] in ART_TYPES}
    if set(old_art) != {layer["layerDefUid"] for layer in source_art}:
        raise ValueError("As camadas dos dois levels precisam compartilhar as mesmas definicoes.")
    rebuilt = []
    for source in primary["layerInstances"]:
        if source["__type"] in ART_TYPES:
            destination = deepcopy(source)
            destination.update(iid=old_art[source["layerDefUid"]]["iid"], levelId=scenery["uid"])
            rebuilt.append(destination)
            source.update(gridTiles=[], autoLayerTiles=[], entityInstances=[], intGridCsv=[], visible=False)
        else:
            destination = deepcopy(next(layer for layer in scenery["layerInstances"] if layer["layerDefUid"] == source["layerDefUid"]))
            destination.update(gridTiles=[], autoLayerTiles=[], entityInstances=[], visible=False)
            if destination["intGridCsv"]:
                destination["intGridCsv"] = [0] * len(destination["intGridCsv"])
            rebuilt.append(destination)
    scenery["layerInstances"] = rebuilt
    scenery.update(pxWid=primary["pxWid"], pxHei=primary["pxHei"], bgColor=primary["bgColor"],
                   __bgColor=primary["__bgColor"], bgRelPath=None, bgPos=None, __bgPos=None)
    for instance in scenery["fieldInstances"]:
        if instance["__identifier"] == "SceneryLevel":
            set_value(instance, "")
    set_value(next(field for field in primary["fieldInstances"] if field["__identifier"] == "SceneryLevel"), "Room_2_Cenario")
    primary.update(bgRelPath=REFERENCE, bgPos="Unscaled", bgPivotX=0.0, bgPivotY=0.0,
                   __bgPos={"topLeftPx": [0, 0], "scale": [1, 1],
                            "cropRect": [0, 0, primary["pxWid"], primary["pxHei"]]})
    actual = [layer for layer in rebuilt if layer["__type"] in ART_TYPES]
    for wanted, copied in zip(expected, actual, strict=True):
        normalized = deepcopy(copied)
        normalized.update(iid=wanted["iid"], levelId=wanted["levelId"])
        assert normalized == wanted, "Source artwork changed during transfer."
    assert gameplay_before == [layer for layer in primary["layerInstances"] if layer["__type"] not in ART_TYPES], "Gameplay changed."
    report = validate(data)
    report.update(transferred_tiles=total, support_tiles=support,
                  source="saved Room_2", destination="Room_2_Cenario", exact_art_copy=True,
                  gameplay_preserved=True, reference_updated=True,
                  layers=[{"name": layer["__identifier"], "tiles": len(layer["gridTiles"]) + len(layer["autoLayerTiles"]),
                           "visible": layer["visible"], "offset": [layer["pxOffsetX"], layer["pxOffsetY"]]}
                          for layer in actual])
    return report


def rebuild(project: Path, apply: bool = False) -> dict:
    original = project.read_bytes()
    before = json.loads(original.decode("utf-8-sig"))
    after = deepcopy(before)
    report = convert(after)
    for old in all_levels(before):
        if old["identifier"] not in ["Room_2", "Room_2_Cenario"]:
            assert old == next(level for level in all_levels(after) if level["iid"] == old["iid"])
    assert before["defs"] == after["defs"], "Definitions must not change."
    report.update(applied=apply, input_sha256=hashlib.sha256(original).hexdigest())
    if apply:
        if editor_busy() or project.read_bytes() != original:
            raise RuntimeError("LDtk aberto ou arquivo modificado. Transferencia preparada, original preservado.")
        guide = reference_bytes(after, project.parent)
        backup = project.parent / "ldtk_backups" / f"before_room2_scenery_replace_{datetime.now():%Y%m%d_%H%M%S}_{hashlib.sha256(original).hexdigest()[:12]}.ldtk"
        backup.write_bytes(original)
        content = json.dumps(after, ensure_ascii=False, indent=2) + "\n"
        if b"\r\n" in original:
            content = content.replace("\n", "\r\n")
        with tempfile.NamedTemporaryFile(dir=project.parent, prefix=".rebuild_scenery_", suffix=".tmp", mode="wb", delete=False) as stream:
            temporary = Path(stream.name)
            stream.write(content.encode("utf-8"))
        try:
            if editor_busy() or project.read_bytes() != original:
                raise RuntimeError("Mapa mudou durante a transferencia; original preservado.")
            os.replace(temporary, project)
        finally:
            temporary.unlink(missing_ok=True)
        (project.parent / REFERENCE).write_bytes(guide)
        report["backup"] = str(backup)
    folder = project.parent / "output/room2_scenery_rebuild"
    folder.mkdir(exist_ok=True, parents=True)
    (folder / ("applied.json" if apply else "preview.json")).write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return report


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()
    print(json.dumps(rebuild(ROOT / "monster_booster.ldtk", args.apply), ensure_ascii=False, indent=2))
