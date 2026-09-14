# Piso ativo — atlas de 16 px

`floor_tileset.png` é a única textura usada para piso, bordas e caminho. Atlas de 64×48 px; quatro colunas e três linhas de células 16×16.

- `(0,0)`: preenchimento liso do caminho e do entorno do trono.
- `(1,1)`: chão liso do ambiente.
- `(2,1)`: decalque com rotações de 0°, 90°, 180° ou 270°.
- Demais perfis: bordas e quinas da composição anterior.

Interior: 1.369 células, sendo 1.027 lisas (75,02%) e 342 com decalque (24,98%). Decalques não ficam imediatamente ao lado, acima ou abaixo de outro. Bordas, preenchimentos especiais e caminho não entram nessa contagem.

O recurso `resources/floor_tileset.tres` usa somente esse PNG. A distribuição está salva na cena, sem geração em runtime. Camadas: `Floor` e `ThronePath`, sem recortes de 32 px ou dependência de `path_color.png`.

Atlas de 32 px, fontes, recursos e mapeamentos desativados em `old/floor32_disabled/`.
