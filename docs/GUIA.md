# Guia do projeto

## Onde procurar

- [README](../README.md): apresentação da ideia, sem diário de implementação.
- [One-page](ONE_PAGE.md): visão geral curta de conceito, características e direção artística; sua versão visual é gerada em `output/pdf`.
- [GDD](GDD.md): intenção, regras, identidade e catálogo de estudo.
- [TDD](TDD.md): cenas, responsabilidades, contratos e limites reais do código.
- `docs/old`: originais preservados e estudos históricos, fora da documentação ativa e do Git.

Para decidir uma mudança, consultar o GDD; para implementá-la, conferir o TDD e os recursos reais. Se houver divergência, verificar o código e registrar a decisão no documento responsável, sem criar outra cópia do mesmo assunto.

## Abrir e trabalhar

1. Obter o repositório com `assets`, `resources`, `scenes`, `scripts`, `tools`, `tests`, `project.godot` e `monster_booster.ldtk`.
2. Abrir `project.godot` no Godot 4.7. A inspeção desta base usou 4.7.1; alinhar a versão do time antes de atualizar o projeto.
3. Executar o projeto para entrar no mundo aberto (`Room_2`). `Enter` abre a mesa de cartas. `Tab` oferece os atalhos de desenvolvimento descritos no TDD.
4. Para mapas, instalar o [LDtk pelo site oficial](https://ldtk.io/download/) e abrir `monster_booster.ldtk`. A base usa formato JSON 1.5.3; não é necessário levar o programa instalado junto com o repositório.

O editor Godot recria `.godot` localmente. Não remover PNGs originais nem arquivos `.uid`/presets `.import` para “limpar” o projeto: são diferentes do cache gerado.

Os seis altares de horda do mundo aberto usam a escala escolhida de +50% (1,5×): 96×96 px, com relevo de 6 px, área de apoio e ativação acompanhando o tamanho. O altar do tutorial permanece em 64×64 px e relevo de 4 px. A cena temporária de comparação e seu atalho F7 foram removidos.

### Portal final e paletas do mundo

O portal final fica no centro da parte superior do castelo, entre os altares superiores. O altar esquerdo permanece em (432,448); o direito e sua arena foram alinhados em (2336,448), com o portal em (1384,288). Cada um dos seis altares concluídos acende quatro das 24 runas em laranja. A estática branca com fundo transparente aparece quando todos estão concluídos; a viagem para a batalha final ainda não existe. O portal usa somente `portal1.png`; os sprites de escadas foram retirados e as subidas mantêm o terreno e a física existentes.

Os insetos compartilham corpo malva `#D2AEC8`, sombra `#70526F` e detalhe `#F0E3EB`. Slimes usam corpo menta `#90DDD0` e sombra azul `#315767`; Flying Skull conserva o laranja e creme originais. As trocas de cor acontecem no jogo, inclusive nos restos dos inimigos, preservando os PNGs.

### Mesa de cartas

No mapa principal, `Enter` abre `scenes/cards/card_table.tscn` e pausa o mundo. As 24 cartas jogáveis e a prévia do Grito de Banshee começam em três pilhas, com Manifestação à esquerda, Infusão no centro e Mutação à direita. Clique na pilha para retirar uma carta, arraste direto da pilha ou use **Desempilhar todas**. Depois, arraste as cartas pela mesa e clique sem arrastar para examiná-las. A carta examinada sobe, fica reta, acompanha suavemente o mouse nas bordas e pode ser arrastada. Outro clique nela devolve a carta à posição anterior na mesa. `Esc` devolve a carta examinada, e `Enter` ou **Voltar** fecha a mesa e retoma o mapa. `Esc` também fecha quando nenhuma carta está em destaque. [Catálogo de cartas](CARTAS.md)

As cartas usam a base nativa `assets/cards/base/base_4x.png` em 208×320. Com Python e Pillow instalados, executar `python tools/build_card_labels.py --preview` gera as 25 capas da mesa, a máscara de borda e o recorte usados pelo jogo. O mapeamento dos textos fica em `tools/card_labels_layout.json`. `python tools/build_card_labels.py --check` valida o lote sem gravar imagens.

A apresentação adapta a projeção e o amortecimento da antiga abertura de boosters e o reflexo dependente do ângulo do exemplo em `tools/holographic-card-vfx`. Olho de Beholder tem borda holográfica roxa, Ovo de Slaad verde e Mandrágora de Bolso dourada. As três candidatas vêm de `docs/old/documentacao/CARTAS.md` e estão selecionadas para comparação visual. Cores e seleção ficam em `resources/cards/card_table_finishes.json`; reabrir a mesa após editar esse arquivo. O acabamento acompanha a inclinação e permanece restrito à moldura externa.

### Equipamento durante o jogo

Pressione **I** durante o jogo para abrir a troca de cartas, inclusive no meio de uma horda. O jogo pausa enquanto o menu estiver aberto. Clique no espaço e depois na carta para equipar. Infusão e Mutação também podem ser removidas. Pressione **I** novamente para fechar e retomar o jogo. **Esc** volta aos espaços e depois fecha. A equipagem usa o mesmo componente nas quatro cenas jogáveis e acompanha as transições. **Fragmentos de Basilisco** (M05) e **Garganta de Dragão** (M08) aparecem no espaço de Manifestação.

**F** aciona a Mutação equipada quando ela é ativa: Mandrágora de Bolso ou Doppelganger. O canto inferior esquerdo mostra o comando e a recarga. As outras quatro Mutações são passivas. **E** continua sendo o botão de interação com estruturas e diálogos.

As Manifestações usam a mesma implementação no mundo aberto, altar, Asterion e golem. Disparos com projétil reproduzem os cinco frames originais da arma com a cor principal do projétil. O feixe de Beholder e o jato da Garganta de Dragão continuam enquanto o botão do mouse estiver pressionado. Trocar de cena conserva a Manifestação equipada. Reiniciar a partida restaura o conjunto inicial.

## LDtk: o que distribuir

**Recomendação:** versionar o arquivo `.ldtk`, os PNGs originais e os scripts auxiliares. Instalar o editor separadamente. As definições de tilesets, entidades, campos, camadas e a pintura já estão no arquivo do projeto, não em uma instalação personalizada do LDtk. Essa separação segue a [estrutura oficial do JSON](https://ldtk.io/docs/game-dev/json-overview/).

Um configurador/launcher portátil pode ser uma melhoria posterior: localizar Python e LDtk, conferir versões e fontes e abrir o projeto existente. Não precisa recriar mapas nem instalar outro editor em cada clone. O launcher atual ainda não é portátil; sua limitação está abaixo. Não redistribuir o `.exe` unsigned bloqueado nem desativar a segurança do Windows.

Níveis externos podem reduzir conflitos quando várias pessoas editarem salas, mas **não ativar essa opção agora**: o loader Godot atual só lê níveis internos. Antes seria necessário adaptá-lo e testar o formato [`.ldtkl` separado](https://ldtk.io/docs/game-dev/json-overview/optional-separate-levels/).

### Alterei um PNG e o editor não mudou

1. Confirmar que foi editado o original apontado pelo tileset — por exemplo `assets/tiles/wall/leaves.png`, `assets/tiles/wall/decor/column_round.png` ou `assets/tiles/wall/wall_tileset.png`.
2. Salvar e fechar o LDtk antes de executar a atualização. O helper se recusa a escrever com o editor aberto para não perder alterações da pintura.
3. Conferir com `AtualizarLDtk.cmd --dry-run`; aplicar com `AtualizarLDtk.cmd --refresh-only` e abrir novamente o mapa. Dois cliques executam a atualização e tentam abrir o editor instalado no caminho padrão.
4. Verificar dimensões e layout do atlas. Reordenar ou redimensionar sprites exige revisar o mapeamento; atualizar pixels não deve recriar a sala.

O helper [refresh_ldtk_sources.py](../tools/refresh_ldtk_sources.py) limpa o cache de imagem dos tilesets, atualiza dimensões e preserva coordenadas dos tiles. Quando precisa alterar o mapa, salva backup em `ldtk_backups`. “Atualizar” aqui significa sincronizar o **projeto com os PNGs**, não baixar uma versão nova do programa LDtk.

`AtualizarLDtk.cmd` procura o Python no runtime local do Codex. Em outra máquina, usar Python com Pillow instalado e rodar, na raiz do projeto:

```powershell
python -m pip install Pillow
python tools/refresh_ldtk_sources.py --summary --dry-run
python tools/refresh_ldtk_sources.py --summary
```

Esses comandos não dependem do Codex. Abrir o `.ldtk` manualmente se o editor estiver em um caminho diferente do padrão. Não executar os builders/configuradores para atualizar uma pintura existente: eles tratam criação ou migrações específicas, não o fluxo cotidiano.

No jogo em desenvolvimento, os PNGs são rechecados pelo runtime; alterações na pintura/JSON exigem recarregar a cena. Isso é diferente do cache de visualização do editor LDtk.

### Contratos de autoria do mapa

- Paredes: cortes 8 × 8 somente no tileset e camadas de walls; gameplay/piso continuam 16 × 16.
- Leaves: cobertura visual na frente de atores e props, sem física ou luz própria.
- Gameplay: colisão, travessia, fluxo da sala e perigos separados em grupos. `Start` define entrada/respawn; `DashGap` marca o vão, com piso seguro antes e depois.
- GameplayAreas: `DashGapArea` define vãos; `DoorControl` associa DoorBlock a uma condição; `GameplayTrigger` altera essa condição quando o jogador entra.
- AmbientArea: posição, temporização e referência para animação decorativa; sem sprites vinculados, nada aparece.
- WaterArea: superfície delimitada do modo manual, com tamanho, preset e máscara. O mar automático da arena dispensa essa entidade; água não muda colisão ou regras de travessia.
- Personagens, portas e trono foram retirados do modelo LDtk. Nox continua sendo criado pela cena Godot, usando `Start`; os assets das cenas existentes permanecem no projeto.

### Organização do modelo LDtk

As camadas são apresentadas nesta ordem: `Gameplay`, `GameplayAreas`, `WaterAreas`, `AmbientAreas`, `Leaves`, `ObjectsSquare`, `ObjectsRound`, `ObjectsStair`, `WallsFront`, `WallsSides`, `WallsBack`, `Borders`, `WaterBanks`, `Floor` e `PlatformUnderside`. Cada camada possui descrição no editor. Os objetos antigos Front/Back foram reunidos por fonte: todos compartilham Z=2 e ordenação pela base Y na Godot. Os tilesets continuam separados porque quadrados, redondos e escadas usam PNGs e grades próprios.

`Borders` usa `bordas.png` na grade de 8 px e gera bloqueio físico automaticamente nos pixels opacos. Os 10 stamps, tamanhos nativos e uso estão no [mapa das bordas](LDtk_BORDAS.md). Não é necessário duplicar essas peças em Gameplay/Solid.

`Gameplay` concentra os valores antes divididos entre Gameplay e Collisions:

| Grupo | Valores | Utilidade |
| --- | --- | --- |
| Colisao | `MapLimit` (1), `Solid` (6), `DoorBlock` (3) | Limite do mapa, sólido explícito e barreira inicialmente fechada, liberada por condição. |
| Travessia | `DashGap` (2) | Vão que exige dash e retorna ao ponto seguro ao cair. |
| FluxoDaSala | `Start` (4), `End` (5) | Entrada/respawn e evento de fim da sala. |
| Perigos | `Hazard` (7) | Zona reservada; atualmente bloqueia passagem, sem dano automático. |

No LDtk 1.5.3, grupos/valores IntGrid não têm campo de descrição individual. A descrição da camada Gameplay explica cada valor; as áreas utilitárias têm descrições próprias. `DoorBlock` mantém o código numérico 3 do antigo EncounterBlock. Pinte o bloqueio em Gameplay e use DoorControl/GameplayTrigger em GameplayAreas para ligar sua condição; ver [DOOR_BLOCKS.md](DOOR_BLOCKS.md). A Godot mostra uma faixa âmbar enquanto a porta está fechada.

As águas que estavam em `Entities` foram movidas para `WaterAreas`, preservando os IIDs, tamanhos, campos e posições. A camada `Entities`, os marcadores de personagens, as camadas/paletas de portas/trono e a camada `Collisions` foram removidos. O início é pintado com Start; nenhum personagem é colocado pela paleta.

Para aplicar essa organização a uma cópia antiga, salvar e fechar o LDtk e executar `python tools/clean_ldtk_model.py --dry-run`, depois `python tools/clean_ldtk_model.py`. A limpeza cria backup, é idempotente e recusa sobreposições ambíguas de regras em vez de sobrescrevê-las. Usar `python -m unittest discover -s tools -p test_ldtk_cleanup.py -v` e `godot --headless --debug --ignore-error-breaks --path . --script res://tools/ldtk_cleanup_regression.gd` para verificar o contrato.

### Tileset de chão roxo

[purple_floor_v1.png](../assets/tiles/floor/purple_floor_v1.png) é um atlas novo de **256 × 256 px**, com **256 tiles de 16 × 16**, sem margem ou espaçamento. Usa seis cores discretas de vinho/roxo, com formas simplificadas: `#25131A`, `#362030`, `#3D253B`, `#45283C`, `#533048` e `#6F4358`. O PNG original de piso e a pintura dos mapas continuam como estavam.

Cada par de linhas contém uma família, de cima para baixo: terra lisa, cascalho, terra rachada, vegetação rasteira, lajes, bordas de caminho, cantos/composições e pedras quebradas. As coordenadas do atlas começam em zero. Usar [purple_floor_tileset_16.tres](../resources/purple_floor_tileset_16.tres) em TileMapLayer; cada tile identifica sua família em `ground_family`. A pintura é manual, sem colisão ou regras automáticas de terreno. Na importação de outro editor, configurar corte 16 px e espaçamento/margem zero.

Abrir [purple_floor_preview.tscn](../scenes/maps/purple_floor_preview.tscn) e executar com F6 para ver o atlas e um caminho montado com TileMapLayer. A prévia usa base de 640 × 360, filtro nearest e fundo vinho.

A arte foi criada com ImageGen integrado e preparada para resolução/paleta nativas com [build_purple_floor.gd](../tools/build_purple_floor.gd). A fonte gerada permanece em `assets/tiles/floor/source`, excluída da importação da Godot por `.gdignore`; os prompts, a paleta e o mapa das linhas ficam em [purple_floor_v1.json](../assets/tiles/floor/purple_floor_v1.json). Para reconstruir, executar o script com `-- --art`, importar o projeto e executar com `-- --resources`. Não trocar automaticamente o atlas de uma camada já pintada: os IDs/recortes desse atlas são próprios.

### Água procedural no LDtk

A Room_1 usa somente a luz **Equilibrada**, com raio-base de **30,8 px** (redução de 30%) e sem alternância por Backspace. A luz respira, cresce ao andar e contrai ao parar; há sombra de contato e bordas com brilho 1,65×. Ajustes estão em [ROOM_1_SETUPS.md](ROOM_1_SETUPS.md), com o mapa dos assets em [ROOM_1_AMBIENTE.md](ROOM_1_AMBIENTE.md). `Automatic Water` está desligado: sem WaterArea no LDtk, o fundo usa a cor padrão `#25131a`.

As salas também recebem a entidade **Warp** em GameplayAreas, usando o PNG autoral `assets/tiles/floor/warp.png` integral em **48×48**, com pivô central e no nível do chão. O modelo inicial contém uma chegada junto a cada Start; a Room_1 inicia com uma coluna branca em pixels, pulso de largura e materialização vertical em 0,6 s. A saída dura 0,4 s. Para ligar salas e outros arquivos de mapa, preencher TargetLevel, TargetWarp e TargetMap. Ver [WARPS.md](WARPS.md).

O projeto inicia atualmente em `scenes/bosses/elemental_golem_arena.tscn`, carregando `Room_4_Elemental`, com void preto e sem água. Piso, regras e marcadores dessa arena são editáveis no LDtk; ver [ROOM_4_ELEMENTAL.md](ROOM_4_ELEMENTAL.md). A cena `scenes/dungeon/ldtk_arena.tscn` continua carregando `Room_1`, com **Automatic Water desligado**. Somente WaterArea colocada no LDtk cria água nessa cena. O sistema de fundo automático continua disponível: ao habilitá-lo na Godot, o mar aparece nos espaços vazios e continua além do canvas, acompanhando a câmera, sem ajustar retângulos.

O terreno fica acima da água. Blocos totalmente opacos de Floor, PlatformUnderside e Walls não recebem malha de água; partes transparentes conservam o fundo. A espuma é criada automaticamente nas bordas desse terreno, incluindo ilhas e buracos internos. Objetos e folhas cobrem a água pela ordem de desenho, mas não geram praias em torno de suas silhuetas.

O script genérico tem `automatic_water=true`, mas a cena Room_1 o sobrescreve com false. `water_profile` aponta para [sea.tres](../resources/visual/water/sea.tres), e `shore_foam_enabled` permite desligar a espuma. Quando o mar automático está ativo, o perfil concentra cor, ondas, reflexos e espuma. As regiões de 256 px aparecem ao redor da câmera; recursos recentes e regiões preparadas antecipadamente ficam em um cache limitado. A leitura do terreno acontece no carregamento; depois de editar pintura/alfa dos PNGs, salvar e recarregar a arena para reconstruir o contorno.

`Sea` usa superfície contínua na resolução final, manchas suaves de água azul esverdeada mais saturada e brilhos pontuais com centros quase brancos e halo local. `reflection_style=GLINTS` substitui as linhas compridas da superfície por pequenos agrupamentos que aparecem e desaparecem em fases diferentes. O Voronoi permanece desligado; Lake/River continuam usando células. Nearest permanece nos sprites. As cores do corpo são âncoras com interpolações suaves; `sparkle_color` controla os centros dos reflexos. A espuma combina contato, chegada da onda e resíduo. A faixa rasa muda de largura; sombra de contato aparece somente em margem elevada. O campo local une cantos e margens próximas pelo mínimo de distância. A ocupação continua em blocos de 4 px; o campo tem amostras de 2 px.

Para ajustar o visual, abrir `sea.tres` pelo campo `water_profile` da arena:

Estado atual de trabalho: **brilhos e espuma estão temporariamente desligados**, com `sparkle_intensity=0` e `foam_opacity=0`. O fundo saturado, manchas, movimento e faixa rasa permanecem. Para retomar a versão anterior dos efeitos, usar `sparkle_intensity=1` e `foam_opacity=0,75`; os demais controles continuam configurados.

O fluxo atual aponta para a direita: `flow_direction=(1,0)` e `flow_speed_px_s=12`, aumentado de 2,4. Esse parâmetro acelera o deslocamento direcional dos ruídos; a deformação orgânica e o relógio de animação continuam com suas velocidades próprias.

- `reflection_style`: `GLINTS` é o Sea atual; `WAVES` conserva as cristas alongadas anteriores para outros perfis contínuos.
- `wave_strength`: variação das manchas no modo GLINTS; força das ondas no WAVES. `reflection_strength`: intensidade geral dos reflexos.
- Grupo **Sun glints**: `sparkle_color`, `sparkle_density`, `sparkle_spacing_px`, `sparkle_size_px`, `sparkle_intensity`, `sparkle_lifetime_s` e `sparkle_halo_strength` controlam cor, distribuição, tamanho, intensidade, duração e halo.
- Sea usa espaçamento 34 px, densidade 0,32, tamanho 1,55 px, duração-base 1,4 s e halo 0,5. Densidade/intensidade zero desliga os brilhos. O espaçamento deve ser pelo menos 12 vezes o tamanho, preservando o halo dentro de cada célula.
- No estilo WAVES, `wave_length_px` e `secondary_wave_strength` controlam comprimento e segunda família. `calmness` modula a presença dos reflexos nos dois estilos.
- `voronoi_strength`: detalhe de células; zero no Sea padrão. Ativar acrescenta custo por fragmento.
- `shallow_width_px` e `shore_tint_strength`: faixa mais clara perto da costa.
- `foam_color`, `foam_width_px`, `foam_reach_px`, `foam_opacity` e `shore_wave_period_s`: espuma e ritmo da onda de margem.
- `foam_coverage`, `foam_irregularity` e `foam_residue`: cobertura, variação e resíduo após a frente da onda. `foam_coverage=0` remove a espuma.
- `shore_shadow_strength`: sombra rasa de contato nas margens `Raised`.

Recarregar a cena após editar o perfil. Em ferramentas/runtime, `Water.apply_profile()` atualiza cores/intensidades sem perder malhas ou cache; alterações que mudam o alcance do campo invalidam esses recursos. Não é necessário ajustar áreas no LDtk. Para recuperar a aparência de três tons discretos, escolher Lake/River ou desligar `smooth_surface` no perfil; `pixel_size_px` só se aplica a esse modo.

Para exceções artísticas, colocar **WaterShoreOverride** na camada **WaterAreas** e estender o retângulo sobre a borda do terreno. A entidade classifica células da costa dentro da área; não cria água nem altera o piso. Sem exceção, Floor usa `Default` e Walls/PlatformUnderside usam `Raised`.

| CoastType | Resultado |
| --- | --- |
| `Default` | Espuma e faixa rasa padrão, sem sombra elevada. |
| `Rock` | Espuma mais presente e faixa rasa mais estreita, sem sombra elevada. |
| `Beach` | Espuma mais leve e faixa rasa mais larga, sem sombra elevada. |
| `Raised` | Espuma reduzida, faixa rasa estreita e sombra de contato. |
| `None` | Suprime espuma; mantém água e distância para a faixa rasa. |

`Priority` maior vence em áreas sobrepostas; em empate vence o maior IID em ordem alfabética. `Enabled=false` ou camada oculta ignora a exceção. A classificação da costa mais próxima acompanha o campo de distância, inclusive em `None`: espuma de outra margem não atravessa uma ilha para preencher o trecho desativado. A interpolação de 2 px suaviza a transição entre tipos. A área deve tocar as células do terreno que formam a costa; um retângulo solto no mar não define uma nova praia. Essas exceções pertencem ao mar automático; o modo manual conserva suas máscaras e acabamentos autorais.

O registro já está aplicado no mapa. Para outro mapa compatível: `python tools/configure_ldtk_water_shores.py --project caminho.ldtk --dry-run`, revisar e executar sem `--dry-run`. A migração adiciona somente a definição da entidade, com backup e proteção contra editor aberto ou edição concorrente. Não altera pintura, níveis ou instâncias existentes.

Os controles técnicos ficam em `WaterBackground`, separados do perfil: `cache_max_chunks=48` e `cache_budget_mb=12` limitam o cache inativo; as regiões visíveis são atendidas integralmente mesmo em teleporte. `prefetch_margin_chunks=1` e `prefetch_budget_usec=1500` preparam até uma região por quadro. Esse orçamento é suave: uma construção iniciada termina no mesmo quadro e pode excedê-lo em costas complexas. `combine_foam=true` compõe a espuma na superfície e é o padrão medido; desligar mantém a passagem separada para comparação. `Water.diagnostics()` informa uso estimado de recursos, acertos, descartes e construções. O cache é liberado ao sair da sala. As estimativas não incluem overhead da engine/driver.

As definições `WaterArea`, `WaterAreas` e `WaterBanks` e as águas já pintadas continuam no `.ldtk`. No modo automático, WaterArea não limita nem sobrepõe o mar. WaterBanks fica disponível para acabamentos artísticos adicionais. Para uma cena que precise exclusivamente de lagos/rios delimitados, definir `automatic_water=false` e seguir o fluxo manual:

1. Na Godot, abrir [water_demo.tscn](../scenes/visual/water_demo.tscn) e executar com F6 para ver lago contínuo em dois sprites, uma máscara irregular e rio.
2. No LDtk, selecionar `WaterAreas`, colocar `WaterArea` e redimensionar a região. O snap padrão é 16 px; o pivô fica no canto superior esquerdo.
3. Preencher `Preset` com `Sea`, `Lake` ou `River`. `MaskId=Rectangle` aceita qualquer retângulo positivo. `MaskId=Pond` exige **112 × 96 px**, o tamanho nativo da máscara incluída.
4. Para várias regiões da mesma superfície, usar o mesmo preset e, opcionalmente, o mesmo `SurfaceId`. O identificador permite detectar configurações divergentes; o padrão já compartilha coordenadas mundiais e relógio. `Enabled=false` desativa uma região.
5. Usar `WaterBanks` para pintar o acabamento acima da água. No modo manual, as margens continuam autorais; a espuma automática pertence ao mar de fundo.
6. Salvar o LDtk e recarregar a arena na Godot. O editor LDtk exibe a região de identificação; a animação é renderizada pelo jogo.

Os perfis [sea.tres](../resources/visual/water/sea.tres), [lake.tres](../resources/visual/water/lake.tres) e [river.tres](../resources/visual/water/river.tres) controlam a aparência. `flow_speed_px_s=0` conserva deformação/ondas; `animation_speed=0` congela superfície e espuma. Para criar um preset de mar automático, duplicar um perfil e atribuí-lo a `water_profile` na arena. Para usá-lo em entidades do modo manual, dar outro `preset_id` e registrá-lo em `WaterSurface.profiles`; `Preset` é String para permitir essa extensão sem migrar enums no mapa.

Máscaras novas são PNGs com alfa binário e tamanho nativo igual à entidade, nearest e sem mipmaps. Registrar cada textura em `WaterSurface.mask_catalog`, usando o mesmo ID em `MaskId`; preloads/catálogos explícitos conservam as dependências na exportação. Preset, máscara ou tamanho inválidos omitem a região e produzem um aviso com seu IID. Ajustes em perfis/catálogos exigem recarregar a cena; o refresh de PNGs em debug reaproveita o cache do mapa.

Para um mapa anterior a essa base, com o LDtk salvo e fechado:

```powershell
python tools/configure_ldtk_water.py --dry-run
python tools/configure_ldtk_water.py
```

O configurador mantém backup e pode ser executado novamente sem duplicar definições. Não usar o builder inicial para atualizar mapas pintados. Para verificar a integração e a renderização, com Godot no PATH:

```powershell
python -m unittest discover -s tools -p test_ldtk_water.py -v
godot --headless --debug --ignore-error-breaks --path . --script res://tools/ldtk_water_regression.gd
godot --windowed --debug --ignore-error-breaks --path . --script res://tools/ldtk_water_regression.gd -- --render
godot --headless --debug --ignore-error-breaks --path . --script res://tools/water_background_regression.gd
godot --windowed --debug --ignore-error-breaks --path . --script res://tools/water_background_regression.gd -- --render
python -m unittest discover -s tools -p test_ldtk_water_shores.py -v
godot --windowed --disable-vsync --debug --ignore-error-breaks --path . --script res://tools/water_quality_benchmark.gd -- --tag revisao --render
```

Os testes salvam capturas locais em `tmp/water_demo_480.png`, `tmp/water_demo_960.png`, `tmp/automatic_water_foam_960.png`, `tmp/water_room1_480.png` e `tmp/water_room1_960.png`. A posição do padrão permanece no mundo. Sea é contínuo; nos perfis discretos, zoom fracionário ainda influencia a rasterização dos pixels. Água/espuma não alteram a navegabilidade: editar Floor pode mudar as barreiras existentes por meio de FloorBoundary. Ao exportar, incluir o `.ldtk` nos dados do preset e testar o build; o projeto ainda não fornece um preset de exportação.

Adicionar `--sequence` depois de `--render` na regressão de fundo grava 48 frames de superfície em `tmp/water_quality_frames` e 48 de câmera em `tmp/water_motion_frames`, verificando cobertura e reuso no retorno. Captura também Room_1 em 1920 × 1080 e uma galeria dos cinco tipos de margem. A revisão de espuma/cache está em `output/water/evolution`: antes/depois, GIFs, JSONs de medição e `REPORT.md`. São apresentações locais, não texturas usadas pelo jogo. O benchmark usa um viewport isolado e não mede o FPS total da arena.

A revisão de brilhos/saturação fica em `output/water/glints`, com PNGs antes/depois e `after/room1_glints.gif`. `output/water/evolution` preserva a revisão anterior de espuma/cache e suas medições. Os brilhos usam o relógio comum, posição mundial e o shader da superfície, sem sprites individuais ou passe global de bloom; a espuma de margem continua separada conceitualmente. Suas fases são independentes por célula, e a posição só muda quando o brilho está invisível. Detalhes pequenos desaparecem gradualmente com o afastamento da câmera.

## Git e documentação

| Versionar | Manter local/ignorado |
| --- | --- |
| README, GDD, TDD, one-page e este guia | `docs/old`, capturas, estudos auxiliares e `output` gerado |
| `.ldtk`, PNGs e fontes autorais | Editor LDtk instalado, atalhos `.lnk`, backups LDtk |
| Scripts, recursos, cenas, `.uid`, presets `.import` | `.godot`, caches Python, builds e temporários |
| Regressões `.gd`, cenários `.json` e fixtures intencionais | Capturas PNG geradas na raiz de `tests` |

O `.gitignore` permite `GDD.md`, `TDD.md`, `GUIA.md` e `ONE_PAGE.md` dentro de `docs`. O one-page é uma apresentação derivada, não uma segunda fonte de regras. Novos documentos auxiliares ali ficam locais; incorporar decisões importantes aos três arquivos canônicos. Um arquivo já rastreado não deixa de ser rastreado só por entrar no ignore: revisar o diff, não remover coisas do índice indiscriminadamente.

Para gerar a apresentação visual do one-page, executar `tools/docs/build_one_page.py` com Python, ReportLab, Pillow e pypdf disponíveis. O conteúdo vem de `docs/ONE_PAGE.md`; o PDF de uma página fica em `output/pdf/Monster_Booster_One_Page.pdf`. A diagramação reaproveita as fontes do pitch arquivado ou Bahnschrift/Segoe UI locais, a paleta vinho/roxo e os sprites do projeto. O GDD e o TDD continuam sendo a referência para regras completas e implementação.

O arquivo `.ldtk` é fonte autoral, não cache. Revisar o diff junto dos sprites usados, evitando alterações automáticas de todo o mapa. Sem níveis externos, coordenar edições simultâneas do mesmo arquivo. Alterações de definição ou tamanho do tileset merecem revisão separada da pintura.

Preparar arquivos não significa publicá-los: commit e push exigem uma decisão explícita do responsável.

## Ciclo de atualização

1. Definir a regra no GDD e localizar o contrato correspondente no TDD.
2. Implementar somente o escopo combinado; preservar pintura, sprites e mudanças de outras pessoas.
3. Executar verificações adequadas e registrar limitações concretas, sem declarar sistemas prontos só porque existe uma cena.
4. Atualizar TDD para o comportamento real e este guia se mudou o fluxo de trabalho.
5. Revisar arquivos preparados e decidir a publicação separadamente.

Exemplo de regressão, com o executável Godot disponível no PATH:

```powershell
godot --headless --path . --script res://tools/ldtk_ambient_regression.gd
```

Escolher a regressão da alteração, não supor que todos os experimentos antigos são testes ativos.

## Resultado da revisão documental

Foram preservados 115 arquivos originais, incluindo textos, HTMLs, imagens, mapeamentos e scripts de documentação. Nenhum foi apagado. A organização do arquivo local é:

- `docs/old/documentacao`: estrutura anterior de `docs`, incluindo o GDD extenso e seus materiais.
- `docs/old/raiz`: README anterior e orientações LDtk que ficavam na raiz.
- `docs/old/arquivos`: notas de assets/cartas e documentação do sistema de diálogo, com caminhos de origem preservados.

Documentos que já estavam em pastas `old` permaneceram lá. O arquivo conserva os bytes originais; links históricos podem apontar para locais antigos e não são o fluxo ativo.

Foram consolidados os contratos ainda usados: tutorial/recompensas, cartas e previews, IA/navegação, diálogo, HUD, iluminação e mapas LDtk. Descrições de “base vazia”, mercante como cena inicial, ausência de IA integrada, duração antiga do tiro, mapas/atlas antigos e ausência de vida no boss foram substituídas por informações verificadas. Medições de sprites, capturas, estudos de câmera/projeção e catálogos extensos ficam como referência histórica; isso não remove os recursos de gameplay correspondentes.

`docs/old` não vai para o repositório. Manter backup dessa pasta em outro local se for necessário compartilhar ou preservar o histórico fora desta máquina; o Git conterá somente a documentação enxuta.
