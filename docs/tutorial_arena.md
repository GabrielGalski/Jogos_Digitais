# Arena do tutorial — base jogável

- Cena fixa: `scenes/tutorial_arena.tscn`; o mapa não é gerado durante o jogo.
- Piso: 640 × 704 px, 40 × 44 tiles de 16 px. Extensão local: x=-320..320, y=-384..320. As quatro novas fileiras foram adicionadas ao topo.
- A cena principal mantém a arena em (130, -420). A câmera converte os limites locais para globais, conserva zoom 1,20 e margem externa de 32 px.
- Mox mantém a posição final de entrada (0, 284). Escada centrada em (0, 334).
- Buraco esquerdo, colisão, bordas e duas correntes deslocados juntos em (+16, +48). Buraco direito e corrente preservados.
- Trono alinhado ao eixo x=0 da escada. Ver `minotaur_chair_mapping.md`.

## Caminho e piso escuro

O contorno escuro do trono mede 112 × 64 px (7 × 4 tiles), centrado no eixo da escada. O trono conserva sua escala de 0,78. As duas células verticais centrais foram restauradas; a redução acontece pela retirada de duas fileiras superiores, mantendo as faixas horizontais e o suporte inferior.

ThronePath é um TileMapLayer editável, salvo na cena. Os trechos do caminho têm 48 px (três tiles), com alargamentos nos cotovelos e no entorno do trono. Os contornos usam o atlas original do piso; o interior usa path_color.png como fonte 1 do TileSet. A célula central inferior (0,19) usa path_color.png; há dez células sólidas fechando os encontros de bordas do buraco esquerdo, sem sprites de canto sobrepostos.

## Entrada

`scripts/tutorial_intro.gd` controla somente a sequência de abertura: o personagem inicia no marcador (0, 424), fora da tela, caminha para (0, 284) com sua animação de corrida e para. A câmera fica no enquadramento da chegada durante a subida. A escada recua 48 px, comprime sua altura e desaparece em 0,7 s; o controle WASD e o acompanhamento da câmera são liberados. O limite inferior continua bloqueando o retorno. A reabertura ao concluir o tutorial ainda não foi implementada.

## Validação

tests/tutorial_arena_smoke.gd verifica destino da entrada, escada oculta, liberação do controle, limites globais da câmera, bordas da arena, passagem atrás do encosto, bloqueio na base de 64 × 18 px e travessia do caminho com um corpo de colisão de raio 5.

Executar com Godot: `--headless --path . --script tests/tutorial_arena_smoke.gd`. Sem `--headless`, também salva capturas e a visão geral em `docs/tutorial_arena_layout.png`.
