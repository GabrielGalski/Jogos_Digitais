"""Register the horde totem and preserve the authored encounter and terrain."""
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
from configure_ldtk_spirit_horde import convert_data as configure_horde, ENTRY_IID, EXIT_IID
from clean_ldtk_model import LAYER_DOCS
from ldtk_field_values import set_value, preserve_editor_values

SOURCE = "assets/tiles/structures/booster_opener/new/pedestal.png"
TOTEM_DOC = "ENCONTRO / Totem abridor. Aproxime-se e pressione E para iniciar a horda. O aviso acompanha o combate. Depois da vitoria o totem abre por proximidade."
ENCOUNTER = "spirit_horde_1"
AREA_FIELDS = (
    ("EncounterId", "String", ENCOUNTER, "ID local do encontro; igual ao EncounterId do HordePedestal."),
    ("ActivateOnEnter", "Bool", True, "False: somente o pedestal inicia a horda; True: modo legado por entrada na area."),
)
PEDESTAL_FIELDS = (
    ("EncounterId", "String", ENCOUNTER, "ID da SpiritHordeArea que esta plataforma inicia por E."),
    ("HeightPx", "Int", 0, "Legado. O totem acompanha o nivel do terreno."),
    ("RampWidth", "Int", 8, "Legado da antiga plataforma."),
    ("Enabled", "Bool", True, "Ativa este pedestal de horda."),
)


def _fields(entity: dict) -> dict:
    return {f["__identifier"]: f["__value"] for f in entity["fieldInstances"]}


