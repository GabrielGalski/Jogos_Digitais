"""Register empty visual-only LDtk areas, preserving all authored map content."""
from copy import deepcopy
from datetime import datetime
import hashlib
import json
import os
from pathlib import Path
import tempfile
import uuid

from refresh_ldtk_sources import editor_busy

ROOT = Path(__file__).resolve().parents[1]
FIELDS = [
    ("AnimationId", "String", "", None, None, "Identificador para vincular SpriteFrames posteriormente."),
    ("FramesFolder", "String", "", None, None, "Pasta em assets com a sequencia PNG; vazio nao mostra nada."),
    ("FPS", "Float", 12.0, 1, 120, "Velocidade da animacao."),
    ("MinDelay", "Float", 6.0, 0.1, None, "Espera minima entre tentativas, em segundos."),
    ("MaxDelay", "Float", 18.0, 0.1, None, "Espera maxima entre tentativas, em segundos."),
    ("Chance", "Float", 0.6, 0, 1, "Probabilidade por tentativa: 0 nunca, 1 sempre."),
    ("RepeatCount", "Int", 1, 1, 20, "Ciclos completos antes de sumir."),
    ("Scale", "Float", 1.0, 0.01, 10, "Escala visual, sem alterar o mapa ou a fisica."),
    ("FlipX", "Bool", False, None, None, "Espelha horizontalmente."),
    ("FlipY", "Bool", False, None, None, "Espelha verticalmente."),
    ("Enabled", "Bool", True, None, None, "Habilita somente esta area de ambientacao."),
]


def field(uid, spec):
    name, kind, default, minimum, maximum, doc = spec
    return dict(identifier=name, doc=doc, __type=kind, uid=uid, type=f"F_{kind}",
                isArray=False, canBeNull=False, arrayMinLength=None, arrayMaxLength=None,
                editorDisplayMode="Hidden", editorDisplayScale=1, editorDisplayPos="Above",
                editorLinkStyle="StraightArrow", editorDisplayColor=None,
                editorAlwaysShow=False, editorShowInWorld=False, editorCutLongValues=True,
                editorTextSuffix=None, editorTextPrefix=None, useForSmartColor=False,
                exportToToc=False, searchable=False, min=minimum, max=maximum, regex=None,
                acceptFileTypes=None, defaultOverride={"id": f"V_{kind}", "params": [default]},
                textLanguageMode=None, symmetricalRef=False, autoChainRef=True,
                allowOutOfLevelRef=True, allowedRefs="OnlySame", allowedRefsEntityUid=None,
                allowedRefTags=[], tilesetUid=None)


def register(project=ROOT / "monster_booster.ldtk"):
    if editor_busy():
        raise RuntimeError("Salve e feche o LDtk antes de registrar AmbientAreas. Mapa preservado.")
    original = project.read_bytes()
    before = json.loads(original.decode("utf-8-sig"))
    data = deepcopy(before)
    definitions = data["defs"]
    entity = next((e for e in definitions["entities"] if e["identifier"] == "AmbientArea"), None)
    if entity is None:
        uid = data["nextUid"]
        entity = deepcopy(next(e for e in definitions["entities"] if e["identifier"] == "DoorDash"))
        entity.update(identifier="AmbientArea", uid=uid, tags=["ambient"],
                      allowOutOfBounds=True, width=48, height=48, minWidth=16, minHeight=16,
                      resizableX=True, resizableY=True, pivotX=0, pivotY=0,
                      color="#CBB5E9", fillOpacity=0.12, lineOpacity=0.7, tileOpacity=0,
                      doc="Zona visual fora do piso. Aparicoes aleatorias, sem colisao/interacao. Sem sprites vinculados, fica invisivel no jogo.",
                      fieldDefs=[field(uid + i + 1, spec) for i, spec in enumerate(FIELDS)])
        definitions["entities"].append(entity)
        data["nextUid"] = uid + 1 + len(FIELDS)
    layer = next((l for l in definitions["layers"] if l["identifier"] == "AmbientAreas"), None)
    if layer is None:
        layer = deepcopy(next(l for l in definitions["layers"] if l["type"] == "Entities"))
        layer.update(identifier="AmbientAreas", uid=data["nextUid"], uiColor="#CBB5E9",
                     doc="Posicione AmbientArea fora do piso, inclusive fora do canvas. Sem arte temporaria.",
                     requiredTags=["ambient"], excludedTags=[], uiFilterTags=["ambient"],
                     pxOffsetX=0, pxOffsetY=0, parallaxFactorX=0, parallaxFactorY=0)
        definitions["layers"].insert(1, layer)
        data["nextUid"] += 1
    levels = list(data["levels"])
    for world in data["worlds"]:
        levels.extend(world["levels"])
    for level in levels:
        if level["layerInstances"] is None:
            raise ValueError("Mapa externo nao suportado. Nada foi modificado.")
        if any(l["layerDefUid"] == layer["uid"] for l in level["layerInstances"]):
            continue
        instance = deepcopy(next(l for l in level["layerInstances"] if l["__type"] == "Entities"))
        instance.update(__identifier="AmbientAreas", layerDefUid=layer["uid"],
                        iid=str(uuid.uuid4()), entityInstances=[], gridTiles=[], autoLayerTiles=[],
                        intGridCsv=[], pxOffsetX=0, pxOffsetY=0,
                        __pxTotalOffsetX=0, __pxTotalOffsetY=0, visible=True)
        level["layerInstances"].insert(1, instance)
    for leaf_layer in definitions["layers"]:
        if leaf_layer["identifier"] == "Leaves":
            leaf_layer["doc"] = "Foreground leaves cover all world props/actors; no physics, projected light or halo."
    # Verify preservation before any write, including multi-world projects.
    old_levels = list(before["levels"])
    for world in before["worlds"]:
        old_levels.extend(world["levels"])
    for old_level, new_level in zip(old_levels, levels):
        original_layers = {l["iid"]: l for l in old_level["layerInstances"]}
        assert all(original_layers[l["iid"]] == l for l in new_level["layerInstances"] if l["iid"] in original_layers)
    if data == before:
        return {"changed": False, "backup": None}
    backup_root = project.parent / "ldtk_backups"
    backup_root.mkdir(exist_ok=True)
    backup = backup_root / f"before_ambient_{datetime.now():%Y%m%d_%H%M%S_%f}_{hashlib.sha256(original).hexdigest()[:12]}.ldtk"
    if project.read_bytes() != original or editor_busy():
        raise RuntimeError("LDtk abriu ou o mapa mudou; nada foi sobrescrito.")
    backup.write_bytes(original)
    with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", dir=project.parent,
                                     prefix=".ambient_", suffix=".tmp", delete=False) as file:
        temporary = Path(file.name)
        json.dump(data, file, ensure_ascii=False, indent=2)
        file.write("\n")
    try:
        if project.read_bytes() != original or editor_busy():
            raise RuntimeError("Mapa mudou durante o registro; nada foi sobrescrito.")
        os.replace(temporary, project)
    finally:
        temporary.unlink(missing_ok=True)
    return {"changed": True, "backup": str(backup), "layer": layer["uid"], "entity": entity["uid"]}


if __name__ == "__main__":
    print(json.dumps(register(), ensure_ascii=False))
