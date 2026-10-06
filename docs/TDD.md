# TDD — estrutura técnica

Referência do funcionamento atual, verificada contra cenas, scripts e recursos. Intenção de design fica no [GDD](GDD.md); instalação, edição e Git ficam no [guia](GUIA.md). Não usar documentos de `old` como contrato de implementação.

## Projeto e entradas

[project.godot](../project.godot) usa Godot 4.7, renderer Compatibility, viewport 480 × 270, stretch `canvas_items` e filtro de textura nearest. A cena inicial é o tutorial, não uma cena vazia. O cursor global é o autoload `GameCursor`.

| Cena | Função |
| --- | --- |
| [tutorial_arena.tscn](../scenes/tutorial_arena.tscn) | Introdução, horda, Asterion e saída. |
| [merchant_corridor.tscn](../scenes/merchant_corridor.tscn) | Corredor, Tin, acesso ao treino e ao fim do corredor. |
| [merchant_platform.tscn](../scenes/dungeon/merchant_platform.tscn) | Sala de treino e preview de Manifestação. |
| [ldtk_arena.tscn](../scenes/dungeon/ldtk_arena.tscn) | Arena carregada do mapa LDtk. |

`Tab` mantém os atalhos de desenvolvimento: confronto com Asterion → corredor do mercante → arena LDtk no final do corredor. Não é um sistema de seleção de níveis da progressão final.

## Controle, encontro e diálogo

[player.gd](../scripts/player.gd) concentra movimento, dash e vida, emitindo sinais de dano e derrota. Referência de combate: movimento 82 px/s, dash 330 px/s durante 0,16 s, recuperação de 0,65 s e vida máxima 60. O corredor tem movimentação própria; não assumir a mesma velocidade em todas as cenas.

[tutorial_encounter.gd](../scripts/tutorial_encounter.gd) controla as fases de introdução, revelação da arma, horda, retorno, desafio, boss, vitória e derrota. A primeira horda dura 35 s; não descrevê-la como uma sequência fixa de ondas antigas. O tutorial equipa a Manifestação `preview/M01.tres` sobre a combinação inicial.

[tutorial_completion.gd](../scripts/tutorial_completion.gd) controla rendição, prioridade da derrota de Nox, recompensas uma vez por tentativa e transição para o mercante. As recompensas ficam em metadata `tutorial_rewards` do jogador; isso não constitui inventário persistente compartilhado com Tin.

O [sistema de diálogo](../tools/dialogue%20system/dialogue_box.tscn) usa `DialogueSpeaker`, `DialogueLine`, `DialogueChoice` e `DialogueSequence`. `start_dialogue(sequence)` inicia a apresentação; `dialogue_event_requested` entrega eventos à cena e `dialogue_finished` devolve o controle. `E` completa o texto e depois avança; `W/S` ou setas selecionam respostas e `E` confirma. O retrato é opcional e a fonte é Fixedsys Excelsior. As falas do tutorial e de Tin ficam em [resources/dialogue](../resources/dialogue).

## Cartas e ataques

[CardCombatRuntime](../scripts/cards/card_combat_runtime.gd) mantém a execução da combinação equipada. Recursos de carta descrevem parâmetros; timers, heat e estado de combate não devem virar estado global compartilhado de um `.tres`. O ataque conserva a origem da combinação para atribuir dano e eliminações corretamente.

[BoosterShooter](../scripts/combat/booster_shooter.gd) dispara a Manifestação. A Infusão acrescenta consequências conforme os eventos permitidos; uma reação secundária não deve reativar a mesma cadeia sem limite. A Mutação inicial não está equipada; Coração da Fúria é um recurso de teste opcional.

