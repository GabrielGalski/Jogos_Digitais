"""Repair the scenery's editor indices while retaining the game's exact paint."""
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
from ldtk_editor_coordinates import grid_dimensions, synchronize_level
from split_ldtk_room2 import REFERENCE, reference_bytes, validate

ROOT = Path(__file__).resolve().parents[1]


def editor_view(data: dict) -> dict:
    result = deepcopy(data)
    for level in all_levels(result):
        if level["identifier"] != "Room_2_Cenario":
            continue
        for layer in level["layerInstances"]:
            width, _ = grid_dimensions(level, layer)
            grid = layer["__gridSize"]
            for stamp in layer["gridTiles"]:
                index = stamp["d"][0]
                stamp["px"] = [index % width * grid, index // width * grid]
    return result


def repair(project: Path, apply: bool = False) -> dict:
    original = project.read_bytes()
    before = json.loads(original.decode("utf-8-sig"))
    after = deepcopy(before)
    edits = []
    for level in all_levels(after):
        if level["identifier"] in ["Room_2", "Room_2_Cenario"]:
            edits.extend(synchronize_level(level))
    checked = deepcopy(after)
    for old_level in all_levels(before):
        level = next(entry for entry in all_levels(checked) if entry["iid"] == old_level["iid"])
        for old_layer in old_level["layerInstances"]:
            layer = next(entry for entry in level["layerInstances"] if entry["iid"] == old_layer["iid"])
            layer["__cWid"], layer["__cHei"] = old_layer["__cWid"], old_layer["__cHei"]
            for old_stamp, stamp in zip(old_layer["gridTiles"], layer["gridTiles"], strict=True):
                stamp["d"] = old_stamp["d"]
    assert checked == before, "Repair changed actual art, gameplay or unrelated levels."
    repeat = deepcopy(after)
    for level in all_levels(repeat):
        if level["identifier"] in ["Room_2", "Room_2_Cenario"]:
            synchronize_level(level)
    assert repeat == after, "Repair must be idempotent."
    guide = reference_bytes(after, project.parent)
    native_editor = reference_bytes(editor_view(after), project.parent)
    assert guide == native_editor, "Native editor coordinates still differ from game coordinates."
    report = validate(after)
    report.update(changed=before != after, applied=apply, exact_art_and_gameplay_preserved=True,
                  editor_matches_pixels=True, idempotent=True,
                  edits=[entry for entry in edits if entry["dimensions_changed"] or entry["reindexed_tiles"]],
                  preview_sha256=hashlib.sha256(guide).hexdigest())
    output = project.parent / "output/ldtk_editor_repair"
    output.mkdir(exist_ok=True, parents=True)
    if apply and before != after:
        if editor_busy() or project.read_bytes() != original:
            raise RuntimeError("LDtk aberto ou projeto modificado; original preservado.")
        backup = project.parent / "ldtk_backups" / f"before_editor_coordinates_{datetime.now():%Y%m%d_%H%M%S}_{hashlib.sha256(original).hexdigest()[:12]}.ldtk"
        backup.write_bytes(original)
        content = json.dumps(after, ensure_ascii=False, indent=2) + "\n"
        if b"\r\n" in original:
            content = content.replace("\n", "\r\n")
        with tempfile.NamedTemporaryFile(mode="wb", dir=project.parent, prefix=".editor_coordinates_", suffix=".tmp", delete=False) as stream:
            temporary = Path(stream.name)
            stream.write(content.encode("utf-8"))
        try:
            if editor_busy() or project.read_bytes() != original:
                raise RuntimeError("Projeto mudou durante a correcao; original preservado.")
            os.replace(temporary, project)
        finally:
            temporary.unlink(missing_ok=True)
        (project.parent / REFERENCE).write_bytes(guide)
        (output / "editor_before.png").write_bytes(reference_bytes(editor_view(before), project.parent))
        (output / "editor_after.png").write_bytes(native_editor)
        report["backup"] = str(backup)
    (output / ("applied.json" if apply else "preview.json")).write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return report


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()
    print(json.dumps(repair(ROOT / "monster_booster.ldtk", args.apply), ensure_ascii=False, indent=2))
