# Dungeon Boomer Shooter

Base em primeira pessoa para Godot 4, estruturada como uma dungeon modular de
32 × 32 unidades.

## Controles

- `W`, `A`, `S`, `D`: movimentação relativa à direção da câmera.
- Dois toques rápidos em `W`, `A`, `S` ou `D`: mini dash.
- Segure uma direção adjacente durante o duplo toque para um dash diagonal.
- Mouse: olhar ao redor.
- Setas: inclinação independente da câmera, inclusive nas diagonais.
- `Esc`: liberar o cursor.
- Clique na janela: capturar o cursor novamente.

O dash aplica kick de FOV, deslocamento direcional e impacto de câmera. Colidir
com uma parede durante o impulso produz um impacto mais forte.

## Dungeon

- Piso e teto são grades de blocos de 1 × 1 unidade.
- As paredes são colunas formadas por quatro cubos de 1 × 1 × 1, com textura
  nas quatro faces laterais.
- Há paredes internas, corredores laterais e pilares de cobertura.
- O teto reutiliza o sprite do piso.
- A geometria visual usa `MultiMesh`, enquanto as colisões permanecem simples.

As texturas ficam em `res://sprites/`:

- `Sprite_floor.png`: piso e teto.
- `Sprite_wall.png`: paredes.

Abra `project.godot` no Godot 4 e execute com `F6` ou `F5`.