def choose_center(room: dict, area: dict) -> list[int]:
    layers = room["layerInstances"]
    floor = next(l for l in layers if l["__identifier"] == "Floor")
    cells = {(t["px"][0] // 16, t["px"][1] // 16) for t in floor["gridTiles"] + floor["autoLayerTiles"]}
    borders = next((l for l in layers if l["__identifier"] == "Borders"), {})
    blocked = [tuple(t["px"]) for t in borders.get("gridTiles", []) + borders.get("autoLayerTiles", [])]
    rules = next(l for l in layers if l["__identifier"] == "Gameplay")
    grid = rules["intGridCsv"]
    width = rules["__cWid"]
    x0,y0 = area["px"]
    center = (x0 + area["width"] / 2, y0 + area["height"] / 2)
    candidates = []
    for y in range(y0 + 32, y0 + area["height"] - 31, 16):
        for x in range(x0 + 32, x0 + area["width"] - 31, 16):
            if not all((xx//16, yy//16) in cells for yy in range(y-40,y+41,8) for xx in range(x-40,x+41,8)):
                continue
            if any(x-40 <= bx < x+40 and y-40 <= by < y+40 for bx,by in blocked):
                continue
            if any(grid[(yy//16)*width+xx//16] in (1,2,3,6,7) for yy in range(y-32,y+32,16) for xx in range(x-32,x+32,16)):
                continue
            candidates.append(((x-center[0])**2 + (y-center[1])**2, [x,y]))
    if not candidates:
        raise ValueError("Nao ha espaco central seguro de 64x64 para o pedestal. Pintura preservada.")
    return min(candidates, key=lambda item:item[0])[1]


def repair_room_links(data: dict) -> None:
    """Repair exported-only legacy fields without moving any authored entity."""
    room = next(l for l in all_levels(data) if l["identifier"] == "Room_1")
    layer = next(l for l in room["layerInstances"] if l["__identifier"] == "GameplayAreas")
    instances = layer["entityInstances"]
    area = next(e for e in instances if e["__identifier"] == "SpiritHordeArea")
    config = _fields(area)
    definitions = {e["identifier"]:e for e in data["defs"]["entities"]}
    def assign(entity, values):
        known = {f["__identifier"]:f for f in entity["fieldInstances"]}
        for field in definitions[entity["__identifier"]]["fieldDefs"]:
            name = field["identifier"]
            if name not in known:
                known[name] = {"__identifier":name,"__type":field["__type"],"defUid":field["uid"],
                               "__value":field["defaultOverride"]["params"][0],"__tile":None,"realEditorValues":[]}
                entity["fieldInstances"].append(known[name])
            if name in values:
                set_value(known[name],values[name])
        preserve_editor_values(entity)
    entry = next(e for e in instances if e["iid"] == ENTRY_IID)
    exit_warp = next(e for e in instances if e["iid"] == EXIT_IID)
    assign(entry,{"WarpId":"entry","IsEntrance":True})
    target_scene = next((f["__value"] for f in exit_warp["fieldInstances"] if f["__identifier"] == "TargetScene"), "")
    assign(exit_warp,{"WarpId":"restart","TargetLevel":"" if target_scene else "Room_1","TargetWarp":"entry",
                      "TargetMap":"","IsEntrance":False,"Interact":True,"RequiredCondition":config["ClearCondition"],
                      "RestartGame":not bool(target_scene),"WhiteRing":True})
    gameplay = next(l for l in room["layerInstances"] if l["__identifier"] == "Gameplay")
    width = gameplay["__cWid"]
    cells = {(i%width,i//width) for i,v in enumerate(gameplay["intGridCsv"]) if v==3}
    groups = []
    while cells:
        group = [cells.pop()]
        cursor = 0
        while cursor<len(group):
            x,y = group[cursor];cursor += 1
            for neighbour in ((x-1,y),(x+1,y),(x,y-1),(x,y+1)):
                if neighbour in cells:
                    cells.remove(neighbour);group.append(neighbour)
        groups.append((min(x for x,y in group)*16,min(y for x,y in group)*16,
                       (max(x for x,y in group)-min(x for x,y in group)+1)*16,
                       (max(y for x,y in group)-min(y for x,y in group)+1)*16))
    if len(groups)!=2:
        raise ValueError("Reparo de Room_1 exige as duas passagens pintadas; mapa preservado.")
    groups.sort(key=lambda r:(r[0]-entry["px"][0])**2+(r[1]-entry["px"][1])**2)
    for rect,door_id,condition in zip(groups,("spirit_entry","spirit_exit"),(config["EntryCondition"],config["ClearCondition"]),strict=True):
        x,y,w,h = rect
        controls = [e for e in instances if e["__identifier"]=="DoorControl" and e["px"]==[x,y] and e["width"]==w and e["height"]==h]
        if not controls:
            definition = definitions["DoorControl"]
            control = {"__identifier":"DoorControl","__grid":[x//16,y//16],"__pivot":[0,0],"__tags":["gameplay"],
                       "__tile":None,"__smartColor":definition["color"],"__worldX":room.get("worldX",0)+x,"__worldY":room.get("worldY",0)+y,
                       "iid":str(uuid.uuid4()),"width":w,"height":h,"defUid":definition["uid"],"px":[x,y],"fieldInstances":[]}
            instances.append(control)
            controls.append(control)
        for control in controls:
            assign(control,{"DoorId":door_id,"ConditionId":condition})


def convert_data(data: dict, source_size: tuple[int,int] | None = None, repair_links: bool = False) -> bool:
    before = deepcopy(data)
    configure_horde(data)
    definitions = data["defs"]
    template = deepcopy(next(f for e in definitions["entities"] for f in e["fieldDefs"] if f["__type"] == "String"))
    if source_size is None:
        with Image.open(ROOT / SOURCE) as image:
            source_size = image.size
    if any(size <= 0 or size % 16 for size in source_size):
        raise ValueError("O atlas do totem deve usar celulas inteiras de 16 pixels.")
    def allocate():
        uid = data["nextUid"]
        data["nextUid"] += 1
        return uid
    def add_fields(definition, specs):
        existing = {f["identifier"]: f["__type"] for f in definition["fieldDefs"]}
        for name, kind, default, doc in specs:
            if name in existing:
                if existing[name] != kind:
                    raise ValueError(f"Tipo incompativel em {definition['identifier']}.{name}")
                continue
            field = deepcopy(template)
            field.update(identifier=name, uid=allocate(), __type=kind, type=f"F_{kind}", doc=doc,
                         defaultOverride={"id":f"V_{kind}","params":[default]}, min=0 if name == "HeightPx" else (1 if kind == "Int" else None),
                         max=None, regex=None, editorAlwaysShow=name=="EncounterId", editorDisplayMode="NameAndValue")
            definition["fieldDefs"].append(field)
    area_definition = next(e for e in definitions["entities"] if e["identifier"] == "SpiritHordeArea")
    add_fields(area_definition, AREA_FIELDS)
    area_definition["doc"] = "ENCONTRO / Spirits. Delimita a arena/spawn. ActivateOnEnter=false espera E no HordePedestal com mesmo EncounterId. KillTarget=40 libera portas. Sem HUD."
    tileset = next((t for t in definitions["tilesets"] if t["identifier"] == "Pedestal_16"), None)
    if tileset is None:
        tileset = deepcopy(next(t for t in definitions["tilesets"] if t["identifier"] == "Warp_16"))
        tileset.update(identifier="Pedestal_16",uid=allocate(),relPath=SOURCE,cachedPixelData=None,tags=[],enumTags=[],customData=[])
        definitions["tilesets"].append(tileset)
    width,height = source_size
    if tileset["relPath"] != SOURCE:
        tileset["cachedPixelData"] = None
    tileset.update(relPath=SOURCE, pxWid=width, pxHei=height, __cWid=width//16, __cHei=height//16,
                   savedSelections=[{"ids":list(range((width//16)*(height//16))),"mode":"Stamp"}])
    tile_rect = {"tilesetUid":tileset["uid"],"x":0,"y":0,"w":width,"h":height}
    pedestal = next((e for e in definitions["entities"] if e["identifier"] == "HordePedestal"), None)
    if pedestal is None:
        pedestal = deepcopy(next(e for e in definitions["entities"] if e["identifier"] == "Warp"))
        pedestal.update(identifier="HordePedestal",uid=allocate(),fieldDefs=[],
                        pivotX=0.5,pivotY=0.5,resizableX=False,resizableY=False,
                        tilesetId=tileset["uid"],tileRect=tile_rect,uiTileRect=tile_rect,
                        tileRenderMode="FitInside",color="#BAC9CD")
        definitions["entities"].append(pedestal)
    pedestal.update(width=80, height=40, tileRect=tile_rect, uiTileRect=tile_rect, doc=TOTEM_DOC)
    add_fields(pedestal, PEDESTAL_FIELDS)
    for field in pedestal["fieldDefs"]:
        if field["identifier"] == "HeightPx":
            field.update(min=0, defaultOverride={"id":"V_Int","params":[0]})
        if field["identifier"] in ("HeightPx", "RampWidth"):
            field["doc"] = next(doc for name, _, _, doc in PEDESTAL_FIELDS if name == field["identifier"])
    by_name = {e["identifier"]:e for e in definitions["entities"]}
    def set_fields(instance, values):
        present = {f["__identifier"]:f for f in instance["fieldInstances"]}
        for field in by_name[instance["__identifier"]]["fieldDefs"]:
            name = field["identifier"]
            if name not in present:
                present[name] = {"__identifier":name,"__type":field["__type"],"__value":field["defaultOverride"]["params"][0],
                                 "defUid":field["uid"],"realEditorValues":[],"__tile":None}
                instance["fieldInstances"].append(present[name])
            if name in values:
                set_value(present[name], values[name])
        preserve_editor_values(instance)
    for level in all_levels(data):
        for layer in level["layerInstances"]:
            for entity in layer["entityInstances"]:
                if entity["__identifier"] == "SpiritHordeArea":
                    set_fields(entity,{})
                elif entity["__identifier"] == "HordePedestal":
                    entity.update(width=pedestal["width"], height=pedestal["height"], __tile=tile_rect)
                    height_field = next((f for f in entity["fieldInstances"] if f["__identifier"] == "HeightPx"), None)
                    if height_field is not None and height_field["__value"] != 0:
                        set_value(height_field, 0)
    room = next(l for l in all_levels(data) if l["identifier"] == "Room_1")
    utilities = next(l for l in room["layerInstances"] if l["__identifier"] == "GameplayAreas")
    area = next(e for e in utilities["entityInstances"] if e["__identifier"] == "SpiritHordeArea")
    set_fields(area,{"EncounterId":ENCOUNTER,"ActivateOnEnter":False})
    if not any(e["__identifier"] == "HordePedestal" and _fields(e).get("EncounterId") == ENCOUNTER for e in utilities["entityInstances"]):
        x,y = choose_center(room,area)
        entity = {"__identifier":"HordePedestal","__grid":[x//16,y//16],"__pivot":[0.5,0.5],"__tags":["gameplay"],
                  "__tile":tile_rect,"__smartColor":"#BAC9CD","__worldX":room.get("worldX",0)+x,"__worldY":room.get("worldY",0)+y,
                  "iid":str(uuid.uuid4()),"width":pedestal["width"],"height":pedestal["height"],"defUid":pedestal["uid"],"px":[x,y],"fieldInstances":[]}
        set_fields(entity,{})
        utilities["entityInstances"].append(entity)
    next(l for l in definitions["layers"] if l["identifier"] == "GameplayAreas")["doc"] = LAYER_DOCS["GameplayAreas"]
    if repair_links:
        repair_room_links(data)
    for old,new in zip(all_levels(before),all_levels(data),strict=True):
        for old_layer,new_layer in zip(old["layerInstances"],new["layerInstances"],strict=True):
            assert {k:v for k,v in old_layer.items() if k!="entityInstances"} == {k:v for k,v in new_layer.items() if k!="entityInstances"}
            by_iid = {e["iid"]:e for e in new_layer["entityInstances"]}
            for entity in old_layer["entityInstances"]:
                updated_keys = {"fieldInstances"}
                if entity["__identifier"] == "HordePedestal":
                    updated_keys.update(("width", "height", "__tile"))
                assert {k:v for k,v in entity.items() if k not in updated_keys} == {k:v for k,v in by_iid[entity["iid"]].items() if k not in updated_keys}
    return data != before


def register(project: Path = ROOT / "monster_booster.ldtk", dry_run: bool = False, repair_links: bool = False) -> dict:
    original = project.read_bytes()
    before = json.loads(original.decode("utf-8-sig"))
    data = deepcopy(before)
    result = {"changed":convert_data(data,repair_links=repair_links),"dry_run":dry_run,"backup":None}
    if not result["changed"] or dry_run:
        return result
    content = serialize_preserving_layout(original,before,data)
    if editor_busy() or project.read_bytes() != original:
        raise RuntimeError("LDtk aberto ou mapa mudou. Salve e feche o editor; nada foi sobrescrito.")
    backup_root = project.parent / "ldtk_backups"
    backup_root.mkdir(exist_ok=True)
    backup = backup_root / f"before_pedestal_{datetime.now():%Y%m%d_%H%M%S_%f}_{hashlib.sha256(original).hexdigest()[:12]}.ldtk"
    backup.write_bytes(original)
    with tempfile.NamedTemporaryFile(mode="wb",dir=project.parent,prefix=".pedestal_",suffix=".tmp",delete=False) as file:
        temporary = Path(file.name)
        file.write(content)
    try:
        if editor_busy() or project.read_bytes() != original:
            raise RuntimeError("LDtk abriu ou arquivo foi alterado; mapa preservado.")
        os.replace(temporary,project)
    finally:
        temporary.unlink(missing_ok=True)
    result["backup"] = str(backup)
    return result


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project",type=Path,default=ROOT/"monster_booster.ldtk")
    parser.add_argument("--dry-run",action="store_true")
    parser.add_argument("--repair-links",action="store_true",help="Repara valores de porta/warp revertidos pelo editor, sem mover entidades.")
    args = parser.parse_args()
    print(json.dumps(register(args.project,args.dry_run,args.repair_links),ensure_ascii=False))
