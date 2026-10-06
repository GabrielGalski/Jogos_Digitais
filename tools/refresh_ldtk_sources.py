"""Refresh the current LDtk map from original PNGs, without replacing authored maps."""
from __future__ import annotations

import argparse
from copy import deepcopy
import csv
from datetime import datetime
import hashlib
from io import BytesIO
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
DIRECT = {
    101: "assets/tiles/floor/floor_tileset.png",
    102: "assets/tiles/inferior/inferior.png",
    103: "assets/tiles/wall/wall_tileset.png",
    105: "assets/tiles/wall/decor/column_square.png",
    502: "assets/tiles/wall/decor/column_round.png",
    503: "assets/tiles/wall/decor/stair.png",
    104: "assets/tiles/door/door_front_closed_superior.png",
    504: "assets/tiles/door/door_front_opened_superior.png",
    505: "assets/tiles/door/door_front_closed_inferior.png",
    506: "assets/tiles/door/door_front_opened_inferior.png",
    106: "assets/tiles/decor/minotaur_chair.png",
    107: "assets/tiles/decor/minotaur_chair_back.png",
    108: "assets/tiles/decor/minotaur_chair_seat.png",
    109: "assets/characters/player/idle/player_idle_01.png",
    507: "assets/merchant/character/merchant_idle1.png",
    508: "assets/enemies/minotaur/walk/minotaur_walk_01.png",
    518: "assets/tiles/wall/leaves.png",
}


def editor_busy() -> bool:
    result = subprocess.run(["tasklist.exe", "/FI", "IMAGENAME eq LDtk.exe", "/FO", "CSV", "/NH"],
                            capture_output=True, timeout=10, check=True)
    return any(row and row[0].casefold() == "ldtk.exe"
               for row in csv.reader(result.stdout.decode(errors="replace").splitlines()))


def inside(root: Path, relative: str) -> Path:
    path = (root / relative).resolve()
    if not path.is_relative_to(root.resolve()):
        raise ValueError(f"Fonte fora do projeto: {relative}")
    return path


def digest(content: bytes) -> str:
    return hashlib.sha256(content).hexdigest()


def remap_id(value: int, old_columns: int, columns: int, rows: int) -> int:
    x, y = int(value) % old_columns, int(value) // old_columns
    if x >= columns or y >= rows:
        raise ValueError("PNG reduzido: um stamp/metadado ficaria fora do atlas. Mapa preservado.")
    return y * columns + x


