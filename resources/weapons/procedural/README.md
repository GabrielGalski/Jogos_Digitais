# Primeira rodada de manifestações procedurais

Os quatro cenários jogáveis usam o mesmo `player_gameplay_kit.gd` e controlador de manifestações. **I** abre o equipamento e pausa o jogo. Clique no espaço de Manifestação e depois na carta para equipar. **I** ou **Backspace** fecham o menu aberto. A fileira ajusta a largura das cartas à quantidade de opções. A mira acompanha a cor do modelo.

M01, M02, M05, M06 e M07 usam os cinco frames originais da boca da arma, tingidos pela `body_color` do modelo. M04 e M08 mantêm seu feixe ou jato enquanto o mouse estiver pressionado. Abrir o equipamento encerra o canal atual e pausa os projéteis já emitidos.

Cada `.tres` é um `ProceduralManifestationModel`: referencia a carta de combate existente, escolhe o executor e configura sua receita visual. Os valores de dano, intervalo, velocidade e duração continuam nas cartas referenciadas em `resources/cards/preview`; não são duplicados nos desenhos.

| Modelo | Comportamento | Cor principal |
|---|---|---|
| M01 | Gota rápida, um contato, sem ricochete. | `#00baa7` |
| M02 | Massa perfurante a 897,75 px/s, intervalo de 0,5614 s e explosão de raio 28 no primeiro impacto. | `#67c974` |
| M04 | Laser contínuo, primeiro alvo/paredes, dano a cada 0,12 s. | `#ffe26b` |
| M05 | Cinco fragmentos com ângulos independentes sorteados a cada disparo. Alcance de M01, frequência 0,25% menor. | `#5296fd` |
| M06 | Caçaluz. Clarão de alcance curto que se curva em direção ao inimigo visível mais próximo. | `#ffc724` |
| M07 | Cinco brasas luminosas em leque, com origens distintas e duração de 0,25 s. | `#fa6a0a` |
| M08 | Garganta de Dragão. Jato crescente, cone de até 128 px, dano a cada 0,1 s e dissipação sem dano ao soltar. | `#ffd541` |
| M10 | Presas Rubras. Duas lâminas partem separadas e podem acertar o mesmo alvo ao se cruzarem. | `#f53d61` |

As receitas continuam no espaço lógico 32×32, mas a apresentação usa texturas geradas em 96×96, filtro Linear e rotação contínua. `visual_scale=0.6` reduz as cabeças em 40% sem alterar dano, alcance ou colisões. O desenho usa três tons: borda derivada da cor principal, corpo saturado e núcleo `#f6ede5`. A borda colorida substitui o contorno quase preto; suavização, transparência e luz produzem tons intermediários na tela. A receita de referência 32×32 mantém a paleta original para inspeção. O cenário conserva seu filtro pixel art.

Rastros curtos afinam e desaparecem progressivamente. M05 e M07 usam sprites PNG luminosos com a mesma silhueta. O laser tem corpo de 2,1 px, núcleo de aproximadamente 0,75 px e halo discreto. A Garganta de Dragão usa partículas pixeladas de chama e fagulhas em duas camadas. O fogo sai amarelo e passa por laranja e vermelho até se dissipar. Impactos usam faíscas finas e anéis suaves com fade.

Campos visuais: `shape`, `shadow_color`, `body_color`, `core_color`, `trail_length`, `halo_size`, `halo_opacity`. Campos físicos e nativos: `hit_radius`, `blast_radius`, `spread_degrees`, `attached_duration`, `dot_interval`, `dot_damage`. Campos de canal: `reach`, `start_half_width`, `end_half_width`, `infusion_interval`. Mudanças estruturais exigem recarregar a cena para refazer o cache.

`homing_range` define a distância de busca da Caçaluz. Presas Rubras (M10) usa `muzzle_spread` para separar as lâminas na saída e `cross_distance` para definir o ponto de encontro.

O controlador local do portador compõe os equipamentos por `CardCombatRuntime.copy_loadout()`, substitui somente a Manifestação e preserva Infusão/Mutação. Cada emissão captura seu `CardAttack`; balas no ar mantêm modelo, dano e autoria após trocar de arma. A geração do runtime impede que balas antigas ativem a Mutação recém-equipada. DOT e explosões nativas secundárias não redisparam Infusão. Canais mantêm limites de Infusão por código (M04 0,5 s; M08 0,3 s), sem reiniciar ao soltar ou trocar de alvo.

A fábrica de texturas pertence à cena, compartilha os frames entre tiros e limita o cache a 128 entradas (até 4,5 MiB de pixels). O runtime usa quatro fases por modelo e rotaciona os desenhos em tempo de apresentação; seis modelos ocupam no máximo 24 texturas. Há quatro pares reutilizáveis de brilho no chão e PointLight2D. Os brilhos do chão também funcionam com o solo unshaded, enquanto os núcleos conservam as cores sob a exposição equilibrada. Não é adicionada uma luz por bala. Asterion e Room_1 usam os mesmos executores e receitas do mundo aberto.

Código: `scripts/combat/manifestations` separa dados, equipamento, fábrica, projéteis e canais; `scripts/visual/weapons` gera frames, rastros, impactos e iluminação. Não há autoload novo nem alterações no LDtk.

Validação: `tools/equipment_menu_regression.gd` cobre o menu real, as seis cartas, a animação e cor da arma, os canais e a transferência de equipamento nas quatro cenas. `tools/procedural_weapons_regression.gd` cobre mouse, paletas, snapshots, cadência, explosão, DOT, paredes, cone e liberação do canal. `tools/procedural_weapons_capture.gd` gera capturas no mundo real e uma galeria em 1×/3× em `output/procedural_weapons`. A referência visual é [Raining Blood: Hellfire](https://store.steampowered.com/app/2147530/Raining_Blood_Hellfire/), adaptada ao cenário roxo e aos espíritos claros.
