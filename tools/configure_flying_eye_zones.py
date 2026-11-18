"""Add editable ambient zones to Room_2 without modifying existing authoring."""
from __future__ import annotations

import argparse
from copy import deepcopy
from datetime import datetime
import hashlib
import json
import math
import os
from pathlib import Path
import tempfile
import uuid

from configure_ldtk_water import all_levels, editor_busy, serialize_preserving_layout
from ldtk_field_values import set_value
from split_ldtk_room2 import composed_layers, validate

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "monster_booster.ldtk"
NAME = "FlyingEyeZone"
LAYER = "EnemyZones"
SPECS = [
    ("ZoneId", "String", "eye_zone", "Identidade estavel da zona de exploracao."),
    ("PackLimit", "Int", 2, "Maximo de bandos por ativacao desta zona: 0 a 2. Cada bando tem 2 a 5 olhos."),
    ("MinimumPackDistancePx", "Int", 320, "Separacao minima entre ancoras, incluindo bandos das duas zonas ativas."),
    ("AnchorRadiusPx", "Int", 264, "Distancia maxima do jogador a ancora antes de o bando desistir e retornar."),
    ("ActivationRangePx", "Int", 192, "Distancia do jogador a ancora para acordar o bando parado."),
    ("Enabled", "Bool", True, "Habilita a zona. Sem spawn/ataques ambientais durante hordas de altar."),
]


