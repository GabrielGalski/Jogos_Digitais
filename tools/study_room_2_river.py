"""Read-only river survey: authored geometry, bridge constraints and mapping.

Writes engineering diagrams and measurements to output/river_study only.
It never rewrites LDtk, game resources, terrain, collisions or water masks.
"""
from __future__ import annotations

import csv
import hashlib
import json
from pathlib import Path
from statistics import median

from PIL import Image, ImageDraw, ImageFont

from configure_ldtk_water import all_levels
from configure_room_2_bridges import painted_spans
from split_ldtk_room2 import composed_layers

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "monster_booster.ldtk"
OUTPUT = ROOT / "output/river_study"
GRID = 16


def fields(entity: dict) -> dict:
    return {field["__identifier"]: field.get("__value") for field in entity["fieldInstances"]}


def floor_runs(cells: set[tuple[int, int]], y: int, width: int) -> list[tuple[int, int]]:
    """Half-open runs of authored ground, not runtime bridge or cliff projection."""
    result: list[tuple[int, int]] = []
    start = None
    for x in range(0, width + GRID, GRID):
        solid = x < width and (x, y) in cells
        if solid and start is None:
            start = x
        elif not solid and start is not None:
            result.append((start, x))
            start = None
    return result


def survey(data: dict, source_bytes: bytes) -> tuple[dict, dict, dict]:
    room = next(level for level in all_levels(data) if level["identifier"] == "Room_2")
    layers = {layer["__identifier"]: layer for layer in composed_layers(data, room)}
    floor = layers["Floor"]
    assert floor["__gridSize"] == GRID
    assert floor.get("__pxTotalOffsetX", 0) == floor.get("__pxTotalOffsetY", 0) == 0
    assert floor["__tilesetRelPath"].endswith("/ground_base.png")
    cells = {tuple(tile["px"]) for tile in floor["gridTiles"]}
    entities = [entity for layer in layers.values() for entity in layer.get("entityInstances", [])]
    areas = [entity for entity in entities if entity["__identifier"] == "WaterArea" and fields(entity).get("Enabled", True)]
    assert len(areas) == 1, "Survey expects this map's single authored river region."
    area = areas[0]
    wx, wy = area["px"]
    width, height = area["width"], area["height"]
    rows = []
    unresolved = []
    for y in range(0, room["pxHei"], GRID):
        land = floor_runs(cells, y, room["pxWid"])
        candidates = [(left[1], right[0]) for left, right in zip(land, land[1:])
                      if wx <= left[1] < right[0] <= wx + width
                      and 112 <= right[0] - left[1] <= 512]
        if not candidates:
            unresolved.append(y)
            continue
        west, east = max(candidates, key=lambda interval: interval[1] - interval[0])
        rows.append({"y": y, "west": west, "east": east, "width": east - west, "center": (west + east) / 2})
    assert len(rows) >= 190 and all(b["y"] - a["y"] == GRID for a, b in zip(rows, rows[1:]))
    bridges = []
    for index, (x, y, deck_width, deck_height) in enumerate(painted_spans(layers), 1):
        deck_rows = [row for row in rows if y <= row["y"] < y + deck_height]
        west = [row["west"] for row in deck_rows]
        east = [row["east"] for row in deck_rows]
        bridges.append({
            "id": f"B{index}", "deck_rect": [x, y, deck_width, deck_height],
            "bank_range_west": [min(west), max(west)], "bank_range_east": [min(east), max(east)],
            "channel_width_range": [min(row["width"] for row in deck_rows), max(row["width"] for row in deck_rows)],
            "proposed_straight_core_y": [y - 32, y + deck_height + 32],
            "proposed_transition_y": [y - 96, y + deck_height + 96],
            "proposal_applied": False,
        })
    report = {
        "source": str(SOURCE), "source_sha256": hashlib.sha256(source_bytes).hexdigest(),
        "room": "Room_2", "scenery": "Room_2_Cenario", "coordinate_space": "local room pixels",
        "room_size": [room["pxWid"], room["pxHei"]], "grid_px": GRID,
        "water_rect": [wx, wy, width, height], "water_fields": fields(area),
        "water_regions": len(areas), "floor_source": floor["__tilesetRelPath"],
        "method": "Main bounded gap between adjacent Floor runs within WaterArea, sampled every 16 px. Floor_Bridges is excluded. Cliff art alpha/projection is not used to measure the logical bank.",
        "bounded_rows": len(rows), "unbounded_rows_y": unresolved,
        "width_px": {"min": min(row["width"] for row in rows), "median": median(row["width"] for row in rows), "max": max(row["width"] for row in rows)},
        "west_bank_x_range": [min(row["west"] for row in rows), max(row["west"] for row in rows)],
        "east_bank_x_range": [min(row["east"] for row in rows), max(row["east"] for row in rows)],
        "castle": {"elevation_rect": [80, 0, 2608, 1088], "height_px": 56, "preserve_west_bank_above_y": 1088,
                   "foot_transition_review_y": [1088, 1120]},
        "bridges": bridges, "proposal_implemented": False,
        "notes": ["Top 48 px are open/unbounded in the authored Floor and are not interpolated into measurements.",
                  "The diagrams show current logical geometry. Highlighted straightening bands are planning constraints only.",
                  "No decorative tree, path, pedestal, bridge or gameplay position was changed."],
        "profile": rows,
    }
    return report, room, layers


