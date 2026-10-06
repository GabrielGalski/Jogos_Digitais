"""Exercise the Python updater and CMD launcher against private map copies."""
from copy import deepcopy
from contextlib import redirect_stdout
import hashlib
from io import StringIO
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
from unittest.mock import patch

from PIL import Image
import refresh_ldtk_sources as updater

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "tools/refresh_ldtk_sources.py"


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def run(project: Path, *args: str, expected: int = 0) -> dict:
    result = subprocess.run([sys.executable, "-X", "utf8", str(SCRIPT), "--project", str(project), *args],
                            capture_output=True, encoding="utf-8", timeout=15)
    assert result.returncode == expected, (result.returncode, result.stdout, result.stderr)
    return json.loads(result.stdout) if result.stdout.strip() else {}


def test() -> None:
    (ROOT / "tmp").mkdir(exist_ok=True)
    folder = Path(tempfile.mkdtemp(prefix="ldtk_updater_", dir=ROOT / "tmp"))
    project = folder / "monster_booster.ldtk"
    shutil.copyfile(ROOT / project.name, project)
    before = json.loads(project.read_bytes())
    # Ensure the cache invalidation/backup case remains covered after a real refresh.
    before["defs"]["tilesets"][0]["cachedPixelData"] = {"testCache": True}
    project.write_text(json.dumps(before, ensure_ascii=False), encoding="utf-8")
    for source in before["defs"]["tilesets"]:
        target = folder / source["relPath"]
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(ROOT / source["relPath"], target)
    pngs = {path: digest(folder / path) for path in (t["relPath"] for t in before["defs"]["tilesets"])}
    original = project.read_bytes()
    dry = run(project, "--dry-run")
    assert dry["pngsRead"] == 17 and project.read_bytes() == original
    refreshed = run(project)
    assert Path(refreshed["backup"]).read_bytes() == original
    after = json.loads(project.read_bytes())
    restored = deepcopy(after)
    for old, new in zip(before["defs"]["tilesets"], restored["defs"]["tilesets"]):
        assert new["cachedPixelData"] is None
        new["cachedPixelData"] = old["cachedPixelData"]
    assert restored == before, "Refresh changed paint, grids, entities or other map settings"
    assert all(digest(folder / p) == sha for p, sha in pngs.items()), "Updater modified a PNG"
    stable = project.read_bytes()
    assert not run(project)["changed"] and project.read_bytes() == stable
    leaves = folder / "assets/tiles/wall/leaves.png"
    with Image.open(leaves) as source:
        image = source.convert("RGBA")
    image.putpixel((0, 0), (202, 173, 238, 255))
    image.save(leaves)
    report = run(project)
    assert report["pngHashes"][str(leaves)] == digest(leaves), "Updater did not read the edited PNG"
    assert project.read_bytes() == stable, "Same-size PNG edit should not move any painted tile"
    floor = folder / "assets/tiles/floor/floor_tileset.png"
    with Image.open(floor) as source:
        image = source.convert("RGBA")
    grown = Image.new("RGBA", (80, 48))
    grown.paste(image)
    grown.save(floor)
    run(project)
    grown_data = json.loads(project.read_bytes())
    floor_def = next(t for t in grown_data["defs"]["tilesets"] if t["uid"] == 101)
    assert (floor_def["pxWid"], floor_def["__cWid"], floor_def["tileGridSize"]) == (80, 5, 16)
    for level in grown_data["levels"]:
        for layer in level["layerInstances"]:
            if layer["__identifier"] == "Floor":
                assert all(t["t"] == t["src"][1] // 16 * 5 + t["src"][0] // 16 for t in layer["gridTiles"])
    safe_map = project.read_bytes()
    Image.new("RGBA", (16, 16)).save(floor)
    run(project, expected=1)
    assert project.read_bytes() == safe_map, "Reduced PNG corrupted existing paint"
    grown.save(floor)
    # Simulate the busy state without creating an unsigned process or closing apps.
    with patch.object(updater, "editor_busy", return_value=True):
        try:
            updater.refresh(project)
        except RuntimeError as error:
            assert "Salve e feche" in str(error)
        else:
            raise AssertionError("Open editor did not block the update")
    assert project.read_bytes() == safe_map
    # Verify the launch argument without opening the editor during automated tests.
    with patch.object(sys, "argv", [str(SCRIPT), "--project", str(project), "--open"]), \
            patch.object(updater, "editor_busy", return_value=False), \
            patch.object(updater.subprocess, "Popen") as launch, redirect_stdout(StringIO()):
        assert updater.main() == 0
        expected_editor = Path(updater.os.environ["LOCALAPPDATA"]) / "Programs/ldtk/LDtk.exe"
        launch.assert_called_once_with([str(expected_editor), str(project.resolve())], cwd=project.resolve().parent)
    actual_before = (ROOT / project.name).read_bytes()
    command = subprocess.run(["cmd.exe", "/d", "/c", str(ROOT / "AtualizarLDtk.cmd"), "--dry-run"],
                             capture_output=True, encoding="utf-8", timeout=15)
    assert command.returncode == 0, (command.stdout, command.stderr)
    assert "17 PNGs lidos" in command.stdout
    assert (ROOT / project.name).read_bytes() == actual_before
    print("LDTK UPDATER PASS: CMD, dry run, exact backup, paint/grids preserved, PNG edits read, idempotence, resizing IDs, shrinking rollback, busy-editor protection, correct editor-open argument")
    print(f"Private fixtures: {folder}")


if __name__ == "__main__":
    test()
