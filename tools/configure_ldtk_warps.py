"""Register the native warp and one entrance at each authored Start, without repainting maps."""
from __future__ import annotations
import argparse
from copy import deepcopy
from datetime import datetime
import hashlib
import json
import os
from pathlib import Path
import tempfile
import uuid
from PIL import Image

from configure_ldtk_water import ROOT, all_levels, editor_busy, serialize_preserving_layout
from ldtk_field_values import preserve_editor_values

SOURCE = "assets/tiles/floor/warp.png"
WARP_DOC = "TRAVESSIA / Warp. PNG autoral integral, plano e pivo central. IsEntrance define inicio; TargetLevel/TargetWarp ligam salas. Interact exige E; RequiredCondition libera uso; RestartGame recria a cena inicial; WhiteRing desenha circulacao branca somente apos liberar."
FIELDS = (
    ("WarpId", "String", "entry", "ID unico nesta sala. A chegada procura este ID."),
    ("TargetLevel", "String", "", "Nome exato da sala de destino. Vazio: plataforma somente de chegada."),
    ("TargetWarp", "String", "entry", "WarpId da plataforma de destino. Chegar nao dispara outro teleporte ate sair dela."),
    ("TargetMap", "String", "", "Arquivo .ldtk relativo ao mapa atual, ou res://. Vazio: mesmo arquivo."),
    ("IsEntrance", "Bool", False, "Ponto de chegada na inicializacao desta sala; usar somente um por sala."),
    ("Enabled", "Bool", True, "Ativa a plataforma e sua ligacao."),
    ("Interact", "Bool", False, "Exige pressionar E sobre a plataforma; sem aviso na tela."),
    ("RequiredCondition", "String", "", "Condicao local necessaria para ativar este portal."),
    ("RestartGame", "Bool", False, "Recria a cena inicial apos feixe e fade; restaura toda a fase e jogador."),
    ("WhiteRing", "Bool", False, "Circulacao branca em pixel art, visivel apenas com RequiredCondition satisfeita."),
    ("TargetScene", "String", "", "Cena Godot res://...tscn. Se preenchida, tem prioridade sobre TargetLevel e RestartGame; vazio mantem a rota LDtk."),
)


def assert_preserved(before: dict, after: dict) -> None:
    before = deepcopy(before)
    stripped = deepcopy(after)
    for key in ("entities", "tilesets"):
        ids = {x["uid"] for x in before["defs"][key]}
        stripped["defs"][key] = [x for x in stripped["defs"][key] if x["uid"] in ids]
        old_by_uid = {x["uid"]: x for x in before["defs"][key]}
        for item in stripped["defs"][key]:
            old_item = old_by_uid[item["uid"]]
            if item["identifier"] == "Warp_16":
                for field in ("pxWid", "pxHei", "__cWid", "__cHei", "savedSelections", "cachedPixelData"):
                    item[field] = deepcopy(old_item[field])
            elif item["identifier"] == "Warp":
                for field in ("width", "height", "pivotX", "pivotY", "tileRect", "uiTileRect", "doc"):
                    item[field] = deepcopy(old_item[field])
                old_fields = {x["uid"] for x in old_item["fieldDefs"] if x["identifier"] != "HeightPx"}
                additions = {x["uid"] for x in item["fieldDefs"] if x["identifier"] in {f[0] for f in FIELDS[6:]}}
                if old_fields != {x["uid"] for x in item["fieldDefs"]} - (additions - old_fields):
                    raise ValueError("Somente o antigo campo de altura pode ser removido do Warp.")
                item["fieldDefs"] = [x for x in item["fieldDefs"] if x["uid"] in old_fields]
                old_item["fieldDefs"] = [x for x in old_item["fieldDefs"] if x["identifier"] != "HeightPx"]
    for old, new in zip(all_levels(before), all_levels(stripped), strict=True):
        for old_layer, new_layer in zip(old["layerInstances"], new["layerInstances"], strict=True):
            ids = {x["iid"] for x in old_layer["entityInstances"]}
            added = [x for x in new_layer["entityInstances"] if x["iid"] not in ids]
            if any(x["__identifier"] != "Warp" for x in added):
                raise ValueError("Somente novas instancias Warp sao permitidas.")
            new_layer["entityInstances"] = [x for x in new_layer["entityInstances"] if x["iid"] in ids]
            old_by_iid = {x["iid"]: x for x in old_layer["entityInstances"]}
            for instance in new_layer["entityInstances"]:
                if instance["__identifier"] != "Warp":
                    continue
                old_instance = old_by_iid[instance["iid"]]
                for field in ("width", "height", "__pivot", "__tile"):
                    instance[field] = deepcopy(old_instance[field])
                old_fields = {x["__identifier"] for x in old_instance["fieldInstances"] if x["__identifier"] != "HeightPx"}
                additions = {f[0] for f in FIELDS[6:]} - old_fields
                if old_fields != {x["__identifier"] for x in instance["fieldInstances"]} - additions:
                    raise ValueError("Somente a antiga altura pode ser removida do Warp.")
                instance["fieldInstances"] = [x for x in instance["fieldInstances"] if x["__identifier"] in old_fields]
                old_instance["fieldInstances"] = [x for x in old_instance["fieldInstances"] if x["__identifier"] != "HeightPx"]
                # Canonical editor data is allowed to change; exported gameplay values are not.
                old_raw = {x["__identifier"]:x["realEditorValues"] for x in old_instance["fieldInstances"]}
                for field in instance["fieldInstances"]:
                    field["realEditorValues"] = deepcopy(old_raw[field["__identifier"]])
    stripped["nextUid"] = before["nextUid"]
    if stripped != before:
        raise ValueError("Conteudo autoral alterado. Mapa preservado.")


