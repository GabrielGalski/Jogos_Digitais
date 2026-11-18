"""Bake the exposed south-facing floor into Room 4's existing decorative layer."""
from copy import deepcopy
from pathlib import Path
import json

from PIL import Image
from configure_elemental_ldtk import ROOT, ROOM, serialize, editor_busy

ATLAS = "assets/tiles/floor/dungeon/platform_underside.png"


def extrude(top):
    """Follow the last opaque pixel, so chamfers cast a sloping brick face too."""
    mask = top.getchannel("A").load()
    face = Image.new("RGBA", top.size)
    pixels = face.load()
    for x in range(top.width):
        depth = 24
        for y in range(top.height):
            if mask[x, y]:
                depth = 0
                continue
            if depth >= 24:
                continue
            d = depth
            depth += 1
            # Courses follow the lip around bevels; offset the vertical joints.
            course, row = divmod(d, 7)
            u = (x + (course % 2) * 14) % 28
            value = 0.81 if row == 6 or u == 0 else 1.08 if row == 0 or u == 1 else 1.
            shade = value * (1. - d / 24) ** 1.25
            pixels[x, y] = tuple(round(v * shade) for v in (72, 44, 66)) + (255,)
    return face


def upper_rim(top):
    """Thin masonry coping on the walking surface, with returns down exposed sides."""
    alpha = top.getchannel("A").load()
    cap = Image.new("RGBA", top.size)
    out = cap.load()
    for y in range(top.height):
        for x in range(top.width):
            if not alpha[x, y]:
                continue
            # Ignore the canvas boundary: the corridor continues through it.
            north = next((i for i in range(1, 9) if y >= i and not alpha[x,y-i]), 99)
            side = next((i for i in range(1, 6) if (x >= i and not alpha[x-i,y])
                         or (x+i < top.width and not alpha[x+i,y])), 99)
            if min(north, side) == 99:
                continue
            horizontal = north <= side or side == 99
            d, span, u = (north, 8, x % 28) if horizontal else (side, 5, (y+14) % 28)
            if d == 1: color = (48, 29, 45)
            elif d == span or u == 0: color = (59, 35, 52)
            elif d == 2 or u == 1: color = (92, 57, 80)
            else: color = (77, 46, 66)
            out[x,y] = color + (255,)
    return cap


def main():
    path = ROOT / "monster_booster.ldtk"
    original = path.read_bytes()
    before = json.loads(original)
    data = deepcopy(before)
    room = next(r for r in data["levels"] if r["identifier"] == ROOM)
    layers = {l["__identifier"]: l for l in room["layerInstances"]}
    floor, under = layers["Floor_Elemental"], layers["PlatformUnderside"]
    if under["gridTiles"] and under["__tilesetRelPath"] != ATLAS:
        raise ValueError("PlatformUnderside already has a different painting")
    source = Image.open(ROOT / floor["__tilesetRelPath"]).convert("RGBA")
    top = Image.new("RGBA", (room["pxWid"], room["pxHei"]))
    for t in floor["gridTiles"]:
        x, y = t["src"]
        g = floor["__gridSize"]
        tile = source.crop((x, y, x+g, y+g))
        if t["f"] & 1: tile = tile.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
        if t["f"] & 2: tile = tile.transpose(Image.Transpose.FLIP_TOP_BOTTOM)
        top.alpha_composite(tile, (t["px"][0]+floor["__pxTotalOffsetX"], t["px"][1]+floor["__pxTotalOffsetY"]))
    face = extrude(top)
    rim = upper_rim(top)
    cap_layer = layers["TerrainCliffRim"]
    if cap_layer["gridTiles"] and cap_layer["__tilesetRelPath"] != ATLAS:
        raise ValueError("TerrainCliffRim already has a different painting")
    # The first rows form a reusable, continuous brush for the original floor model.
    model = Image.new("RGBA", (source.width, source.height+32))
    model.paste(source)
    cut = extrude(model)
    atlas = Image.new("RGBA", (256, 256))
    model_strip = cut.crop((0, source.height-32, source.width, source.height+32))
    atlas.paste(model_strip)
    ids = {}
    for y in range(0, model_strip.height, 16):
        for x in range(0, model_strip.width, 16):
            ids.setdefault(atlas.crop((x,y,x+16,y+16)).tobytes(), (x,y))
    next_id = 64
    def pack(layer, image):
        nonlocal next_id
        tiles = []
        for n in range(layer["__cWid"] * layer["__cHei"]):
            row, col = divmod(n, layer["__cWid"])
            x, y = col*16+layer["__pxTotalOffsetX"], row*16+layer["__pxTotalOffsetY"]
            tile = image.crop((x,y,x+16,y+16))
            if not tile.getbbox(): continue
            key = tile.tobytes()
            if key not in ids:
                if next_id >= 256: raise ValueError("Atlas capacity exceeded")
                ids[key] = (next_id%16*16, next_id//16*16)
                next_id += 1
                atlas.paste(tile, ids[key])
            sx, sy = ids[key]
            tiles.append(dict(px=[col*16,row*16], src=[sx,sy], f=0, t=sy//16*16+sx//16,
                              d=[n], a=1))
        return tiles
    tiles = pack(under, face)
    caps = pack(cap_layer, rim)
    definition = next((t for t in data["defs"]["tilesets"] if t["relPath"] == ATLAS), None)
    if definition is None:
        definition = deepcopy(next(t for t in data["defs"]["tilesets"] if t["uid"] == floor["__tilesetDefUid"]))
        definition.update(identifier="DungeonPlatformUnderside", uid=data["nextUid"], relPath=ATLAS,
                          pxWid=256, pxHei=256, __cWid=16, __cHei=16, tileGridSize=16,
                          cachedPixelData=None, savedSelections=[], customData=[], enumTags=[])
        data["nextUid"] += 1
        data["defs"]["tilesets"].append(definition)
    under.update(gridTiles=tiles, overrideTilesetUid=definition["uid"],
                 __tilesetDefUid=definition["uid"], __tilesetRelPath=ATLAS)
    cap_layer.update(gridTiles=caps, overrideTilesetUid=definition["uid"],
                     __tilesetDefUid=definition["uid"], __tilesetRelPath=ATLAS)
    payload = serialize(original, before, data) if before != data else original
    if editor_busy() or path.read_bytes() != original:
        raise RuntimeError("LDtk is open or the map changed during bake")
    atlas.save(ROOT / ATLAS)
    if before != data:
        tmp = path.with_suffix(".underside.tmp")
        tmp.write_bytes(payload)
        tmp.replace(path)
    preview = Image.new("RGBA", top.size, "black")
    preview.alpha_composite(face)
    preview.alpha_composite(top)
    preview.alpha_composite(rim)
    output = ROOT / "output/elemental_golem"
    output.mkdir(exist_ok=True, parents=True)
    preview.convert("RGB").save(output / "platform_floor_preview.png")
    print(f"{len(tiles)} decorative tiles; original floor and gameplay layers preserved")


if __name__ == "__main__":
    main()
