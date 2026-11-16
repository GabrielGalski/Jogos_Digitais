# Base de chão do MonsterShift

Cópias dos arquivos de `C:/Projetos/MonsterShift/assets/tiles/floor`, sem editar pixels ou paleta. Os nomes ficam nesta subpasta para não substituir os atlases já usados pela Room_1 e pelas cenas antigas.

- `texturized_floor.png`: original de autoria, 1254×1254.
- `texturized_floor_atlas.png`: atlas 512×512 já preparado no projeto de origem; corte de 16×16.
- `floor_tileset2.png`: atlas 256×48, com solo roxo e bordas escuras; corte de 16×16. É usado nos caminhos e no acabamento das plataformas.
- `floor_tileset2.ase`: fonte de autoria correspondente, preservada.
- `floor_tileset3.png` e `floor_tileset_2.png`: demais bases do mesmo conjunto, preservadas para autoria futura.

Os arquivos `.import` são gerados neste projeto. O shader adaptado fica em `shaders/terrain_clouds.gdshader`, com o transformador de cores original em `shaders/terrain_scenery_grade.gdshaderinc`. A Room_2 e o template usam o perfil `open_world_soil.tres`, com estado da animação por cena. A cena do Asterion conserva o chão, a trilha e o efeito fraco de nuvens anteriores; ela foi apenas uma referência visual.