| Base / preview | Comportamento relevante |
| --- | --- |
| M01 no tutorial/treino | Dano 3, intervalo 0,18 s, velocidade 180 px/s, duração 5 s e um ricochete em parede com +75% de velocidade. |
| M02 | Massa com explosão; dano experimental 7,5, não padrão aprovado. |
| M03 | Cone contínuo com heat, bloqueio por sobreaquecimento e cadência de dano; não implementa medo nativo. |
| M04 | Laser contínuo com limites de frequência para a Infusão. |
| M05 | Brotos perseguidores, até três, com explosão única; sem DOT nativo. |
| M06 | Espinhos que permanecem e causam DOT; a Infusão não reaparece em cada tick. |
| M07 / M08 | Bola de fogo / emissor contínuo experimental, com janelas próprias de acerto. |

Os previews estão em [resources/cards/preview](../resources/cards/preview). O recurso inicial antigo de slime possui defaults diferentes: não transportar sua duração de 1,4 s para o M01 atual do tutorial. A sala usa `Espaço` para trocar o preview e `Shift` para dash; não representa desbloqueio das oito cartas em uma run.

## Inimigos e navegação

As famílias de IA estão em [scripts/ai](../scripts/ai): observação e decisão no núcleo; sensores de mundo e navegação na integração; execução física nos controladores. Minotauro e Asterion já usam essa estrutura — os estudos anteriores que dizem não haver integração estão defasados.

[EnemyNavigationGrid](../scripts/ai/integration/enemy_navigation_grid.gd) compartilha AStarGrid2D em células de 8 px, com diagonais sem cortar cantos e mapas por raio/máscara. A observação não deve modificar o mundo. Geometria dinâmica precisa atualizar ou invalidar a navegação; não presumir reconstrução automática de qualquer obstáculo.

[minotaur.gd](../scripts/enemies/minotaur.gd) tem 18 de vida e comportamento comum/fortalecido. Asterion tem 270 de vida, fases de vulnerabilidade e Skybreaker com antecipação, voo, queda, impacto e recuperação. A rendição encerra spawns e ataques restantes; a apresentação do trono e o corpo do ator não são dois inimigos.

## Mapas LDtk

A fonte autoral é [monster_booster.ldtk](../monster_booster.ldtk). O arquivo contém definições e níveis internamente (`externalLevels=false`); [ldtk_arena.gd](../scripts/dungeon/ldtk_arena.gd) lê `levels[].layerInstances`. O loader atual **não carrega arquivos de nível externos `.ldtkl`**.

Os tilesets apontam diretamente para os PNGs em `assets`, sem cópia intermediária obrigatória. Paredes usam `assets/tiles/wall/wall_tileset.png`: tileset `Wall_16` e camadas WallsBack, WallsSides e WallsFront reconhecem cortes de **8 × 8**, apesar do nome legado. Piso e gameplay continuam em 16 × 16; escadas usam corte de 4 × 4. Não converter toda a base para 8 px.

O runtime monta TileMapLayers e a geometria de paredes/props. Texturas PNG soltas são rechecadas aproximadamente a cada 0,3 s; alterações no JSON do mapa exigem reentrada/recarregamento da cena. Mudança de tamanho, layout ou ordem do atlas não equivale a uma simples troca de pixels e precisa preservar coordenadas e revisar a pintura.

| Camada / entidade | Contrato |
| --- | --- |
| Gameplay: MapLimit / DashGap / DoorBlock / Start / End | Limite físico, vão de dash, bloqueio de porta, início e saída. End emite sinal; não escolhe outra cena sozinho. |
| DoorDash | Região redimensionável de vão, equivalente ao DashGap pintado. Atravessar exige dash; andar ou terminar o dash no vazio retorna ao ponto seguro sem dano de vida. Paredes continuam bloqueando. |
| Leaves | Primeiro plano, Z absoluto 1000: cobre atores, projéteis e outros props, mas não HUD. Sem colisão, halo ou luz própria. |
| AmbientArea | Região exclusivamente visual para aparições animadas; não cria hitbox nem interação. |
| NoxStart / demais marcadores | NoxStart define o início. Tin, MinotaurSpawn e outros marcadores não são uma fábrica automática de NPCs. |

Com o dash atual, o deslocamento nominal é cerca de 53 px; testar vãos de 16–32 px com piso seguro dos dois lados, sem confundir a distância nominal com garantia de travessia.

### AmbientArea

