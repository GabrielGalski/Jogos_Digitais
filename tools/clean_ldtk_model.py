"""Clean the LDtk authoring model while preserving surviving paint and utilities."""
from __future__ import annotations

import argparse
from copy import deepcopy
from datetime import datetime
import hashlib
import json
import os
from pathlib import Path
import tempfile

from configure_ldtk_water import ROOT, all_levels, editor_busy

REMOVED_ENTITIES = {"NoxStart", "Tin", "MinotaurSpawn", "DoorLink"}
REMOVED_TILESETS = {104, 504, 505, 506, 106, 107, 108, 109, 507, 508}
OBJECTS = {"ObjectsSquare": ("ObjectsBackSquare", "ObjectsFrontSquare"),
           "ObjectsRound": ("ObjectsBackRound", "ObjectsFrontRound"),
           "ObjectsStair": ("ObjectsBackStair", "ObjectsFrontStair")}
ORDER = ["Gameplay", "GameplayAreas", "WaterAreas", "AmbientAreas", "Leaves",
         "ObjectsSquare", "ObjectsRound", "ObjectsStair", "WallsFront", "WallsSides",
         "WallsBack", "Borders", "WaterBanks", "Floor", "PlatformUnderside"]
LAYER_DOCS = {
    "Gameplay": "REGRAS, grade 16px. Colisao: MapLimit delimita o mapa; Solid bloqueia passagem; DoorBlock (3) inicia fechado e abre por condicao ou comando. DoorControl vincula as celulas a uma ConditionId; GameplayTrigger ativa a condicao. Travessia: DashGap exige dash e retorna ao Start ao cair. FluxoDaSala: Start define entrada/respawn; End emite fim da sala. Perigos: Hazard reserva uma zona perigosa, atualmente solida e sem dano automatico.",
    "GameplayAreas": "AREAS DE GAMEPLAY. HordePedestal (64x64) inicia a horda por E sobre a plataforma elevada; vincule EncounterId a SpiritHordeArea, que delimita a arena sem ativacao automatica quando ActivateOnEnter=false. DoorControl vincula DoorBlock a uma ConditionId. GameplayTrigger altera condicoes. DashGapArea define vao; Warp liga salas ou reinicia por E. Personagens nao sao colocados por esta camada.",
    "WaterAreas": "VISUAL / AGUA. Coloque WaterArea com tamanho, Preset e MaskId; sem fisica ou navegacao. A Godot desenha em Z=-18, acima do Floor. Mascara Pond exige 112x96; Rectangle aceita tamanho livre.",
    "AmbientAreas": "VISUAL / AMBIENTACAO. Coloque AmbientArea para aparicoes animadas atras do mapa (Z=-90). Configure pasta/ID, espera e chance; sem arte vinculada nada aparece, sem colisao.",
    "Leaves": "VISUAL / PRIMEIRO PLANO. Folhas em Z=1000, sobre atores, projeteis e objetos; abaixo da HUD. Sem colisao ou luz propria.",
    "ObjectsSquare": "OBJETOS / mesma profundidade dos atores (Z=2, ordenacao pela base Y). Colunas quadradas. Cortes 16px. Camadas antigas Front/Back reunidas; colisao da base calculada na Godot.",
    "ObjectsRound": "OBJETOS / mesma profundidade dos atores (Z=2, ordenacao pela base Y). Colunas redondas. Cortes 16px. Camadas antigas Front/Back reunidas; colisao da base calculada na Godot.",
    "ObjectsStair": "OBJETOS / mesma profundidade dos atores (Z=2, ordenacao pela base Y). Escadas e acabamentos em cortes 4px. Camadas antigas Front/Back reunidas.",
    "WallsFront": "PAREDES / frente, cortes 8px. Fragmentos compartilham a profundidade de sua base (Z=2); a Godot calcula a colisao visivel. Nao pintar regras de gameplay nesta camada.",
    "WallsSides": "PAREDES / laterais, cortes 8px. Mesma faixa de profundidade dos objetos (Z=2), ordenada pela base; conserva os recortes e a colisao da geometria.",
    "WallsBack": "PAREDES / fundo, cortes 8px. Faixa Z=1, abaixo de atores/objetos (Z=2), com profundidade pela base. Evita que o acabamento do fundo cubra colunas.",
    "Borders": "LIMITES / bordas fisicas (Z=-16). PNG nativo bordas.png, grade 8 px, 10 stamps. Pintar aqui bloqueia movimento no jogo somente nos pixels opacos, inclusive com flips; os vaos permanecem livres. Sem duplicar em Gameplay. Medidas: docs/LDtk_BORDAS.md.",
    "WaterBanks": "SUPERFICIE / margens e espuma da agua (Z=-17), acima da superficie Z=-18. Paleta inicial do Floor; trocar por arte de margens quando disponivel. Sem colisao automatica.",
    "Floor": "SUPERFICIE / piso, cortes 16px, Z=-20. Define o chao seguro e os limites FloorBoundary; DashGap em Gameplay recorta os vaos. A agua e desenhada acima deste piso.",
    "PlatformUnderside": "SUPERFICIE / acabamento inferior das plataformas, cortes 16px, Z=-2. Decoracao visual; nao define piso seguro nem substitui as regras em Gameplay.",
}


