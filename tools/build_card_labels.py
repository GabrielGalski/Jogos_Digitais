"""Apply Determination labels to the existing card base, sequentially with Pillow.

Run: python tools/build_card_labels.py
Check without writing: python tools/build_card_labels.py --check
Include a native-resolution overview: python tools/build_card_labels.py --preview
Each catalog entry needs a matching card folder.
Requires Pillow >= 9.1 (python -m pip install Pillow).
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import time
import unicodedata
from pathlib import Path

from PIL import Image, ImageColor, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
CARDS = ROOT / "assets/cards"
LAYOUT = ROOT / "tools/card_labels_layout.json"
REPORT = ROOT / "output/cards/card_labels"
GROUPS = {
    "M": ("manifestacao", "Manifestação"),
    "I": ("infusao", "Infusão"),
    "U": ("mutacao", "Mutação"),
}


def normalize(value: str) -> str:
    plain = unicodedata.normalize("NFKD", value).encode("ascii", "ignore").decode()
    return re.sub(r"[^a-z0-9]+", "_", plain.casefold()).strip("_")


def read_catalog() -> list[dict]:
    gdd = (ROOT / "docs/GDD.md").read_text(encoding="utf-8")
    section = gdd.split("### Catálogo de estudo", 1)[1].split("\n## ", 1)[0]
    entries = re.findall(r"\b([MIU]\d{2}) — ([^|\n]+)", section)
    catalog = {}
    for code, name in entries:
        if code in catalog:
            raise ValueError(f"Duplicate card in GDD: {code}")
        catalog[code] = name.strip()
    if not catalog:
        raise ValueError("The GDD card table is empty.")
    cards = []
    seen = set()
    for prefix, (group, aspect) in GROUPS.items():
        for folder in sorted((CARDS / group).iterdir()):
            if not folder.is_dir():
                continue
            match = re.fullmatch(r"(.+) ([MIU]\d{2})", folder.name)
            if match is None:
                raise ValueError(f"Unrecognized card folder: {folder.relative_to(ROOT)}")
            slug, code = match.groups()
            if code not in catalog or not code.startswith(prefix) or code in seen:
                raise ValueError(f"Folder does not match a unique GDD entry: {folder.name}")
            if normalize(slug) != normalize(catalog[code]):
                raise ValueError(f"GDD name and folder disagree: {folder.name}")
            cards.append({"id": code, "name": catalog[code], "aspect": aspect,
                          "file": (folder / f"{folder.name}.png").relative_to(ROOT).as_posix()})
            seen.add(code)
    if seen != catalog.keys():
        raise ValueError(f"GDD entries without an existing folder: {sorted(catalog.keys() - seen)}")
    return sorted(cards, key=lambda card: (list(GROUPS).index(card["id"][0]), card["id"]))


def text_mask(text: str, font: ImageFont.FreeTypeFont) -> Image.Image:
    left, top, right, bottom = font.getbbox(text)
    mask = Image.new("L", (max(1, right - left), max(1, bottom - top)))
    drawing = ImageDraw.Draw(mask)
    drawing.text((-left, -top), text, font=font, fill=255)
    ink_bounds = mask.getbbox()
    if ink_bounds is None:
        raise ValueError(f"The font rendered no pixels for {text!r}.")
    return mask.crop(ink_bounds)


def fit_font(text: str, bounds: list[int], font_path: Path, max_size: int) -> Image.Image:
    width, height = bounds[2] - bounds[0], bounds[3] - bounds[1]
    for size in range(max_size, 0, -1):
        font = ImageFont.truetype(str(font_path), size)
        mask = text_mask(text, font)
        if mask.width <= width and mask.height <= height:
            return mask
    raise ValueError(f"No font size fits {text!r} in the mapped bounds.")


def validate_mapping(base: Image.Image, layout: dict) -> None:
    if list(base.size) != layout["source_size"]:
        raise ValueError("The base dimensions changed. Update the layout before rendering.")
    background = ImageColor.getcolor(layout["background"], "RGBA")
    for role in ("aspect", "name"):
        area, bounds = layout[role]["area"], layout[role]["text_bounds"]
        if not (0 <= area[0] < bounds[0] < bounds[2] < area[2] <= base.width
                and 0 <= area[1] < bounds[1] < bounds[3] < area[3] <= base.height):
            raise ValueError(f"Invalid inset for {role}: {bounds}")
        region = base.crop(bounds)
        if region.getcolors(region.width * region.height) != [(region.width * region.height, background)]:
            raise ValueError(f"The mapped {role} region is no longer entirely {layout['background']}.")


def render_card(base: Image.Image, card: dict, layout: dict, masks: dict) -> tuple:
    image = base.copy()
    placements = {}
    for role, text in (("aspect", card["aspect"]), ("name", card["name"])):
        mask = masks[role][text]
        left, top, right, bottom = layout[role]["text_bounds"]
        x = left + (right - left - mask.width) // 2
        y = top + (bottom - top - mask.height) // 2
        image.paste(ImageColor.getcolor(layout["ink"], "RGBA"), (x, y), mask)
        placements[role] = {"text": text, "ink_bounds": [x, y, x + mask.width, y + mask.height]}

    # Changes are permitted only inside the two mapped labels, including alpha.
    for y in range(base.height):
        for x in range(base.width):
            if image.getpixel((x, y)) == base.getpixel((x, y)):
                continue
            if not any(layout[r]["text_bounds"][0] <= x < layout[r]["text_bounds"][2]
                       and layout[r]["text_bounds"][1] <= y < layout[r]["text_bounds"][3]
                       for r in ("aspect", "name")):
                raise ValueError(f"Unexpected change outside labels at {(x, y)}")
            if image.getpixel((x, y))[3] != base.getpixel((x, y))[3]:
                raise ValueError("Text must preserve the base alpha channel.")
    return image, placements


def save_if_changed(image: Image.Image, path: Path) -> bool:
    if path.exists():
        with Image.open(path) as current:
            if current.mode == image.mode and current.size == image.size and current.tobytes() == image.tobytes():
                return False
    temporary = path.with_suffix(".png.tmp")
    image.save(temporary, format="PNG")
    temporary.replace(path)
    return True


def export_art_layout(base: Image.Image, layout: dict, check: bool) -> None:
    """Publish the source geometry and a border-only mask for the in-game renderer."""
    inner = layout["border_inner_bounds"]
    border = Image.new("L", base.size, 0)
    for y in range(base.height):
        for x in range(base.width):
            in_center = inner[0] <= x < inner[2] and inner[1] <= y < inner[3]
            if not in_center and base.getpixel((x, y))[3] > 0:
                border.putpixel((x, y), 255)
    for role in ("aspect", "name"):
        if border.crop(layout[role]["text_bounds"]).getbbox() is not None:
            raise ValueError("The foil mask overlaps a text field.")
    bounds = base.getchannel("A").getbbox()
    geometry = {"source_size": list(base.size),
                "visible_rect": [bounds[0], bounds[1], bounds[2] - bounds[0], bounds[3] - bounds[1]],
                "border_mask": "res://assets/visual/cards/border_mask.png"}
    geometry_file = ROOT / "resources/cards/card_art_layout.json"
    mask_file = ROOT / "assets/visual/cards/border_mask.png"
    if check:
        if json.loads(geometry_file.read_text(encoding="utf-8")) != geometry:
            raise ValueError("The runtime card geometry is out of date.")
        with Image.open(mask_file) as existing:
            if existing.size != border.size or existing.convert("L").tobytes() != border.tobytes():
                raise ValueError("The border mask is out of date.")
    else:
        mask_file.parent.mkdir(parents=True, exist_ok=True)
        save_if_changed(border, mask_file)
        content = json.dumps(geometry, ensure_ascii=False, indent=2) + "\n"
        if not geometry_file.exists() or geometry_file.read_text(encoding="utf-8") != content:
            geometry_file.write_text(content, encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="Validate the full batch without writing.")
    parser.add_argument("--preview", action="store_true", help="Save a native-resolution overview outside assets/cards.")
    args = parser.parse_args()
    started = time.perf_counter()
    layout = json.loads(LAYOUT.read_text(encoding="utf-8"))
    source = ROOT / layout["base"]
    source_hash = hashlib.sha256(source.read_bytes()).hexdigest()
    with Image.open(source) as opened:
        base = opened.convert("RGBA")
    validate_mapping(base, layout)
    scale = layout["output_scale"]
    if not isinstance(scale, int) or scale < 1:
        raise ValueError("output_scale must be a positive integer.")
    if scale != 1:
        base = base.resize((base.width * scale, base.height * scale), Image.Resampling.NEAREST)
    render_layout = dict(layout)
    for role in ("aspect", "name"):
        render_layout[role] = {key: [coordinate * scale for coordinate in rect]
                               for key, rect in layout[role].items()}
    render_layout["border_inner_bounds"] = [coordinate * scale for coordinate in layout["border_inner_bounds"]]
    cards = read_catalog()
    masks, widest = {}, {}
    font_sizes = {role: size * scale for role, size in layout["font_sizes"].items()}
    for role in ("aspect", "name"):
        texts = sorted({card[role] for card in cards})
        masks[role] = {text: fit_font(text, render_layout[role]["text_bounds"], ROOT / layout["font"],
                                     font_sizes[role]) for text in texts}
        widest[role] = max(texts, key=lambda text: masks[role][text].width)
    tile_width, tile_height = base.width + 16, base.height + 16
    preview = Image.new("RGBA", (6 * tile_width, ((len(cards) + 5) // 6) * tile_height), "#737373") if args.preview else None
    records, written = [], 0
    for index, card in enumerate(cards):
        image, placements = render_card(base, card, render_layout, masks)
        target = ROOT / card["file"]
        if args.check:
            if not target.is_file():
                raise ValueError(f"Missing generated card: {card['file']}")
            with Image.open(target) as existing:
                if existing.convert("RGBA").tobytes() != image.tobytes() or existing.size != base.size:
                    raise ValueError(f"Generated pixels differ: {card['file']}")
        else:
            written += save_if_changed(image, target)
        records.append({**card, "placements": placements})
        if preview is not None:
            preview.alpha_composite(image, ((index % 6) * tile_width + 8, (index // 6) * tile_height + 8))
    if hashlib.sha256(source.read_bytes()).hexdigest() != source_hash:
        raise ValueError("The source base changed during processing.")
    expected = {ROOT / card["file"] for card in cards}
    existing = {p for group, _aspect in GROUPS.values() for p in (CARDS / group).glob("*/*.png")}
    if expected != existing:
        raise ValueError(f"Unexpected PNGs remain in cards: {sorted(str(p) for p in existing - expected)}")
    export_art_layout(base, render_layout, args.check)
    if not args.check:
        REPORT.mkdir(parents=True, exist_ok=True)
        (REPORT / ".gdignore").touch()
        report = {"base": layout["base"], "source_sha256": source_hash, "size": list(base.size),
                  "count": len(cards), "font": layout["font"], "font_sizes": font_sizes,
                  "widest_labels": widest, "layout": layout,
                  "rendered_layout": render_layout, "cards": records}
        (REPORT / "report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        if preview is not None:
            preview.save(REPORT / "preview.png")
    print(json.dumps({"checked" if args.check else "generated": len(cards), "files_written": written,
                      "size": list(base.size), "font_sizes": font_sizes,
                      "elapsed_seconds": round(time.perf_counter() - started, 3)}, ensure_ascii=True))


if __name__ == "__main__":
    main()
