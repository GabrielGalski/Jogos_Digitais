"""Subdivide only the existing wall atlas/layers into 8px cells, without rescaling."""
from __future__ import annotations

import argparse
from copy import deepcopy
import hashlib
import json
from pathlib import Path

from PIL import Image, ImageStat

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / "monster_booster.ldtk"


def _ids(ids: list[int], old_columns: int, new_columns: int) -> list[int]:
    return sorted({(int(t) // old_columns * 2 + y) * new_columns
                   + int(t) % old_columns * 2 + x
                   for t in ids for y in range(2) for x in range(2)})


def subdivide_tile(tile: dict, new_columns: int, layer_columns: int) -> list[dict]:
    result = []
    flip = int(tile.get("f", 0))
    for y in range(2):
        for x in range(2):
            part = deepcopy(tile)
            sx = 1 - x if flip & 1 else x
            sy = 1 - y if flip & 2 else y
            part["px"] = [int(tile["px"][0]) + x * 8, int(tile["px"][1]) + y * 8]
            part["src"] = [int(tile["src"][0]) + sx * 8, int(tile["src"][1]) + sy * 8]
            part["t"] = part["src"][1] // 8 * new_columns + part["src"][0] // 8
            # Manual tiles store their layer-coordinate ID, not their atlas ID.
            part["d"] = [part["px"][1] // 8 * layer_columns + part["px"][0] // 8]
            result.append(part)
    return result


def convert_data(data: dict) -> bool:
    definitions = data["defs"]
    wall = next(t for t in definitions["tilesets"]
                if str(t["relPath"]).replace("\\", "/").endswith("/wall_tileset.png"))
    if int(wall["tileGridSize"]) == 8:
        return False
    assert int(wall["tileGridSize"]) == 16
    assert int(wall["spacing"]) == int(wall["padding"]) == 0
    old_columns = int(wall["__cWid"])
    new_columns = old_columns * 2
    wall_uid = wall["uid"]
    for selection in wall["savedSelections"]:
        selection["ids"] = _ids(selection["ids"], old_columns, new_columns)
    for tag in wall["enumTags"]:
        tag["tileIds"] = _ids(tag["tileIds"], old_columns, new_columns)
    wall["customData"] = [{**entry, "tileId": t}
                          for entry in wall["customData"]
                          for t in _ids([entry["tileId"]], old_columns, new_columns)]
    wall.update(tileGridSize=8, __cWid=new_columns, __cHei=int(wall["__cHei"]) * 2)
    with Image.open(ROOT / wall["relPath"]) as source:
        image = source.convert("RGBA")
        assert image.size == (int(wall["pxWid"]), int(wall["pxHei"]))
        opaque, colors = [], []
        for y in range(0, image.height, 8):
            for x in range(0, image.width, 8):
                tile = image.crop((x, y, x + 8, y + 8))
                opaque.append("1" if tile.getchannel("A").getextrema() == (255, 255) else "0")
                red, green, blue, alpha = ImageStat.Stat(tile).mean
                colors.append("".join(f"{min(15, round(c / 17)):x}" for c in (alpha, red, green, blue)))
        wall["cachedPixelData"] = {"opaqueTiles": "".join(opaque), "averageColors": "".join(colors)}
    layer_uids = set()
    for layer in definitions["layers"]:
        if layer.get("tilesetDefUid") == wall_uid:
            assert layer["identifier"].startswith("Walls") and layer["type"] == "Tiles"
            assert int(layer["gridSize"]) == 16 and not layer["autoRuleGroups"]
            layer["gridSize"] = 8
            layer_uids.add(layer["uid"])
    for level in data["levels"]:
        for layer in level["layerInstances"]:
            if layer["layerDefUid"] not in layer_uids:
                continue
            assert layer["__tilesetDefUid"] == wall_uid and not layer["autoLayerTiles"]
            layer["__gridSize"] = 8
            layer["__cWid"] = int(layer["__cWid"]) * 2
            layer["__cHei"] = int(layer["__cHei"]) * 2
            layer["gridTiles"] = [part for tile in layer["gridTiles"]
                                  for part in subdivide_tile(tile, new_columns, layer["__cWid"])]
    return True


def assert_scope(before: dict, after: dict) -> None:
    """Reject any accidental edit outside wall metadata and wall instances."""
    restored = deepcopy(after)
    for i, source in enumerate(before["defs"]["tilesets"]):
        if str(source["relPath"]).replace("\\", "/").endswith("/wall_tileset.png"):
            restored["defs"]["tilesets"][i] = source
    for i, layer in enumerate(before["defs"]["layers"]):
        if layer["identifier"].startswith("Walls"):
            restored["defs"]["layers"][i] = layer
    for level_index, level in enumerate(before["levels"]):
        for i, layer in enumerate(level["layerInstances"]):
            if layer["__identifier"].startswith("Walls"):
                restored["levels"][level_index]["layerInstances"][i] = layer
    assert restored == before, "A non-wall value changed"


def configure(apply: bool) -> None:
    original = PROJECT.read_bytes()
    before = json.loads(original.decode("utf-8-sig"))
    data = deepcopy(before)
    if not convert_data(data):
        print("Wall atlas already 8px; authored project unchanged.")
        return
    assert_scope(before, data)
    print("Only wall atlas and WallsBack/Sides/Front become 8px. All other data unchanged.")
    if not apply:
        print("Dry run. Use --apply to save, with an exact backup.")
        return
    assert PROJECT.read_bytes() == original, "LDtk saved during conversion; retry with the newest map"
    digest = hashlib.sha256(original).hexdigest()[:12]
    backup = ROOT / "ldtk_backups" / f"before_walls_8_{digest}.ldtk"
    backup.parent.mkdir(exist_ok=True)
    if not backup.exists():
        backup.write_bytes(original)
    assert backup.read_bytes() == original
    PROJECT.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Existing paint/stamps subdivided in place. Backup: {backup}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apply", action="store_true")
    configure(parser.parse_args().apply)