def _offset(layer: dict) -> tuple[int, int]:
    return int(layer.get("__pxTotalOffsetX", 0)), int(layer.get("__pxTotalOffsetY", 0))


def _paint(layer: dict, point: tuple[int, int], value: int) -> None:
    grid, width, height = int(layer["__gridSize"]), int(layer["__cWid"]), int(layer["__cHei"])
    ox, oy = _offset(layer)
    x, y = point[0] - ox, point[1] - oy
    if x % grid or y % grid or not (0 <= x // grid < width and 0 <= y // grid < height):
        raise ValueError("Gameplay nao pode representar a posicao original sem perda de precisao.")
    if not layer["intGridCsv"]:
        layer["intGridCsv"] = [0] * (width * height)
    index = (y // grid) * width + x // grid
    previous = layer["intGridCsv"][index]
    if previous not in (0, value):
        raise ValueError(f"Regras sobrepostas em {point}: {previous} e {value}. Mapa preservado.")
    layer["intGridCsv"][index] = value


def clean_data(data: dict) -> dict:
    before = deepcopy(data)
    definitions = data["defs"]
    # Copies predating borders remain valid; registered/painted borders must survive cleanup.
    order = [identifier for identifier in ORDER if identifier != "Borders" or
             any(layer["identifier"] == "Borders" for layer in definitions["layers"])]
    groups = [("Colisao", "#E26363"), ("Travessia", "#9B86C8"),
              ("FluxoDaSala", "#2CF7A3"), ("Perigos", "#FA6A0A")]
    gameplay_def = next(layer for layer in definitions["layers"] if layer["identifier"] == "Gameplay")
    if not gameplay_def["intGridValuesGroups"]:
        for identifier, color in groups:
            gameplay_def["intGridValuesGroups"].append({"uid": data["nextUid"], "identifier": identifier, "color": color})
            data["nextUid"] += 1
    group_uids = {group["identifier"]: group["uid"] for group in gameplay_def["intGridValuesGroups"]}
    specs = [(1, "MapLimit", "#E26363", "Colisao"), (6, "Solid", "#D9A088", "Colisao"),
             (3, "DoorBlock", "#F39C12", "Colisao"), (2, "DashGap", "#9B86C8", "Travessia"),
             (4, "Start", "#2CF7A3", "FluxoDaSala"), (5, "End", "#E9CF6A", "FluxoDaSala"),
             (7, "Hazard", "#FA6A0A", "Perigos")]
    gameplay_def["intGridValues"] = [{"value": value, "identifier": identifier, "color": color,
                                      "tile": None, "groupUid": group_uids[group]}
                                     for value, identifier, color, group in specs]
    for entity in definitions["entities"]:
        if entity["identifier"] == "DoorDash":
            entity["identifier"] = "DashGapArea"
        if entity["identifier"] == "RoomTrigger":
            entity["identifier"] = "GameplayTrigger"
        if entity["identifier"] in ("DashGapArea", "GameplayTrigger"):
            entity["tags"] = ["gameplay"]
            entity["doc"] = ("TRAVESSIA. Vao redimensionavel: atravessar com dash; andar/parar retorna ao Start sem dano. Nao e uma porta visual."
                             if entity["identifier"] == "DashGapArea" else
                             "FLUXO DA SALA. Ao entrar, define ConditionId com ConditionValue; Once controla uso unico. ConditionId vazio nao faz nada. Pode liberar DoorControl com a mesma condicao.")
    definitions["entities"] = [entity for entity in definitions["entities"] if entity["identifier"] not in REMOVED_ENTITIES]
    for level in all_levels(data):
        if level["layerInstances"] is None:
            raise ValueError("Limpeza de niveis externos requer loader proprio.")
        layers = {layer["__identifier"]: layer for layer in level["layerInstances"]}
        gameplay = layers["Gameplay"]
        collisions = layers.get("Collisions")
        if collisions:
            grid, width = int(collisions["__gridSize"]), int(collisions["__cWid"])
            ox, oy = _offset(collisions)
            for index, value in enumerate(collisions["intGridCsv"]):
                if value:
                    _paint(gameplay, ((index % width) * grid + ox, (index // width) * grid + oy), {1: 6, 2: 3, 3: 7}[value])
        utilities = layers.get("GameplayAreas", layers.get("Entities"))
        utilities["__identifier"] = "GameplayAreas"
        for layer in list(layers.values()):
            retained = []
            for entity in layer["entityInstances"]:
                identifier = entity["__identifier"]
                if identifier == "NoxStart":
                    ox, oy = _offset(layer)
                    grid = int(gameplay["__gridSize"])
                    _paint(gameplay, (int(entity["px"][0]) + ox - grid // 2,
                                      int(entity["px"][1]) + oy - grid // 2), 4)
                if identifier in REMOVED_ENTITIES:
                    continue
                renamed = {"DoorDash": "DashGapArea", "RoomTrigger": "GameplayTrigger"}.get(identifier, identifier)
                target = layers["WaterAreas"] if renamed in ("WaterArea", "WaterShoreOverride") else layers["AmbientAreas"] if renamed == "AmbientArea" else utilities
                if renamed not in ("WaterArea", "WaterShoreOverride", "AmbientArea", "DashGapArea", "GameplayTrigger", "Warp", "DoorControl", "SpiritHordeArea", "HordePedestal"):
                    raise ValueError(f"Entidade sem utilidade conhecida: {identifier}. Mapa preservado.")
                if renamed != identifier:
                    entity["__identifier"] = renamed
                    entity["__tags"] = ["gameplay"]
                    if "__type" in entity:
                        entity["__type"] = renamed
                if target is layer:
                    retained.append(entity)
                else:
                    sx, sy = _offset(layer)
                    tx, ty = _offset(target)
                    if (sx, sy) != (tx, ty):
                        entity["px"] = [entity["px"][0] + sx - tx, entity["px"][1] + sy - ty]
                        entity["__grid"] = [int(value) // int(target["__gridSize"]) for value in entity["px"]]
                    target["entityInstances"].append(entity)
            layer["entityInstances"] = retained
        for identifier, names in OBJECTS.items():
            candidates = [layers[name] for name in (*names, identifier) if name in layers]
            target = candidates[0]
            for source in candidates[1:]:
                if (source["__tilesetDefUid"], source["__gridSize"], _offset(source)) != (target["__tilesetDefUid"], target["__gridSize"], _offset(target)):
                    raise ValueError("Objetos com fontes/offsets diferentes requerem migracao explicita.")
                target["gridTiles"].extend(source["gridTiles"])
                target["autoLayerTiles"].extend(source["autoLayerTiles"])
            target["__identifier"] = identifier
            layers[identifier] = target
        layers["GameplayAreas"] = utilities
        level["layerInstances"] = [layers[identifier] for identifier in order]
    by_name = {layer["identifier"]: layer for layer in definitions["layers"]}
    by_name["GameplayAreas"] = by_name.get("GameplayAreas", by_name.get("Entities"))
    for identifier, names in OBJECTS.items():
        by_name[identifier] = by_name.get(identifier, by_name.get(names[0]))
    definitions["layers"] = [by_name[identifier] for identifier in order]
    for layer in definitions["layers"]:
        identifier = next(name for name in order if by_name[name] is layer)
        layer["identifier"] = identifier
        layer["doc"] = LAYER_DOCS[identifier]
        if identifier == "GameplayAreas":
            layer.update(requiredTags=["gameplay"], uiFilterTags=["gameplay"], uiColor="#E9CF6A")
        elif identifier.startswith("Objects"):
            layer["uiColor"] = "#B192D6"
        elif identifier.startswith("Walls"):
            layer["uiColor"] = "#6F4358"
    definitions["tilesets"] = [source for source in definitions["tilesets"] if source["uid"] not in REMOVED_TILESETS]
    data["tutorialDesc"] = "Modelo limpo: Gameplay agrupa colisao, travessia, fluxo da sala e perigos; GameplayAreas recebe areas utilitarias. Personagens, portas e trono removidos da autoria. Objetos agrupados por profundidade. Consulte docs/GUIA.md."
    return {"changed": data != before, "layers_before": len(before["defs"]["layers"]),
            "layers_after": len(definitions["layers"]), "tilesets_before": len(before["defs"]["tilesets"]),
            "tilesets_after": len(definitions["tilesets"]), "entities": [entity["identifier"] for entity in definitions["entities"]]}


def serialize_layout(original: bytes, before: dict, after: dict) -> bytes:
    """Reuse unchanged JSON spans, including every surviving tile record."""
    text = original.decode("utf-8-sig")
    decoder = json.JSONDecoder()
    newline = "\r\n" if "\r\n" in text else "\n"

    def skip(index: int) -> int:
        while index < len(text) and text[index].isspace():
            index += 1
        return index

    def children(start: int) -> dict:
        result, index, array_index = {}, skip(start + 1), 0
        while text[index] not in "]}":
            key = array_index
            if text[start] == "{":
                key, index = decoder.raw_decode(text, index)
                index = skip(skip(index) + 1)
            value_start = index
            _, index = decoder.raw_decode(text, index)
            result[key] = (value_start, index)
            array_index += 1
            index = skip(index)
            if text[index] == ",":
                index = skip(index + 1)
        return result

    def render(old, new, start: int, end: int) -> str:
        if old == new:
            return text[start:end]
        line = text[text.rfind("\n", 0, start) + 1:start]
        indent = line[:len(line) - len(line.lstrip())]
        if isinstance(old, dict) and isinstance(new, dict) and old.keys() == new.keys():
            result = text[start:end]
            spans = children(start)
            for key, (left, right) in reversed(list(spans.items())):
                if old[key] != new[key]:
                    result = result[:left - start] + render(old[key], new[key], left, right) + result[right - start:]
            return result
        if isinstance(old, list) and isinstance(new, list) and new and all(isinstance(item, dict) for item in new):
            key = next((key for key in ("iid", "uid", "value", "__identifier") if all(key in item for item in [*old, *new])), None)
            spans = children(start)
            lookup = {item[key]: (item, *spans[index]) for index, item in enumerate(old)} if key else {}
            entries = []
            for item in new:
                if key and item[key] in lookup:
                    previous, left, right = lookup[item[key]]
                    entries.append(render(previous, item, left, right))
                else:
                    entries.append(json.dumps(item, ensure_ascii=False, indent="\t").replace("\n", newline + indent + "\t"))
            return "[" + newline + indent + "\t" + ("," + newline + indent + "\t").join(entries) + newline + indent + "]"
        return json.dumps(new, ensure_ascii=False, separators=(",", ":"))

    result = render(before, after, skip(0), len(text.rstrip())) + text[len(text.rstrip()):]
    if json.loads(result) != after:
        raise ValueError("A serializacao divergiu do modelo validado.")
    return result.encode("utf-8-sig" if original.startswith(b"\xef\xbb\xbf") else "utf-8")


def clean_project(project: Path = ROOT / "monster_booster.ldtk", dry_run: bool = False) -> dict:
    original = project.read_bytes()
    before = json.loads(original.decode("utf-8-sig"))
    data = deepcopy(before)
    report = clean_data(data)
    report.update(dry_run=dry_run, backup=None)
    if not report["changed"] or dry_run:
        return report
    if editor_busy() or project.read_bytes() != original:
        raise RuntimeError("Salve e feche o LDtk antes da limpeza. Mapa preservado.")
    content = serialize_layout(original, before, data)
    backup_root = project.parent / "ldtk_backups"
    backup_root.mkdir(exist_ok=True)
    backup = backup_root / f"before_cleanup_{datetime.now():%Y%m%d_%H%M%S_%f}_{hashlib.sha256(original).hexdigest()[:12]}.ldtk"
    backup.write_bytes(original)
    with tempfile.NamedTemporaryFile(mode="wb", dir=project.parent, prefix=".ldtk_cleanup_", suffix=".tmp", delete=False) as file:
        temporary = Path(file.name)
        file.write(content)
    try:
        if editor_busy() or project.read_bytes() != original:
            raise RuntimeError("LDtk abriu ou o mapa mudou durante a limpeza. Mapa preservado.")
        os.replace(temporary, project)
    finally:
        temporary.unlink(missing_ok=True)
    report["backup"] = str(backup)
    return report


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", type=Path, default=ROOT / "monster_booster.ldtk")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    print(json.dumps(clean_project(args.project, args.dry_run), ensure_ascii=False))