[ldtk_ambient_areas.gd](../scripts/dungeon/ldtk_ambient_areas.gd) agenda aparições somente em regiões visíveis, com no máximo duas simultâneas, atrás do mapa e sem física. Respeita a pausa da árvore. Sem arte vinculada, a região fica invisível.

Campos: `AnimationId`, `FramesFolder`, `FPS` (12), `MinDelay` (6 s), `MaxDelay` (18 s), `Chance` (0,6), `RepeatCount` (1), `Scale` (1), `FlipX`, `FlipY` e `Enabled`. Os nomes servem de contrato com as definições LDtk. Os frames PNG da pasta têm ordenação numérica natural; também é possível ligar um `SpriteFrames` com `bind_animation(id, frames)`. Não gerar placeholders visíveis para regiões ainda sem animação.

## Apresentação, HUD e iluminação

Os perfis [tutorial_lighting.tres](../resources/visual/tutorial_lighting.tres), [merchant_lighting.tres](../resources/visual/merchant_lighting.tres) e [projectile_world_style.tres](../resources/visual/projectile_world_style.tres) separam aparência de dano e física. Tutorial e treino compartilham o tratamento dos tiros: sombras vinho/roxo, highlights claros e brilho contido, preservando a cor funcional.

No tutorial, as luzes locais acompanham as duas crateras, correntes e boss; sem feixes explícitos nem luz central ampla. No corredor, a modulação escura destaca dois neons, água e Tin. As nuvens continuam como elemento visual; não são a fonte dos feixes removidos. As folhas LDtk não recebem uma luz decorativa própria.

[player_life_bar.gd](../scripts/ui/player_life_bar.gd) usa sprites da barra e empty, seis blocos, verde `#2cf7a3`, sem números e com nearest. O tamanho reduzido é separado do tamanho do atlas; cruzar um bloco dispara aviso vermelho breve. [boss_life_bar.gd](../scripts/ui/boss_life_bar.gd) usa a moldura de Asterion, tamanho de exibição 260 × 29 e nome centralizado acima, com as três cores de redução definidas no GDD.

Não reintroduzir réplicas fantasma dos projéteis nem o acerto azul legado do tutorial. Efeitos devem acompanhar o evento de combate real, sem aparentar tiros adicionais.

## Boosters: funcionamento e limites

[booster_viewer.gd](../scripts/booster_viewer.gd) tem estados IDLE, OPENING e CARDS. A abertura atual é por clique, consome o contador local imediatamente e dura 1,45 s, com três frames de rasgo. A stack começa a aparecer antes do fim do rasgo. As três imagens apresentadas são placeholders fixos; não há sorteio completo das coleções nem inventário persistente integrado às recompensas do tutorial.

O cursor global usa CanvasLayer 90 e o viewer usa 110; a cobertura do cursor pelo viewer exige ajuste ao implementar o slash. O corte guiado pelo mouse e o burst de partículas entre rasgo e stack estão **somente propostos**. Componentes sugeridos: controlador do gesto, efeitos de abertura e perfil visual; confirmar o corte uma vez antes de consumir o pacote. Não existem implementações desses componentes por este documento.

## Verificação

Regressões ficam em `tools` e `tests`; algumas representam experimentos ou caminhos antigos, não uma suíte integral garantidamente verde. Exemplos ativos: [ldtk_ambient_regression.gd](../tools/ldtk_ambient_regression.gd), [ldtk_columns_regression.gd](../tools/ldtk_columns_regression.gd), [player_life_bar_regression.gd](../tools/player_life_bar_regression.gd), [tutorial_tab_skip_regression.gd](../tools/tutorial_tab_skip_regression.gd) e [tutorial_completion_regression.gd](../tests/tutorial_completion_regression.gd).

Após mudar comportamento: validar parsing/importação, executar a regressão correspondente e verificar a cena visualmente. Ao exportar, incluir o `.ldtk` e demais dados não reconhecidos automaticamente como recursos; verificar o fallback das texturas importadas sem depender de PNGs soltos no diretório de desenvolvimento.
