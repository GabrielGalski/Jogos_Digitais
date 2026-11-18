"""Author Room_2's orthogonal, three-tile roads without touching its set dressing.

Explicit waypoints are in local pixels, at cell centres. Bridges use the same
48 px section; the castle's existing ramp entities keep their physical bounds.
Run with --dry-run to inspect the proposed network before saving the LDtk file.
"""
from __future__ import annotations

import argparse
from collections import deque
from copy import deepcopy
from datetime import datetime
import hashlib
import json
import os
from pathlib import Path
import tempfile

from PIL import Image

from configure_ldtk_water import all_levels, editor_busy
from configure_room_2 import validate as validate_map
from split_ldtk_room2 import REFERENCE, composed_layers, reference_bytes

ROOT = Path(__file__).resolve().parents[1]
GRID = 16
FILL = (128, 32)  # Opaque, single-colour #45283c in MonsterShiftTrail_16.
EDITED_LAYERS = {"Floor_Paths", "Floor_Bridges", "TerrainStairs"}

# Only horizontal/vertical segments. Branches end under the existing platforms.
ROUTES = {
    "castelo_oeste": [(360, 456), (360, 1752)],
    "castelo_transversal": [(360, 824), (2216, 824)],
    "altar_castelo_leste": [(1416, 424), (1416, 824)],
    "escada_central": [(1320, 824), (1320, 1752)],
    "escada_leste": [(2216, 824), (2216, 1752)],
    "campo_central": [(360, 1752), (2216, 1752)],
    "chegada": [(1784, 1752), (1784, 2248)],
    "ponte_norte": [(2216, 1416), (3208, 1416)],
    "margem_leste": [(3208, 648), (3208, 2696)],
    "altar_rio_norte": [(3144, 648), (3208, 648)],
    "altar_rio_sul": [(3128, 2696), (3208, 2696)],
    "ponte_sul": [(1640, 2248), (3208, 2248)],
    "floresta_centro_sul": [(1640, 2248), (1640, 2904)],
    "floresta_oeste": [(1640, 2552), (360, 2552), (360, 2984), (168, 2984)],
}


