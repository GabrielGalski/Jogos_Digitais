"""Register the spirit encounter and wire the authored Room_1 doors/warps without repainting."""
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

from configure_ldtk_water import ROOT, all_levels, editor_busy, serialize_preserving_layout
from configure_ldtk_warps import FIELDS as WARP_FIELDS, WARP_DOC
from clean_ldtk_model import LAYER_DOCS
from ldtk_field_values import set_value, preserve_editor_values

ENTRY_IID = "8a06b32c-c356-4a97-ab58-186083c1439c"
EXIT_IID = "db30fc10-bde0-11f1-8a17-959a121f1f55"
CLEAR = "spirit_horde_1_clear"
ENTRY = "spirit_horde_1_entry_open"
AREA_FIELDS = (
    ("ClearCondition", "String", CLEAR, "Condicao satisfeita somente pelas mortes em combate; libera porta e portal."),
    ("EntryCondition", "String", ENTRY, "True antes/depois da horda; false durante. Liga o DoorControl da entrada."),
    ("KillTarget", "Int", 40, "Mortes necessarias. Contato com jogador nao conta. Buffs fixos em 10/20/30."),
    ("Enabled", "Bool", True, "Ativa este encontro, uma vez por carregamento da sala."),
)


def fields(entity: dict) -> dict:
    return {f["__identifier"]: f["__value"] for f in entity["fieldInstances"]}


