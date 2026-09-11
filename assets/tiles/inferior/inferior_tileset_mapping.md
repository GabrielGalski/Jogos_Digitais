# Mapeamento de inferior.png

Atlas de **128×32 px**, sem recorte, espelhamento ou redimensionamento da arte.
Origem das coordenadas no canto superior esquerdo.

| Parte | Região (x, y, largura, altura) | Células do atlas |
|---|---|---|
| Extremo esquerdo completo | (0, 0, 32, 32) | (0,0) e (1,0), juntas |
| Meio A | (32, 0, 16, 32) | (2,0) |
| Meio B | (48, 0, 16, 32) | (3,0) |
| Meio C | (64, 0, 16, 32) | (4,0) |
| Meio D | (80, 0, 16, 32) | (5,0) |
| Extremo direito completo | (96, 0, 32, 32) | (6,0) e (7,0), juntas |

## Aplicação na plataforma

- Recurso nativo: `resources/inferior_tileset.tres`, com células de **16×32 px**.
- Cena: `scenes/arena.tscn`, camada `PlatformUnderside`.
- Origem da camada: **(-344, 192)**, imediatamente abaixo do piso.
- Largura: **43 células / 688 px**, sem lacunas ou esticamento.
- As colunas 0 e 1 preservam o extremo esquerdo de 32 px.
- As colunas 2 a 40 repetem A → B → C → D: **39 módulos / 624 px**.
- As colunas 41 e 42 preservam o extremo direito de 32 px.
- A, B e C aparecem 10 vezes cada; D aparece 9 vezes.
- A transparência original dá o recorte irregular da face inferior.
- A camada é apenas visual, fica atrás do piso/personagens e não adiciona colisão ou navegação.
- O piso de 43×24 células e os limites de movimentação permanecem iguais.
- A camada é salva na cena e pode ser editada no Godot; não há geração durante a partida.

`tools/build_platform_border.gd` é uma ferramenta de autoria offline para repetir a montagem.
