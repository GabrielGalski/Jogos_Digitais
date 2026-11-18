"""Replace Room_2 exploration spawns with six authored circular pedestal events."""
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
from ldtk_field_values import set_value

ROOT = Path(__file__).resolve().parents[1]
RADII = {"castle_west": 240, "castle_east": 256, "forest_west": 176,
         "forest_east": 256, "river_north": 240, "river_south": 224}


def fields(entity: dict) -> dict:
    return {f["__identifier"]: f["__value"] for f in entity["fieldInstances"]}


def convert_data(data: dict) -> dict:
    room = next(l for l in all_levels(data) if l["identifier"] == "Room_2")
    before_tiles = {l["iid"]: deepcopy((l["gridTiles"], l["autoLayerTiles"], l["intGridCsv"])) for l in room["layerInstances"]}
    for layer in room["layerInstances"]:
        layer["entityInstances"] = [e for e in layer["entityInstances"] if e["__identifier"] != "ExplorationRegion"]
    if not any(e["__identifier"] == "ExplorationRegion" for l in all_levels(data) for a in l["layerInstances"] for e in a["entityInstances"]):
        data["defs"]["entities"] = [e for e in data["defs"]["entities"] if e["identifier"] != "ExplorationRegion"]
    entities = data["defs"]["entities"]
    definition = next((e for e in entities if e["identifier"] == "PedestalArena"), None)
    if definition is None:
        source = next(e for e in entities if e["identifier"] == "SpiritHordeArea")
        definition = deepcopy(source)
        definition.update(identifier="PedestalArena", uid=data["nextUid"], width=512, height=512,
            renderMode="Ellipse", color="#BAC9CD", pivotX=0.5, pivotY=0.5, keepAspectRatio=True,
            tileOpacity=0, fillOpacity=0.04, lineOpacity=0.9, hollow=True,
            minWidth=128, minHeight=128, maxWidth=None, maxHeight=None, fieldDefs=[],
            doc="ENCONTRO / Raio circular do ritual. Centralize no HordePedestal com o mesmo EncounterId. "
                "Raio = metade da largura/altura (512x512 = raio 256 px). E no pedestal inicia o evento; "
                "bloqueia somente o jogador ate KillTarget mortes ou vida 0. Nao ativa por entrada. "
                "O altar central fica reservado para o futuro warp final.")
        data["nextUid"] += 1
        for key in ("EncounterId", "KillTarget", "Enabled"):
            field = deepcopy(next(f for f in source["fieldDefs"] if f["identifier"] == key))
            field["uid"] = data["nextUid"]
            data["nextUid"] += 1
            field.update(editorDisplayMode="NameAndValue", editorAlwaysShow=key == "EncounterId")
            if key == "EncounterId":
                field["doc"] = "Igual ao EncounterId do pedestal no centro deste circulo."
                field["defaultOverride"] = {"id": "V_String", "params": ["room_2_ritual"]}
            elif key == "KillTarget":
                field["doc"] = "Eliminacoes necessarias para concluir e liberar o circulo. Vida 0 aborta sem concluir."
            definition["fieldDefs"].append(field)
        entities.insert(next(i for i, e in enumerate(entities) if e["identifier"] == "HordePedestal") + 1, definition)
    area_layer = next(l for l in room["layerInstances"] if l["__identifier"] == "GameplayAreas")
    original_altars = [e for e in area_layer["entityInstances"] if e["__identifier"] == "HordePedestal"]
    for altar in original_altars:
        encounter_id = str(fields(altar).get("EncounterId", ""))
        if encounter_id == "room_2_final_center":
            continue
        existing = next((e for e in area_layer["entityInstances"] if e["__identifier"] == "PedestalArena" and fields(e).get("EncounterId") == encounter_id), None)
        if existing:
            continue  # Preserve the radius, target and position authored after the initial conversion.
        name = encounter_id.removeprefix("room_2_")
        radius = RADII.get(name, 256)
        x, y = altar["px"]
        entry = {"__identifier": "PedestalArena", "__grid": [x // 16, y // 16], "__pivot": [0.5, 0.5],
            "__tags": ["gameplay"], "__tile": None, "__smartColor": definition["color"],
            "__worldX": room["worldX"] + x, "__worldY": room["worldY"] + y,
            "iid": str(uuid.uuid5(uuid.UUID(altar["iid"]), "pedestal_arena")),
            "width": radius * 2, "height": radius * 2, "defUid": definition["uid"], "px": [x, y], "fieldInstances": []}
        for field in definition["fieldDefs"]:
            value = encounter_id if field["identifier"] == "EncounterId" else field["defaultOverride"]["params"][0]
            instance = {"__identifier": field["identifier"], "__type": field["__type"], "defUid": field["uid"], "__tile": None}
            set_value(instance, value)
            entry["fieldInstances"].append(instance)
        area_layer["entityInstances"].append(entry)
    doc = next(l for l in data["defs"]["layers"] if l["identifier"] == "GameplayAreas")
    doc["doc"] = doc["doc"].replace(" ExplorationRegion: populacoes finitas por visita.", "")
    addition = " PedestalArena: raio circular associado por EncounterId; E no pedestal inicia e fecha ate concluir ou morrer."
    if addition not in doc["doc"]:
        doc["doc"] += addition
    assert all(before_tiles[l["iid"]] == (l["gridTiles"], l["autoLayerTiles"], l["intGridCsv"]) for l in room["layerInstances"])
    return validate(data)


def validate(data: dict) -> dict:
    room = next(l for l in all_levels(data) if l["identifier"] == "Room_2")
    entities = [e for l in room["layerInstances"] for e in l["entityInstances"]]
    altars = [e for e in entities if e["__identifier"] == "HordePedestal" and fields(e).get("EncounterId") != "room_2_final_center"]
    arenas = [e for e in entities if e["__identifier"] == "PedestalArena"]
    if len(altars) != 6 or len(arenas) != 6:
        raise ValueError("A Room_2 exige seis pedestais de ritual e seis circulos; central reservado.")
    if any(e["__identifier"] == "ExplorationRegion" for e in entities):
        raise ValueError("Ainda ha spawn automatico de exploracao na Room_2.")
    radii = {}
    for altar in altars:
        encounter_id = fields(altar)["EncounterId"]
        matches = [a for a in arenas if fields(a).get("EncounterId") == encounter_id]
        if len(matches) != 1:
            raise ValueError("Pedestal sem uma unica arena: " + encounter_id)
        arena = matches[0]
        if arena["width"] != arena["height"] or arena["width"] < 128:
            raise ValueError("Arena precisa ser circular e ter diametro minimo de 128 px.")
        if arena["px"] != altar["px"]:
            raise ValueError("Centralize a arena no pedestal de mesmo EncounterId: " + encounter_id)
        radii[encounter_id] = arena["width"] // 2
    return {"level": "Room_2", "arenas": len(arenas), "automatic_spawns": 0, "central_reserved": True, "radii": radii}


def configure(project: Path, dry_run: bool = False) -> dict:
    original = project.read_bytes()
    before = json.loads(original.decode("utf-8-sig"))
    data = deepcopy(before)
    result = convert_data(data)
    for old, new in zip(all_levels(before), all_levels(data), strict=True):
        if old["identifier"] != "Room_2" and old != new:
            raise ValueError("A migracao tentou alterar outro level.")
    result.update(changed=data != before, dry_run=dry_run)
    if data == before or dry_run:
        return result
    if editor_busy() or project.read_bytes() != original:
        raise RuntimeError("LDtk aberto ou mapa alterado: arquivo preservado.")
    backup_root = project.parent / "ldtk_backups"
    backup_root.mkdir(exist_ok=True)
    backup = backup_root / f"before_pedestal_arenas_{datetime.now():%Y%m%d_%H%M%S}_{hashlib.sha256(original).hexdigest()[:12]}.ldtk"
    backup.write_bytes(original)
    with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", dir=project.parent, prefix=".pedestal_arenas_", suffix=".tmp", delete=False) as stream:
        temporary = Path(stream.name)
        json.dump(data, stream, ensure_ascii=False, indent=2)
        stream.write("\n")
    try:
        if editor_busy() or project.read_bytes() != original:
            raise RuntimeError("LDtk abriu ou mapa mudou: arquivo preservado.")
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
    print(json.dumps(configure(args.project, args.dry_run), ensure_ascii=False))