def refresh(project: Path, dry_run: bool = False) -> dict:
    if editor_busy():
        raise RuntimeError("Salve e feche o LDtk antes de atualizar. Nada foi modificado.")
    root = project.resolve().parent
    original = project.read_bytes()
    before = json.loads(original.decode("utf-8-sig"))
    data = deepcopy(before)
    sources, hashes, changed = {}, {}, []
    for source in data["defs"]["tilesets"]:
        uid = int(source["uid"])
        relative = str(source["relPath"]).replace("\\", "/").removeprefix("./")
        full = inside(root, relative)
        if not full.is_file() or "/editor/" in relative:
            relative = DIRECT[uid]
            full = inside(root, relative)
        content = full.read_bytes()
        hashes[str(full)] = digest(content)
        with Image.open(BytesIO(content)) as image:
            image.load()
            width, height = image.size
        grid, padding, spacing = (int(source[k]) for k in ("tileGridSize", "padding", "spacing"))
        if grid <= 0 or padding < 0 or spacing < 0:
            raise ValueError(f"Grade inválida: {relative}")
        columns = (width - padding * 2 + grid + spacing - 1) // (grid + spacing)
        rows = (height - padding * 2 + grid + spacing - 1) // (grid + spacing)
        if columns <= 0 or rows <= 0:
            raise ValueError(f"PNG menor que a grade: {relative}")
        resized = (width, height) != (source["pxWid"], source["pxHei"])
        if resized:
            old_columns = int(source["__cWid"])
            for selection in source["savedSelections"]:
                selection["ids"] = [remap_id(t, old_columns, columns, rows) for t in selection["ids"]]
            for tag in source["enumTags"]:
                tag["tileIds"] = [remap_id(t, old_columns, columns, rows) for t in tag["tileIds"]]
            for entry in source["customData"]:
                entry["tileId"] = remap_id(entry["tileId"], old_columns, columns, rows)
        if resized or source.get("cachedPixelData") is not None or source["relPath"] != relative:
            changed.append(source["identifier"])
        source.update(relPath=relative, pxWid=width, pxHei=height, __cWid=columns, __cHei=rows,
                      cachedPixelData=None)
        sources[uid] = source
    levels = list(data["levels"])
    for world in data["worlds"]:
        levels.extend(world["levels"])
    tiles = 0
    for level in levels:
        if level["layerInstances"] is None:
            raise ValueError("Mapa externo não suportado pelo atualizador; nada foi salvo.")
        for layer in level["layerInstances"]:
            uid = layer["__tilesetDefUid"]
            if uid is None:
                continue
            source = sources[int(uid)]
            layer["__tilesetRelPath"] = source["relPath"]
            grid, padding, spacing = (int(source[k]) for k in ("tileGridSize", "padding", "spacing"))
            for tile in layer["gridTiles"] + layer["autoLayerTiles"]:
                x, y = map(int, tile["src"])
                if not (padding <= x < source["pxWid"] and padding <= y < source["pxHei"]):
                    raise ValueError(f"PNG reduzido deixou tile pintado fora do atlas: {source['relPath']} [{x},{y}]. Mapa preservado.")
                tile["t"] = (y - padding) // (grid + spacing) * source["__cWid"] + (x - padding) // (grid + spacing)
                tiles += 1
    write = data != before
    backup = None
    if write and not dry_run:
        if project.read_bytes() != original or editor_busy():
            raise RuntimeError("O mapa foi salvo/aberto durante a atualização. Nada foi sobrescrito; tente novamente.")
        if any(digest(Path(path).read_bytes()) != sha for path, sha in hashes.items()):
            raise RuntimeError("Um PNG mudou durante a atualização. Espere terminar de salvar e tente novamente.")
        backup_root = inside(root, "ldtk_backups")
        backup_root.mkdir(exist_ok=True)
        backup = backup_root / f"before_png_refresh_{datetime.now():%Y%m%d_%H%M%S_%f}_{digest(original)[:12]}.ldtk"
        backup.write_bytes(original)
        with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", dir=root, prefix=".ldtk_refresh_", suffix=".tmp", delete=False) as file:
            temporary = Path(file.name)
            json.dump(data, file, ensure_ascii=False, indent=2)
            file.write("\n")
        try:
            if project.read_bytes() != original:
                raise RuntimeError("O mapa mudou durante a atualização; tente novamente. Nada foi sobrescrito.")
            os.replace(temporary, project)
        finally:
            temporary.unlink(missing_ok=True)
    return {"ok": True, "project": str(project.resolve()), "dryRun": dry_run, "changed": write,
            "pngsRead": len(sources), "updatedTilesets": changed, "paintedTiles": tiles,
            "backup": str(backup) if backup else None, "pngHashes": hashes}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", type=Path, default=ROOT / "monster_booster.ldtk")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--open", action="store_true")
    parser.add_argument("--summary", action="store_true")
    args = parser.parse_args()
    try:
        report = refresh(args.project, args.dry_run)
        if args.summary:
            print(f"{report['pngsRead']} PNGs lidos; {report['paintedTiles']} tiles pintados preservados.")
            print("Simulação: nenhum arquivo alterado." if args.dry_run else "Fontes e caches atualizados; grades e posições preservadas.")
            if report["backup"]:
                print("Backup: " + report["backup"])
        else:
            print(json.dumps(report, ensure_ascii=False))
        if args.open and not args.dry_run:
            editor = Path(os.environ["LOCALAPPDATA"]) / "Programs/ldtk/LDtk.exe"
            if not editor.is_file():
                raise FileNotFoundError("LDtk.exe não encontrado. Abra o monster_booster.ldtk manualmente.")
            subprocess.Popen([str(editor), str(args.project.resolve())], cwd=args.project.resolve().parent)
        return 0
    except Exception as error:
        print(f"Atualização recusada: {error}", file=sys.stderr)
        return 2 if isinstance(error, RuntimeError) else 1


if __name__ == "__main__":
    raise SystemExit(main())
