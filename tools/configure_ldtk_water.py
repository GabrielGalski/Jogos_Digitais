"""Register placeable visual water without changing any authored layers or tiles."""
from __future__ import annotations

import argparse
from copy import deepcopy
from datetime import datetime
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import uuid

ROOT = Path(__file__).resolve().parents[1]
FIELDS = (
    ("Preset", "String", "Lake", "Perfil visual: Lake ou River; extensivel pelo catalogo Water."),
    ("MaskId", "String", "Rectangle", "Rectangle preenche a area; Pond usa mascara nativa 112x96."),
    ("SurfaceId", "String", "", "Regioes conectadas com o mesmo ID devem compartilhar parametros."),
    ("Enabled", "Bool", True, "Habilita esta regiao visual, sem alterar piso ou fisica."),
)


def editor_busy() -> bool:
    result = subprocess.run(
        ["powershell.exe", "-NoProfile", "-NonInteractive", "-Command",
         "if (@(Get-Process -Name LDtk -ErrorAction SilentlyContinue).Count -gt 0) { 'busy' } else { 'idle' }"],
        capture_output=True, timeout=10, check=True,
    )
    state = result.stdout.decode(errors="replace").strip()
    if state not in ("busy", "idle"):
        raise RuntimeError("Nao foi possivel verificar se o LDtk esta aberto. Mapa preservado.")
    return state == "busy"


def all_levels(data: dict) -> list[dict]:
    return list(data["levels"]) + [level for world in data.get("worlds", []) for level in world["levels"]]


def assert_preserved(before: dict, after: dict) -> None:
    """Only new water definitions/empty layer instances and nextUid may differ."""
    stripped = deepcopy(after)
    for key in ("entities", "layers"):
        old_ids = {item["uid"] for item in before["defs"][key]}
        stripped["defs"][key] = [item for item in stripped["defs"][key] if item["uid"] in old_ids]
    for old_level, new_level in zip(all_levels(before), all_levels(stripped), strict=True):
        old_ids = {layer["iid"] for layer in old_level["layerInstances"]}
        new_level["layerInstances"] = [layer for layer in new_level["layerInstances"] if layer["iid"] in old_ids]
    stripped["nextUid"] = before["nextUid"]
    if stripped != before:
        raise ValueError("A migracao tentou alterar conteudo autoral. Mapa preservado.")