def convert_data(data: dict) -> bool:
    before = deepcopy(data)
    if any(l.get("layerInstances") is None for l in all_levels(data)):
        raise ValueError("Mapa externo nao suportado; mapa preservado.")
    definitions = data["defs"]
    template = deepcopy(next(f for e in definitions["entities"] for f in e["fieldDefs"] if f["__type"] == "String"))

    def allocate():
        uid = data["nextUid"]
        data["nextUid"] += 1
        return uid

    def add_fields(definition, specs):
        existing = {f["identifier"]: f["__type"] for f in definition["fieldDefs"]}
        for name, kind, default, doc in specs:
            if name in existing:
                if existing[name] != kind:
                    raise ValueError(f"Campo incompativel: {name}")
                continue
            field = deepcopy(template)
            field.update(identifier=name, uid=allocate(), __type=kind, type=f"F_{kind}", doc=doc,
                         defaultOverride={"id":f"V_{kind}", "params":[default]}, min=1 if kind == "Int" else None,
                         max=None, regex=None, editorAlwaysShow=name in ("ClearCondition", "KillTarget"),
                         editorDisplayMode="NameAndValue")
            definition["fieldDefs"].append(field)

    warp = next(e for e in definitions["entities"] if e["identifier"] == "Warp")
    warp["doc"] = WARP_DOC
    add_fields(warp, WARP_FIELDS)
    area = next((e for e in definitions["entities"] if e["identifier"] == "SpiritHordeArea"), None)
    if area is None:
        area = deepcopy(next(e for e in definitions["entities"] if e["identifier"] == "DoorControl"))
        area.update(identifier="SpiritHordeArea", uid=allocate(), width=160, height=160,
                    color="#A7C8DC", fillOpacity=0.12, fieldDefs=[],
                    doc="ENCONTRO / Spirits. Area de ativacao, sem desenho no jogo. Ao entrar fecha a entrada, gera spirits fora da camera e do piso; KillTarget mortes abrem saidas (padrao 40). Buffs 10/20/30. Sem HUD. Ajustes em spirit_horde_profile.gd.")
        definitions["entities"].append(area)
    add_fields(area, AREA_FIELDS)
    next(l for l in definitions["layers"] if l["identifier"] == "GameplayAreas")["doc"] = LAYER_DOCS["GameplayAreas"]
    by_name = {e["identifier"]: e for e in definitions["entities"]}

    def set_fields(instance, values):
        definition = by_name[instance["__identifier"]]
        current = {f["__identifier"]: f for f in instance["fieldInstances"]}
        for field in definition["fieldDefs"]:
            name = field["identifier"]
            if name not in current:
                current[name] = {"__identifier":name, "__type":field["__type"], "defUid":field["uid"],
                                 "__value":field["defaultOverride"]["params"][0], "realEditorValues":[], "__tile":None}
                instance["fieldInstances"].append(current[name])
            if name in values:
                set_value(current[name], values[name])
        preserve_editor_values(instance)

    for level in all_levels(data):
        for layer in level["layerInstances"]:
            for entity in layer["entityInstances"]:
                if entity["__identifier"] == "Warp":
                    set_fields(entity, {})
    room = next(l for l in all_levels(data) if l["identifier"] == "Room_1")
    utilities = next(l for l in room["layerInstances"] if l["__identifier"] == "GameplayAreas")
    instances = utilities["entityInstances"]
    if not any(e["__identifier"] == "SpiritHordeArea" for e in instances):
        entry = next(e for e in instances if e["iid"] == ENTRY_IID)
        exit_warp = next(e for e in instances if e["iid"] == EXIT_IID)
        set_fields(entry, {"WarpId":"entry", "IsEntrance":True})
        set_fields(exit_warp, {"WarpId":"restart", "TargetLevel":"Room_1", "TargetWarp":"entry",
                              "IsEntrance":False, "Interact":True, "RequiredCondition":CLEAR,
                              "RestartGame":True, "WhiteRing":True})
        gameplay = next(l for l in room["layerInstances"] if l["__identifier"] == "Gameplay")
        cells = {(i % gameplay["__cWid"], i // gameplay["__cWid"]) for i,v in enumerate(gameplay["intGridCsv"]) if v == 3}
        components = []
        while cells:
            component = {cells.pop()}
            pending = list(component)
            while pending:
                x,y = pending.pop()
                for neighbour in ((x-1,y),(x+1,y),(x,y-1),(x,y+1)):
                    if neighbour in cells:
                        cells.remove(neighbour); component.add(neighbour); pending.append(neighbour)
            components.append(component)
        if len(components) != 2:
            raise ValueError("Room_1 precisa das duas passagens autorais; pintura preservada.")
        rects = [(min(x for x,y in c)*16,min(y for x,y in c)*16,
                  (max(x for x,y in c)-min(x for x,y in c)+1)*16,
                  (max(y for x,y in c)-min(y for x,y in c)+1)*16) for c in components]
        rects.sort(key=lambda r: (r[0]+r[2]/2-entry["px"][0])**2+(r[1]+r[3]/2-entry["px"][1])**2)
        near, far = rects
        chamber = (near[0]+near[2], far[1], far[0]-near[0]-near[2], near[1]+near[3]-far[1])
        if min(chamber[2:]) <= 0:
            raise ValueError("Geometria mudou; area de ativacao precisa ser revista.")

        def create(identifier, rect, values):
            definition = by_name[identifier]
            x,y,w,h = rect
            # Reuse authored controls over these cells; duplicate requirements would deadlock a door.
            if identifier == "DoorControl":
                existing = next((e for e in instances if e["__identifier"] == identifier and
                                 e["px"] == [x,y] and e["width"] == w and e["height"] == h), None)
                if existing is not None:
                    set_fields(existing, values)
                    return
            entity = {"__identifier":identifier, "__grid":[x//16,y//16], "__pivot":[0,0],
                      "__tags":["gameplay"], "__tile":None, "__smartColor":definition["color"],
                      "__worldX":room.get("worldX",0)+x, "__worldY":room.get("worldY",0)+y,
                      "iid":str(uuid.uuid4()), "width":w, "height":h, "defUid":definition["uid"],
                      "px":[x,y], "fieldInstances":[]}
            set_fields(entity,values)
            instances.append(entity)
        create("SpiritHordeArea", chamber, {})
        create("DoorControl", near, {"DoorId":"spirit_entry", "ConditionId":ENTRY})
        create("DoorControl", far, {"DoorId":"spirit_exit", "ConditionId":CLEAR})
    # Verify every byte of semantic paint, sizes, offsets, layer visibility and old entity geometry.
    for old, new in zip(all_levels(before), all_levels(data), strict=True):
        for old_layer, new_layer in zip(old["layerInstances"], new["layerInstances"], strict=True):
            assert {k:v for k,v in old_layer.items() if k != "entityInstances"} == {k:v for k,v in new_layer.items() if k != "entityInstances"}
            by_iid = {e["iid"]:e for e in new_layer["entityInstances"]}
            for entity in old_layer["entityInstances"]:
                assert {k:v for k,v in entity.items() if k != "fieldInstances"} == {k:v for k,v in by_iid[entity["iid"]].items() if k != "fieldInstances"}
    return data != before


def register(project: Path = ROOT / "monster_booster.ldtk", dry_run: bool = False, kill_target: int | None = None) -> dict:
    original = project.read_bytes()
    before = json.loads(original.decode("utf-8-sig"))
    data = deepcopy(before)
    convert_data(data)
    if kill_target is not None:
        if kill_target < 1:
            raise ValueError("KillTarget precisa ser positivo.")
        area_definition = next(e for e in data["defs"]["entities"] if e["identifier"] == "SpiritHordeArea")
        area_definition["doc"] = "ENCONTRO / Spirits. Area de ativacao, sem desenho no jogo. Ao entrar fecha a entrada, gera spirits fora da camera e do piso; KillTarget mortes abrem saidas (padrao 40). Buffs 10/20/30. Sem HUD. Ajustes em spirit_horde_profile.gd."
        next(f for f in area_definition["fieldDefs"] if f["identifier"] == "KillTarget")["defaultOverride"]["params"] = [kill_target]
        room = next(l for l in all_levels(data) if l["identifier"] == "Room_1")
        for layer in room["layerInstances"]:
            for area in layer["entityInstances"]:
                if area["__identifier"] == "SpiritHordeArea":
                    set_value(next(f for f in area["fieldInstances"] if f["__identifier"] == "KillTarget"), kill_target)
    result = {"changed":data != before, "dry_run":dry_run, "backup":None}
    if not result["changed"] or dry_run:
        return result
    content = serialize_preserving_layout(original,before,data)
    if editor_busy() or project.read_bytes() != original:
        raise RuntimeError("LDtk aberto ou arquivo alterado. Nada sobrescrito; salve e feche o LDtk.")
    backup_folder = project.parent / "ldtk_backups"
    backup_folder.mkdir(exist_ok=True)
    backup = backup_folder / f"before_spirit_horde_{datetime.now():%Y%m%d_%H%M%S_%f}_{hashlib.sha256(original).hexdigest()[:12]}.ldtk"
    backup.write_bytes(original)
    with tempfile.NamedTemporaryFile(mode="wb",dir=project.parent,prefix=".spirit_horde_",suffix=".tmp",delete=False) as file:
        temporary = Path(file.name)
        file.write(content)
    try:
        if editor_busy() or project.read_bytes() != original:
            raise RuntimeError("LDtk abriu ou mapa mudou. Nada sobrescrito.")
        os.replace(temporary,project)
    finally:
        temporary.unlink(missing_ok=True)
    result["backup"] = str(backup)
    return result


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project",type=Path,default=ROOT / "monster_booster.ldtk")
    parser.add_argument("--dry-run",action="store_true")
    parser.add_argument("--kill-target",type=int,help="Altera explicitamente a meta das hordas em Room_1, mantendo toda a pintura.")
    args = parser.parse_args()
    print(json.dumps(register(args.project,args.dry_run,args.kill_target),ensure_ascii=False))
