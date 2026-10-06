"""Build the standalone LDtk 1.5.3 map-authoring project.

Uses the schema-compatible sample bundled with the local LDtk installation as
a blank structural template. The resulting project does not depend on it.
Running this again replaces the LDtk project, including hand-painted levels.
"""

from __future__ import annotations

import copy
import json
import os
import struct
import uuid
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "monster_booster.ldtk"
if OUTPUT.exists():
    raise SystemExit("Legacy template generator disabled: use the LDtk editor. It would overwrite authored maps and restore obsolete palette copies.")
SAMPLE = (
    Path(os.environ["LOCALAPPDATA"])
    / "Programs/ldtk/extraFiles/samples/Typical_TopDown_example.ldtk"
)
GRID = 16

TILESETS = [
    (101, "Floor_16", "assets/tiles/floor/floor_tileset.png"),
    (102, "PlatformUnderside_16", "assets/tiles/inferior/inferior.png"),
    (103, "WallPieces_16", "assets/tiles/editor/wall_palette.png"),
    (104, "Doors_16", "assets/tiles/editor/door_palette.png"),
    (105, "Objects_16", "assets/tiles/editor/object_palette.png"),
    (106, "ThroneReference_16", "assets/tiles/decor/minotaur_chair.png"),
    (107, "ThroneBack_16", "assets/tiles/decor/minotaur_chair_back.png"),
    (108, "ThroneSeat_16", "assets/tiles/decor/minotaur_chair_seat.png"),
    (109, "EntityIcons_16", "assets/tiles/editor/ldtk_entities.png"),
]

LAYERS = [
    (201, "Entities", "Entities", None, "#7EE0D1"),
    (202, "Doors", "Tiles", 104, "#FF679C"),
    (203, "ObjectsFront", "Tiles", 105, "#D7A4E0"),
    (213, "ThroneReference", "Tiles", 106, "#C2ACDD"),
    (204, "ThroneSeat", "Tiles", 108, "#B192D6"),
    (205, "WallsFront", "Tiles", 103, "#9C6F9C"),
    (206, "ObjectsBack", "Tiles", 105, "#A885BB"),
    (207, "ThroneBack", "Tiles", 107, "#8573AC"),
    (208, "WallsSides", "Tiles", 103, "#764F85"),
    (209, "WallsBack", "Tiles", 103, "#633C70"),
    (210, "Collisions", "IntGrid", None, "#E26363"),
    (211, "Floor", "Tiles", 101, "#816A86"),
    (212, "PlatformUnderside", "Tiles", 102, "#4B425C"),
]


def image_size(path: Path) -> tuple[int, int]:
    with path.open("rb") as image:
        header = image.read(24)
    if header[:8] != b"\x89PNG\r\n\x1a\n" or header[12:16] != b"IHDR":
        raise ValueError(f"Not a PNG: {path}")
    return struct.unpack(">II", header[16:24])


def stamp(columns: int, x: int, y: int, width: int, height: int) -> dict:
    return {
        "ids": [(y + row) * columns + x + col for row in range(height) for col in range(width)],
        "mode": "Stamp",
    }


def selections(uid: int, columns: int) -> list[dict]:
    if uid == 101:
        return [stamp(columns, x, y, 1, 1) for x, y in [(1, 1), (2, 1), (0, 0)]]
    if uid == 102:
        return [stamp(columns, 0, 0, 2, 2)] + [
            stamp(columns, x, 0, 1, 2) for x in range(2, 6)
        ] + [stamp(columns, 6, 0, 2, 2)]
    if uid == 103:
        result = []
        for y in (0, 4, 8, 12):
            result.extend(stamp(columns, x, y, width, 3) for x, width in ((0, 4), (4, 3), (7, 2), (9, 1), (10, 1)))
        result.extend(
            stamp(columns, x, y, width, height)
            for x, y, width, height in (
                (0, 16, 4, 3), (4, 16, 4, 3), (8, 16, 1, 3),
                (9, 16, 2, 3), (11, 16, 2, 3), (13, 16, 1, 3),
                (0, 20, 2, 3), (2, 20, 1, 3), (3, 20, 1, 1),
                (4, 20, 1, 1),
            )
        )
        return result
    if uid == 104:
        return [stamp(columns, x, 0, 2, 2) for x in (0, 2, 4, 6)]
    if uid == 105:
        return [stamp(columns, 0, 0, 2, 4), stamp(columns, 2, 0, 2, 4), stamp(columns, 4, 0, 8, 8)]
    if uid == 109:
        return [stamp(columns, x, 0, 2, 2) for x in (0, 2, 4)]
    return [stamp(columns, 0, 0, 8, 8)]


