# Golem elemental — boss do altar inferior direito

As cinco folhas `Golem_1_*.png` permanecem intactas. Os frames de 90×64 px estão em `frames/<ice|fire|lightning>/<idle|walk|attack|hurt|die>/`. Cada elemento possui 46 frames, totalizando 138 PNGs. O pivô dos pés é `(45,64)`, comum a todas as poses. `sprite_map.json` registra os hashes das fontes, contagens e paletas.

Somente as quatro cores dos cristais e olhos e o azul claro extra da morte mudam. A pedra, o alpha, o contorno e os frames claros de hurt são preservados. A versão ice reproduz os pixels originais. Os recursos em `resources/enemies/elemental_golem/` incluem as animações completas e os clips:

| Clip | Poses da folha attack, contagem a partir de 1 |
| --- | --- |
| cast | 6, pose isolada para referência |
| charge | 1–6, preparação de 0,58 s |
| slam | 6–11, 1–5, repetido na cadência de cada salva |
| jump_prepare | 3, 4 |
| fall | 7 |
| land | 8–11 |

O mapa autoritativo está em `scripts/bosses/elemental_golem/attack_frames.gd`, reproduzido em `sprite_map.json` pelo preparador. As poses são contadas a partir de 1:

| Pose de attack | Ação |
| --- | --- |
| 1 | Pronto, braços em repouso |
| 2 | Antecipação do movimento |
| 3 | Início da elevação dos braços; também prepara o pulo |
| 4 | Elevação dos braços; também prepara o pulo |
| 5 | Braços chegando ao alto |
| 6 | Braços no alto, início de cada ciclo de golpe |
| 7 | Contato com o chão: libera uma salva elemental |
| 8 | Continuação do impacto, braços no chão |
| 9 | Início da recuperação |
| 10 | Recuperação do corpo |
| 11 | Retorno à postura de repouso |

A rajada percorre todas as poses em ciclo, começando pela 6 para aproveitar o fim da preparação. Cada ciclo dura 0,82 s no gelo, 0,62 s no fogo e 0,72 s no raio. O mesmo relógio de física escolhe a pose e libera os projéteis na pose 7, sem animação independente ou disparos entre os impactos. Os projéteis nascem junto às mãos no chão. O raio solta uma bola por impacto, alternando levemente a direção, a 132 px/s; a cadência espaçada permite ler o golpe pesado do golem. Saltos continuam usando seus próprios clips, e o especial protegido mantém idle.

`die` tem 13 células na fonte, mas a 13 é totalmente transparente. Os SpriteFrames de gameplay terminam na pose 12, último frame visível. Ao concluir a animação, essa textura vira `ElementalGolemRemains`, um Sprite2D sem colisão no local, escala e orientação da derrota. O objeto fica na sala sem desaparecer, inclusive após tentar novamente com o boss já vencido, e é liberado ao sair. Uma nova visita à sala vencida não reproduz a morte nem recria os destroços.

`tools/prepare_elemental_golem.gd` extrai os frames; após importar os PNGs no Godot, executá-lo com `-- --resources` atualiza os três SpriteFrames. A cena jogável é `scenes/bosses/elemental_golem_arena.tscn`.

## Estudos de cor

Foram usados dois edits no ImageGen integrado, salvos em `output/elemental_golem/references/fire_color_study.png` e `lightning_color_study.png`. Como os estudos ampliaram o canvas, os PNGs de gameplay usam as cores normalizadas sobre os pixels das fontes, preservando exatamente a geometria original.

Prompt de fogo: “Edit target: the attached existing golem attack sprite sheet. Make a FIRE elemental variant. This is a strictly palette-only sprite edit. Preserve the 11 poses, their exact positions and dimensions, every original silhouette, all transparent space, and the dark purple-blue stone body pixels unchanged. Recolor ONLY the cyan/blue crystal spikes and the tiny glowing eye accents into amber orange, bright flame orange and pale warm yellow highlights. Do not add flames, do not redraw the golem, do not add effects, do not change the frame count or sheet layout. Crisp pixel art, actual transparent background. Preserve the original 1 pixel grid if possible.”

Prompt de raio: o mesmo pedido, com “LIGHTNING elemental variant” e cristais em “saturated golden yellow and pale lemon-white highlights”, sem adicionar raios ou efeitos. A dimensão correta da fonte é 990×64 px; a organização final usa 11 células de 90×64.
