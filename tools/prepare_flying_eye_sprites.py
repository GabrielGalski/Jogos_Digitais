"""Map existing Flying Eye art and losslessly extract its ten death frames."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
DIRECTORY = ROOT / "assets/enemies/flying eye"
SOURCE = DIRECTORY / "death sprite sheet.png"


def main() -> None:
    original = SOURCE.read_bytes()
    source = Image.open(SOURCE).convert("RGBA")
    assert source.size == (1505, 80), "Re-map an edited sheet before extracting."
    covered = Image.new("L", source.size, 0)
    frames = []
    for index in range(10):
        rect = (index * 156, 0, index * 156 + 96, 80)
        frame = source.crop(rect)
        name = f"death_{index + 1:02}.png"
        path = DIRECTORY / name
        if path.exists():
            with Image.open(path) as previous:
                assert previous.convert("RGBA").tobytes() == frame.tobytes(), f"Refusing to overwrite edited {name}."
        else:
            frame.save(path)
        covered.paste(frame.getchannel("A"), rect)
        frames.append({"file": name, "source_rect": [rect[0], rect[1], 96, 80],
                       "canvas": [96, 80], "pivot": [48, 37], "used_rect": frame.getbbox()})
    assert source.getchannel("A").tobytes() == covered.tobytes(), "A source pixel was left outside the mapped frames."
    poses = []
    for name in ["idle.png", "attack1.png", "attack2.png", "back_looking_left.png", "back_lookin_right.png"]:
        image = Image.open(DIRECTORY / name).convert("RGBA")
        poses.append({"file": name, "canvas": image.size, "used_rect": image.getbbox(),
                      "display_body_px": [16, 16]})
    mapping = {"source": SOURCE.name, "source_sha256": hashlib.sha256(original).hexdigest(),
               "source_size": source.size, "frame_pitch": 156, "frame_canvas": [96, 80],
               "death_fps": 16, "death_loop": False, "death_pivot": [48, 37],
               "death_frames": frames, "poses": poses, "all_opaque_source_pixels_preserved": True}
    (DIRECTORY / "sprite_map.json").write_text(json.dumps(mapping, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    assert SOURCE.read_bytes() == original
    print(json.dumps({"frames": len(frames), "canvas": [96, 80], "source_preserved": True}))


if __name__ == "__main__":
    main()
