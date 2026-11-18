"""Register the recolored cliff atlas and replace the castle's old front face.

Only TerrainFaces paint/source and the four matching HeightPx fields change.
Floor support, ramp rectangles, river, vegetation and authored positions remain
exact. The original 16 px rock pieces repeat vertically without resampling art.
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

from PIL import Image

from configure_ldtk_water import all_levels, editor_busy
from ldtk_field_values import set_value
from split_ldtk_room2 import REFERENCE, reference_bytes

ROOT = Path(__file__).resolve().parents[1]
ART = "assets/tiles/floor/cliff_tileset.png"
ATLAS = "Cliff_Purple_16"
GRID = 16
DEFAULT_HEIGHT = 56
FACE_OFFSET = 11
FACE_DOC = (
    "TERRENO / Montanha do castelo. Cliff_Purple_16 em grade de 16 px; "
    "sequencia crista/rocha/base acompanha a elevacao visual de {height} px. "
    "Apenas desenho, sem suporte ou colisao; tres acessos permanecem em "
    "TerrainStairs + ElevationRamp + Gameplay. Z=-17, recebe sombras de nuvens."
)


def fields(entity: dict) -> dict:
    return {field["__identifier"]: field["__value"] for field in entity["fieldInstances"]}


def bounds(entity: dict) -> tuple[int, int, int, int]:
    pivot = entity.get("__pivot", [0, 0])
    return (
        round(entity["px"][0] - entity["width"] * pivot[0]),
        round(entity["px"][1] - entity["height"] * pivot[1]),
        int(entity["width"]),
        int(entity["height"]),
    )


def runs(values: list[int]) -> list[list[int]]:
    result: list[list[int]] = []
    for value in sorted(set(values)):
        if result and result[-1][1] == value:
            result[-1][1] += GRID
        else:
            result.append([value, value + GRID])
    return result


def make_tile(layer: dict, x: int, y: int, column: int, row: int) -> dict:
    return {
        "px": [x, y], "src": [column * GRID, row * GRID],
        "f": 0, "t": row * 3 + column,
        "d": [y // GRID * layer["__cWid"] + x // GRID], "a": 1,
    }


def body_rows(height_px: int) -> int:
    if height_px < 24 or height_px > 248 or (height_px - 24) % GRID:
        raise ValueError("HeightPx deve ser 24 + N x 16, entre 24 e 248 px.")
    return (height_px - 8) // GRID


def painted_rows(baseline: int, height_px: int) -> list[int]:
    count = body_rows(height_px) + 2
    return list(range(baseline - count * GRID, baseline, GRID))


def alternate_rock(face: dict, baseline: int, height_px: int, front_runs: list[list[int]]) -> dict:
    """Mirror alternate body rows only after verifying the authored cliff pieces."""
    target_rows = painted_rows(baseline, height_px)
    atlas_rows = [2] + [3] * body_rows(height_px) + [4]
    flip_rows = {target_rows[index] for index in range(1, len(target_rows) - 1)
                 if (index - 1) % 2 == 1}
    expected = {}
    for left, right in front_runs:
        for x in range(left, right, GRID):
            column = 0 if x == left else 2 if x == right - GRID else 1
            for row, y in zip(atlas_rows, target_rows, strict=True):
                expected[x, y] = make_tile(face, x, y, column, row)
    if len(face["gridTiles"]) != len(expected):
        raise ValueError("A quantidade de tiles da face mudou; alternancia cancelada.")
    seen = set()
    for tile in face["gridTiles"]:
        point = tuple(tile["px"])
        reference = expected.get(point)
        if point in seen or reference is None or any(tile.get(key) != reference[key] for key in ("src", "t", "d")):
            raise ValueError("Celulas ou pecas do cliff mudaram; alternancia preserva a autoria e foi cancelada.")
        seen.add(point)
        allowed_flips = (0, 3) if point[1] in flip_rows else (0,)
        if tile.get("f", 0) not in allowed_flips:
            raise ValueError("Espelhamento autoral inesperado na face; alternancia cancelada.")
    changed = 0
    for tile in face["gridTiles"]:
        if tile["px"][1] in flip_rows and tile.get("f", 0) != 3:
            tile["f"] = 3
            changed += 1
    return {"mirrored_rows_y": sorted(flip_rows), "mirrored_tiles_changed": changed,
            "mirroring": "vertical + horizontal (LDtk f=3)",
            "coordinates_sources_height_preserved": True}


def convert(data: dict, root: Path = ROOT, height_px: int = DEFAULT_HEIGHT,
            alternate_rock_rows: bool = False) -> dict:
    rock_rows = body_rows(height_px)
    with Image.open(root / ART) as image:
        if image.size != (48, 80):
            raise ValueError("cliff_tileset.png precisa conservar 48 x 80 px, sem reescala.")
    levels = all_levels(data)
    primary = next(level for level in levels if level["identifier"] == "Room_2")
    scenery = next(level for level in levels if level["identifier"] == "Room_2_Cenario")
    face = next(layer for layer in scenery["layerInstances"] if layer["__identifier"] == "TerrainFaces")
    definitions = data["defs"]
    source = next((entry for entry in definitions["tilesets"] if entry.get("relPath") == ART), None)
    entities = [entity for layer in primary["layerInstances"] for entity in layer["entityInstances"]]
    areas = [entity for entity in entities if entity["__identifier"] == "ElevationArea"
             and fields(entity).get("Enabled", True)]
    if len(areas) != 1:
        raise ValueError("A face foi mapeada para um unico patamar elevado.")
    previous_height = int(fields(areas[0]).get("HeightPx", 0))
    body_rows(previous_height)
    plateau = bounds(areas[0])
    baseline = plateau[1] + plateau[3]
    ramp_entities = [entity for entity in entities if entity["__identifier"] == "ElevationRamp"
                     and fields(entity).get("Enabled", True)]
    if len(ramp_entities) != 3:
        raise ValueError("Os tres acessos autorais precisam existir antes da pintura do relevo.")
    if any(fields(entity).get("HeightPx") != previous_height for entity in ramp_entities):
        raise ValueError("Patamar e tres rampas precisam compartilhar a altura anterior.")
    ramps = [bounds(entity) for entity in ramp_entities]
    integrated = bool(source and face["__tilesetDefUid"] == source["uid"])
    if integrated and previous_height == height_px and not alternate_rock_rows:
        return {
            "changed": False, "reason": "Cliff and height already applied; retaining later authored face edits.",
            "atlas": ART, "atlas_uid": source["uid"], "painted_tiles": len(face["gridTiles"]),
            "height_px": height_px, "offset_y": face["pxOffsetY"],
        }
    expected_offset = FACE_OFFSET if integrated else 0
    if face["autoLayerTiles"] or face["pxOffsetX"] or face["pxOffsetY"] != expected_offset:
        raise ValueError("TerrainFaces mudou desde o mapeamento: revisar autoria antes de substituir.")
    old_positions = [tuple(tile["px"]) for tile in face["gridTiles"]]
    columns = sorted({x for x, _ in old_positions})
    previous_rows = painted_rows(baseline, previous_height) if integrated else [baseline - 32, baseline - 16]
    expected = {(x, y) for x in columns for y in previous_rows}
    if len(old_positions) != len(expected) or set(old_positions) != expected:
        raise ValueError("As fileiras da face mudaram desde a migracao; pintura posterior preservada.")
    front_runs = runs(columns)
    if len(front_runs) != 4:
        raise ValueError("Esperadas quatro faces separadas pelos tres acessos do castelo.")
    if any(rx <= x < rx + width for x in columns for rx, _, width, _ in ramps):
        raise ValueError("A face antiga sobrepoe um acesso fisico; revisar antes de alterar.")

    if integrated and previous_height == height_px and alternate_rock_rows:
        if (source["tileGridSize"], source["pxWid"], source["pxHei"]) != (GRID, 48, 80):
            raise ValueError("O atlas de cliff cadastrado possui dimensoes divergentes.")
        style = alternate_rock(face, baseline, height_px, front_runs)
        return {
            "changed": style["mirrored_tiles_changed"] > 0, "atlas": ART,
            "atlas_uid": source["uid"], "height_px": height_px,
            "painted_tiles": len(face["gridTiles"]), "offset_y": face["pxOffsetY"],
            "style_only": True, "alternating_rock": style,
            "elevation_changed": False, "floor_support_changed": False,
            "gameplay_changed": False, "source_png_changed_by_migration": False,
        }

    if source is None:
        source = deepcopy(next(entry for entry in definitions["tilesets"] if entry["identifier"] == "Bush_16"))
        source.update(
            identifier=ATLAS, uid=data["nextUid"], relPath=ART,
            pxWid=48, pxHei=80, __cWid=3, __cHei=5, tileGridSize=GRID,
            spacing=0, padding=0, tags=["terrain", "cliff", "castle"],
            enumTags=[], customData=[], cachedPixelData=None,
            savedSelections=[
                {"ids": list(range(15)), "mode": "Stamp"},
                {"ids": [6, 7, 8, 9, 10, 11, 12, 13, 14], "mode": "Stamp"},
                {"ids": [7, 10, 13], "mode": "Stamp"},
            ],
        )
        data["nextUid"] += 1
        definitions["tilesets"].append(source)
    elif (source["tileGridSize"], source["pxWid"], source["pxHei"]) != (GRID, 48, 80):
        raise ValueError("O atlas de cliff cadastrado possui dimensoes divergentes.")

    definition = next(layer for layer in definitions["layers"] if layer["identifier"] == "TerrainFaces")
    previous_uid = definition["tilesetDefUid"]
    definition.update(tilesetDefUid=source["uid"], doc=FACE_DOC.format(height=height_px))
    for level in levels:
        instance = next(layer for layer in level["layerInstances"] if layer["__identifier"] == "TerrainFaces")
        if level is not scenery and (instance["gridTiles"] or instance["autoLayerTiles"]):
            # A future unrelated room can retain a different hand-painted source.
            instance["overrideTilesetUid"] = instance["__tilesetDefUid"] or previous_uid
            continue
        instance.update(__tilesetDefUid=source["uid"], __tilesetRelPath=ART, overrideTilesetUid=None)
    face.update(gridTiles=[], autoLayerTiles=[], pxOffsetY=FACE_OFFSET, __pxTotalOffsetY=FACE_OFFSET)
    target_rows = painted_rows(baseline, height_px)
    source_rows = [2] + [3] * rock_rows + [4]
    for left, right in front_runs:
        for x in range(left, right, GRID):
            column = 0 if x == left else 2 if x == right - GRID else 1
            for row, y in zip(source_rows, target_rows, strict=True):
                face["gridTiles"].append(make_tile(face, x, y, column, row))
    height_fields = []
    for entity in areas + ramp_entities:
        field = next(entry for entry in entity["fieldInstances"] if entry["__identifier"] == "HeightPx")
        set_value(field, height_px)
        height_fields.append({"entity": entity["__identifier"], "iid": entity["iid"],
                              "before": previous_height, "after": height_px})
    style = alternate_rock(face, baseline, height_px, front_runs) if alternate_rock_rows else None

    return {
        "changed": True, "atlas": ART, "atlas_identifier": source["identifier"],
        "atlas_uid": source["uid"], "atlas_size_px": [48, 80], "tile_grid_px": GRID,
        "plateau_logical_rect": list(plateau), "previous_height_px": previous_height, "height_px": height_px,
        "front_runs_x": front_runs, "logical_front_baseline_y": baseline,
        "painted_grid_rows_y": target_rows, "repeated_rock_rows": rock_rows,
        "layer_offset_y": FACE_OFFSET,
        "center_outline_visual_y": baseline - height_px,
        "center_last_shadow_visual_y": baseline - 1,
        "source_rows": {"crest": [6, 7, 8], "rock": [9, 10, 11], "base": [12, 13, 14]},
        "previous_tiles": len(old_positions), "painted_tiles": len(face["gridTiles"]),
        "preserved_ramp_rects": [list(rect) for rect in ramps],
        "floor_support_changed": False, "gameplay_changed": False,
        "elevation_changed": previous_height != height_px,
        "height_fields": height_fields, "source_png_changed_by_migration": False,
        "alternating_rock": style,
    }


def assert_preserved(before: dict, after: dict) -> None:
    """Allow only source registration, TerrainFaces and four HeightPx fields."""
    checked = deepcopy(after)
    checked["defs"] = before["defs"]
    checked["nextUid"] = before["nextUid"]
    for old_level in all_levels(before):
        level = next(entry for entry in all_levels(checked) if entry["iid"] == old_level["iid"])
        old_face = next(layer for layer in old_level["layerInstances"] if layer["__identifier"] == "TerrainFaces")
        face_index = next(index for index, layer in enumerate(level["layerInstances"])
                          if layer["iid"] == old_face["iid"])
        level["layerInstances"][face_index] = deepcopy(old_face)
        if old_level["identifier"] == "Room_2":
            old_entities = {entity["iid"]: entity for layer in old_level["layerInstances"]
                            for entity in layer["entityInstances"]}
            for layer in level["layerInstances"]:
                for entity in layer["entityInstances"]:
                    if entity["__identifier"] not in ("ElevationArea", "ElevationRamp"):
                        continue
                    previous = old_entities[entity["iid"]]
                    old_field = next(field for field in previous["fieldInstances"] if field["__identifier"] == "HeightPx")
                    field_index = next(index for index, field in enumerate(entity["fieldInstances"])
                                       if field["__identifier"] == "HeightPx")
                    entity["fieldInstances"][field_index] = deepcopy(old_field)
    if checked != before:
        raise AssertionError("A migracao alterou dados fora de TerrainFaces/cadastro/HeightPx.")


def apply(project: Path, dry_run: bool = False, height_px: int = DEFAULT_HEIGHT,
          alternate_rock_rows: bool = False) -> dict:
    original = project.read_bytes()
    before = json.loads(original.decode("utf-8-sig"))
    after = deepcopy(before)
    report = convert(after, project.parent, height_px, alternate_rock_rows)
    assert_preserved(before, after)
    if report.get("style_only"):
        checked = deepcopy(after)
        old_scenery = next(level for level in all_levels(before) if level["identifier"] == "Room_2_Cenario")
        new_scenery = next(level for level in all_levels(checked) if level["iid"] == old_scenery["iid"])
        old_face = next(layer for layer in old_scenery["layerInstances"] if layer["__identifier"] == "TerrainFaces")
        face_index = next(index for index, layer in enumerate(new_scenery["layerInstances"])
                          if layer["iid"] == old_face["iid"])
        new_scenery["layerInstances"][face_index] = deepcopy(old_face)
        if checked != before:
            raise AssertionError("A alternancia visual tentou alterar dados fora de TerrainFaces.")
    repeated = deepcopy(after)
    convert(repeated, project.parent, height_px, alternate_rock_rows)
    if repeated != after:
        raise AssertionError("A migracao deve ser idempotente.")
    report.update(changed=after != before, dry_run=dry_run,
                  idempotent=True, all_other_authored_content_preserved=True)
    if not dry_run and report["changed"]:
        if editor_busy() or project.read_bytes() != original:
            raise RuntimeError("LDtk aberto ou mapa alterado; nenhum arquivo sobrescrito.")
        guide = reference_bytes(after, project.parent)
        backups = project.parent / "ldtk_backups"
        backups.mkdir(exist_ok=True)
        backup = backups / f"before_castle_cliffs_{datetime.now():%Y%m%d_%H%M%S}_{hashlib.sha256(original).hexdigest()[:12]}.ldtk"
        backup.write_bytes(original)
        content = json.dumps(after, ensure_ascii=False, indent=2) + "\n"
        if b"\r\n" in original:
            content = content.replace("\n", "\r\n")
        with tempfile.NamedTemporaryFile(mode="wb", dir=project.parent, prefix=".castle_cliffs_", suffix=".tmp", delete=False) as stream:
            temporary = Path(stream.name)
            stream.write(content.encode("utf-8"))
        try:
            if editor_busy() or project.read_bytes() != original:
                raise RuntimeError("Mapa mudou durante a operacao; autoria preservada.")
            os.replace(temporary, project)
        finally:
            temporary.unlink(missing_ok=True)
        (project.parent / REFERENCE).write_bytes(guide)
        report["backup"] = str(backup)
        report["reference_updated"] = True
    output = project.parent / "output/cliff_castle"
    output.mkdir(parents=True, exist_ok=True)
    target = output / ("migration_preview.json" if dry_run else "migration.json")
    target.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return report


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", type=Path, default=ROOT / "monster_booster.ldtk")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--height-px", type=int, default=DEFAULT_HEIGHT,
                        help="Altura visual do patamar; 24 + N x 16 px. Padrao: 56.")
    parser.add_argument("--alternate-rock", action="store_true",
                        help="Espelha vertical e horizontalmente as fileiras impares do corpo rochoso.")
    arguments = parser.parse_args()
    print(json.dumps(apply(arguments.project.resolve(), arguments.dry_run, arguments.height_px,
                           arguments.alternate_rock), ensure_ascii=False, indent=2))
