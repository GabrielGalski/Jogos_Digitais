"""Connect the existing Room_1 exit to the authored Asterion tutorial, preserving map paint."""
from __future__ import annotations
import argparse
from copy import deepcopy
from datetime import datetime
import hashlib
import json
import os
from pathlib import Path
import tempfile

from configure_ldtk_water import ROOT, all_levels, editor_busy, serialize_preserving_layout
from configure_ldtk_warps import convert_data as configure_warps
from configure_ldtk_spirit_horde import EXIT_IID
from ldtk_field_values import set_value

TARGET = "res://scenes/tutorial_arena.tscn"


def convert_data(data: dict) -> bool:
    before = deepcopy(data)
    configure_warps(data)
    room = next(level for level in all_levels(data) if level["identifier"] == "Room_1")
    matches = [entity for layer in room["layerInstances"] for entity in layer["entityInstances"]
               if entity["iid"] == EXIT_IID and entity["__identifier"] == "Warp"]
    if len(matches) != 1:
        raise ValueError("Warp de saida autoral de Room_1 nao encontrado; mapa preservado.")
    values = {"TargetScene": TARGET, "TargetLevel": "", "TargetMap": "", "RestartGame": False}
    for field in matches[0]["fieldInstances"]:
        if field["__identifier"] in values:
            set_value(field, values[field["__identifier"]])
    return before != data


def register(project: Path = ROOT / "monster_booster.ldtk", dry_run: bool = False) -> dict:
    original = project.read_bytes()
    before = json.loads(original.decode("utf-8-sig"))
    after = deepcopy(before)
    result = {"changed": convert_data(after), "dry_run": dry_run, "backup": None}
    if not result["changed"] or dry_run:
        return result
    if editor_busy() or project.read_bytes() != original:
        raise RuntimeError("Salve e feche o LDtk. Mapa preservado.")
    content = serialize_preserving_layout(original, before, after)
    folder = project.parent / "ldtk_backups"
    folder.mkdir(exist_ok=True)
    backup = folder / f"before_asterion_{datetime.now():%Y%m%d_%H%M%S_%f}_{hashlib.sha256(original).hexdigest()[:12]}.ldtk"
    backup.write_bytes(original)
    with tempfile.NamedTemporaryFile(mode="wb", dir=project.parent, prefix=".asterion_", suffix=".tmp", delete=False) as file:
        temporary = Path(file.name)
        file.write(content)
    try:
        if editor_busy() or project.read_bytes() != original:
            raise RuntimeError("LDtk abriu ou mapa mudou. Nada foi sobrescrito.")
        os.replace(temporary, project)
    finally:
        temporary.unlink(missing_ok=True)
    result["backup"] = str(backup)
    return result


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", type=Path, default=ROOT / "monster_booster.ldtk")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    print(json.dumps(register(args.project, args.dry_run), ensure_ascii=False))
