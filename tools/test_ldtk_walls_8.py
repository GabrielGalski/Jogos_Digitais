"""Prepare isolated old/new wall fixtures; prove pixels and non-wall data match."""
from copy import deepcopy
import json
from pathlib import Path

from PIL import Image

from configure_ldtk_walls_8 import ROOT, PROJECT, assert_scope, convert_data


def compose(source: Image.Image, layer: dict, grid: int, width: int, height: int) -> Image.Image:
    canvas = Image.new("RGBA", (width, height))
    for tile in layer["gridTiles"]:
        sx, sy = map(int, tile["src"])
        part = source.crop((sx, sy, sx + grid, sy + grid))
        if int(tile["f"]) & 1:
            part = part.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
        if int(tile["f"]) & 2:
            part = part.transpose(Image.Transpose.FLIP_TOP_BOTTOM)
        alpha = float(tile.get("a", 1))
        if alpha != 1:
            part.putalpha(part.getchannel("A").point(lambda a: round(a * alpha)))
        canvas.alpha_composite(part, dest=tuple(map(int, tile["px"])))
    return canvas


def prepare() -> None:
    authored = json.loads(PROJECT.read_bytes())
    assert next(t["tileGridSize"] for t in authored["defs"]["tilesets"] if t["uid"] == 103) == 16
    before = deepcopy(authored)
    level = before["levels"][0]
    level["pxWid"], level["pxHei"] = 1024, 256
    for layer in level["layerInstances"]:
        layer["__cWid"], layer["__cHei"] = 64, 16
        layer["gridTiles"], layer["autoLayerTiles"], layer["entityInstances"] = [], [], []
        layer["intGridCsv"] = [0] * 1024 if layer["__type"] == "IntGrid" else []
        if layer["__identifier"] == "WallsBack":
            layer["gridTiles"] = [
                {"px": [x * 16 + flip * 256, y * 16], "src": [x * 16, y * 16],
                 "t": y * 16 + x, "f": flip, "d": [y * 64 + x + flip * 16], "a": 1}
                for flip in range(4) for y in range(16) for x in range(16)]
        elif layer["__identifier"] == "Floor":
            layer["gridTiles"] = [{"px": [x * 16, y * 16], "src": [16, 16], "t": 5,
                                   "f": 0, "d": [y * 64 + x], "a": 1}
                                  for y in range(16) for x in range(64)]
    tmp = ROOT / "tmp"
    tmp.mkdir(exist_ok=True)
    source = Image.open(ROOT / "assets/tiles/wall/wall_tileset.png").convert("RGBA")
    for label, old in [("authored", authored), ("flips", before)]:
        new = deepcopy(old)
        assert convert_data(new)
        assert_scope(old, new)
        for old_level, new_level in zip(old["levels"], new["levels"]):
            for old_layer, new_layer in zip(old_level["layerInstances"], new_level["layerInstances"]):
                if old_layer["__identifier"].startswith("Walls"):
                    args = (int(old_level["pxWid"]), int(old_level["pxHei"]))
                    old_image = compose(source, old_layer, 16, *args)
                    new_image = compose(source, new_layer, 8, *args)
                    assert old_image.tobytes() == new_image.tobytes(), (label, old_layer["__identifier"])
        for kind, value in [("before", old), ("after", new)]:
            (tmp / f"walls_8_{label}_{kind}.ldtk").write_text(json.dumps(value), encoding="utf-8")
    print("Wall subdivision PASS: authored pixels identical; all atlas tiles with H/V/HV flips identical; all non-wall data unchanged.")


if __name__ == "__main__":
    prepare()
