"""Initialize one RiverMask from today's banks, preserving every authored layer.

The mask is the river's authoring data, not an atlas. Reapplying never repaints it.
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

from configure_ldtk_water import all_levels, editor_busy
from split_ldtk_room2 import validate
from study_room_2_river import survey

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "monster_booster.ldtk"


def convert(data: dict, original: bytes) -> dict:
    before = deepcopy(data)
    definition = next((d for d in data["defs"]["layers"] if d["identifier"] == "RiverMask"), None)
    if definition is not None:
        return {"changed": False, "reason": "RiverMask already exists; retaining all author edits.", **validate(data)}
    mapping, room, _layers = survey(data, original)
    definition = deepcopy(next(d for d in data["defs"]["layers"] if d["identifier"] == "Gameplay"))
    definition.update(identifier="RiverMask", uid=data["nextUid"], uiColor="#1D8193", displayOpacity=0.8,
                      inactiveOpacity=0.3, intGridValues=[{"value": 1, "identifier": "River", "color": "#1D8193", "tile": None, "groupUid": 0}],
                      intGridValuesGroups=[], autoRuleGroups=[], autoSourceLayerDefUid=None,
                      doc="AGUA / Forma logica unica do rio. 1=canal. Inicializada pelas margens atuais, sem mover Floor, barreiras ou pontes. Godot gera curvas limitadas a 8px da pintura, espuma e bloqueio; cliff oeste preservado. Editar no Room_2; Room_2_Cenario continua contendo os assets. Manter um trecho continuo por linha e as duas travessias.")
    data["nextUid"] += 1
    index = next(i for i, d in enumerate(data["defs"]["layers"]) if d["identifier"] == "WaterAreas")
    data["defs"]["layers"].insert(index, definition)
    water_cells = {(x // 16, row["y"] // 16) for row in mapping["profile"] for x in range(row["west"], row["east"], 16)}
    for level in all_levels(data):
        instance = deepcopy(next(l for l in level["layerInstances"] if l["__identifier"] == "Gameplay"))
        instance.update(__identifier="RiverMask", layerDefUid=definition["uid"], __opacity=0.8,
                        iid=str(uuid.uuid5(uuid.UUID(level["iid"]), "river_mask")), visible=level is room,
                        gridTiles=[], autoLayerTiles=[], entityInstances=[], optionalRules=[])
        instance["intGridCsv"] = [0] * (instance["__cWid"] * instance["__cHei"])
        if level is room:
            for x, y in water_cells:
                instance["intGridCsv"][y * instance["__cWid"] + x] = 1
        index = next(i for i, l in enumerate(level["layerInstances"]) if l["__identifier"] == "WaterAreas")
        level["layerInstances"].insert(index, instance)
    # Remove only additions in memory to prove all prior bytes of authoring data
    # (including the newly painted physical barriers) remain semantically intact.
    stripped = deepcopy(data)
    stripped["defs"]["layers"] = [d for d in stripped["defs"]["layers"] if d["identifier"] != "RiverMask"]
    for level in all_levels(stripped):
        level["layerInstances"] = [l for l in level["layerInstances"] if l["__identifier"] != "RiverMask"]
    stripped["nextUid"] = before["nextUid"]
    assert stripped == before, "An authored layer, entity or barrier was modified."
    return {"changed": True, "wet_cells": len(water_cells), "widths": mapping["width_px"], "all_authored_content_preserved": True, **validate(data)}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    original = SOURCE.read_bytes()
    data = json.loads(original)
    report = convert(data, original)
    after_first = deepcopy(data)
    convert(data, original)
    assert data == after_first
    report.update(source_sha256=hashlib.sha256(original).hexdigest(), dry_run=args.dry_run, idempotent=True)
    if report["changed"] and not args.dry_run:
        if editor_busy() or SOURCE.read_bytes() != original:
            raise RuntimeError("LDtk aberto ou fonte alterada: mapa preservado.")
        backup = ROOT / "ldtk_backups" / f"before_curved_river_{datetime.now():%Y%m%d_%H%M%S}.ldtk"
        backup.write_bytes(original)
        content = json.dumps(data, ensure_ascii=False, indent=2) + "\n"
        if b"\r\n" in original: content = content.replace("\n", "\r\n")
        with tempfile.NamedTemporaryFile(dir=ROOT, suffix=".tmp", delete=False) as stream:
            pending = Path(stream.name)
            stream.write(content.encode("utf-8"))
        try:
            if editor_busy() or SOURCE.read_bytes() != original: raise RuntimeError("Fonte mudou; mapa preservado.")
            os.replace(pending, SOURCE)
        finally:
            pending.unlink(missing_ok=True)
        report["backup"] = str(backup)
    output = ROOT / "output/curved_river"
    output.mkdir(parents=True, exist_ok=True)
    target = "preview.json" if args.dry_run else "migration.json" if report["changed"] else "last_check.json"
    (output / target).write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report, ensure_ascii=True))


if __name__ == "__main__":
    main()
