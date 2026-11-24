# Tileset da arena do vampiro

Os recortes usam **`(x, y, largura, altura)`** em pixels da imagem, com origem no canto superior esquerdo.

## Paredes

[`tileset_walls.png`](tileset_walls.png) mede **256 × 256 px**, com fundo transparente. No LDtk, o catálogo **`VampireArenaWalls_8`** usa uma grade de **8 × 8 px** (32 × 32 células), sem margem nem espaçamento. As coordenadas das peças seguem os pixels do desenho. Os carimbos do editor seguem a grade.

| ID | Peça | Recorte |
|---|---|---|
| P01 | Parede norte esquerda com remates e cantos | `(0, 5, 103, 18)` |
| P02 | Parede norte direita com remates e cantos | `(154, 5, 102, 18)` |
| P03 | Braço esquerdo da reentrância norte | `(90, 23, 13, 25)` |
| P04 | Fundo horizontal da reentrância norte | `(103, 38, 51, 10)` |
| P05 | Braço direito da reentrância norte | `(154, 23, 13, 25)` |
| P06 | Parede lateral oeste | `(0, 23, 13, 102)` |
| P07 | Parede lateral leste | `(244, 23, 12, 102)` |
| P08 | Parapeito frontal esquerdo | `(0, 125, 77, 12)` |
| P09 | Parapeito frontal direito | `(180, 125, 76, 12)` |
| P10 | Fachada frontal esquerda com ornamento | `(0, 137, 77, 65)` |
| P11 | Fachada frontal direita com ornamento | `(180, 137, 76, 65)` |
| P12 | Lateral esquerda do corredor, com remate | `(77, 120, 13, 65)` |
| P13 | Lateral direita do corredor, com remate | `(167, 120, 13, 65)` |

O eixo da passagem fica em **x = 128,5**, com vão interno de **x = 90 até x = 166**. As laterais do corredor continuam nas laterais da escada.

## Escada de entrada

A escada está na base da mesma folha. A subida vai do sul para o norte.

| ID | Peça | Recorte |
|---|---|---|
| E01 | Escada completa com laterais e lanternas | `(77, 185, 103, 71)` |
| E02 | Miolo dos degraus | `(90, 204, 77, 46)` |
| E03 | Lateral esquerda com lanterna | `(77, 185, 13, 71)` |
| E04 | Lateral direita com lanterna | `(167, 185, 13, 71)` |

E01 reúne as três partes. O topo do miolo em **y = 204** encaixa no fim da passagem.

## Chão

[`tileset_floor.png`](tileset_floor.png) mede **384 × 96 px** e é opaca. É uma faixa de lajes com juntas e pequenas variações de cor. Os três blocos abaixo preservam a altura inteira do desenho.

| ID | Peça | Recorte |
|---|---|---|
| C01 | Trecho esquerdo com detalhe mais irregular | `(0, 0, 128, 96)` |
| C02 | Trecho central com manchas claras no alto | `(128, 0, 128, 96)` |
| C03 | Trecho direito com variação nas juntas | `(256, 0, 128, 96)` |

A ordem **C01 → C02 → C03** reproduz a faixa pintada. As juntas horizontais mais visíveis ficam perto de **y = 16, 56 e 92**. Para repetir a faixa no sentido vertical, vale alinhar essas juntas no encontro. Na escala de referência, cada trecho mede **32 × 24**.
