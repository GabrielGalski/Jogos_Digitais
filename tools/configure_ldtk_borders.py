"""Add the native borders atlas and empty collision-enabled layer, preserving authored maps."""
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

from configure_ldtk_water import ROOT, all_levels, editor_busy, serialize_preserving_layout

SOURCE = "assets/tiles/wall/bordas.png"
# Stamp boxes are aligned to 8 px; visible bounds retain the source's 22/7 px details.
PIECES = (
    ("lateral_direita_A", (0, 8, 24, 64), (0, 8, 24, 64)),
    ("lateral_esquerda_A", (32, 8, 24, 64), (32, 8, 22, 64)),
    ("lateral_direita_B", (72, 0, 24, 64), (72, 0, 24, 64)),
    ("lateral_esquerda_B", (104, 0, 24, 64), (104, 0, 24, 64)),
    ("horizontal_A", (0, 96, 32, 8), (0, 96, 32, 8)),
    ("horizontal_B", (0, 120, 32, 8), (0, 121, 32, 7)),
    ("horizontal_C", (48, 88, 32, 8), (48, 88, 32, 8)),
    ("horizontal_D", (48, 112, 32, 8), (48, 112, 32, 8)),
    ("vertical_A", (96, 96, 8, 32), (96, 96, 8, 32)),
    ("vertical_B", (120, 96, 8, 32), (120, 96, 8, 32)),
)


