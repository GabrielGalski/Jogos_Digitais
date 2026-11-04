# Warps das estruturas

Os PNGs autorais em `assets/tiles/structures/warp.png` e `central_warp.png` permanecem intactos. `warp_visual.gd` aplica pedra malva/roxa e preenche os recortes com **amarelo sólido #f4d16a**, com contorno **#704731** de um pixel. Os destaques são estáticos: sem relógio, fading, halo, degradê ou emissão aditiva. A graduação normal da cena continua atuando sobre o conjunto.

| Modelo | Imagem | Centro útil dentro da imagem | Posição do ator na chegada |
| --- | --- | --- | --- |
| Warp | Fonte 96×96 px, exibição 48×48 px | (24, 24,5) na exibição | Pivô − (0, 3) |
| CentralWarp | 192×256 px | (96, 106), centro do losango | Pivô + (0, HeightPx) − (0, 3) |

Somente os warps comuns usam escala de 50% com filtro Nearest, preservando o PNG e o preview em sua resolução original. As dimensões da entidade no LDtk controlam a escala visual e a área de interação; o indicador de E acompanha o novo tamanho. A entrada do Asterion usa a mesma escala. O warp central mantém seu tamanho anterior de 192×256 px, assim como a praça e os caminhos.

O deslocamento de três pixels corresponde aos pés de Nox. O warp comum permanece plano. No central, `HeightPx=8` eleva o ator, sua arma e as sombras de contato, mantendo a colisão no plano do mapa. A chegada compensa essa altura para conservar os pés visuais no centro do losango. `RampWidth=8` define a faixa de subida nas laterais; a escada sul sobe progressivamente até o topo. Ambos são campos da entidade no LDtk, em pixels do mundo.

A máscara visual é calculada uma vez por textura, a partir dos recortes transparentes internos; o exterior e os vãos da escada central ficam sem preenchimento. A interação usa a superfície útil contínua, para que inscrições transparentes não interrompam o acionamento.

`Warp` e `CentralWarp` são entidades de gameplay do LDtk. Os arquivos `warp_preview.png` e `central_warp_preview.png` são renders dos mesmos materiais para o editor mostrar as cores finais. A arena do Asterion usa a mesma apresentação em `EntranceWarp` e mantém Nox em (0, 204), com os pés no pivô (0, 207).

No mapa aberto, `CentralWarp` substitui o pedestal central reservado e o antigo ponto separado de chegada. Seu `WarpId` continua `room_2_center`, em **(1864, 1752)**. Os seis pedestais de evento permanecem. A viagem para o chefe final continua sem destino configurado.

`Room_2_Cenario/Floor_WarpPlaza` contém uma praça de 432×432 px, com cantos chanfrados. Usa o mesmo tile, paleta, graduação e camada de profundidade dos caminhos. A antiga substituição exclusiva de cor da praça foi removida. `Floor_GrassBorders` cobre seus contornos com as folhas viradas para dentro, incluindo os cantos e as junções abertas com os caminhos. Os eixos, as pontes e as escadas distantes foram preservados. `Room_2` conserva entidades e regras; `Room_2_Cenario` conserva a pintura.

O mapeamento de `central_warp_platform.gd` usa coordenadas da imagem de 192×256 px:

| Pilastra | Recorte visual (x, y, largura, altura) | Centro da base física | Base visual para Y-sort |
| --- | --- | --- | --- |
| Noroeste | (25, 5, 24, 67) | (37, 63) | (37, 70) |
| Nordeste | (143, 5, 25, 67) | (155, 63) | (155, 70) |
| Sudoeste | (25, 115, 24, 67) | (37, 173) | (37, 180) |
| Sudeste | (143, 115, 25, 67) | (155, 173) | (155, 180) |

Cada base usa uma cápsula horizontal de **20×10 px**, na camada física do cenário. Ela bloqueia Nox e inimigos que colidem com o terreno; o comportamento de atravessar paredes dos fantasmas continua pertencendo a seus próprios filtros. A física não cobre a parte alta das colunas. Os quatro recortes originais são desenhados separadamente no Y-sort dos atores, permitindo passar por trás. Não foram criadas pilastras novas nem acrescentado desenho de degrau.

O topo é o octógono (48,31), (144,31), (190,76), (190,140), (144,184), (48,184), (2,140), (2,76). A escada utiliza a faixa central x=55..137, y=184..252. O deslocamento de altura afeta os atores; o chão da praça permanece no nível original.

Depois de editar os sprites fonte, rode `tools/bake_warp_previews.gd` com renderização real na Godot para atualizar os previews e revise as coordenadas acima caso a geometria tenha mudado. `tools/configure_warp_structures.py` registra os modelos e a praça de forma idempotente, salvando um backup antes da alteração. `tools/warp_structures_regression.gd` verifica as três chegadas, as máscaras e a ausência de animação; `tools/central_warp_physics_regression.gd` testa caminhada real, subida e descida, colisões das quatro bases, passagem atrás, correspondência de cores e composição dos recortes.