def convert_data(data: dict) -> bool:
    before = deepcopy(data)
    definitions = data["defs"]
    next_uid = int(data["nextUid"])

    def allocate() -> int:
        nonlocal next_uid
        uid = next_uid
        next_uid += 1
        return uid

    entity = next((item for item in definitions["entities"] if item["identifier"] == "WaterArea"), None)
    if entity is None:
        entity = deepcopy(next(item for item in definitions["entities"] if item["identifier"] in ("DashGapArea", "DoorDash")))
        template = next(field for item in definitions["entities"] for field in item["fieldDefs"] if field["__type"] == "String")
        entity.update(identifier="WaterArea", uid=allocate(), tags=["water"], width=64, height=64,
                      minWidth=16, minHeight=16, resizableX=True, resizableY=True,
                      pivotX=0, pivotY=0, allowOutOfBounds=True, color="#71AA99",
                      fillOpacity=0.35, lineOpacity=1, tileOpacity=0,
                      doc="Agua procedural visual. O jogo cria a superficie nesta area; sem colisao/interacao.", fieldDefs=[])
        for identifier, kind, default, doc in FIELDS:
            field = deepcopy(template)
            field.update(identifier=identifier, uid=allocate(), __type=kind, type=f"F_{kind}",
                         doc=doc, defaultOverride={"id": f"V_{kind}", "params": [default]},
                         editorDisplayMode="NameAndValue", editorAlwaysShow=False,
                         min=None, max=None, regex=None)
            entity["fieldDefs"].append(field)
        definitions["entities"].append(entity)
    required_fields = {spec[0] for spec in FIELDS}
    if not required_fields.issubset({field["identifier"] for field in entity["fieldDefs"]}):
        raise ValueError("WaterArea existente tem contrato incompatível; revisar antes de migrar.")

    new_layers = []
    for identifier, kind in (("WaterAreas", "Entities"), ("WaterBanks", "Tiles")):
        layer = next((item for item in definitions["layers"] if item["identifier"] == identifier), None)
        if layer is None:
            template_id = "AmbientAreas" if kind == "Entities" else "Floor"
            layer = deepcopy(next(item for item in definitions["layers"] if item["identifier"] == template_id))
            layer.update(identifier=identifier, uid=allocate(), __type=kind, type=kind,
                         uiColor="#71AA99", gridSize=16, pxOffsetX=0, pxOffsetY=0,
                         requiredTags=["water"] if kind == "Entities" else [],
                         excludedTags=[], uiFilterTags=["water"] if kind == "Entities" else [],
                         doc="Agua visual colocavel: WaterArea." if kind == "Entities" else
                         "Margens/espuma visuais acima da agua; paleta inicial do Floor, sem fisica.")
            floor_index = next(index for index, item in enumerate(definitions["layers"]) if item["identifier"] == "Floor")
            definitions["layers"].insert(floor_index, layer)
        if layer["type"] != kind:
            raise ValueError(f"Camada {identifier} existente tem tipo incompatível.")
        new_layers.append(layer)

    tilesets = {item["uid"]: item for item in definitions["tilesets"]}
    for level in all_levels(data):
        if level["layerInstances"] is None:
            raise ValueError("Niveis externos nao sao suportados pelo loader atual.")
        for definition in new_layers:
            if any(layer["layerDefUid"] == definition["uid"] for layer in level["layerInstances"]):
                continue
            kind = definition["type"]
            instance = deepcopy(next(layer for layer in level["layerInstances"] if layer["__type"] == kind))
            source = tilesets.get(definition["tilesetDefUid"], {})
            instance.update(__identifier=definition["identifier"], __type=kind,
                            __gridSize=16, __cWid=(int(level["pxWid"]) + 15) // 16,
                            __cHei=(int(level["pxHei"]) + 15) // 16,
                            __opacity=1, __pxTotalOffsetX=0, __pxTotalOffsetY=0,
                            __tilesetDefUid=definition["tilesetDefUid"], __tilesetRelPath=source.get("relPath"),
                            iid=str(uuid.uuid4()), levelId=level["uid"], layerDefUid=definition["uid"],
                            entityInstances=[], gridTiles=[], autoLayerTiles=[], intGridCsv=[],
                            optionalRules=[], pxOffsetX=0, pxOffsetY=0, visible=True, overrideTilesetUid=None)
            floor_index = next(index for index, layer in enumerate(level["layerInstances"]) if layer["__identifier"] == "Floor")
            level["layerInstances"].insert(floor_index, instance)
    data["nextUid"] = next_uid
    assert_preserved(before, data)
    return data != before


