"""Add optional coast overrides to WaterAreas; preserve all authored data/layout."""
from __future__ import annotations

import argparse
from copy import deepcopy
from datetime import datetime
import hashlib
import json
import os
from pathlib import Path
import tempfile

from configure_ldtk_water import ROOT, all_levels, assert_preserved, editor_busy, serialize_preserving_layout

FIELDS = (
    ("CoastType", "String", "Default", "Default, Rock, Beach, Raised ou None. Classifica a costa sob a area; nao cria terreno/agua."),
    ("Priority", "Int", 0, "Maior prioridade vence. Empate: maior IID em ordem alfabetica. Area deve cobrir a borda do terreno."),
    ("Enabled", "Bool", True, "Ativa somente a excecao visual. Sem efeito na fisica ou no modo manual WaterArea."),
)


def convert_data(data: dict) -> bool:
    before = deepcopy(data)
    if any(level.get("layerInstances") is None for level in all_levels(data)):
        raise ValueError("Niveis externos nao suportados. Mapa preservado.")
    source = next(e for e in data["defs"]["entities"] if e["identifier"] == "WaterArea")
    layer = next(layer for layer in data["defs"]["layers"] if layer["identifier"] == "WaterAreas")
    if layer["type"] != "Entities" or "water" not in layer["requiredTags"]:
        raise ValueError("WaterAreas incompativel. Mapa preservado.")
    existing = next((e for e in data["defs"]["entities"] if e["identifier"] == "WaterShoreOverride"), None)
    if existing:
        if {f["identifier"]: f["__type"] for f in existing["fieldDefs"]} != {name: kind for name, kind, _, _ in FIELDS}:
            raise ValueError("WaterShoreOverride existente tem contrato incompativel.")
        return False
    entity = deepcopy(source)
    entity.update(identifier="WaterShoreOverride", uid=data["nextUid"], width=64, height=32,
                  tags=["water"], color="#D9A56A", fillOpacity=0.15, tileOpacity=0,
                  doc="Excecao opcional de margem do mar automatico. Cobrir a borda do terreno; a costa mais proxima define espuma/faixa rasa/sombra. Sem colisao.", fieldDefs=[])
    data["nextUid"] += 1
    for name, kind, default, doc in FIELDS:
        field = deepcopy(source["fieldDefs"][0])
        field.update(identifier=name, uid=data["nextUid"], __type=kind, type=f"F_{kind}", doc=doc,
                     defaultOverride={"id": f"V_{kind}", "params": [default]}, min=None, max=None,
                     regex="^(Default|Rock|Beach|Raised|None)$" if kind == "String" else None)
        if name == "Priority":
            field.update(min=-1000, max=1000)
        entity["fieldDefs"].append(field)
        data["nextUid"] += 1
    data["defs"]["entities"].append(entity)
    assert_preserved(before, data)
    return True


def register(project: Path = ROOT / "monster_booster.ldtk", dry_run: bool = False) -> dict:
    original = project.read_bytes()
    before = json.loads(original.decode("utf-8-sig"))
    after = deepcopy(before)
    result = {"changed": convert_data(after), "dry_run": dry_run, "backup": None, "entity": "WaterShoreOverride", "layer": "WaterAreas"}
    if not result["changed"] or dry_run:
        return result
    if editor_busy() or project.read_bytes() != original:
        raise RuntimeError("LDtk aberto ou mapa alterado. Mapa preservado.")
    content = serialize_preserving_layout(original, before, after)
    backup_root = project.parent / "ldtk_backups"
    backup_root.mkdir(exist_ok=True)
    backup = backup_root / f"before_water_shores_{datetime.now():%Y%m%d_%H%M%S_%f}_{hashlib.sha256(original).hexdigest()[:12]}.ldtk"
    backup.write_bytes(original)
    with tempfile.NamedTemporaryFile(mode="wb", dir=project.parent, prefix=".water_shores_", suffix=".tmp", delete=False) as file:
        temporary = Path(file.name)
        file.write(content)
    try:
        if editor_busy() or project.read_bytes() != original:
            raise RuntimeError("LDtk abriu ou mapa mudou durante a migracao. Nada foi sobrescrito.")
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
