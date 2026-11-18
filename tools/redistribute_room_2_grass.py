"""Repaint only Floor_Grass with the organised atlas, covering 10% of Floor.

Density is measured in occupied 16px terrain cells, excluding water from the
denominator. Paint avoids roads, castle, ramps and altar/warp approaches.
"""
from __future__ import annotations

import argparse
from collections import Counter, defaultdict
from copy import deepcopy
from datetime import datetime
import hashlib
import json
import math
import os
from pathlib import Path
import random
import tempfile

from PIL import Image
from configure_ldtk_water import all_levels, editor_busy
from split_ldtk_room2 import REFERENCE, composed_layers, reference_bytes

ROOT = Path(__file__).resolve().parents[1]
SEED = 31102026
GRID = 16
SECTOR = 256
BACKGROUND = (83, 48, 72, 255)


def cells(layer: dict) -> set[tuple[int, int]]:
    return {tuple(t["px"]) for t in layer["gridTiles"] + layer["autoLayerTiles"]}


def rectangle(x: float, y: float, width: float, height: float) -> set[tuple[int, int]]:
    return {(cx, cy) for cy in range(math.floor(y / GRID) * GRID, math.ceil((y + height) / GRID) * GRID, GRID)
            for cx in range(math.floor(x / GRID) * GRID, math.ceil((x + width) / GRID) * GRID, GRID)}