def font(size: int, bold: bool = False) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype("C:/Windows/Fonts/" + ("seguisb.ttf" if bold else "segoeui.ttf"), size)


def diagram(report: dict, room: dict, layers: dict) -> Image.Image:
    image = Image.new("RGB", (1520, 1240), "#211b29")
    draw = ImageDraw.Draw(image)
    ink, muted = "#eee6f1", "#c0adc5"

    def text(x: int, y: int, value: str, size: int = 19, bold: bool = False, color: str = ink) -> None:
        draw.text((x, y), value, font=font(size, bold), fill=color)

    text(48, 25, "RIO / ROOM_2", 34, True)
    text(48, 72, "Levantamento da geometria atual + restrições para a próxima versão. Proposta ainda não aplicada.", 21, color=muted)
    text(48, 121, "A. Contexto do mapa", 24, True)
    text(48, 154, "Esquema lógico: chão, caminhos e estruturas; sem decoração ou iluminação.", 17, color=muted)
    scale, ox, oy = 0.178, 48, 194
    mw, mh = room["pxWid"] * scale, room["pxHei"] * scale

    def mapped(rect: tuple | list) -> tuple[float, float, float, float]:
        x, y, width, height = rect
        return ox + x * scale, oy + max(0, y) * scale, ox + (x + width) * scale, oy + min(room["pxHei"], y + height) * scale

    draw.rectangle((ox, oy, ox + mw, oy + mh), fill="#332235")
    draw.rectangle(mapped(report["water_rect"]), fill="#1d8193")
    floor = {tuple(tile["px"]) for tile in layers["Floor"]["gridTiles"]}
    for y in range(0, room["pxHei"], GRID):
        for start, end in floor_runs(floor, y, room["pxWid"]):
            draw.rectangle(mapped((start, y, end - start, GRID)), fill="#533048")
    for tile in layers["Floor_Paths"]["gridTiles"]:
        draw.rectangle(mapped((*tile["px"], GRID, GRID)), fill="#986c8e")
    draw.rectangle(mapped(report["castle"]["elevation_rect"]), outline="#b192d6", width=2)
    text(ox + 12, oy + 12, "CASTELO  /  +56 px", 17, True)
    for bridge in report["bridges"]:
        rect = mapped(bridge["deck_rect"])
        draw.rectangle(rect, fill="#efbc76", outline="#ffe4b6", width=2)
        text(int(rect[0] - 32), int(rect[1] - 22), bridge["id"], 17, True)
    for layer in layers.values():
        for entity in layer.get("entityInstances", []):
            if entity["__identifier"] != "HordePedestal":
                continue
            x, y = entity["px"]
            px, py = ox + x * scale, oy + y * scale
            draw.ellipse((px - 4, py - 4, px + 4, py + 4), fill="#ddd1e5", outline="#211b29", width=1)
    draw.rectangle((ox, oy, ox + mw, oy + mh), outline="#a78cae", width=2)
    text(48, int(oy + mh + 15), "3696 × 3248 px  •  grade de 16 px  •  posições preservadas", 18, color=muted)

    text(48, 850, "Leitura do canal", 23, True)
    text(48, 890, "Largura atual: 224–336 px; mediana: 272 px.", 21)
    text(48, 925, "Uma região de água: 688 × 3312 px.", 21)
    text(48, 960, "A margem do cliff exige tratamento de altura próprio.", 20)
    text(48, 995, "Curvas longas entre as pontes; travessias retas nas pontes.", 20)
    text(48, 1050, "Não é um render da futura arte do rio.", 20, True, "#efbc76")
    text(48, 1085, "A imagem enviada orienta o formato, não a paleta.", 19, color=muted)
    text(48, 1120, "O estudo não cria máscara, espuma, tiles ou colisão novos.", 19, color=muted)

    text(790, 121, "B. Margens e pontes em coordenadas locais", 23, True)
    text(790, 154, "Contorno medido do Floor, antes da projeção do cliff.", 17, color=muted)
    cs, cx, cy = 0.285, 895, 194
    wx, _, width, _ = report["water_rect"]

    def p(x: float, y: float) -> tuple[float, float]:
        return cx + (x - wx) * cs, cy + y * cs

    draw.rectangle((*p(wx, 0), *p(wx + width, room["pxHei"])), fill="#533048", outline="#8a698d", width=1)
    rows = report["profile"]
    west = [p(value, y) for row in rows for value, y in [(row["west"], row["y"]), (row["west"], row["y"] + GRID)]]
    east = [p(value, y) for row in rows for value, y in [(row["east"], row["y"]), (row["east"], row["y"] + GRID)]]
    draw.polygon(west + east[::-1], fill="#1d8193")
    draw.line(west, fill="#d4c1da", width=2)
    draw.line(east, fill="#d4c1da", width=2)
    draw.line([p(row["center"], row["y"] + GRID / 2) for row in rows], fill="#5ed9d6", width=1)
    draw.rectangle((*p(wx, 0), *p(wx + width, 48)), fill="#423945")
    x0, y0 = p(wx, 1088)
    x1, _ = p(wx + width, 1088)
    draw.line((x0 - 15, y0, x1 + 10, y0), fill="#b192d6", width=2)
    text(1110, int(y0 - 15), "y = 1088 / pé do cliff", 17, True, "#c7ace0")
    for y in [0, 512, 1024, 1536, 2048, 2560, 3072, 3248]:
        _, py = p(wx, y)
        text(822, int(py - 11), str(y), 16, color=muted)
        draw.line((cx - 10, py, cx - 2, py), fill=muted)
    for bridge in report["bridges"]:
        x, y, w, h = bridge["deck_rect"]
        start, end = bridge["proposed_transition_y"]
        x0, y0 = p(wx, start)
        x1, y1 = p(wx + width, end)
        draw.rectangle((x0 - 8, y0, x1 + 8, y1), outline="#efbc76", width=2)
        draw.rectangle((*p(x, y), *p(x + w, y + h)), fill="#bd8c58", outline="#ffe4b6", width=2)
        text(1110, int((y0 + y1) / 2 - 24), f"{bridge['id']}  /  {w} × {h} px", 19, True)
        text(1110, int((y0 + y1) / 2 + 5), f"deck em y {y}–{y + h}", 17, color=muted)
        text(1110, int((y0 + y1) / 2 + 31), f"transição proposta: {start}–{end}", 16, color="#efbc76")
    text(790, 1150, "Azul: canal atual   |   Claro: margens medidas   |   Dourado: estudo das travessias", 17)
    text(790, 1180, "Topo aberto (48 px) excluído das estatísticas; sem interpolação automática.", 17, color=muted)
    return image


def main() -> None:
    original = SOURCE.read_bytes()
    data = json.loads(original)
    report, room, layers = survey(data, original)
    OUTPUT.mkdir(parents=True, exist_ok=True)
    (OUTPUT / "river_mapping.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    with (OUTPUT / "river_profile.csv").open("w", encoding="utf-8", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=["y", "west", "east", "width", "center"])
        writer.writeheader()
        writer.writerows(report["profile"])
    diagram(report, room, layers).save(OUTPUT / "river_mapping.png")
    assert SOURCE.read_bytes() == original, "A read-only survey cannot modify the LDtk source."
    print(json.dumps({key: report[key] for key in ["bounded_rows", "width_px", "bridges", "proposal_implemented"]}, ensure_ascii=True))


if __name__ == "__main__":
    main()