def make_tileset(sample: dict, uid: int, name: str, rel_path: str) -> dict:
    width, height = image_size(ROOT / rel_path)
    if width % GRID or height % GRID:
        raise ValueError(f"Tileset not divisible by 16: {rel_path} {width}x{height}")
    result = copy.deepcopy(sample)
    result.update(
        {
            "__cWid": width // GRID,
            "__cHei": height // GRID,
            "identifier": name,
            "uid": uid,
            "relPath": rel_path,
            "embedAtlas": None,
            "pxWid": width,
            "pxHei": height,
            "tileGridSize": GRID,
            "spacing": 0,
            "padding": 0,
            "tags": [],
            "tagsSourceEnumUid": None,
            "enumTags": [],
            "customData": [],
            "savedSelections": selections(uid, width // GRID),
            "cachedPixelData": None,
        }
    )
    return result


def make_layer_def(sample_tile: dict, sample_entity: dict, sample_int: dict, spec: tuple) -> dict:
    uid, name, layer_type, tileset_uid, color = spec
    base = {"Tiles": sample_tile, "Entities": sample_entity, "IntGrid": sample_int}[layer_type]
    result = copy.deepcopy(base)
    result.update(
        {
            "__type": layer_type,
            "identifier": name,
            "type": layer_type,
            "uid": uid,
            "doc": None,
            "uiColor": color,
            "gridSize": GRID,
            "displayOpacity": 0.35 if layer_type == "IntGrid" else 1,
            "autoRuleGroups": [],
            "intGridValues": [],
            "intGridValuesGroups": [],
            "autoSourceLayerDefUid": None,
            "tilesetDefUid": tileset_uid,
            "pxOffsetX": 0,
            "pxOffsetY": 0,
        }
    )
    if layer_type == "IntGrid":
        result["intGridValues"] = [
            {"value": 1, "identifier": "Solid", "color": "#25131A", "tile": None, "groupUid": 0},
            {"value": 2, "identifier": "DoorBlock", "color": "#FF4E91", "tile": None, "groupUid": 0},
            {"value": 3, "identifier": "Hazard", "color": "#FA6A0A", "tile": None, "groupUid": 0},
        ]
    return result


def make_entity(sample: dict, uid: int, name: str, color: str, width: int = 16, height: int = 16) -> dict:
    result = copy.deepcopy(sample)
    icon_rect = {
        "NoxStart": (109, 0, 0),
        "Tin": (109, 32, 0),
        "MinotaurSpawn": (109, 64, 0),
        "DoorLink": (104, 0, 0),
    }.get(name)
    result.update(
        {
            "identifier": name,
            "uid": uid,
            "tags": [],
            "exportToToc": False,
            "doc": "Authoring marker only; gameplay integration is not automatic.",
            "width": width,
            "height": height,
            "color": color,
            "renderMode": "Tile" if icon_rect else "Rectangle",
            "showName": True,
            "tilesetId": icon_rect[0] if icon_rect else None,
            "tileRect": (
                {"tilesetUid": icon_rect[0], "x": icon_rect[1], "y": icon_rect[2], "w": 32, "h": 32}
                if icon_rect else None
            ),
            "uiTileRect": None,
            "tileRenderMode": "FitInside",
            "maxCount": 0,
            "limitScope": "PerLevel",
            "limitBehavior": "DiscardOldOnes",
            "fieldDefs": [],
        }
    )
    return result


def tile(x: int, y: int, atlas_x: int, atlas_y: int,
         atlas_columns: int, level_columns: int) -> dict:
    return {
        "px": [x, y],
        "src": [atlas_x * GRID, atlas_y * GRID],
        "f": 0,
        "t": atlas_y * atlas_columns + atlas_x,
        "d": [(y // GRID) * level_columns + x // GRID],
        "a": 1,
    }


def make_level(sample_level: dict, sample_instance: dict, name: str, uid: int,
               world_x: int, world_y: int, columns: int, rows: int,
               floor_rect: tuple[int, int, int, int], paths: dict[int, str]) -> dict:
    level = copy.deepcopy(sample_level)
    level.update(
        {
            "identifier": name,
            "iid": str(uuid.uuid4()),
            "uid": uid,
            "worldX": world_x,
            "worldY": world_y,
            "worldDepth": 0,
            "pxWid": columns * GRID,
            "pxHei": rows * GRID,
            "__bgColor": "#25131A",
            "bgColor": "#25131A",
            "useAutoIdentifier": False,
            "__smartColor": "#7C5A82",
            "__neighbours": [],
            "fieldInstances": [],
        }
    )
    instances = []
    for layer_uid, layer_name, layer_type, tileset_uid, _ in LAYERS:
        instance = copy.deepcopy(sample_instance)
        instance.update(
            {
                "__identifier": layer_name,
                "__type": layer_type,
                "__cWid": columns,
                "__cHei": rows,
                "__gridSize": GRID,
                "__opacity": 0.35 if layer_type == "IntGrid" else 1,
                "__pxTotalOffsetX": 0,
                "__pxTotalOffsetY": 0,
                "__tilesetDefUid": tileset_uid,
                "__tilesetRelPath": paths.get(tileset_uid),
                "iid": str(uuid.uuid4()),
                "levelId": uid,
                "layerDefUid": layer_uid,
                "pxOffsetX": 0,
                "pxOffsetY": 0,
                "visible": True,
                "optionalRules": [],
                "intGridCsv": [0] * (columns * rows) if layer_type == "IntGrid" else [],
                "autoLayerTiles": [],
                "gridTiles": [],
                "entityInstances": [],
                "seed": uid + layer_uid,
                "overrideTilesetUid": None,
            }
        )
        if layer_name == "Floor":
            x0, y0, x1, y1 = floor_rect
            instance["gridTiles"] = [
                tile(x * GRID, y * GRID, 1, 1, 4, columns)
                for y in range(y0, y1)
                for x in range(x0, x1)
            ]
        instances.append(instance)
    level["layerInstances"] = instances
    return level


def main() -> None:
    if not SAMPLE.is_file():
        raise FileNotFoundError(f"LDtk 1.5.3 sample not found: {SAMPLE}")
    with SAMPLE.open("r", encoding="utf-8") as source:
        project = json.load(source)
    if project.get("jsonVersion") != "1.5.3":
        raise ValueError("Expected LDtk JSON 1.5.3")

    sample_tileset = project["defs"]["tilesets"][0]
    sample_tile_layer = next(layer for layer in project["defs"]["layers"] if layer["type"] == "Tiles")
    sample_entity_layer = next(layer for layer in project["defs"]["layers"] if layer["type"] == "Entities")
    sample_int_layer = next(layer for layer in project["defs"]["layers"] if layer["type"] == "IntGrid")
    sample_level = project["levels"][0]
    sample_instance = next(layer for layer in sample_level["layerInstances"] if layer["__type"] == "Tiles")

    project.update(
        {
            "iid": str(uuid.uuid4()),
            "appBuildId": 473703,
            "nextUid": 500,
            "worldLayout": "Free",
            "worldGridWidth": 512,
            "worldGridHeight": 352,
            "defaultLevelWidth": 512,
            "defaultLevelHeight": 352,
            "defaultGridSize": GRID,
            "bgColor": "#25131A",
            "defaultLevelBgColor": "#25131A",
            "backupOnSave": True,
            "backupLimit": 10,
            "backupRelPath": "ldtk_backups",
            "levelNamePattern": "Room_%idx",
            "tutorialDesc": "Monster Booster: see docs/GUIA.md for map editing, tileset grids, door openings and Godot import notes.",
            "toc": [],
            "worlds": [],
            "dummyWorldIid": str(uuid.uuid4()),
        }
    )
    project["defs"] = {
        "layers": [
            make_layer_def(sample_tile_layer, sample_entity_layer, sample_int_layer, spec)
            for spec in LAYERS
        ],
        "entities": [
            make_entity(project["defs"]["entities"][0], uid, name, color, width, height)
            for uid, name, color, width, height in (
                (301, "NoxStart", "#7EE0D1", 16, 16),
                (302, "Tin", "#FF679C", 32, 32),
                (303, "MinotaurSpawn", "#D7575D", 32, 32),
                (304, "DoorLink", "#F2E7C3", 32, 16),
                (305, "RoomTrigger", "#D1A6E0", 16, 16),
            )
        ],
        "tilesets": [make_tileset(sample_tileset, *entry) for entry in TILESETS],
        "enums": [],
        "externalEnums": [],
        "levelFields": [],
    }
    paths = {uid: rel_path for uid, _, rel_path in TILESETS}
    project["levels"] = [
        make_level(sample_level, sample_instance, "RoomTemplate_30x16", 401,
                   0, 0, 32, 22, (1, 3, 31, 19), paths),
        make_level(sample_level, sample_instance, "CorridorTemplate_16x2", 402,
                   544, 112, 16, 8, (0, 3, 16, 5), paths),
    ]
    with OUTPUT.open("w", encoding="utf-8", newline="\n") as target:
        json.dump(project, target, ensure_ascii=False, indent=2)
        target.write("\n")
    print(f"LDtk project created: {OUTPUT} ({len(TILESETS)} tilesets, {len(LAYERS)} layers, 2 templates)")


if __name__ == "__main__":
    main()