def atlas_variants(path: Path) -> tuple[list[dict], tuple[int, int]]:
    variants = []
    with Image.open(path) as original:
        image = original.convert("RGBA")
    if image.width % GRID or image.height % GRID:
        raise ValueError("O atlas de grama precisa estar alinhado a 16 px.")
    columns = image.width // GRID
    for sy in range(0, image.height, GRID):
        for sx in range(0, image.width, GRID):
            patch = image.crop((sx, sy, sx + GRID, sy + GRID))
            marks = [(x, y) for y in range(GRID) for x in range(GRID)
                     if patch.getpixel((x, y))[3] and patch.getpixel((x, y)) != BACKGROUND]
            if not marks:
                continue
            box = (min(x for x, _ in marks), min(y for _, y in marks),
                   max(x for x, _ in marks) + 1, max(y for _, y in marks) + 1)
            if box[0] == 0 or box[1] == 0 or box[2] == GRID or box[3] == GRID:
                raise ValueError("Revisar variante cortada na borda da celula: " + str((sx, sy)))
            signature = hashlib.sha256(patch.crop(box).tobytes()).hexdigest()
            variants.append({"src": [sx, sy], "t": sy // GRID * columns + sx // GRID, "signature": signature})
    if not variants:
        raise ValueError("Nenhuma variante inteira de grama encontrada.")
    return variants, image.size


def patch_noise(x: int, y: int) -> float:
    gx, gy = x / 64.0, y / 64.0
    ix, iy = math.floor(gx), math.floor(gy)
    fx, fy = gx - ix, gy - iy
    fx, fy = fx * fx * (3 - 2 * fx), fy * fy * (3 - 2 * fy)

    def value(cx: int, cy: int) -> float:
        number = (cx * 73856093 ^ cy * 19349663 ^ SEED) & 0xffffffff
        number = ((number ^ (number >> 13)) * 1274126177) & 0xffffffff
        return (number ^ (number >> 16)) / 4294967295.0

    return ((value(ix, iy) * (1 - fx) + value(ix + 1, iy) * fx) * (1 - fy)
            + (value(ix, iy + 1) * (1 - fx) + value(ix + 1, iy + 1) * fx) * fy)


def convert(data: dict, root: Path) -> dict:
    room = next(l for l in all_levels(data) if l["identifier"] == "Room_2")
    layers = {l["__identifier"]: l for l in composed_layers(data, room)}
    layer = layers["Floor_Grass"]
    definition = next(d for d in data["defs"]["tilesets"] if d["uid"] == layer["__tilesetDefUid"])
    atlas_path = root / definition["relPath"]
    variants, dimensions = atlas_variants(atlas_path)
    if dimensions != (definition["pxWid"], definition["pxHei"]) or definition["tileGridSize"] != GRID:
        raise ValueError("O cadastro Grass_16 diverge das dimensoes do PNG atual.")
    floor = cells(layers["Floor"])
    roads = set().union(*(cells(layers[name]) for name in ("Floor_Paths", "Floor_Bridges", "TerrainStairs")))
    protected = set(roads)
    for source in room["layerInstances"]:
        for entity in source["entityInstances"]:
            name = entity["__identifier"]
            if name not in ("ElevationArea", "ElevationRamp", "HordePedestal", "Warp"):
                continue
            x, y = entity["px"]
            if name in ("HordePedestal", "Warp"):
                protected.update(rectangle(x - 72, y - 72, 144, 144))
            else:
                pivot = entity.get("__pivot", [0, 0])
                protected.update(rectangle(x - pivot[0] * entity["width"], y - pivot[1] * entity["height"], entity["width"], entity["height"]))
    eligible = floor - protected
    target = round(len(floor) * 0.10)
    if target > len(eligible):
        raise ValueError("Terreno disponivel insuficiente para a densidade pedida.")
    sectors = defaultdict(list)
    for point in sorted(eligible, key=lambda p: (p[1], p[0])):
        sectors[(point[0] // SECTOR, point[1] // SECTOR)].append(point)
    rng = random.Random(SEED)
    quotas = {key: math.floor(len(points) * target / len(eligible)) for key, points in sectors.items()}
    remainder = sorted(sectors, key=lambda key: (len(sectors[key]) * target / len(eligible) - quotas[key], rng.random()), reverse=True)
    for key in remainder[:target - sum(quotas.values())]:
        quotas[key] += 1
    chosen = []
    for key, points in sectors.items():
        # A regional quota scatters marks across the whole usable map. Local
        # 64px variation adds loose groups without concentrating all paint in
        # one biome or creating a regular grid of isolated tufts.
        scores = sorted(((rng.random() * 0.62 + patch_noise(x + 8, y + 8) * 0.38, x, y)
                         for x, y in points), reverse=True)
        chosen.extend((x, y) for _, x, y in scores[:quotas[key]])
    duplicates = Counter(v["signature"] for v in variants)
    weights = [1.0 / duplicates[v["signature"]] for v in variants]
    tiles = []
    for x, y in sorted(chosen, key=lambda p: (p[1], p[0])):
        variant = rng.choices(variants, weights=weights, k=1)[0]
        tiles.append({"px": [x, y], "src": variant["src"], "f": rng.randrange(2), "t": variant["t"],
                      "d": [y // GRID * layer["__cWid"] + x // GRID], "a": 1})
    previous = len(layer["gridTiles"]) + len(layer["autoLayerTiles"])
    layer.update(gridTiles=tiles, autoLayerTiles=[], visible=True)
    definition["cachedPixelData"] = None
    assert len(chosen) == len(set(chosen)) == target
    assert set(chosen) <= floor and not set(chosen) & protected
    return {"seed": SEED, "density_basis": "Floor terrain cells; water excluded", "floor_cells": len(floor),
            "eligible_cells": len(eligible), "target_percent": 10, "placed_tiles": target,
            "actual_percent": round(target * 100 / len(floor), 5), "previous_grass_tiles": previous,
            "sector_size_px": SECTOR, "sectors": len(sectors), "atlas": definition["relPath"],
            "atlas_sha256": hashlib.sha256(atlas_path.read_bytes()).hexdigest(), "valid_variant_ids": [v["t"] for v in variants],
            "variant_counts": dict(sorted(Counter(t["t"] for t in tiles).items())), "source_png_unchanged": True,
            "roads_castle_ramps_altar_warp_approaches_clear": True, "no_new_floor_support": True}


def apply(project: Path, dry_run: bool) -> dict:
    original = project.read_bytes()
    before = json.loads(original.decode("utf-8-sig"))
    after = deepcopy(before)
    report = convert(after, project.parent)
    # Only the target paint, its visibility and the source editor cache may
    # change. All other rooms, trees, reactive grass and gameplay stay exact.
    checked = deepcopy(after)
    for level in all_levels(checked):
        old = next(l for l in all_levels(before) if l["iid"] == level["iid"])
        if level["identifier"] == "Room_2_Cenario":
            layer = next(l for l in level["layerInstances"] if l["__identifier"] == "Floor_Grass")
            previous = next(l for l in old["layerInstances"] if l["__identifier"] == "Floor_Grass")
            layer.update(gridTiles=previous["gridTiles"], autoLayerTiles=previous["autoLayerTiles"], visible=previous["visible"])
    source = next(s for s in checked["defs"]["tilesets"] if s["relPath"] == report["atlas"])
    source["cachedPixelData"] = next(s for s in before["defs"]["tilesets"] if s["uid"] == source["uid"])["cachedPixelData"]
    assert checked == before, "A redistribuicao alterou conteudo externo a grama."
    repeated = deepcopy(after)
    convert(repeated, project.parent)
    assert repeated == after, "A distribuicao precisa ser deterministica."
    report.update(changed=after != before, dry_run=dry_run, other_authored_content_preserved=True, idempotent=True)
    output = project.parent / "output/grama_10_percent"
    output.mkdir(parents=True, exist_ok=True)
    if not dry_run and report["changed"]:
        if editor_busy() or project.read_bytes() != original:
            raise RuntimeError("LDtk aberto ou arquivo alterado; nenhum mapa sobrescrito.")
        reference = reference_bytes(after, project.parent)
        folder = project.parent / "ldtk_backups"
        folder.mkdir(exist_ok=True)
        backup = folder / f"before_grass_10_percent_{datetime.now():%Y%m%d_%H%M%S}_{hashlib.sha256(original).hexdigest()[:12]}.ldtk"
        backup.write_bytes(original)
        content = json.dumps(after, ensure_ascii=False, indent=2) + "\n"
        if b"\r\n" in original:
            content = content.replace("\n", "\r\n")
        with tempfile.NamedTemporaryFile(mode="wb", dir=project.parent, prefix=".grass_density_", suffix=".tmp", delete=False) as stream:
            temporary = Path(stream.name)
            stream.write(content.encode("utf-8"))
        try:
            if editor_busy() or project.read_bytes() != original:
                raise RuntimeError("Mapa mudou durante a autoria; arquivo preservado.")
            if hashlib.sha256((project.parent / report["atlas"]).read_bytes()).hexdigest() != report["atlas_sha256"]:
                raise RuntimeError("O atlas mudou durante a autoria; arquivo preservado.")
            os.replace(temporary, project)
        finally:
            temporary.unlink(missing_ok=True)
        (project.parent / REFERENCE).write_bytes(reference)
        (output / "01_ldtk.png").write_bytes(reference)
        report["backup"] = str(backup)
    (output / ("preview.json" if dry_run else "resultado.json")).write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return report


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", type=Path, default=ROOT / "monster_booster.ldtk")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    print(json.dumps(apply(args.project.resolve(), args.dry_run), ensure_ascii=False, indent=2))
