"""Map authored portal cutouts and stair colors without rewriting either sprite."""
from __future__ import annotations

import argparse
from collections import Counter, deque
from hashlib import sha256
from io import BytesIO
import json
import math
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
PORTAL = ROOT / "assets/tiles/structures/final portal/portal1.png"
STAIRS = ROOT / "assets/tiles/structures/stairs/stairs.png"
MASK = ROOT / "assets/visual/structures/final_portal_map.png"
LAYOUT = ROOT / "resources/visual/castle_structure_layout.json"


def holes(image: Image.Image) -> list[list[tuple[int, int]]]:
    width, height = image.size
    remaining = {(x, y) for y in range(height) for x in range(width)
                 if image.getpixel((x, y))[3] == 0}
    result = []
    while remaining:
        start = min(remaining, key=lambda point: (point[1], point[0]))
        remaining.remove(start)
        queue = deque([start])
        component = []
        outside = False
        while queue:
            x, y = queue.popleft()
            component.append((x, y))
            outside |= x in (0, width - 1) or y in (0, height - 1)
            for neighbor in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
                if neighbor in remaining:
                    remaining.remove(neighbor)
                    queue.append(neighbor)
        if not outside:
            result.append(component)
    return result


def bounds(points: list[tuple[int, int]]) -> list[int]:
    xs, ys = zip(*points)
    return [min(xs), min(ys), max(xs) - min(xs) + 1, max(ys) - min(ys) + 1]


def centroid(points: list[tuple[int, int]]) -> tuple[float, float]:
    return tuple(sum(point[axis] for point in points) / len(points) for axis in (0, 1))


def mapped() -> tuple[bytes, bytes]:
    image = Image.open(PORTAL).convert("RGBA")
    enclosed = holes(image)
    opening = max(enclosed, key=len)
    runes = [region for region in enclosed if region is not opening]
    if image.size != (192, 112) or len(runes) != 24:
        raise ValueError("Expected portal1 at 192x112, one opening and 24 authored rune cutouts.")
    center = centroid(opening)
    runes.sort(key=lambda points: (math.atan2(centroid(points)[1] - center[1],
                                              centroid(points)[0] - center[0]) + math.pi / 2) % math.tau)
    # Opaque data texture prevents alpha-border import processing from changing rune IDs.
    mask = Image.new("RGBA", image.size, (0, 0, 0, 255))
    for x, y in opening:
        mask.putpixel((x, y), (0, 255, 0, 255))
    for index, points in enumerate(runes, 1):
        for point in points:
            mask.putpixel(point, (index, 0, 0, 255))
    buffer = BytesIO()
    mask.save(buffer, format="PNG", optimize=True)
    stair_image = Image.open(STAIRS).convert("RGBA")
    if stair_image.size != (32, 128):
        raise ValueError("Expected authored stairs at 32x128.")
    layout = {
        "portal": {
            "source": "res://" + PORTAL.relative_to(ROOT).as_posix(),
            "source_sha256": sha256(PORTAL.read_bytes()).hexdigest(),
            "size": list(image.size), "feet_pivot": [96, 104],
            "opening_bounds": bounds(opening), "opening_pixels": len(opening),
            "rune_count": 24, "runes_per_altar": 4,
            "rune_order": "clockwise, starting at the top",
            "runes": [{"id": index, "bounds": bounds(points), "pixels": len(points)}
                      for index, points in enumerate(runes, 1)],
            "arch_colors_preserved": ["#2e222f", "#3e3546"],
            "inactive_rune": "#3e3546",
            "mask_channels": {"R": "rune ID, byte 1..24", "G": "opening, byte 255"},
        },
        "stairs": {
            "source": "res://" + STAIRS.relative_to(ROOT).as_posix(),
            "source_sha256": sha256(STAIRS.read_bytes()).hexdigest(),
            "size": list(stair_image.size), "horizontal_repeat_px": 32,
            "palette": ["#%02x%02x%02x" % color[:3]
                        for color, _ in Counter(stair_image.get_flattened_data()).most_common()
                        if color[3] == 255],
            "placement": "source reference only; no stair sprites rendered in the current world",
        },
    }
    return buffer.getvalue(), (json.dumps(layout, ensure_ascii=False, indent=2) + "\n").encode("utf-8")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    payloads = zip((MASK, LAYOUT), mapped())
    for path, payload in payloads:
        if args.check:
            if not path.is_file() or path.read_bytes() != payload:
                raise SystemExit(f"Outdated mapping: {path.relative_to(ROOT)}")
        elif not path.is_file() or path.read_bytes() != payload:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(payload)
    print("CASTLE_STRUCTURE_MAPS PASS: 24 runes, 1 transparent opening, 32x128 stair source preserved")


if __name__ == "__main__":
    main()
