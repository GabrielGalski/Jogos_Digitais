"""Move the elemental blockout into Room_4_Elemental without repainting other rooms."""
from __future__ import annotations

import argparse
from copy import deepcopy
from datetime import datetime
import hashlib
import json
import math
import os
from pathlib import Path
import struct
import tempfile
import uuid

from configure_ldtk_water import all_levels, editor_busy
from ldtk_editor_coordinates import synchronize_level
from ldtk_field_values import set_value

ROOT = Path(__file__).resolve().parents[1]
ROOM = "Room_4_Elemental"
FLOOR = "assets/tiles/floor/dungeon/floor.png"
GRID = 8
SIZE = (672, 864)
HALL = (224, 464, 224, 384)
PLATFORMS = [(24 + column * 216, 32 + row * 152, 192, 128)
             for row in range(3) for column in range(3)]
LAYER_NAMES = ("ElementalLayout", "Floor_Elemental")


def identity(room: dict, label: str) -> str:
    return str(uuid.uuid5(uuid.UUID(room["iid"]), "elemental:" + label))


def empty_layer(room: dict, definition: dict, tilesets: dict) -> dict:
    grid = definition["gridSize"]
    source = tilesets.get(definition.get("tilesetDefUid"), {})
    width, height = math.ceil(room["pxWid"] / grid), math.ceil(room["pxHei"] / grid)
    return dict(__identifier=definition["identifier"], __type=definition["type"],
                __cWid=width, __cHei=height, __gridSize=grid,
                __opacity=definition["displayOpacity"], __pxTotalOffsetX=0, __pxTotalOffsetY=0,
                __tilesetDefUid=definition.get("tilesetDefUid"), __tilesetRelPath=source.get("relPath"),
                iid=identity(room, definition["identifier"]), levelId=room["uid"], layerDefUid=definition["uid"],
                pxOffsetX=0, pxOffsetY=0, visible=False if definition["identifier"] == "ElementalLayout" else True,
                optionalRules=[], intGridCsv=[0] * (width * height) if definition["type"] == "IntGrid" else [],
                autoLayerTiles=[], seed=9137, overrideTilesetUid=None, gridTiles=[], entityInstances=[])


