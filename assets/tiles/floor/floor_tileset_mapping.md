# Mapeamento do `floor_tileset.png`

## Dimensões

- Atlas: **64×48 px**.
- Grade: **4 colunas × 3 linhas**.
- Célula: **16×16 px**.
- Coordenadas abaixo usam origem no canto superior esquerdo.

## Layout lógico

| Linha/coluna | 0 | 1 | 2 | 3 |
|---:|---|---|---|---|
| 0 | quina superior esquerda | superior reto | duplicata superior | quina superior direita |
| 1 | lateral esquerda | centro padrão | centro variante | lateral direita |
| 2 | quina inferior esquerda | inferior reto | duplicata inferior | quina inferior direita |

## Regiões exatas

| Função | Célula | Região em pixels `(x, y, largura, altura)` | Uso no MVP |
|---|---:|---:|---|
| Quina superior esquerda | `(0,0)` | `(0, 0, 16, 16)` | canto superior esquerdo da arena |
| Superior reto | `(1,0)` | `(16, 0, 16, 16)` | repetição entre as quinas superiores |
| Superior duplicado | `(2,0)` | `(32, 0, 16, 16)` | reservado; visualmente idêntico ao anterior |
| Quina superior direita | `(3,0)` | `(48, 0, 16, 16)` | canto superior direito da arena |
| Lateral esquerda | `(0,1)` | `(0, 16, 16, 16)` | repetição vertical esquerda |
| Centro padrão | `(1,1)` | `(16, 16, 16, 16)` | base fixa das células internas |
| Centro variante | `(2,1)` | `(32, 16, 16, 16)` | aproximadamente 35% do interior |
| Lateral direita | `(3,1)` | `(48, 16, 16, 16)` | repetição vertical direita |
| Quina inferior esquerda | `(0,2)` | `(0, 32, 16, 16)` | canto inferior esquerdo da arena |
| Inferior reto | `(1,2)` | `(16, 32, 16, 16)` | repetição entre as quinas inferiores |
| Inferior duplicado | `(2,2)` | `(32, 32, 16, 16)` | reservado; visualmente idêntico ao anterior |
| Quina inferior direita | `(3,2)` | `(48, 32, 16, 16)` | canto inferior direito da arena |

Os seis perfis principais do contorno são as quatro quinas, o superior reto e o inferior reto. A linha central contém também os dois fechamentos laterais necessários para completar o perímetro.

## Distribuição do piso

- Somente células internas podem usar o centro variante.
- O centro padrão da esquerda é usado nas demais células.
- A seleção usa hash espacial determinístico com limiar de `350/1000`; na arena atual de 43×24 tiles, são **318 variantes em 902 células internas**, aproximadamente **35,25%**.
- Cada variante recebe uma rotação determinística de `0°`, `90°`, `180°` ou `270°`.
- Contorno, quinas e centro padrão nunca são rotacionados.
- A composição permanece igual entre execuções; não há mudança visual aleatória a cada `play`.

## Aplicação no Godot

O atlas é usado diretamente pelo recurso nativo `resources/floor_tileset.tres`. A plataforma de **43×24 células** está salva no `TileMapLayer` da cena `scenes/arena.tscn`; ela não é montada por script durante a execução.

O arquivo `renders/arena_ground.png`, com **688×384 px**, permanece apenas como referência visual consolidada.