def tile_ids(box: tuple[int, int, int, int]) -> list[int]:
    x, y, width, height = box
    return [row * 16 + col for row in range(y // 8, (y + height) // 8)
            for col in range(x // 8, (x + width) // 8)]


def assert_preserved(before: dict, after: dict) -> None:
    stripped = deepcopy(after)
    for key in ("tilesets", "layers"):
        old_ids = {item["uid"] for item in before["defs"][key]}
        stripped["defs"][key] = [item for item in stripped["defs"][key] if item["uid"] in old_ids]
    for old, new in zip(all_levels(before), all_levels(stripped), strict=True):
        old_ids = {item["iid"] for item in old["layerInstances"]}
        additions = [item for item in new["layerInstances"] if item["iid"] not in old_ids]
        if any(item["gridTiles"] or item["autoLayerTiles"] or item["entityInstances"] or item["intGridCsv"] for item in additions):
            raise ValueError("A camada nova precisa estar vazia. Mapa preservado.")
        new["layerInstances"] = [item for item in new["layerInstances"] if item["iid"] in old_ids]
    stripped["nextUid"] = before["nextUid"]
    if stripped != before:
        raise ValueError("A migracao alterou conteudo autoral. Mapa preservado.")


def convert_data(data: dict) -> bool:
    before = deepcopy(data)
    if any(level.get("layerInstances") is None for level in all_levels(data)):
        raise ValueError("Niveis externos nao suportados. Mapa preservado.")
    defs = data["defs"]

    def allocate() -> int:
        value = int(data["nextUid"])
        data["nextUid"] = value + 1
        return value

    source = next((item for item in defs["tilesets"] if item["identifier"] == "Borders_8"), None)
    if source is None:
        source = deepcopy(next(item for item in defs["tilesets"] if item["identifier"] == "Wall_16"))
        source.update(identifier="Borders_8", uid=allocate(), relPath=SOURCE,
                      __cWid=16, __cHei=16, pxWid=128, pxHei=128, tileGridSize=8,
                      spacing=0, padding=0, tags=[], tagsSourceEnumUid=None, enumTags=[],
                      cachedPixelData=None, embedAtlas=None, savedSelections=[], customData=[])
        for label, box, visible in PIECES:
            ids = tile_ids(box)
            source["savedSelections"].append({"ids": ids, "mode": "Stamp"})
            source["customData"].append({"tileId": ids[0], "data": json.dumps({
                "piece": label, "stamp_px": list(box), "visible_px": list(visible),
                "collision": "opaque_alpha", "use": "Limite fisico do movimento; pintar em Borders"
            }, ensure_ascii=False)})
        wall_index = next(i for i, item in enumerate(defs["tilesets"]) if item["identifier"] == "Wall_16")
        defs["tilesets"].insert(wall_index + 1, source)
    if source["relPath"] != SOURCE or source["tileGridSize"] != 8 or (source["pxWid"], source["pxHei"]) != (128, 128):
        raise ValueError("Borders_8 existente tem contrato incompativel.")

    layer = next((item for item in defs["layers"] if item["identifier"] == "Borders"), None)
    if layer is None:
        layer = deepcopy(next(item for item in defs["layers"] if item["identifier"] == "WaterBanks"))
        layer.update(identifier="Borders", uid=allocate(), gridSize=8, tilesetDefUid=source["uid"],
                     uiColor="#533048", requiredTags=[], excludedTags=[], uiFilterTags=[],
                     doc="LIMITES / bordas fisicas (Z=-16). PNG nativo bordas.png, grade 8 px, 10 stamps. Pintar aqui bloqueia movimento no jogo somente nos pixels opacos, inclusive com flips; os vaos permanecem livres. Sem duplicar em Gameplay. Medidas: docs/LDtk_BORDAS.md.")
        index = next(i for i, item in enumerate(defs["layers"]) if item["identifier"] == "WaterBanks")
        defs["layers"].insert(index, layer)
    if layer["type"] != "Tiles" or layer["gridSize"] != 8 or layer["tilesetDefUid"] != source["uid"]:
        raise ValueError("Camada Borders existente tem contrato incompativel.")

    for level in all_levels(data):
        if any(item["layerDefUid"] == layer["uid"] for item in level["layerInstances"]):
            continue
        instance = deepcopy(next(item for item in level["layerInstances"] if item["__identifier"] == "WaterBanks"))
        instance.update(__identifier="Borders", __gridSize=8, __cWid=(level["pxWid"] + 7) // 8,
                        __cHei=(level["pxHei"] + 7) // 8, __opacity=1,
                        __pxTotalOffsetX=0, __pxTotalOffsetY=0, __tilesetDefUid=source["uid"],
                        __tilesetRelPath=SOURCE, iid=str(uuid.uuid4()), layerDefUid=layer["uid"],
                        gridTiles=[], autoLayerTiles=[], intGridCsv=[], entityInstances=[],
                        pxOffsetX=0, pxOffsetY=0, optionalRules=[], visible=True, overrideTilesetUid=None)
        index = next(i for i, item in enumerate(level["layerInstances"]) if item["__identifier"] == "WaterBanks")
        level["layerInstances"].insert(index, instance)
    assert_preserved(before, data)
    return before != data


def register(project: Path = ROOT / "monster_booster.ldtk", dry_run: bool = False) -> dict:
    original = project.read_bytes()
    before = json.loads(original.decode("utf-8-sig"))
    after = deepcopy(before)
    result = {"changed": convert_data(after), "dry_run": dry_run, "backup": None,
              "tileset": "Borders_8", "layer": "Borders", "grid_px": 8, "stamps": len(PIECES)}
    if not result["changed"] or dry_run:
        return result
    if editor_busy() or project.read_bytes() != original:
        raise RuntimeError("LDtk aberto ou mapa alterado. Mapa preservado.")
    content = serialize_preserving_layout(original, before, after)
    backup_root = project.parent / "ldtk_backups"
    backup_root.mkdir(exist_ok=True)
    backup = backup_root / f"before_borders_{datetime.now():%Y%m%d_%H%M%S_%f}_{hashlib.sha256(original).hexdigest()[:12]}.ldtk"
    backup.write_bytes(original)
    with tempfile.NamedTemporaryFile(mode="wb", dir=project.parent, prefix=".borders_", suffix=".tmp", delete=False) as file:
        temporary = Path(file.name)
        file.write(content)
    try:
        if editor_busy() or project.read_bytes() != original:
            raise RuntimeError("LDtk abriu ou mapa mudou durante a migracao. Mapa preservado.")
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
