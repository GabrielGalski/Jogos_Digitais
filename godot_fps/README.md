# Dungeon Card Shooter

Base em primeira pessoa para Godot 4. A direção do jogo é uma progressão por
salas: cada porta será liberada após o jogador eliminar a quantidade exigida de
inimigos, avançando até um primeiro chefe e depois ao chefe final.

## Controles

- `W`, `A`, `S`, `D`: movimentação relativa à direção da câmera.
- Dois toques rápidos em `W`, `A`, `S` ou `D`: mini dash.
- Segure uma direção adjacente durante o duplo toque para um dash diagonal.
- Mouse: olhar ao redor.
- Scroll do mouse: alternar entre Rifle, Shotgun e Katana.
- Botão esquerdo do mouse: ativar a carta selecionada.
- Setas: inclinação independente da câmera, inclusive nas diagonais.
- `Esc`: liberar o cursor.
- Clique na janela: capturar o cursor novamente.

O dash aplica kick de FOV, deslocamento direcional e impacto de câmera. Colidir
com uma parede durante o impulso produz um impacto mais forte.

## Cartas de verificação

- `RIFLE`: automático enquanto o botão esquerdo estiver pressionado.
- `SHOTGUN`: nove pellets por disparo; o som de pump toca depois do tiro.
- `KATANA`: glow trail de duas camadas; os dois sons de corte se alternam e
  nunca se repetem consecutivamente.

As três cartas são brancas, exibem somente seus nomes e ficam no canto superior
direito. A carta ativa recebe uma borda azul. Cada carta troca também a mira no
centro da tela. Nesta verificação, as cartas ainda não gastam usos.

## Dungeon

- O piso é uma grade de blocos de 1 × 1 unidade.
- Não há teto: acima da arena existe um céu totalmente preto.
- Todas as paredes têm exatamente um cubo de 1 × 1 × 1 de altura, com textura
  nas quatro faces laterais.
- Há paredes internas, corredores laterais e pilares de cobertura.
- Neblina de distância e cortinas com degradê nas quatro bordas escondem o
  limite do piso e o vazio, mas deixam parte do céu visível.
- A geometria visual usa `MultiMesh`, enquanto as colisões permanecem simples.

As texturas ficam em `res://sprites/`:

- `Sprite_floor.png`: piso.
- `Sprite_wall.png`: paredes.
- `crosshair_rifle.png`: mira do Rifle.
- `crosshair_shotgun.png`: mira da Shotgun.
- `crosshair_melee.png`: mira da Katana.

Os cinco arquivos de áudio ficam em `res://sfx/`.

Abra `project.godot` no Godot 4 e execute com `F6` ou `F5`.