def convert_data(data: dict) -> bool:
    before = deepcopy(data)
    if any(x.get("layerInstances") is None for x in all_levels(data)):
        raise ValueError("Niveis externos nao suportados por esta migracao.")
    defs = data["defs"]
    with Image.open(ROOT/SOURCE) as image:
        width, height = image.size
    if width % 16 or height % 16:
        raise ValueError("O canvas do Warp precisa ser multiplo de 16px; PNG e mapa preservados.")
    columns, rows = width//16, height//16
    def allocate():
        uid = data["nextUid"]
        data["nextUid"] += 1
        return uid
    tileset = next((x for x in defs["tilesets"] if x["identifier"] == "Warp_16"), None)
    if tileset is None:
        tileset = deepcopy(defs["tilesets"][0])
        tileset.update(identifier="Warp_16", uid=allocate(), relPath=SOURCE, pxWid=width, pxHei=height,
                       __cWid=columns, __cHei=rows, tileGridSize=16, padding=0, spacing=0, embedAtlas=None,
                       tags=[], tagsSourceEnumUid=None, enumTags=[], customData=[], cachedPixelData=None,
                       savedSelections=[{"ids":list(range(columns*rows)), "mode":"Stamp"}])
        defs["tilesets"].append(tileset)
    if tileset["relPath"] != SOURCE or tileset["tileGridSize"] != 16:
        raise ValueError("Warp_16 existente incompativel.")
    old_stamp = {"ids":list(range(tileset["__cWid"]*tileset["__cHei"])), "mode":"Stamp"}
    tileset["savedSelections"] = [
        {"ids":list(range(columns*rows)), "mode":"Stamp"} if stamp == old_stamp else stamp
        for stamp in tileset["savedSelections"]
    ]
    tileset.update(pxWid=width, pxHei=height, __cWid=columns, __cHei=rows, cachedPixelData=None)
    tile_rect = {"tilesetUid":tileset["uid"], "x":0, "y":0, "w":width, "h":height}
    entity = next((x for x in defs["entities"] if x["identifier"] == "Warp"), None)
    if entity is None:
        entity = deepcopy(next(x for x in defs["entities"] if x["identifier"] == "GameplayTrigger"))
        entity.update(identifier="Warp", uid=allocate(), width=width, height=height, tags=["gameplay"],
                      renderMode="Tile", tileRenderMode="FitInside", tilesetId=tileset["uid"],
                      tileRect=tile_rect, uiTileRect=tile_rect, color="#E1A845", tileOpacity=1,
                      fillOpacity=0, lineOpacity=0.6, allowOutOfBounds=False,
                      doc=WARP_DOC, fieldDefs=[])
        defs["entities"].append(entity)
    entity["fieldDefs"] = [x for x in entity["fieldDefs"] if x["identifier"] != "HeightPx"]
    actual = {x["identifier"]:x["__type"] for x in entity["fieldDefs"]}
    expected = {name:kind for name,kind,_,_ in FIELDS}
    if any(name not in expected or expected[name] != kind for name,kind in actual.items()):
        raise ValueError("Warp existente tem campos incompativeis.")
    entity.update(width=width, height=height, pivotX=0.5, pivotY=0.5,
                  tileRect=tile_rect, uiTileRect=tile_rect, doc=WARP_DOC)
    template = next(f for e in defs["entities"] for f in e["fieldDefs"] if f["__type"] == "String")
    for name, kind, default, doc in FIELDS:
        if name not in actual:
            field = deepcopy(template)
            field.update(identifier=name, uid=allocate(), __type=kind, type=f"F_{kind}", doc=doc,
                         defaultOverride={"id":f"V_{kind}", "params":[default]}, min=None, max=None,
                         regex=None, editorDisplayMode="NameAndValue", editorAlwaysShow=False)
            entity["fieldDefs"].append(field)
    for level in all_levels(data):
        existing = [e for l in level["layerInstances"] for e in l["entityInstances"] if e["__identifier"] == "Warp"]
        for instance in existing:
            instance.update(width=width,height=height,__pivot=[0.5,0.5],__tile=tile_rect)
            instance["fieldInstances"] = [x for x in instance["fieldInstances"] if x["__identifier"] != "HeightPx"]
            present = {x["__identifier"] for x in instance["fieldInstances"]}
            for field in entity["fieldDefs"]:
                if field["identifier"] not in present:
                    instance["fieldInstances"].append({"__identifier":field["identifier"],"__type":field["__type"],
                        "defUid":field["uid"],"__value":field["defaultOverride"]["params"][0],"realEditorValues":[]})
            preserve_editor_values(instance)
        if existing:
            continue
        points = []
        for layer in level["layerInstances"]:
            if layer["__identifier"] == "Gameplay":
                grid, layer_columns = layer["__gridSize"], layer["__cWid"]
                points = [(i % layer_columns * grid + grid/2 + layer["__pxTotalOffsetX"],
                           i // layer_columns * grid + grid/2 + layer["__pxTotalOffsetY"])
                          for i, value in enumerate(layer["intGridCsv"]) if value == 4]
        if not points:
            continue
        target = next(x for x in level["layerInstances"] if x["__identifier"] == "GameplayAreas")
        px = [round(sum(x for x,y in points)/len(points))-target["__pxTotalOffsetX"],
              round(sum(y for x,y in points)/len(points))+10-target["__pxTotalOffsetY"]]
        fields = [{"__identifier":f["identifier"], "__type":f["__type"], "defUid":f["uid"],
                   "__value":True if f["identifier"] == "IsEntrance" else f["defaultOverride"]["params"][0],
                   "realEditorValues":[]} for f in entity["fieldDefs"]]
        target["entityInstances"].append({"__identifier":"Warp", "__grid":[p//target["__gridSize"] for p in px],
            "__pivot":[0.5,0.5], "__tags":["gameplay"], "__tile":tile_rect,
            "__smartColor":"#E1A845", "iid":str(uuid.uuid4()), "width":width, "height":height,
            "defUid":entity["uid"], "px":px, "fieldInstances":fields,
            "__worldX":level.get("worldX",0)+px[0], "__worldY":level.get("worldY",0)+px[1]})
        preserve_editor_values(target["entityInstances"][-1])
    assert_preserved(before,data)
    return data != before


def register(project: Path = ROOT/"monster_booster.ldtk", dry_run: bool = False) -> dict:
    original = project.read_bytes()
    before = json.loads(original.decode("utf-8-sig"))
    after = deepcopy(before)
    result = {"changed":convert_data(after), "dry_run":dry_run, "backup":None}
    if not result["changed"] or dry_run:
        return result
    if editor_busy() or project.read_bytes() != original:
        raise RuntimeError("Salve e feche o LDtk. Mapa preservado.")
    content = serialize_preserving_layout(original,before,after)
    folder = project.parent/"ldtk_backups"
    folder.mkdir(exist_ok=True)
    backup = folder/f"before_warps_{datetime.now():%Y%m%d_%H%M%S_%f}_{hashlib.sha256(original).hexdigest()[:12]}.ldtk"
    backup.write_bytes(original)
    with tempfile.NamedTemporaryFile(mode="wb",dir=project.parent,prefix=".warps_",suffix=".tmp",delete=False) as file:
        temporary = Path(file.name)
        file.write(content)
    try:
        if editor_busy() or project.read_bytes() != original:
            raise RuntimeError("LDtk abriu ou mapa mudou. Nada foi sobrescrito.")
        os.replace(temporary,project)
    finally:
        temporary.unlink(missing_ok=True)
    result["backup"] = str(backup)
    return result


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project",type=Path,default=ROOT/"monster_booster.ldtk")
    parser.add_argument("--dry-run",action="store_true")
    args = parser.parse_args()
    print(json.dumps(register(args.project,args.dry_run),ensure_ascii=False))
