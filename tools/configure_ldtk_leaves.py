"""Register live leaves PNG/foreground layer without touching authored map content."""
from copy import deepcopy
import hashlib
import json
from pathlib import Path
import uuid

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / "monster_booster.ldtk"
SOURCE = "assets/tiles/wall/leaves.png"


def register() -> None:
    original = PROJECT.read_bytes()
    data = json.loads(original.decode("utf-8-sig"))
    definitions = data["defs"]
    existing = next((t for t in definitions["tilesets"]
                     if str(t["relPath"]).replace("\\", "/").removeprefix("./") == SOURCE), None)
    if existing is not None:
        assert any(l["tilesetDefUid"] == existing["uid"] for l in definitions["layers"])
        print("Leaves already registered; authored project unchanged.")
        return
    assert (ROOT / SOURCE).is_file(), "Copy the original leaves.png first"
    next_uid = data["nextUid"]
    tileset = deepcopy(definitions["tilesets"][0])
    tileset.update(identifier="Leaves_16", uid=next_uid, relPath=SOURCE,
                   pxWid=256, pxHei=176, tileGridSize=16, __cWid=16, __cHei=11,
                   spacing=0, padding=0, customData=[], enumTags=[], tags=[],
                   cachedPixelData=None,
                   savedSelections=[
                       {"ids": list(range(176)), "mode": "Stamp"},
                       {"ids": [y * 16 + x for y in range(3, 8) for x in range(8)], "mode": "Stamp"},
                       {"ids": [y * 16 + x for y in range(3, 11) for x in range(11, 16)], "mode": "Stamp"},
                   ])
    definitions["tilesets"].append(tileset)
    layer = deepcopy(next(l for l in definitions["layers"] if l["type"] == "Tiles"))
    layer.update(identifier="Leaves", uid=next_uid + 1, tilesetDefUid=next_uid,
                 doc="Foreground leaves: cover all world props/actors; no physics, projected light or halo.",
                 uiColor="#CBB5E9", gridSize=16, pxOffsetX=0, pxOffsetY=0,
                 parallaxFactorX=0, parallaxFactorY=0,
                 requiredTags=[], excludedTags=[], uiFilterTags=[])
    definitions["layers"].insert(0, layer)
    for level in data["levels"]:
        untouched = deepcopy(level["layerInstances"])
        instance = deepcopy(next(l for l in untouched if l["__type"] == "Tiles"))
        instance.update(__identifier="Leaves", __type="Tiles", __gridSize=16,
                        __cWid=level["pxWid"] // 16, __cHei=level["pxHei"] // 16,
                        __opacity=1, __pxTotalOffsetX=0, __pxTotalOffsetY=0,
                        __tilesetDefUid=next_uid, __tilesetRelPath=SOURCE,
                        iid=str(uuid.uuid4()), levelId=level["uid"], layerDefUid=next_uid + 1,
                        pxOffsetX=0, pxOffsetY=0, visible=True, optionalRules=[],
                        intGridCsv=[], autoLayerTiles=[], gridTiles=[], entityInstances=[],
                        overrideTilesetUid=None)
        level["layerInstances"].insert(0, instance)
        assert level["layerInstances"][1:] == untouched, "Authored layers were changed"
    data["nextUid"] = next_uid + 2
    digest = hashlib.sha256(original).hexdigest()[:12]
    backup = ROOT / "ldtk_backups" / f"before_leaves_{digest}.ldtk"
    backup.parent.mkdir(exist_ok=True)
    if not backup.exists():
        backup.write_bytes(original)
    assert backup.read_bytes() == original
    assert PROJECT.read_bytes() == original, "LDtk changed during registration; retry with the newest map"
    PROJECT.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Leaves registered. Existing layers preserved. Backup: {backup}")


if __name__ == "__main__":
    register()
