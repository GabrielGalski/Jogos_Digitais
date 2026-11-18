"""Clear current tree paint, retain tree tools, and register bush/reactive grass.

New painting layers stay empty. The grass palette shows grass_animated1 only;
Godot owns the four-frame reaction to the player's passage.
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

from PIL import Image
from configure_ldtk_water import all_levels, editor_busy
from split_ldtk_room2 import composed_layers, reference_bytes, REFERENCE

ROOT = Path(__file__).resolve().parents[1]
ASSETS = (
    ("Bush_16", "assets/tiles/floor/bush.png", "Bushes", 32,
     "CENARIO / Arbustos 32x32, carimbo 2x2 de 16px. Paleta roxa na Godot; corpo inferior solido 28x24 e topo livre de 8px para passagem por tras."),
    ("GrassAnimated_16", "assets/tiles/floor/grass_animated1.png", "GrassAnimated", 16,
     "CENARIO / Grama reativa 16x16. Pintar grass_animated1 como repouso. Na Godot, a passagem do jogador toca os quatro frames e retorna ao frame 1; sem colisao ou animacao continua."),
)


def convert(data: dict) -> dict:
    before = deepcopy(data)
    if all(any(l["identifier"] == name for l in data["defs"]["layers"]) for _, _, name, _, _ in ASSETS):
        return {"changed": False, "reason": "Vegetation already configured; preserving subsequent painting."}
    levels = all_levels(data)
    tree_sources = {t["uid"] for t in data["defs"]["tilesets"] if
                    str(t.get("relPath", "")).replace("\\", "/").endswith("/tree.png")}
    removed = {}
    for level in levels:
        count = 0
        for layer in level["layerInstances"]:
            if layer.get("__tilesetDefUid") in tree_sources:
                count += len(layer["gridTiles"]) + len(layer["autoLayerTiles"])
                layer["gridTiles"] = []
                layer["autoLayerTiles"] = []
        removed[level["identifier"]] = count
    new_sources, new_layers, registered = [], [], []
    for name, relative, layer_name, size, description in ASSETS:
        with Image.open(ROOT / relative) as image:
            assert image.size == (size, size), (relative, image.size)
        source = next((s for s in data["defs"]["tilesets"] if s.get("relPath") == relative), None)
        if source is None:
            source = deepcopy(next(s for s in data["defs"]["tilesets"] if s["identifier"] == "Tree_16"))
            source.update(identifier=name, uid=data["nextUid"], relPath=relative,
                pxWid=size, pxHei=size, __cWid=size // 16, __cHei=size // 16,
                tags=["scenery", "vegetation"], enumTags=[], customData=[], cachedPixelData=None,
                savedSelections=[{"ids": list(range((size // 16) ** 2)), "mode": "Stamp"}])
            data["nextUid"] += 1
            data["defs"]["tilesets"].append(source)
            new_sources.append(source["uid"])
        if not any(l["identifier"] == layer_name for l in data["defs"]["layers"]):
            template = next(l for l in data["defs"]["layers"] if l["identifier"] == "Trees")
            definition = deepcopy(template)
            definition.update(identifier=layer_name, uid=data["nextUid"], tilesetDefUid=source["uid"], doc=description)
            data["nextUid"] += 1
            index = next(i for i, l in enumerate(data["defs"]["layers"]) if l["identifier"] == "Trees_Border")
            data["defs"]["layers"].insert(index, definition)
            new_layers.append(definition["uid"])
            for level in levels:
                layer = deepcopy(next(l for l in level["layerInstances"] if l["__identifier"] == "Trees"))
                layer.update(__identifier=layer_name, __tilesetDefUid=source["uid"], __tilesetRelPath=relative,
                    layerDefUid=definition["uid"], iid=str(uuid.uuid5(uuid.UUID(level["iid"]), "vegetation:" + layer_name)),
                    gridTiles=[], autoLayerTiles=[], entityInstances=[], intGridCsv=[], overrideTilesetUid=None,
                    visible=level["identifier"] == "Room_2_Cenario")
                index = next(i for i, l in enumerate(level["layerInstances"]) if l["__identifier"] == "Trees_Border")
                level["layerInstances"].insert(index, layer)
        registered.append({"tileset": source["identifier"], "layer": layer_name, "size": size, "default": relative})
    # Only the tree paint and newly registered empty layers may differ.
    stripped = deepcopy(data)
    stripped["nextUid"] = before["nextUid"]
    stripped["defs"]["tilesets"] = [s for s in stripped["defs"]["tilesets"] if s["uid"] not in new_sources]
    stripped["defs"]["layers"] = [l for l in stripped["defs"]["layers"] if l["uid"] not in new_layers]
    for level in all_levels(stripped):
        old = next(l for l in all_levels(before) if l["iid"] == level["iid"])
        level["layerInstances"] = [l for l in level["layerInstances"] if l["layerDefUid"] not in new_layers]
        for layer in level["layerInstances"]:
            if layer.get("__tilesetDefUid") in tree_sources:
                original = next(l for l in old["layerInstances"] if l["iid"] == layer["iid"])
                layer["gridTiles"] = original["gridTiles"]
                layer["autoLayerTiles"] = original["autoLayerTiles"]
    assert stripped == before, "Unrelated authored data changed"
    composed_layers(data, next(l for l in levels if l["identifier"] == "Room_2"))
    return {"changed": True, "removed_tree_tiles": removed, "registered": registered,
            "tree_definitions_retained": True, "new_layers_empty": True}


def apply(project: Path, dry_run: bool) -> dict:
    original = project.read_bytes()
    data = json.loads(original.decode("utf-8-sig"))
    report = convert(data)
    if dry_run or not report["changed"]: return report
    if editor_busy() or project.read_bytes() != original:
        raise RuntimeError("LDtk aberto ou mapa modificado; nenhum mapa sobrescrito.")
    folder = project.parent / "ldtk_backups"
    folder.mkdir(exist_ok=True)
    backup = folder / f"before_vegetation_{datetime.now():%Y%m%d_%H%M%S}_{hashlib.sha256(original).hexdigest()[:12]}.ldtk"
    backup.write_bytes(original)
    content = json.dumps(data, ensure_ascii=False, indent=2) + "\n"
    if b"\r\n" in original: content = content.replace("\n", "\r\n")
    with tempfile.NamedTemporaryFile(mode="wb", dir=project.parent, prefix=".vegetation_", suffix=".tmp", delete=False) as stream:
        temporary = Path(stream.name)
        stream.write(content.encode("utf-8"))
    try:
        if editor_busy() or project.read_bytes() != original:
            raise RuntimeError("LDtk abriu ou mapa mudou durante a preparacao; mapa preservado.")
        os.replace(temporary, project)
    finally:
        temporary.unlink(missing_ok=True)
    (project.parent / REFERENCE).write_bytes(reference_bytes(data, project.parent))
    report["backup"] = str(backup)
    return report


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", type=Path, default=ROOT / "monster_booster.ldtk")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    print(json.dumps(apply(args.project, args.dry_run), ensure_ascii=False))
