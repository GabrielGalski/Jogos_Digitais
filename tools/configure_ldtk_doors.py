"""Register MonsterShift-style DoorBlock and condition utilities, preserving map paint."""
from __future__ import annotations
import argparse
from copy import deepcopy
from datetime import datetime
import hashlib
import json
import os
from pathlib import Path
import tempfile

from configure_ldtk_water import ROOT, all_levels, editor_busy, serialize_preserving_layout
from clean_ldtk_model import LAYER_DOCS
from ldtk_field_values import preserve_editor_values

TRIGGER_DOC = "FLUXO DA SALA. Ao entrar, define ConditionId com ConditionValue; Once controla uso unico. ConditionId vazio nao faz nada. Pode liberar DoorControl com a mesma condicao."
DOOR_DOC = "COLISAO / CONDICAO. Delimite celulas DoorBlock pintadas em Gameplay. DoorId identifica esta passagem; ConditionId libera a porta quando verdadeira. Nao cria colisao sem celulas DoorBlock. Controles sobrepostos exigem todas as condicoes."
FIELDS = {
    "DoorControl": (("DoorId","String","exit","ID da passagem; permite comandos por nome."),
                    ("ConditionId","String","room_clear","Condicao que abre esta passagem. Vazio: controle manual."),
                    ("Enabled","Bool",True,"Ativa este controle de porta.")),
    "GameplayTrigger": (("ConditionId","String","","Condicao a alterar ao jogador entrar. Vazio: marcador sem acao."),
                        ("ConditionValue","Bool",True,"True satisfaz a condicao e libera suas portas; False volta a bloquear."),
                        ("Once","Bool",True,"Ativar apenas uma vez por carregamento da sala."),
                        ("Enabled","Bool",True,"Ativa este gatilho.")),
}


def assert_preserved(before: dict, after: dict) -> None:
    stripped = deepcopy(after)
    old_ids = {x["uid"] for x in before["defs"]["entities"]}
    added = [x for x in stripped["defs"]["entities"] if x["uid"] not in old_ids]
    if any(x["identifier"] != "DoorControl" for x in added):
        raise ValueError("Somente DoorControl pode ser acrescentado.")
    stripped["defs"]["entities"] = [x for x in stripped["defs"]["entities"] if x["uid"] in old_ids]
    old_entities = {x["uid"]: x for x in before["defs"]["entities"]}
    for entity in stripped["defs"]["entities"]:
        if entity["identifier"] not in FIELDS:
            continue
        old = old_entities[entity["uid"]]
        old_fields = {x["uid"] for x in old["fieldDefs"]}
        allowed = {x[0] for x in FIELDS[entity["identifier"]]}
        if any(x["uid"] not in old_fields and x["identifier"] not in allowed for x in entity["fieldDefs"]):
            raise ValueError("Campo nao autorizado acrescentado.")
        entity["fieldDefs"] = [x for x in entity["fieldDefs"] if x["uid"] in old_fields]
        entity["doc"] = old["doc"]
    old_layers = {x["uid"]: x for x in before["defs"]["layers"]}
    for layer in stripped["defs"]["layers"]:
        if layer["identifier"] in ("Gameplay","GameplayAreas"):
            old = old_layers[layer["uid"]]
            layer["doc"] = old["doc"]
            if layer["identifier"] == "Gameplay":
                for value in layer["intGridValues"]:
                    if value["value"] == 3:
                        previous = next(x for x in old["intGridValues"] if x["value"] == 3)
                        value["identifier"], value["color"] = previous["identifier"], previous["color"]
    for old_level, level in zip(all_levels(before),all_levels(stripped),strict=True):
        for old_layer, layer in zip(old_level["layerInstances"],level["layerInstances"],strict=True):
            old_entities = {x["iid"]: x for x in old_layer["entityInstances"]}
            for entity in layer["entityInstances"]:
                if entity["__identifier"] != "GameplayTrigger":
                    continue
                old = old_entities[entity["iid"]]
                old_fields = {x["defUid"] for x in old["fieldInstances"]}
                if any(x["defUid"] not in old_fields and x["__identifier"] not in {f[0] for f in FIELDS["GameplayTrigger"]} for x in entity["fieldInstances"]):
                    raise ValueError("Campo de instancia nao autorizado.")
                entity["fieldInstances"] = [x for x in entity["fieldInstances"] if x["defUid"] in old_fields]
                old_raw = {x["defUid"]:x["realEditorValues"] for x in old["fieldInstances"]}
                for field in entity["fieldInstances"]:
                    field["realEditorValues"] = deepcopy(old_raw[field["defUid"]])
    stripped["nextUid"] = before["nextUid"]
    if stripped != before:
        raise ValueError("Conteudo autoral alterado. Mapa preservado.")