def convert(data: dict) -> dict:
    before = deepcopy(data)
    if any(e["identifier"] == NAME for e in data["defs"]["entities"]):
        return {"changed": False, "reason": "Existing zone authoring retained", **validate(data)}

    def allocate() -> int:
        result = data["nextUid"]
        data["nextUid"] += 1
        return result

    area = deepcopy(next(e for e in data["defs"]["entities"] if e["identifier"] == "PedestalArena"))
    area.update(identifier=NAME, uid=allocate(), tags=["ambient_enemy"], width=688, height=768,
                renderMode="Rectangle", keepAspectRatio=False, minWidth=128, minHeight=128,
                fillOpacity=0.035, lineOpacity=0.55, color="#F2384E", pivotX=0, pivotY=0, fieldDefs=[],
                doc="EXPLORACAO / Flying Eye. Duas zonas recentes ficam carregadas; entrar na terceira despawna a mais antiga. Ate 2 bandos por zona, 2 a 5 olhos cada, sempre gerados fora da camera. A ancora e definida pelo spawn; cerco e ataques alternados so ao se aproximar. Sem spawn durante evento de altar.")
    templates = {kind: next(f for e in data["defs"]["entities"] for f in e["fieldDefs"] if f["__type"] == kind) for kind in ["String", "Int", "Bool"]}
    for name, kind, default, doc in SPECS:
        field = deepcopy(templates[kind])
        field.update(identifier=name, uid=allocate(), __type=kind, type="F_" + kind, doc=doc,
                     defaultOverride={"id": "V_" + kind, "params": [default]},
                     min=0 if name=="PackLimit" else 64 if kind=="Int" else None,
                     max=2 if name=="PackLimit" else 1024 if kind=="Int" else None,
                     editorAlwaysShow=name=="ZoneId", editorDisplayMode="NameAndValue")
        area["fieldDefs"].append(field)
    data["defs"]["entities"].append(area)
    layer_def = deepcopy(next(d for d in data["defs"]["layers"] if d["identifier"] == "GameplayAreas"))
    layer_def.update(identifier=LAYER, uid=allocate(), requiredTags=["ambient_enemy"], uiFilterTags=["ambient_enemy"],
                     uiColor="#F2384E", doc="INIMIGOS / Zonas de exploracao ambiental e ancoras de bandos. Independente de PedestalArena e de sua contagem. Campos de utilidade em FlyingEyeZone.")
    data["defs"]["layers"].insert(1, layer_def)
    levels = all_levels(data)
    room = next(l for l in levels if l["identifier"] == "Room_2")
    layers = {l["__identifier"]: l for l in composed_layers(before, next(l for l in all_levels(before) if l["identifier"] == "Room_2"))}
    floor = {(t["px"][0]//16, t["px"][1]//16) for t in layers["Floor"]["gridTiles"]}
    grid = layers["Gameplay"]
    floor = {p for p in floor if grid["intGridCsv"][p[1]*grid["__cWid"]+p[0]] not in [1,2,3,6,7]}
    left, top = min(x for x,y in floor)*16, min(y for x,y in floor)*16
    right, bottom = (max(x for x,y in floor)+1)*16, (max(y for x,y in floor)+1)*16
    step_x = math.ceil((right-left)/5/16)*16
    step_y = math.ceil((bottom-top)/4/16)*16
    rectangles = []
    for level in levels:
        instance = deepcopy(next(l for l in level["layerInstances"] if l["__identifier"] == "GameplayAreas"))
        instance.update(__identifier=LAYER, layerDefUid=layer_def["uid"], entityInstances=[],
                        iid=str(uuid.uuid5(uuid.UUID(level["iid"]), "flying_eye_zones")), visible=level is room)
        level["layerInstances"].insert(1, instance)
        if level is not room: continue
        for row, y in enumerate(range(top,bottom,step_y)):
            for column, x in enumerate(range(left,right,step_x)):
                width, height = min(step_x,right-x), min(step_y,bottom-y)
                zone_id = f"eye_{column+1}_{row+1}"
                entity = {"__identifier":NAME, "__grid":[x//16,y//16], "__pivot":[0,0],
                          "__tags":["ambient_enemy"], "__tile":None, "__smartColor":"#F2384E",
                          "iid":str(uuid.uuid5(uuid.UUID(level["iid"]),zone_id)), "width":width,"height":height,
                          "defUid":area["uid"],"px":[x,y],"fieldInstances":[],
                          "__worldX":level["worldX"]+x,"__worldY":level["worldY"]+y}
                for definition in area["fieldDefs"]:
                    field = {"__identifier":definition["identifier"], "__type":definition["__type"],
                             "defUid":definition["uid"], "__tile":None}
                    set_value(field,zone_id if definition["identifier"]=="ZoneId" else definition["defaultOverride"]["params"][0])
                    entity["fieldInstances"].append(field)
                instance["entityInstances"].append(entity)
                rectangles.append({"id":zone_id,"rect":[x,y,width,height]})
    stripped = deepcopy(data)
    stripped["defs"]["entities"] = [d for d in stripped["defs"]["entities"] if d["identifier"]!=NAME]
    stripped["defs"]["layers"] = [d for d in stripped["defs"]["layers"] if d["identifier"]!=LAYER]
    for level in all_levels(stripped): level["layerInstances"] = [l for l in level["layerInstances"] if l["__identifier"]!=LAYER]
    stripped["nextUid"] = before["nextUid"]
    assert stripped==before,"Existing tiles, gameplay or water were modified."
    return {"changed":True,"zones":rectangles,"original_content_preserved":True,**validate(data)}


def main() -> None:
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dry-run",action="store_true")
    args=parser.parse_args()
    original=SOURCE.read_bytes()
    before=json.loads(original)
    data=deepcopy(before)
    report=convert(data)
    repeat=deepcopy(data);convert(repeat);assert repeat==data
    report.update(dry_run=args.dry_run,idempotent=True,source_sha256=hashlib.sha256(original).hexdigest())
    if report["changed"] and not args.dry_run:
        if editor_busy() or SOURCE.read_bytes()!=original:raise RuntimeError("LDtk aberto ou fonte alterada; mapa preservado.")
        backup=ROOT/"ldtk_backups"/f"before_flying_eye_zones_{datetime.now():%Y%m%d_%H%M%S}.ldtk"
        backup.write_bytes(original)
        content=serialize_preserving_layout(original,before,data)
        with tempfile.NamedTemporaryFile(dir=ROOT,suffix=".tmp",delete=False) as stream:
            pending=Path(stream.name);stream.write(content)
        try:
            if editor_busy() or SOURCE.read_bytes()!=original:raise RuntimeError("Fonte mudou; mapa preservado.")
            os.replace(pending,SOURCE)
        finally:pending.unlink(missing_ok=True)
        report["backup"]=str(backup)
    output=ROOT/"output/flying_eye";output.mkdir(parents=True,exist_ok=True)
    name="zones_preview.json" if args.dry_run else "zones_migration.json" if report["changed"] else "zones_check.json"
    (output/name).write_text(json.dumps(report,indent=2)+"\n",encoding="utf-8")
    print(json.dumps(report,ensure_ascii=True))


if __name__=="__main__":main()
