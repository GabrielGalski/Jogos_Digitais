# Dungeon Card Shooter

Base em primeira pessoa para Godot 4. A direção do jogo é uma progressão por
salas: cada porta será liberada após o jogador eliminar a quantidade exigida de
inimigos, avançando até um primeiro chefe e depois ao chefe final.

## Controles

- `W`, `A`, `S`, `D`: movimentação relativa à direção da câmera.
- `Shift`: dash na direção das teclas `W`, `A`, `S` e `D` pressionadas;
  combinações adjacentes produzem dash diagonal.
- Mouse: olhar ao redor.
- Scroll do mouse: alternar entre Rifle, Shotgun e Katana.
- Botão esquerdo do mouse: ativar a carta selecionada.
- `Espaço`: alternar entre o mundo normal e o Upside.
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
- Há um teto na altura de 4 unidades, usando o mesmo material das paredes.
- Todas as paredes têm quatro blocos de 1 × 1 × 1 empilhados, totalizando
  4 unidades de altura, com textura nas quatro faces laterais.
- Há paredes internas, corredores laterais e pilares de cobertura.
- A fog do ambiente e as antigas cortinas de borda estão desativadas.
- A geometria visual usa `MultiMesh`, enquanto as colisões permanecem simples.

## Mundos

- O mundo normal usa `Sprite_floor.png`, `Sprite_wall.png` e `normal_base.wav`.
- O Upside usa `Sprite_floor_upside.png`, `Sprite_wall_upside.png` e
  `upside_base.wav`.
- As músicas permanecem em loop, fazem um crossfade curto e retomam da posição
  em que cada mundo foi deixado.
- Piso, paredes e teto mudam juntos; a troca ainda não consome tempo nesta base.

As texturas ficam em `res://sprites/`:

- `Sprite_floor.png`: piso.
- `Sprite_wall.png`: paredes.
- `crosshair_rifle.png`: mira do Rifle.
- `crosshair_shotgun.png`: mira da Shotgun.
- `crosshair_melee.png`: mira da Katana.

Os cinco arquivos de áudio ficam em `res://sfx/`.

Abra `project.godot` no Godot 4 e execute com `F6` ou `F5`.