def convert_data(data: dict) -> bool:
    before = deepcopy(data)
    if any(x.get("layerInstances") is None for x in all_levels(data)):
        raise ValueError("Niveis externos nao suportados; mapa preservado.")
    definitions = data["defs"]
    def allocate():
        value = data["nextUid"]
        data["nextUid"] += 1
        return value
    for layer in definitions["layers"]:
        if layer["identifier"] in ("Gameplay","GameplayAreas"):
            layer["doc"] = LAYER_DOCS[layer["identifier"]]
        if layer["identifier"] == "Gameplay":
            block = next(x for x in layer["intGridValues"] if x["value"] == 3)
            if block["identifier"] not in ("EncounterBlock","DoorBlock"):
                raise ValueError("Valor 3 desconhecido; mapa preservado.")
            block.update(identifier="DoorBlock",color="#F39C12")
    door = next((x for x in definitions["entities"] if x["identifier"] == "DoorControl"),None)
    if door is None:
        door = deepcopy(next(x for x in definitions["entities"] if x["identifier"] == "DashGapArea"))
        door.update(identifier="DoorControl",uid=allocate(),width=32,height=48,minWidth=16,minHeight=16,
                    resizableX=True,resizableY=True,pivotX=0,pivotY=0,renderMode="Rectangle",
                    color="#E1A845",fillOpacity=0.15,lineOpacity=0.9,tags=["gameplay"],fieldDefs=[])
        definitions["entities"].append(door)
    template = next(f for e in definitions["entities"] for f in e["fieldDefs"] if f["__type"] == "String")
    for identifier, specs in FIELDS.items():
        entity = next(x for x in definitions["entities"] if x["identifier"] == identifier)
        entity["doc"] = DOOR_DOC if identifier == "DoorControl" else TRIGGER_DOC
        actual = {x["identifier"]:x["__type"] for x in entity["fieldDefs"]}
        expected = {name:kind for name,kind,_,_ in specs}
        if any(name not in expected or expected[name] != kind for name,kind in actual.items()):
            raise ValueError(f"Campos incompativeis em {identifier}.")
        for name,kind,default,doc in specs:
            if name in actual:
                continue
            field = deepcopy(template)
            field.update(identifier=name,uid=allocate(),__type=kind,type=f"F_{kind}",doc=doc,
                         defaultOverride={"id":f"V_{kind}","params":[default]},min=None,max=None,regex=None,
                         editorAlwaysShow=name in ("DoorId","ConditionId"))
            entity["fieldDefs"].append(field)
    trigger = next(x for x in definitions["entities"] if x["identifier"] == "GameplayTrigger")
    for level in all_levels(data):
        for layer in level["layerInstances"]:
            for entity in layer["entityInstances"]:
                if entity["__identifier"] != "GameplayTrigger":
                    continue
                existing = {x["__identifier"] for x in entity["fieldInstances"]}
                for field in trigger["fieldDefs"]:
                    if field["identifier"] not in existing:
                        entity["fieldInstances"].append({"__identifier":field["identifier"],"__type":field["__type"],
                            "defUid":field["uid"],"__value":field["defaultOverride"]["params"][0],"realEditorValues":[]})
                preserve_editor_values(entity)
    assert_preserved(before,data)
    return data != before


def register(project: Path = ROOT/"monster_booster.ldtk", dry_run: bool = False) -> dict:
    original = project.read_bytes()
    before = json.loads(original.decode("utf-8-sig"))
    data = deepcopy(before)
    result = {"changed":convert_data(data),"dry_run":dry_run,"backup":None}
    if not result["changed"] or dry_run:
        return result
    if editor_busy() or project.read_bytes() != original:
        raise RuntimeError("Salve e feche o LDtk. Mapa preservado.")
    content = serialize_preserving_layout(original,before,data)
    backup_folder = project.parent/"ldtk_backups"
    backup_folder.mkdir(exist_ok=True)
    backup = backup_folder/f"before_door_blocks_{datetime.now():%Y%m%d_%H%M%S_%f}_{hashlib.sha256(original).hexdigest()[:12]}.ldtk"
    backup.write_bytes(original)
    with tempfile.NamedTemporaryFile(mode="wb",dir=project.parent,prefix=".door_blocks_",suffix=".tmp",delete=False) as file:
        temporary = Path(file.name)
        file.write(content)
    try:
        if editor_busy() or project.read_bytes() != original:
            raise RuntimeError("LDtk abriu ou mapa mudou; nada foi sobrescrito.")
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