def serialize_preserving_layout(original: bytes, before: dict, after: dict) -> bytes:
    """Insert new array entries in place, keeping LDtk's authored JSON formatting."""
    text = original.decode("utf-8-sig")
    newline = "\r\n" if "\r\n" in text else "\n"
    decoder = json.JSONDecoder()

    def skip_space(index: int) -> int:
        while text[index].isspace():
            index += 1
        return index

    def value_span(path: tuple) -> tuple[int, int]:
        start = skip_space(0)
        for part in path:
            cursor = skip_space(start + 1)
            if isinstance(part, str):
                while text[cursor] != "}":
                    key, key_end = decoder.raw_decode(text, cursor)
                    value_start = skip_space(skip_space(key_end) + 1)
                    _, value_end = decoder.raw_decode(text, value_start)
                    if key == part:
                        start = value_start
                        break
                    cursor = skip_space(value_end)
                    if text[cursor] == ",":
                        cursor = skip_space(cursor + 1)
                else:
                    raise ValueError(f"Campo JSON nao encontrado: {path}")
            else:
                for _ in range(part):
                    _, cursor = decoder.raw_decode(text, cursor)
                    cursor = skip_space(skip_space(cursor) + 1)
                start = cursor
        _, end = decoder.raw_decode(text, start)
        return start, end

    edits: list[tuple[int, int, str]] = []

    def insert_members(path: tuple, old: list, new: list, key: str, replace_modified: bool = False) -> None:
        spans = {item[key]: value_span(path + (index,)) for index, item in enumerate(old)}
        previous = {item[key]: item for item in old}
        first_start = next(iter(spans.values()))[0] if spans else value_span(path)[0]
        indent = text[text.rfind("\n", 0, first_start) + 1:first_start]
        pending = []

        def formatted(items: list) -> str:
            return ("," + newline + indent).join(
                json.dumps(item, ensure_ascii=False, indent="\t").replace("\n", newline + indent)
                for item in items
            )

        for item in new:
            if item[key] not in spans:
                pending.append(item)
            elif pending:
                start = spans[item[key]][0]
                edits.append((start, start, formatted(pending) + "," + newline + indent))
                pending = []
            if replace_modified and item[key] in spans and item != previous[item[key]]:
                start, end = spans[item[key]]
                edits.append((start, end, formatted([item])))
        if pending:
            if spans:
                end = list(spans.values())[-1][1]
                edits.append((end, end, "," + newline + indent + formatted(pending)))
            else:
                start, end = value_span(path)
                edits.append((start, end, json.dumps(new, ensure_ascii=False, indent="\t")))

    for key in ("entities", "layers", "tilesets"):
        insert_members(("defs", key), before["defs"][key], after["defs"][key], "uid", True)
    for index, level in enumerate(before["levels"]):
        insert_members(("levels", index, "layerInstances"), level["layerInstances"],
                       after["levels"][index]["layerInstances"], "iid")
        new_layers = {layer["iid"]: layer for layer in after["levels"][index]["layerInstances"]}
        for layer_index, layer in enumerate(level["layerInstances"]):
            insert_members(("levels", index, "layerInstances", layer_index, "entityInstances"),
                           layer["entityInstances"], new_layers[layer["iid"]]["entityInstances"], "iid", True)
    for world_index, world in enumerate(before.get("worlds", [])):
        for level_index, level in enumerate(world["levels"]):
            insert_members(("worlds", world_index, "levels", level_index, "layerInstances"),
                           level["layerInstances"], after["worlds"][world_index]["levels"][level_index]["layerInstances"], "iid")
            new_layers = {layer["iid"]: layer for layer in after["worlds"][world_index]["levels"][level_index]["layerInstances"]}
            for layer_index, layer in enumerate(level["layerInstances"]):
                insert_members(("worlds", world_index, "levels", level_index, "layerInstances", layer_index, "entityInstances"),
                               layer["entityInstances"], new_layers[layer["iid"]]["entityInstances"], "iid", True)
    start, end = value_span(("nextUid",))
    edits.append((start, end, str(after["nextUid"])))
    for start, end, value in sorted(edits, reverse=True):
        text = text[:start] + value + text[end:]
    if json.loads(text) != after:
        raise ValueError("Serializacao da migracao divergiu dos dados validados.")
    encoding = "utf-8-sig" if original.startswith(b"\xef\xbb\xbf") else "utf-8"
    return text.encode(encoding)


def register(project: Path = ROOT / "monster_booster.ldtk", dry_run: bool = False) -> dict:
    original = project.read_bytes()
    before = json.loads(original.decode("utf-8-sig"))
    data = deepcopy(before)
    changed = convert_data(data)
    result = {"changed": changed, "dry_run": dry_run, "backup": None,
              "entity": "WaterArea", "layers": ["WaterAreas", "WaterBanks"]}
    if not changed or dry_run:
        return result
    if editor_busy() or project.read_bytes() != original:
        raise RuntimeError("Salve e feche o LDtk antes de registrar agua. Mapa preservado.")
    backup_root = project.parent / "ldtk_backups"
    backup_root.mkdir(exist_ok=True)
    backup = backup_root / f"before_water_{datetime.now():%Y%m%d_%H%M%S_%f}_{hashlib.sha256(original).hexdigest()[:12]}.ldtk"
    backup.write_bytes(original)
    content = serialize_preserving_layout(original, before, data)
    with tempfile.NamedTemporaryFile(mode="wb", dir=project.parent,
                                     prefix=".water_", suffix=".tmp", delete=False) as file:
        temporary = Path(file.name)
        file.write(content)
    try:
        if editor_busy() or project.read_bytes() != original:
            raise RuntimeError("LDtk abriu ou o mapa mudou durante a migracao. Nada foi sobrescrito.")
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