def convert(data: dict) -> dict:
    before = deepcopy(data)
    room = next(level for level in all_levels(data) if level["identifier"] == ROOM)
    definitions = data["defs"]

    def allocate() -> int:
        result = data["nextUid"]
        data["nextUid"] += 1
        return result

    atlas = next((item for item in definitions["tilesets"] if item["relPath"] == FLOOR), None)
    if atlas is None:
        width, height = struct.unpack(">II", (ROOT / FLOOR).read_bytes()[16:24])
        atlas = deepcopy(definitions["tilesets"][0])
        atlas.update(identifier="DungeonFloor_8", uid=allocate(), relPath=FLOOR,
                     pxWid=width, pxHei=height, __cWid=math.ceil(width / GRID), __cHei=math.ceil(height / GRID),
                     tileGridSize=GRID, padding=0, spacing=0, embedAtlas=None,
                     tags=["floor", "dungeon"], tagsSourceEnumUid=None, enumTags=[], customData=[],
                     savedSelections=[], cachedPixelData=None)
        definitions["tilesets"].append(atlas)
    if atlas["tileGridSize"] != GRID:
        raise ValueError("Dungeon floor already has another authored grid; map preserved")

    added = []
    for name, template, kind, source, anchor in (
        ("ElementalLayout", "Gameplay", "IntGrid", None, "Gameplay"),
        ("Floor_Elemental", "Floor", "Tiles", atlas["uid"], "Floor"),
    ):
        definition = next((item for item in definitions["layers"] if item["identifier"] == name), None)
        if definition is None:
            definition = deepcopy(next(item for item in definitions["layers"] if item["identifier"] == template))
            definition.update(identifier=name, uid=allocate(), type=kind, __type=kind, gridSize=GRID,
                              tilesetDefUid=source, displayOpacity=0.3 if kind == "IntGrid" else 1,
                              uiColor="#795A88", intGridValues=[], intGridValuesGroups=[],
                              autoRuleGroups=[], autoSourceLayerDefUid=None)
            definition["doc"] = (
                "ELEMENTAL / Grade 8px: Void preto, Wall solido, Hall e Platform_1..9 seguros. "
                "Identificadores das plataformas orientam a IA. Alternar visibilidade para editar regras; "
                "pintura em Floor_Elemental e Walls existentes. Usado apenas em Room_4_Elemental."
                if kind == "IntGrid" else
                "ELEMENTAL / Piso da dungeon, PNG original em grade 8px; regras em ElementalLayout. "
                "Deixar Void sem tiles; nao ha agua. Usado em Room_4_Elemental."
            )
            if kind == "IntGrid":
                brushes = [(1, "Void", "#000000"), (2, "Wall", "#33233F"), (3, "Hall", "#795A88")]
                brushes += [(11 + index, "Platform_%d" % (index + 1), "#795A88") for index in range(9)]
                definition["intGridValues"] = [dict(value=value, identifier=label, color=color, tile=None, groupUid=0)
                                                for value, label, color in brushes]
            index = next(index for index, item in enumerate(definitions["layers"]) if item["identifier"] == anchor)
            definitions["layers"].insert(index, definition)
            added.append(definition["uid"])
        if definition["gridSize"] != GRID or definition["type"] != kind or definition["tilesetDefUid"] != source:
            raise ValueError("Existing elemental layer contract differs: " + name)

    spawn = next((item for item in definitions["entities"] if item["identifier"] == "ElementalGolemSpawn"), None)
    if spawn is None:
        spawn = deepcopy(next(item for item in definitions["entities"] if item["identifier"] == "SpiritHordeArea"))
        spawn.update(identifier="ElementalGolemSpawn", uid=allocate(), tags=["gameplay"],
                     doc="ELEMENTAL / Ponto inicial dos pes do golem. Colocar sobre uma Platform em ElementalLayout.",
                     width=16, height=16, resizableX=False, resizableY=False,
                     minWidth=None, maxWidth=None, minHeight=None, maxHeight=None,
                     pivotX=0.5, pivotY=0.5, color="#36A0F1", renderMode="Cross", showName=True,
                     tileRect=None, uiTileRect=None, tilesetId=None, tileOpacity=0, fieldDefs=[],
                     maxCount=1, limitScope="PerLevel", limitBehavior="DiscardOldOnes")
        definitions["entities"].append(spawn)

    tilesets = {item["uid"]: item for item in definitions["tilesets"]}
    order = {item["uid"]: index for index, item in enumerate(definitions["layers"])}
    for level in all_levels(data):
        for definition in definitions["layers"]:
            if definition["identifier"] in LAYER_NAMES and not any(a["layerDefUid"] == definition["uid"] for a in level["layerInstances"]):
                level["layerInstances"].append(empty_layer(level, definition, tilesets))
        level["layerInstances"].sort(key=lambda item: order[item["layerDefUid"]])

    layout = next(item for item in room["layerInstances"] if item["__identifier"] == "ElementalLayout")
    if any(layout["intGridCsv"]):
        # Once authored, the room is the source of truth; do not regenerate over edits.
        assert_preserved(before, data)
        return dict(changed=data != before, already_authored=True, room=ROOM)
    if any(a["gridTiles"] or a["autoLayerTiles"] or a["entityInstances"] or any(a["intGridCsv"]) for a in room["layerInstances"]):
        raise ValueError("Room_4_Elemental already has authored content; refusing to repaint it")

    room.update(pxWid=SIZE[0], pxHei=SIZE[1], bgColor="#000000", __bgColor="#000000", __smartColor="#795A88")
    for layer in room["layerInstances"]:
        grid = layer["__gridSize"]
        layer["__cWid"], layer["__cHei"] = math.ceil(SIZE[0] / grid), math.ceil(SIZE[1] / grid)
        if layer["__type"] == "IntGrid":
            layer["intGridCsv"] = [0] * (layer["__cWid"] * layer["__cHei"])
    layers = {item["__identifier"]: item for item in room["layerInstances"]}
    layout = layers["ElementalLayout"]
    columns = layout["__cWid"]
    layout["intGridCsv"] = [1] * (columns * layout["__cHei"])

    def paint(rect: tuple, value: int) -> None:
        left, top, width, height = rect
        for y in range(top // GRID, (top + height) // GRID):
            for x in range(left // GRID, (left + width) // GRID):
                layout["intGridCsv"][x + y * columns] = value

    paint((0, 0, SIZE[0], 16), 2)
    paint((0, 16, 8, SIZE[1] - 16), 2)
    paint((SIZE[0] - 8, 16, 8, SIZE[1] - 16), 2)
    paint((0, SIZE[1] - 16, SIZE[0], 16), 2)
    paint(HALL, 3)
    for index, rect in enumerate(PLATFORMS): paint(rect, 11 + index)

    def tile(layer: dict, point: tuple, source: tuple, flip: int = 0) -> None:
        source_def = tilesets[layer["__tilesetDefUid"]]
        grid = layer["__gridSize"]
        x, y = point
        sx, sy = source
        layer["gridTiles"].append(dict(px=[x, y], src=[sx, sy], f=flip,
                                       t=sx // grid + sy // grid * source_def["__cWid"],
                                       d=[x // grid + y // grid * layer["__cWid"]], a=1))

    for rect in PLATFORMS + [HALL]:
        left, top, width, height = rect
        for y in range(top, top + height, GRID):
            for x in range(left, left + width, GRID):
                source = (16 + (x // GRID % 12) * GRID, 16 + (y // GRID % 7) * GRID)
                flip = 0
                if y in (top, top + height - GRID):
                    source, flip = (16 + (x // GRID % 12) * GRID, 0), 2 if y > top else 0
                elif x in (left, left + width - GRID):
                    source, flip = (0, 16 + (y // GRID % 7) * GRID), 1 if x > left else 0
                # The corridor joins the bottom-centre platform without an internal trim.
                if HALL[0] <= x < HALL[0] + HALL[2] and y in (HALL[1] - GRID, HALL[1]):
                    source, flip = (16 + (x // GRID % 12) * GRID, 16), 0
                tile(layers["Floor_Elemental"], (x, y), source, flip)
    for y in range(0, SIZE[1], GRID):
        for x in range(0, SIZE[0], GRID):
            if layout["intGridCsv"][x // GRID + y // GRID * columns] != 2: continue
            name = "WallsBack" if y < 16 else "WallsFront" if y >= SIZE[1] - 16 else "WallsSides"
            sy = 16 + y if y < 16 else 48 + (y % 16) if y >= SIZE[1] - 16 else 32
            tile(layers[name], (x, y), (16, sy), 1 if x == SIZE[0] - GRID else 0)

    def entity(definition: dict, label: str, position: tuple, values: dict) -> dict:
        fields = []
        for field in definition["fieldDefs"]:
            default = field.get("defaultOverride")
            value = values.get(field["identifier"], default["params"][0] if default else "")
            entry = dict(__identifier=field["identifier"], __type=field["__type"], __value=None,
                         __tile=None, defUid=field["uid"], realEditorValues=[])
            set_value(entry, value)
            fields.append(entry)
        return dict(__identifier=definition["identifier"], __grid=[position[0] // 16, position[1] // 16],
                    __pivot=[definition["pivotX"], definition["pivotY"]], __tags=definition["tags"],
                    __tile=deepcopy(definition.get("tileRect")), __worldX=room["worldX"] + position[0],
                    __worldY=room["worldY"] + position[1], iid=identity(room, label),
                    width=definition["width"], height=definition["height"], defUid=definition["uid"],
                    px=list(position), fieldInstances=fields)

    warp = next(item for item in definitions["entities"] if item["identifier"] == "Warp")
    layers["GameplayAreas"]["entityInstances"] = [
        entity(warp, "entry", (336, 800), dict(WarpId="elemental_entry", IsEntrance=True,
               Interact=True, Enabled=True, TargetScene="res://scenes/maps/open_world.tscn")),
        entity(spawn, "boss", (336, 96), {}),
    ]
    synchronize_level(room)
    assert_preserved(before, data)
    return dict(changed=data != before, room=ROOM, size=list(SIZE), platforms=9,
                floor_tiles=len(layers["Floor_Elemental"]["gridTiles"]),
                void_cells=layout["intGridCsv"].count(1), dungeon_tileset=atlas["identifier"])


def assert_preserved(before: dict, after: dict) -> None:
    restored = deepcopy(after)
    for key in ("entities", "tilesets", "layers"):
        previous = {item["uid"] for item in before["defs"][key]}
        restored["defs"][key] = [item for item in restored["defs"][key] if item["uid"] in previous]
    for old, new in zip(all_levels(before), all_levels(restored), strict=True):
        if old["identifier"] == ROOM:
            new.clear()
            new.update(deepcopy(old))
        else:
            previous = {item["layerDefUid"] for item in old["layerInstances"]}
            new["layerInstances"] = [item for item in new["layerInstances"] if item["layerDefUid"] in previous]
    restored["nextUid"] = before["nextUid"]
    if restored != before:
        raise AssertionError("Migration altered existing levels or definitions")


def serialize(original: bytes, before: dict, after: dict) -> bytes:
    """Patch new entries and this room only; keep every other painted layer byte-for-byte."""
    text = original.decode("utf-8-sig")
    newline = "\r\n" if "\r\n" in text else "\n"
    decoder = json.JSONDecoder()
    edits = []

    def skip(index: int) -> int:
        while text[index].isspace(): index += 1
        return index

    def span(path: tuple) -> tuple:
        start = skip(0)
        for part in path:
            cursor = skip(start + 1)
            if isinstance(part, str):
                while text[cursor] != "}":
                    key, end = decoder.raw_decode(text, cursor)
                    value = skip(skip(end) + 1)
                    _, end = decoder.raw_decode(text, value)
                    if key == part:
                        start = value
                        break
                    cursor = skip(end)
                    if text[cursor] == ",": cursor = skip(cursor + 1)
                else: raise ValueError("Missing JSON path: " + str(path))
            else:
                for _ in range(part):
                    _, cursor = decoder.raw_decode(text, cursor)
                    cursor = skip(skip(cursor) + 1)
                start = cursor
        _, end = decoder.raw_decode(text, start)
        return start, end

    def formatted(value, start: int) -> str:
        indent = text[text.rfind("\n", 0, start) + 1:start]
        return json.dumps(value, ensure_ascii=False, indent="\t").replace("\n", newline + indent)

    def insert(path: tuple, old: list, new: list, key: str) -> None:
        array_start, _ = span(path)
        cursor = skip(array_start + 1)
        positions = {}
        for item in old:
            _, end = decoder.raw_decode(text, cursor)
            positions[item[key]] = (cursor, end)
            cursor = skip(end)
            if text[cursor] == ",": cursor = skip(cursor + 1)
        pending = []
        for item in new:
            if item[key] not in positions:
                pending.append(item)
            elif pending:
                start = positions[item[key]][0]
                indent = text[text.rfind("\n", 0, start) + 1:start]
                payload = ("," + newline + indent).join(formatted(entry, start) for entry in pending)
                edits.append((start, start, payload + "," + newline + indent))
                pending = []
        if pending:
            if not positions: raise ValueError("Expected a nonempty authoring array")
            start, end = list(positions.values())[-1]
            indent = text[text.rfind("\n", 0, start) + 1:start]
            payload = ("," + newline + indent).join(formatted(entry, start) for entry in pending)
            edits.append((end, end, "," + newline + indent + payload))

    for key in ("entities", "tilesets", "layers"):
        insert(("defs", key), before["defs"][key], after["defs"][key], "uid")
    for index, old in enumerate(before["levels"]):
        new = after["levels"][index]
        if old["identifier"] == ROOM:
            if old != new:
                start, end = span(("levels", index))
                edits.append((start, end, formatted(new, start)))
        else:
            insert(("levels", index, "layerInstances"), old["layerInstances"], new["layerInstances"], "iid")
    start, end = span(("nextUid",))
    edits.append((start, end, str(after["nextUid"])))
    for start, end, value in sorted(edits, reverse=True): text = text[:start] + value + text[end:]
    if json.loads(text) != after: raise AssertionError("Serialized map differs from validated migration")
    return text.encode("utf-8-sig" if original.startswith(b"\xef\xbb\xbf") else "utf-8")


def run(project: Path, dry_run: bool) -> dict:
    original = project.read_bytes()
    before = json.loads(original.decode("utf-8-sig"))
    data = deepcopy(before)
    report = convert(data)
    report["dry_run"] = dry_run
    if not report["changed"] or dry_run: return report
    payload = serialize(original, before, data)
    if editor_busy() or project.read_bytes() != original:
        raise RuntimeError("LDtk open or project edited concurrently; map preserved")
    backup = project.parent / "ldtk_backups" / ("before_elemental_%s_%s.ldtk" % (
        datetime.now().strftime("%Y%m%d_%H%M%S"), hashlib.sha256(original).hexdigest()[:12]))
    backup.parent.mkdir(exist_ok=True)
    backup.write_bytes(original)
    with tempfile.NamedTemporaryFile(dir=project.parent, prefix=".elemental_", suffix=".tmp", delete=False) as stream:
        temporary = Path(stream.name)
        stream.write(payload)
    try:
        if editor_busy() or project.read_bytes() != original:
            raise RuntimeError("Map changed while preparing migration; map preserved")
        os.replace(temporary, project)
    finally:
        temporary.unlink(missing_ok=True)
    report["backup"] = str(backup)
    return report


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", type=Path, default=ROOT / "monster_booster.ldtk")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    print(json.dumps(run(args.project, args.dry_run), ensure_ascii=False))
