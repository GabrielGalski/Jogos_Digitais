"""Configure direct PNG sources; explicitly reset the old LDtk maps once.

Never changes MonsterShift. An exact, recoverable backup precedes the reset.
Re-running after conversion is a no-op, including after the user paints maps.
"""

from __future__ import annotations

import argparse
import copy
import hashlib
import json
import uuid
from pathlib import Path

from PIL import Image, ImageStat

ROOT = Path(__file__).resolve().parents[1]
MAP = ROOT / "monster_booster.ldtk"


def configure(apply: bool, clear_maps: bool) -> None:
    original = MAP.read_bytes()
    data = json.loads(original.decode("utf-8-sig"))
    if any(layer["identifier"] == "Gameplay" for layer in data["defs"]["layers"]) and all(
        "/editor/" not in tile["relPath"] for tile in data["defs"]["tilesets"]
    ):
        print("Direct sprites already configured; authored maps left untouched.")
        return
    if not clear_maps:
        raise SystemExit("This one-time reset requires --clear-maps. Backups are automatic.")
    before = copy.deepcopy(data)
    templates = before["defs"]
    next_uid = int(data["nextUid"])

    def uid() -> int:
        nonlocal next_uid
        result = next_uid
        next_uid += 1
        return result

    def atlas(name: str, path: str, grid: int = 16, fixed_uid: int | None = None) -> dict:
        result = copy.deepcopy(templates["tilesets"][0])
        with Image.open(ROOT / path) as image:
            rgba = image.convert("RGBA")
            width, height = rgba.size
            assert width % grid == 0 and height % grid == 0, (path, width, height, grid)
            opaque, colors = [], []
            for y in range(0, height, grid):
                for x in range(0, width, grid):
                    tile = rgba.crop((x, y, x + grid, y + grid))
                    opaque.append("1" if tile.getchannel("A").getextrema() == (255, 255) else "0")
                    red, green, blue, alpha = ImageStat.Stat(tile).mean
                    colors.append("".join(f"{min(15, round(c / 17)):x}" for c in (alpha, red, green, blue)))
        result.update(identifier=name, uid=fixed_uid if fixed_uid is not None else uid(), relPath=path,
                      pxWid=width, pxHei=height, __cWid=width // grid, __cHei=height // grid,
                      tileGridSize=grid, spacing=0, padding=0, customData=[], enumTags=[], tags=[],
                      savedSelections=[], embedAtlas=None,
                      cachedPixelData={"opaqueTiles": "".join(opaque), "averageColors": "".join(colors)})
        return result

    floor = atlas("Floor_16", "assets/tiles/floor/floor_tileset.png", fixed_uid=101)
    underside = atlas("PlatformUnderside_16", "assets/tiles/inferior/inferior.png", fixed_uid=102)
    wall = atlas("Wall_16", "assets/tiles/wall/wall_tileset.png", fixed_uid=103)
    # Native 64/48/32/16px strips from the same source, not copied PNGs.
    for y in (1, 5, 9, 13):
        for width in (4, 3, 2, 1):
            wall["savedSelections"].append({"ids": [(y + row) * 16 + 12 + col
                                                     for row in range(3) for col in range(width)], "mode": "Stamp"})
    square = atlas("ColumnSquare_16", "assets/tiles/wall/decor/column_square.png", fixed_uid=105)
    rounded = atlas("ColumnRound_16", "assets/tiles/wall/decor/column_round.png")
    stair = atlas("Stair_4", "assets/tiles/wall/decor/stair.png", grid=4)
    for tile in (square, rounded, stair):
        tile["savedSelections"] = [{"ids": list(range(tile["__cWid"] * tile["__cHei"])), "mode": "Stamp"}]
    doors = [atlas("Door" + label + "_16", "assets/tiles/door/" + filename,
                   fixed_uid=104 if index == 0 else None)
             for index, (label, filename) in enumerate([
                 ("ClosedSuperior", "door_front_closed_superior.png"),
                 ("OpenedSuperior", "door_front_opened_superior.png"),
                 ("ClosedInferior", "door_front_closed_inferior.png"),
                 ("OpenedInferior", "door_front_opened_inferior.png")])]
    for tile in doors:
        tile["savedSelections"] = [{"ids": [0, 1, 2, 3], "mode": "Stamp"}]
    thrones = [copy.deepcopy(t) for t in templates["tilesets"] if t["uid"] in (106, 107, 108)]
    icons = {
        "NoxStart": atlas("NoxMarker", "assets/characters/player/idle/player_idle_01.png", grid=1, fixed_uid=109),
        "Tin": atlas("TinMarker", "assets/merchant/character/merchant_idle1.png", grid=1),
        "MinotaurSpawn": atlas("MinotaurMarker", "assets/enemies/minotaur/walk/minotaur_walk_01.png", grid=1),
    }
    data["defs"]["tilesets"] = [floor, underside, wall, square, rounded, stair, *doors, *thrones, *icons.values()]

    def layer(name: str, tile: dict, template_name: str, fixed_uid: int | None = None) -> dict:
        result = copy.deepcopy(next(l for l in templates["layers"] if l["identifier"] == template_name))
        result.update(identifier=name, uid=fixed_uid if fixed_uid is not None else uid(),
                      tilesetDefUid=tile["uid"], gridSize=tile["tileGridSize"])
        return result

    layers = []
    for old in templates["layers"]:
        name = old["identifier"]
        if name in ("ObjectsFront", "ObjectsBack"):
            layers.extend([layer(name + "Square", square, name, old["uid"]),
                           layer(name + "Round", rounded, name), layer(name + "Stair", stair, name)])
        elif name == "Doors":
            layers.extend(layer("Doors" + d["identifier"][4:-3], d, name,
                                old["uid"] if index == 0 else None) for index, d in enumerate(doors))
        else:
            layers.append(copy.deepcopy(old))
    gameplay = copy.deepcopy(next(l for l in templates["layers"] if l["identifier"] == "Collisions"))
    gameplay.update(identifier="Gameplay", uid=uid(), doc="Door Dash: DashGap permite travessia somente durante dash; andar ou parar no vao retorna ao Start.")
    gameplay["intGridValues"] = [
        {"value": value, "identifier": name, "color": color, "tile": None, "groupUid": 0}
        for value, name, color in [(1, "MapLimit", "#25131A"), (2, "DashGap", "#9B86C8"),
                                   (3, "DoorBlock", "#FF4E91"), (4, "Start", "#2CF7A3"), (5, "End", "#E9CF6A")]
    ]
    layers.insert(0, gameplay)
    data["defs"]["layers"] = layers
    for entity in data["defs"]["entities"]:
        if entity["identifier"] in icons:
            source = icons[entity["identifier"]]
            entity.update(tilesetId=source["uid"], tileRect={"tilesetUid": source["uid"], "x": 0, "y": 0,
                                                          "w": source["pxWid"], "h": source["pxHei"]})
        if entity["identifier"] == "NoxStart":
            entity["doc"] = "Ponto de entrada e respawn de Nox, usado tambem para retorno do DoorDash."
    dash_entity = copy.deepcopy(next(e for e in templates["entities"] if e["identifier"] == "RoomTrigger"))
    dash_entity.update(identifier="DoorDash", uid=uid(), width=32, height=48, resizableX=True,
                       resizableY=True, minWidth=16, minHeight=16, maxWidth=None, maxHeight=None,
                       pivotX=0, pivotY=0, renderMode="Rectangle", tilesetId=None, tileRect=None,
                       uiTileRect=None, color="#9B86C8", fillOpacity=0.18, lineOpacity=1, hollow=False,
                       doc="Vao atravessavel durante dash. Sem dash, retorna ao ultimo Start/NoxStart, sem dano.")
    data["defs"]["entities"].append(dash_entity)

    level = copy.deepcopy(before["levels"][0])
    level.update(identifier="RoomTemplate_30x16", uid=401, iid=str(uuid.uuid4()), pxWid=480, pxHei=256,
                 worldX=0, worldY=0, __neighbours=[], fieldInstances=[], bgPos=None, bgRelPath=None,
                 __bgPos=None, layerInstances=[])
    templates_by_type = {instance["__type"]: instance for instance in before["levels"][0]["layerInstances"]}
    for definition in layers:
        kind = definition["type"]
        item = copy.deepcopy(templates_by_type[kind])
        grid = definition["gridSize"]
        columns, rows = level["pxWid"] // grid, level["pxHei"] // grid
        source = next((t for t in data["defs"]["tilesets"] if t["uid"] == definition["tilesetDefUid"]), None)
        item.update(__identifier=definition["identifier"], __type=kind, __cWid=columns, __cHei=rows,
                    __gridSize=grid, __tilesetDefUid=definition["tilesetDefUid"],
                    __tilesetRelPath=source["relPath"] if source else None, iid=str(uuid.uuid4()),
                    levelId=401, layerDefUid=definition["uid"], intGridCsv=[0] * (columns * rows) if kind == "IntGrid" else [],
                    autoLayerTiles=[], gridTiles=[], entityInstances=[], overrideTilesetUid=None,
                    pxOffsetX=0, pxOffsetY=0, __pxTotalOffsetX=0, __pxTotalOffsetY=0)
        level["layerInstances"].append(item)
    data["levels"] = [level]
    data["worlds"] = []
    data["nextUid"] = next_uid
    data["tutorialDesc"] = "Sprites PNG diretos. Pinte Floor e Wall; DoorDash em Entities ou DashGap em Gameplay cria o vao de dash. Consulte docs/GUIA.md."
    identifiers = {t["identifier"] for t in data["defs"]["tilesets"]}
    assert "Wall_16" in identifiers and not any("/editor/" in t["relPath"] for t in data["defs"]["tilesets"])
    assert all(not l["gridTiles"] and not l["entityInstances"] and not any(l["intGridCsv"]) for l in level["layerInstances"])
    print(f"Reset {len(before['levels'])} LDtk maps; one empty 30x16 sandbox, {len(data['defs']['tilesets'])} direct PNG sources.")
    if not apply:
        print("Dry run; nothing changed. Use --apply --clear-maps.")
        return
    assert MAP.read_bytes() == original, "LDtk changed during configuration; retry after closing/saving the editor."
    backup = ROOT / "ldtk_backups" / ("before_direct_sprites_" + hashlib.sha256(original).hexdigest()[:12] + ".ldtk")
    backup.parent.mkdir(parents=True, exist_ok=True)
    if backup.exists():
        assert backup.read_bytes() == original
    else:
        backup.write_bytes(original)
    MAP.write_text(json.dumps(data, ensure_ascii=False, indent="\t") + "\n", encoding="utf-8")
    print("Recoverable backup:", backup)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apply", action="store_true")
    parser.add_argument("--clear-maps", action="store_true")
    arguments = parser.parse_args()
    configure(arguments.apply, arguments.clear_maps)
