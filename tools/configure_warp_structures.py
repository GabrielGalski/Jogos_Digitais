"""Register the two authored structures and replace the reserved central pedestal.

Gameplay stays in Room_2; the path plaza is editable in Room_2_Cenario.
The original sprite palettes are treated by Godot materials, like the tree assets.
"""
from __future__ import annotations

from copy import deepcopy
from datetime import datetime
import hashlib
import json
import os
from pathlib import Path
import tempfile
import uuid

from configure_ldtk_water import all_levels
from ldtk_field_values import preserve_editor_values
from split_ldtk_room2 import reference_bytes, REFERENCE
from complete_room_2_grass_borders import convert as border_tiles

ROOT = Path(__file__).resolve().parents[1]
GRID = 16


def fields(entity: dict) -> dict:
    return {f['__identifier']: f['__value'] for f in entity['fieldInstances']}


def convert(data: dict) -> dict:
    def allocate() -> int:
        value = data['nextUid']
        data['nextUid'] += 1
        return value

    warp = next(e for e in data['defs']['entities'] if e['identifier'] == 'Warp')
    warp_set = next(t for t in data['defs']['tilesets'] if t['identifier'] == 'Warp_16')
    warp_set.update(relPath='assets/tiles/structures/warp_preview.png', pxWid=96, pxHei=96,
                    __cWid=6, __cHei=6, cachedPixelData=None,
                    savedSelections=[{'ids': list(range(36)), 'mode': 'Stamp'}])
    warp.update(width=48, height=48, pivotX=0.5, pivotY=49 / 96,
                doc='TRAVESSIA / Warp 48x48, escala 50% da fonte 96x96 preservada. Centro util no pivo (24,24.5); chegada com os pes no centro. Pedra malva e recortes amarelos solidos com borda escura, estaticos. Preview colorido no LDtk; mesma apresentacao na Godot.')
    warp['tileRect'] = warp['uiTileRect'] = {'tilesetUid': warp_set['uid'], 'x': 0, 'y': 0, 'w': 96, 'h': 96}
    central_set = next((t for t in data['defs']['tilesets'] if t['identifier'] == 'CentralWarp_16'), None)
    if central_set is None:
        central_set = deepcopy(warp_set)
        central_set.update(uid=allocate(), identifier='CentralWarp_16')
        data['defs']['tilesets'].append(central_set)
    central_set.update(relPath='assets/tiles/structures/central_warp_preview.png', pxWid=192, pxHei=256,
                       __cWid=12, __cHei=16, cachedPixelData=None,
                       savedSelections=[{'ids': list(range(192)), 'mode': 'Stamp'}])
    central = next((e for e in data['defs']['entities'] if e['identifier'] == 'CentralWarp'), None)
    if central is None:
        central = deepcopy(warp)
        central.update(uid=allocate(), identifier='CentralWarp')
        for field in central['fieldDefs']:
            field['uid'] = allocate()
        data['defs']['entities'].append(central)
    central.update(width=192, height=256, pivotX=0.5, pivotY=106 / 256,
                   tilesetId=central_set['uid'],
                   doc='TRAVESSIA / Warp central 192x256. Pivo no centro do losango (96,106), simbolos amarelos estaticos. HeightPx eleva atores no topo e na escada; RampWidth suaviza as quatro laterais. Quatro pilastras com bases solidas e topo em Y-sort. Destino futuro ainda sem configuracao.')
    central['tileRect'] = central['uiTileRect'] = {'tilesetUid': central_set['uid'], 'x': 0, 'y': 0, 'w': 192, 'h': 256}
    for definition in (warp, central):
        for field in definition['fieldDefs']:
            if field['identifier'] == 'WhiteRing':
                field['doc'] = 'Legado, sem animacao no modelo atual: os simbolos sao amarelos solidos com borda escura.'
    pedestal_def = next(e for e in data['defs']['entities'] if e['identifier'] == 'HordePedestal')
    for name, documentation in (
        ('HeightPx', 'Altura em pixels do topo do warp central. Padrao 8; Nox, arma e sombra sobem juntos.'),
        ('RampWidth', 'Faixa de subida nas laterais do topo. A escada sul sobe ao longo do desenho. Padrao 8.')):
        field = next((f for f in central['fieldDefs'] if f['identifier'] == name), None)
        if field is None:
            field = deepcopy(next(f for f in pedestal_def['fieldDefs'] if f['identifier'] == name))
            field['uid'] = allocate()
            central['fieldDefs'].append(field)
        field.update(doc=documentation, defaultOverride={'id': 'V_Int', 'params': [8]}, max=32 if name == 'HeightPx' else 24)

    for level in all_levels(data):
        for layer in level['layerInstances']:
            for entity in layer['entityInstances']:
                if entity['__identifier'] == 'Warp':
                    entity.update(width=48, height=48, __pivot=[0.5, 49 / 96], __tile=deepcopy(warp['tileRect']))

    room = next(l for l in all_levels(data) if l['identifier'] == 'Room_2')
    scenery = next(l for l in all_levels(data) if l['identifier'] == 'Room_2_Cenario')
    entities = next(l for l in room['layerInstances'] if l['__identifier'] == 'GameplayAreas')['entityInstances']
    arrival = next((e for e in entities if e['__identifier'] in ('Warp', 'CentralWarp') and fields(e).get('WarpId') == 'room_2_center'), None)
    if arrival is None:
        raise ValueError('Chegada central existente ausente; nenhuma entidade foi inventada.')
    entities[:] = [e for e in entities if not (e['__identifier'] == 'HordePedestal' and fields(e).get('EncounterId') == 'room_2_final_center')]
    arrival.update(__identifier='CentralWarp', defUid=central['uid'], width=192, height=256,
                   __pivot=[0.5, 106 / 256], px=[1864, 1752], __grid=[116, 109],
                   __worldX=room['worldX'] + 1864, __worldY=room['worldY'] + 1752,
                   __tile=deepcopy(central['tileRect']))
    field_defs = {f['identifier']: f for f in central['fieldDefs']}
    for name in ('HeightPx', 'RampWidth'):
        if not any(f['__identifier'] == name for f in arrival['fieldInstances']):
            arrival['fieldInstances'].append({'__identifier': name, '__type': 'Int', '__value': 8,
                                              'defUid': field_defs[name]['uid'], 'realEditorValues': []})
    for field in arrival['fieldInstances']:
        field['defUid'] = field_defs[field['__identifier']]['uid']
    preserve_editor_values(arrival)

    path_def = next(l for l in data['defs']['layers'] if l['identifier'] == 'Floor_Paths')
    plaza_def = next((l for l in data['defs']['layers'] if l['identifier'] == 'Floor_WarpPlaza'), None)
    if plaza_def is None:
        plaza_def = deepcopy(path_def)
        plaza_def.update(uid=allocate(), identifier='Floor_WarpPlaza',
                         doc='PISO / Praca do warp central. Mesmo preenchimento e tratamento dos caminhos; folhas para dentro do contorno. Editar somente no Room_2_Cenario.')
        data['defs']['layers'].insert(data['defs']['layers'].index(path_def), plaza_def)
    plaza_def['doc'] = 'PISO / Praca do warp central. Mesmo preenchimento e tratamento dos caminhos; folhas para dentro do contorno. Editar somente no Room_2_Cenario.'
    for level in all_levels(data):
        if not any(l['__identifier'] == 'Floor_WarpPlaza' for l in level['layerInstances']):
            source = next(l for l in level['layerInstances'] if l['__identifier'] == 'Floor_Paths')
            layer = deepcopy(source)
            layer.update(__identifier='Floor_WarpPlaza', layerDefUid=plaza_def['uid'], iid=str(uuid.uuid4()),
                         gridTiles=[], autoLayerTiles=[], entityInstances=[], intGridCsv=[])
            level['layerInstances'].insert(level['layerInstances'].index(source), layer)

    layers = {l['__identifier']: l for l in scenery['layerInstances']}
    paths = layers['Floor_Paths']
    plaza = layers['Floor_WarpPlaza']
    floor = {tuple(t['px']) for t in layers['Floor']['gridTiles']}
    # A compact chamfered square around the platform and its authored stair sprite.
    first_x, first_y, columns, rows = 103, 97, 27, 27
    cells = set()
    for y in range(rows):
        for x in range(columns):
            if min(x, columns - 1 - x) + min(y, rows - 1 - y) < 3:
                continue
            cells.add(((first_x + x) * GRID, (first_y + y) * GRID))
    if cells - floor:
        raise ValueError('A praca saiu do terreno existente.')
    atlas = next(t for t in data['defs']['tilesets'] if t['uid'] == paths['__tilesetDefUid'])
    plaza['gridTiles'] = [dict(px=[x, y], src=[128, 32], f=0, t=2 * atlas['__cWid'] + 8,
                               d=[y // GRID * plaza['__cWid'] + x // GRID], a=1)
                          for x, y in sorted(cells, key=lambda p: (p[1], p[0]))]
    # Paths enter the plaza on their existing axes; preserve all distant roads/bridges.
    for key in ('Floor_Paths', 'Floor_Grass', 'Floor_GrassBorders', 'GrassAnimated', 'Leaves'):
        layers[key]['gridTiles'] = [t for t in layers[key]['gridTiles'] if tuple(t['px']) not in cells]
    for key in ('Bushes', 'Trees', 'Trees_Border', 'Trees_Border_2', 'Trees_Border_3'):
        layer = layers[key]
        tileset = next(t for t in data['defs']['tilesets'] if t['uid'] == layer['__tilesetDefUid'])
        removed = set()
        for tile in layer['gridTiles']:
            origin = (tile['px'][0] - tile['src'][0], tile['px'][1] - tile['src'][1])
            if any((origin[0] + dx, origin[1] + dy) in cells
                   for dx in range(0, tileset['pxWid'], GRID) for dy in range(0, tileset['pxHei'], GRID)):
                removed.add(origin)
        layer['gridTiles'] = [t for t in layer['gridTiles'] if (t['px'][0] - t['src'][0], t['px'][1] - t['src'][1]) not in removed]
    # Recompute only the plaza and neighbouring junctions, preserving authored
    # borders everywhere else (including the bridges and the castle).
    affected = {(x + dx, y + dy) for x, y in cells for dx in (-GRID, 0, GRID) for dy in (-GRID, 0, GRID)}
    borders = layers['Floor_GrassBorders']
    preserved = [deepcopy(t) for t in borders['gridTiles'] if tuple(t['px']) not in affected]
    border_tiles(data, ROOT)
    added = [t for t in borders['gridTiles'] if tuple(t['px']) in affected]
    borders['gridTiles'] = preserved + added
    assert len([e for e in entities if e['__identifier'] == 'HordePedestal']) == 6
    assert fields(arrival)['TargetLevel'] == '' and fields(arrival)['TargetScene'] == ''
    return {'central_position': arrival['px'], 'central_arrival_feet': arrival['px'],
            'plaza_tiles': len(cells), 'plaza_bounds': [1648, 1552, 432, 432],
            'plaza_border_tiles': len(added), 'height_px': fields(arrival)['HeightPx'],
            'event_pedestals_preserved': 6, 'final_boss_travel_implemented': False}


if __name__ == '__main__':
    path = ROOT / 'monster_booster.ldtk'
    original = path.read_bytes()
    data = json.loads(original)
    report = convert(data)
    # Keep all other authored values and cached atlas data; back up before replacing.
    content = (json.dumps(data, ensure_ascii=False, indent=2) + '\n').encode('utf-8')
    backup = ROOT / 'ldtk_backups' / f'before_warp_structures_{datetime.now():%Y%m%d_%H%M%S}_{hashlib.sha256(original).hexdigest()[:12]}.ldtk'
    backup.parent.mkdir(exist_ok=True)
    backup.write_bytes(original)
    reference = reference_bytes(data, ROOT)
    with tempfile.NamedTemporaryFile(dir=ROOT, prefix='.warp_structures_', suffix='.tmp', delete=False) as stream:
        temporary = Path(stream.name)
        stream.write(content)
    try:
        if path.read_bytes() != original:
            raise RuntimeError('O LDtk mudou durante a migracao; arquivo preservado.')
        os.replace(temporary, path)
    finally:
        temporary.unlink(missing_ok=True)
    (ROOT / REFERENCE).write_bytes(reference)
    print(json.dumps(dict(report, backup=str(backup)), ensure_ascii=False, indent=2))