def road_cells() -> set[tuple[int, int]]:
    cells: set[tuple[int, int]] = set()
    for name, points in ROUTES.items():
        for first, last in zip(points, points[1:]):
            if any(value % GRID != 8 for point in (first, last) for value in point):
                raise ValueError("Waypoint fora do centro da grade: " + name)
            if first[0] != last[0] and first[1] != last[1]:
                raise ValueError("Segmento diagonal: " + name)
            start = (first[0] // GRID, first[1] // GRID)
            end = (last[0] // GRID, last[1] // GRID)
            for y in range(min(start[1], end[1]) - 1, max(start[1], end[1]) + 2):
                for x in range(min(start[0], end[0]) - 1, max(start[0], end[0]) + 2):
                    cells.add((x * GRID, y * GRID))
    return cells


def tile(point: tuple[int, int], source: tuple[int, int], columns: int, width: int) -> dict:
    x, y = point
    sx, sy = source
    return {"px": [x, y], "src": [sx, sy], "f": 0,
            "t": sy // GRID * columns + sx // GRID,
            "d": [y // GRID * width + x // GRID], "a": 1}


def convert(data: dict, root: Path) -> dict:
    room = next(l for l in all_levels(data) if l["identifier"] == "Room_2")
    if (room["pxWid"], room["pxHei"]) != (3536, 3248):
        raise ValueError("O roteiro foi desenhado para a Room_2 de 3536 x 3248 px.")
    layers = {l["__identifier"]: l for l in composed_layers(data, room)}
    path_layer = layers["Floor_Paths"]
    definitions = {t["uid"]: t for t in data["defs"]["tilesets"]}
    source = definitions[path_layer["__tilesetDefUid"]]
    image = Image.open(root / source["relPath"]).convert("RGBA")
    if image.crop((*FILL, FILL[0] + GRID, FILL[1] + GRID)).getcolors() != [(256, (69, 40, 60, 255))]:
        raise ValueError("O tile escolhido deixou de ser o preenchimento sólido #45283c.")
    floor = {tuple(t["px"]) for t in layers["Floor"]["gridTiles"]}
    old_bridges = {tuple(t["px"]) for t in layers["Floor_Bridges"]["gridTiles"]}
    old_stairs = {tuple(t["px"]) for t in layers["TerrainStairs"]["gridTiles"]}
    network = road_cells()
    bridges = {p for p in old_bridges if p in network}
    stairs = {p for p in old_stairs if p in network}
    paths = network - bridges - stairs
    if paths - floor:
        raise ValueError("Um caminho saiu do terreno existente: " + str(sorted(paths - floor)[:8]))
    if any(p not in floor | bridges for p in network):
        raise ValueError("Travessia nova fora das duas pontes.")
    gameplay = layers["Gameplay"]
    solids = {(i % gameplay["__cWid"] * GRID, i // gameplay["__cWid"] * GRID)
              for i, value in enumerate(gameplay["intGridCsv"]) if value in (1, 2, 3, 6, 7)}
    if network & solids:
        raise ValueError("O caminho atravessou uma parede: " + str(sorted(network & solids)[:8]))
    found = {next(iter(network))}
    queue = deque(found)
    while queue:
        x, y = queue.popleft()
        for p in ((x - GRID, y), (x + GRID, y), (x, y - GRID), (x, y + GRID)):
            if p in network and p not in found:
                found.add(p)
                queue.append(p)
    if found != network:
        raise ValueError("A rede de caminhos ficou desconectada.")
    destinations = [e for l in room["layerInstances"] for e in l["entityInstances"]
                    if e["__identifier"] in ("HordePedestal", "Warp")]
    for entity in destinations:
        point = tuple(int(v) // GRID * GRID for v in entity["px"])
        if point not in network:
            raise ValueError("Destino sem acesso pelo caminho: " + str(entity["px"]))
    # All decks are rectangular horizontal strips, exactly three tiles high.
    for centre in (1416, 2248):
        band = {p for p in bridges if abs(p[1] + 8 - centre) <= GRID}
        xs = {p[0] for p in band}
        ys = {p[1] for p in band}
        if len(ys) != 3 or len(band) != len(xs) * 3:
            raise ValueError("A ponte precisa de três fileiras retas, sem recortes.")
    old_counts = {name: len(layers[name]["gridTiles"]) for name in EDITED_LAYERS}
    for name, cells in (("Floor_Paths", paths), ("Floor_Bridges", bridges), ("TerrainStairs", stairs)):
        layer = layers[name]
        if layer["__tilesetDefUid"] != source["uid"] or layer["autoLayerTiles"]:
            raise ValueError("Fonte ou auto-tiles inesperados em " + name)
        layer["gridTiles"] = [tile(p, FILL, source["__cWid"], layer["__cWid"])
                              for p in sorted(cells, key=lambda point: (point[1], point[0]))]
        # Short horizontal risers identify the existing height transitions.
        # No perimeter tiles or corner tiles are used on the roads/decks.
        if name == "TerrainStairs":
            for stamp in layer["gridTiles"]:
                if (stamp["px"][1] // GRID) % 2 == 0:
                    stamp.update(src=[16, 0], t=1)
    validation = validate_map(data)
    return {"width_tiles": 3, "width_px": 48, "colour": "#45283c", "borders": False,
            "segments": sum(len(points) - 1 for points in ROUTES.values()),
            "routes": ROUTES, "old_tiles": old_counts,
            "new_tiles": {name: len(layers[name]["gridTiles"]) for name in EDITED_LAYERS},
            "all_destinations_connected": True, "geometry": validation}


def configure(project: Path, dry_run: bool = False) -> dict:
    original = project.read_bytes()
    before = json.loads(original.decode("utf-8-sig"))
    after = deepcopy(before)
    report = convert(after, project.parent)
    # This migration may change only the tile lists of the three road layers.
    preserved = deepcopy(after)
    original_scenery = next(l for l in all_levels(before) if l["identifier"] == "Room_2_Cenario")
    checked_scenery = next(l for l in all_levels(preserved) if l["identifier"] == "Room_2_Cenario")
    old_layers = {l["__identifier"]: l for l in original_scenery["layerInstances"]}
    for layer in checked_scenery["layerInstances"]:
        if layer["__identifier"] in EDITED_LAYERS:
            layer["gridTiles"] = old_layers[layer["__identifier"]]["gridTiles"]
    if preserved != before:
        raise ValueError("Foi alterado conteúdo fora dos caminhos, pontes ou escadas.")
    report.update(changed=after != before, dry_run=dry_run)
    if dry_run:
        return report
    if editor_busy() or project.read_bytes() != original:
        raise RuntimeError("LDtk aberto ou arquivo alterado durante a autoria; mapa preservado.")
    png = reference_bytes(after, project.parent)
    if report["changed"]:
        backup_root = project.parent / "ldtk_backups"
        backup_root.mkdir(exist_ok=True)
        backup = backup_root / f"before_straight_paths_{datetime.now():%Y%m%d_%H%M%S}_{hashlib.sha256(original).hexdigest()[:12]}.ldtk"
        backup.write_bytes(original)
        newline = "\r\n" if b"\r\n" in original else "\n"
        with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", newline=newline,
                                        dir=project.parent, prefix=".straight_paths_", suffix=".tmp", delete=False) as stream:
            temporary = Path(stream.name)
            json.dump(after, stream, ensure_ascii=False, indent=2)
            stream.write("\n")
        try:
            if editor_busy() or project.read_bytes() != original:
                raise RuntimeError("Mapa alterado durante a gravação; arquivo preservado.")
            os.replace(temporary, project)
        finally:
            temporary.unlink(missing_ok=True)
        report["backup"] = str(backup)
    (project.parent / REFERENCE).write_bytes(png)
    output = project.parent / "output/caminhos"
    output.mkdir(exist_ok=True, parents=True)
    (output / "roteiro.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return report


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", type=Path, default=ROOT / "monster_booster.ldtk")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    print(json.dumps(configure(args.project.resolve(), args.dry_run), ensure_ascii=False))
