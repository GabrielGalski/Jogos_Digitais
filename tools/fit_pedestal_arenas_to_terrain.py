"""Repair audited old floor voids and give pedestal combat one radius control.

The editor ellipse shows the maximum disk. Runtime clips it to connected,
permitted ground around the matching HordePedestal.
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
from repair_pedestal_floor import repair
from split_ldtk_room2 import REFERENCE, reference_bytes

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_RADIUS = 512


def fields(entity: dict) -> dict:
    return {f["__identifier"]: f["__value"] for f in entity["fieldInstances"]}


def convert(data: dict) -> dict:
    report = {"floor_repair": repair(data)}
    definition = next(d for d in data["defs"]["entities"] if d["identifier"] == "PedestalArena")
    field = next((f for f in definition["fieldDefs"] if f["identifier"] == "RadiusPx"), None)
    if field is None:
        field = deepcopy(next(f for f in definition["fieldDefs"] if f["identifier"] == "KillTarget"))
        field.update(identifier="RadiusPx", uid=data["nextUid"], min=64, max=2048,
                     defaultOverride={"id": "V_Int", "params": [DEFAULT_RADIUS]},
                     editorDisplayMode="NameAndValue", editorAlwaysShow=True,
                     doc="Unico controle de tamanho: raio maximo em pixels (512 = 32 tiles). Centro vem do HordePedestal com mesmo EncounterId. Godot recorta o disco ao chao conectado, excluindo agua/MapLimit/solidos. A elipse e apenas guia maxima.")
        data["nextUid"] += 1
        definition["fieldDefs"].append(field)
    definition.update(width=DEFAULT_RADIUS * 2, height=DEFAULT_RADIUS * 2,
                      doc="ENCONTRO / Arena recortada ao terreno. Ajuste somente RadiusPx para o tamanho. O centro acompanha o HordePedestal de mesmo EncounterId; a elipse indica o alcance maximo e pode ultrapassar o mapa no editor, mas a Godot mantem a area no chao permitido. E inicia; KillTarget libera; vida 0 aborta.")
    arenas = []
    for level in all_levels(data):
        all_entities = [e for l in level["layerInstances"] for e in l["entityInstances"]]
        pedestals = {fields(e).get("EncounterId"): e for e in all_entities if e["__identifier"] == "HordePedestal"}
        for entity in all_entities:
            if entity["__identifier"] != "PedestalArena":
                continue
            config = fields(entity)
            radius_field = next((f for f in entity["fieldInstances"] if f["__identifier"] == "RadiusPx"), None)
            if radius_field is None:
                radius_field = {"__identifier": "RadiusPx", "__type": "Int", "defUid": field["uid"], "__tile": None}
                set_value(radius_field, DEFAULT_RADIUS if level["identifier"] == "Room_2" else min(entity["width"], entity["height"]) // 2)
                entity["fieldInstances"].append(radius_field)
            if level["identifier"] != "Room_2":
                continue
            pedestal = pedestals.get(config.get("EncounterId"))
            if pedestal is None:
                raise ValueError("Arena sem pedestal correspondente: " + str(config))
            radius = int(radius_field["__value"])
            if not 64 <= radius <= 2048:
                raise ValueError("RadiusPx precisa estar em 64..2048.")
            entity["px"] = pedestal["px"].copy()
            entity["__grid"] = pedestal["__grid"].copy()
            entity["__worldX"], entity["__worldY"] = pedestal["__worldX"], pedestal["__worldY"]
            entity["width"] = entity["height"] = radius * 2
            arenas.append({"encounter": config["EncounterId"], "center": entity["px"], "radius_px": radius,
                           "kill_target": config["KillTarget"]})
    report.update(arenas=arenas, only_size_control="PedestalArena.RadiusPx", center_follows_pedestal=True,
                  player_region="maximum disk intersect connected permitted ground", editor_ellipse="maximum guide only")
    return report


def apply(project: Path, dry_run: bool = False) -> dict:
    original = project.read_bytes()
    before = json.loads(original.decode("utf-8-sig"))
    after = deepcopy(before)
    report = convert(after)
    repeated = deepcopy(after)
    convert(repeated)
    assert repeated == after, "A migracao precisa ser idempotente."
    # Restore the intentional changes and prove all other authored data exact.
    checked = deepcopy(after)
    checked["defs"] = before["defs"]
    checked["nextUid"] = before["nextUid"]
    for old_level in all_levels(before):
        level = next(l for l in all_levels(checked) if l["iid"] == old_level["iid"])
        for old_layer in old_level["layerInstances"]:
            layer = next(l for l in level["layerInstances"] if l["iid"] == old_layer["iid"])
            if level["identifier"] == "Room_2_Cenario" and layer["__identifier"] == "Floor":
                layer["gridTiles"] = old_layer["gridTiles"]
            old_entities = {e["iid"]: e for e in old_layer["entityInstances"]}
            for index, entity in enumerate(layer["entityInstances"]):
                if entity["__identifier"] == "PedestalArena":
                    layer["entityInstances"][index] = old_entities[entity["iid"]]
    assert checked == before, "Conteudo autoral fora da correcao foi alterado."
    report.update(changed=after != before, dry_run=dry_run, other_authored_content_preserved=True, idempotent=True)
    if not dry_run and report["changed"]:
        if editor_busy() or project.read_bytes() != original:
            raise RuntimeError("LDtk aberto ou mapa modificado; nenhum arquivo sobrescrito.")
        guide = reference_bytes(after, project.parent)
        backups = project.parent / "ldtk_backups"
        backups.mkdir(exist_ok=True)
        backup = backups / f"before_terrain_arenas_{datetime.now():%Y%m%d_%H%M%S}_{hashlib.sha256(original).hexdigest()[:12]}.ldtk"
        backup.write_bytes(original)
        content = json.dumps(after, ensure_ascii=False, indent=2) + "\n"
        if b"\r\n" in original:
            content = content.replace("\n", "\r\n")
        with tempfile.NamedTemporaryFile(mode="wb", dir=project.parent, prefix=".terrain_arenas_", suffix=".tmp", delete=False) as stream:
            temporary = Path(stream.name)
            stream.write(content.encode("utf-8"))
        try:
            if editor_busy() or project.read_bytes() != original:
                raise RuntimeError("Mapa mudou durante a operacao; autoria preservada.")
            os.replace(temporary, project)
        finally:
            temporary.unlink(missing_ok=True)
        (project.parent / REFERENCE).write_bytes(guide)
        report["backup"] = str(backup)
    output = project.parent / "output/pedestal_arenas"
    output.mkdir(parents=True, exist_ok=True)
    (output / ("migration_preview.json" if dry_run else "migration.json")).write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return report


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    result = apply(ROOT / "monster_booster.ldtk", args.dry_run)
    summary = deepcopy(result)
    summary["floor_repair"].pop("cells", None)
    print(json.dumps(summary, ensure_ascii=False, indent=2))
