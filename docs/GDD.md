# GDD — Monster Booster

Este documento define a proposta e as regras de design. O [TDD](TDD.md) distingue essas regras do que o código já executa; o [guia](GUIA.md) reúne o fluxo de trabalho. Valores de recursos e scripts são a referência para ajustes numéricos.

## Identidade

Roguelike de ação em visão superior, com combate bullet hell e combinações de cartas de monstros. Nox usa um Shooter guiado pelo mouse, dash duplo e parry para enfrentar os domínios dos Dark Lords; as cartas compõem seus poderes. O tom combina ambição, estranheza e humor: um pequeno invasor confronta criaturas muito maiores e arrogantes.

O combate deve ser legível, responsivo e permitir combinações distintas, sem depender de efeitos visuais para comunicar uma regra que não existe. Tin é a mercante; Asterion é o elite do tutorial, não um chefe morto ao final da introdução.

## Ciclo de jogo

Explorar uma sala → enfrentar hordas e elites → obter cartas e boosters → visitar uma câmara segura → abrir pacotes, reorganizar poderes e negociar → seguir para outro domínio.

Coleção, compra, venda de duplicatas e progressão entre runs fazem parte do design. A existência de imagens de cartas ou de uma tela de boosters não implica que esses sistemas estejam integrados ou persistentes.

## Cartas e combinação

O equipamento combina uma Manifestação, uma Infusão e uma Mutação. O conjunto inicial é Gotas de Slime + Núcleo de Golem, sem Mutação equipada.

| Tipo | Responsabilidade | Limite de interpretação |
| --- | --- | --- |
| Manifestação | Forma e comportamento do ataque | Não define sozinha toda a combinação. |
| Infusão | Consequências de ataque, acerto ou eliminação creditada | Não se limita a elemento ou cor. |
| Mutação | Habilidade, reação ou efeito sobre Nox | Não é automaticamente uma explosão do projétil. |

Efeitos precisam respeitar autoria do dano, cadências e limites de ativação. Dano secundário não deve iniciar uma cadeia infinita de Infusões. As regras particulares de cada carta precisam ser explícitas antes de entrar no catálogo aprovado.

As cinco Infusões e seis Mutações funcionam com cada Manifestação ativa, em qualquer combinação de uma carta de cada tipo. Efeitos já emitidos conservam sua origem após a troca. **F** é o botão de ação das Mutações; passivas não ganham uma ação adicional. Os valores de teste e os limites atuais estão no TDD.

Regras específicas aprovadas para esta implementação: I01 começa somente após um abate e encadeia explosões de raio fixo de 18 px, com danos 18 → 9 → 3 → 3, até não haver novo abate. I02 lança fragmentos com 15% do dano final do golpe que matou; I03 recupera 3% da vida máxima por abate creditado à arma. I04 equipa um disparo com Slaad a cada 6 s, controla temporariamente inimigos simples e exclui bosses. I05 alterna fogo, veneno e empurrão, com contornos vermelho, verde e amarelo.

U01 renova a velocidade em abates. U02 gera uma cobra ao receber dano de inimigo, com intervalo de 1,5 s e derrota após três ataques. U03 marca um alvo próximo com um círculo e causa dano em área após 0,25 s. U04 mostra a mandrágora sobre Nox e afasta inimigos ao pressionar F. U05 deixa fumaça venenosa roxa e verde durante o movimento. U06 deixa uma cópia ao pressionar F, torna Nox invisível por 1,5 s e bloqueia seus disparos; sua recarga de 30 s também governa a proteção automática contra dano letal, que restaura 10% da vida máxima quando disponível.

### Catálogo de estudo

Os identificadores abaixo organizam os conceitos; não indicam implementação completa, raridade definitiva ou aprovação de balanceamento.

| Manifestação | Infusão | Mutação |
| --- | --- | --- |
| M01 — Gotas de Slime | I01 — Núcleo de Golem | U01 — Coração da Fúria |
| M02 — Massa de Slime | I02 — Casca Estilhaçante | U02 — Pele de Medusa |
| M03 — Grito de Banshee | I03 — Fragmento de Odopi | U03 — Chão Carnívoro |
| M04 — Olho de Beholder | I04 — Ovo de Slaad | U04 — Mandrágora de Bolso |
| M05 — Brotos de Fungoide | I05 — Essência de Quimera | U05 — Glândulas de Lesma |
| M06 — Cauda de Manticora | — | U06 — Doppelganger |
| M07 — Coração de Efreeti | — | — |

M08, o lança-chamas de teste, usa temporariamente uma carta-base vazia para seleção ingame, além das 18 cartas do catálogo de estudo. Probabilidades dos boosters, raridades individuais e economia precisam de definição própria; não deduzir essas regras dos placeholders.

Para a prévia de acabamentos na mesa, o estudo arquivado em `docs/old/documentacao/CARTAS.md` indica Mandrágora de Bolso, Ovo de Slaad e Olho de Beholder como candidatas a destaque de coleção. Elas recebem bordas holográficas experimentais dourada, verde e roxa, respectivamente. A comparação visual permite avaliar essa direção enquanto a raridade definitiva permanece em estudo.

## Tutorial e Asterion

O tutorial apresenta movimentação, arma, combate, elite e recompensas em um encontro curto, de baixa dificuldade. Nox fala por símbolos; Asterion usa diálogos provocativos. As falas são mantidas nos recursos de diálogo, sem uma segunda transcrição neste documento.

Sequência de referência:

1. Após a horda inicial de `Room_1`, atravessar seu warp com `E`, chegar à arena do Asterion e conversar.
2. Apresentar o Shooter, movimentação, dash duplo e parry.
3. Enfrentar a primeira horda usando disparos e defesa; voltar a Asterion ao concluir.
4. Restaurar a vida de Nox, apresentar o Skybreaker e explicar o confronto de elite.
5. Enfrentar Asterion e seus minotauros fortalecidos.
6. Asterion se rende e permanece na cena; encerrar ataques e minions.
7. Mostrar recompensas e devolver o controle. Futuramente, um novo warp e o primeiro pedestal de abertura de boosters aparecerão perto do ponto da conversa; essa continuação ainda não está implementada. O corredor de Tin não faz parte desse percurso.

Diálogos e explicações de comandos avançam com `E`. A apresentação não deve manter dano ativo enquanto tira o controle do jogador. Se Nox e Asterion chegarem à derrota juntos, a derrota de Nox tem prioridade. No tutorial, perder reinicia o encontro.

A recompensa é concedida uma vez por tentativa: as duas cartas iniciais e três boosters, um de cada coleção, com três cartas por pacote. A última posição do primeiro pacote deve garantir uma Mutação comum. Não acumular um quarto booster pela regra genérica de recompensa de elite. O TDD registra o limite atual entre essa regra e a abertura visual.

## Segundo boss — Golem Elemental

Concluir o altar inferior direito do mundo aberto revela um warp para a arena do golem. Nove plataformas são separadas por pequenos vãos que o dash atravessa; o corredor de entrada liga o warp à plataforma inferior central. A arena é o level `Room_4_Elemental` no LDtk, com o piso original da dungeon, paredes do tileset existente e void preto, sem água. O corredor mede 224×384 px e os vãos mantêm 24 px. Cair fora do piso retira um quadrado completo da barra de vida e devolve Nox ao último local seguro da plataforma, com um segundo de invulnerabilidade contra ataques. O custo é um sexto da vida máxima, sem arredondamento: 10 pontos na base de 60. Se esse custo zerar a vida, ocorre a derrota normal, com as opções de tentar novamente na entrada ou sair para o mundo. O warp desbloqueado continua disponível ao retornar.

O golem muda de plataforma e anda sobre ela antes de disparar. Nunca realiza duas rajadas consecutivas na mesma plataforma. Os cristais anunciam gelo, fogo ou raio; a pedra mantém a paleta original. Após levantar os braços até a pose 6 de attack, repete o golpe no chão; cada salva sai exatamente na pose 7, no contato das mãos com o piso. O ciclo acompanha a cadência de cada elemento: gelo a cada 0,82 s, fogo a cada 0,62 s e raio a cada 0,72 s, com uma bola elétrica a 132 px/s por impacto. Bolas podem ser evitadas ou devolvidas por parry, com velocidade maior e dano no próprio boss. Uma rajada termina após um intervalo curto ou depois de seus projéteis retirarem 15% da vida máxima do jogador.

Após a derrota, a animação die termina em destroços estáticos no ponto em que o golem caiu, com a mesma escala e orientação. O último frame visível é a pose 12; a célula 13 da folha original é vazia. Esses destroços não têm colisão e permanecem enquanto o jogador estiver na sala. Sair libera o objeto; voltar a uma sala já vencida não reproduz a morte.

Em 75%, 50% e 25% de vida restante, o boss interrompe a ação, fica invulnerável e pula para a plataforma central. Em idle, protegido por um escudo, preenche a tela com dezesseis linhas que chegam uma após a outra. Cada linha começa branca e muda gradualmente para a cor do elemento: gelo, fogo ou raio. Ao completar sua própria carga, vira um clarão branco largo na direção marcada, aplica um único corte e desaparece. Chegada, corte e desaparecimento seguem a mesma ordem; enquanto uma linha corta, as seguintes continuam carregando. A sequência dura aproximadamente 5,5 s. Os flashes são fixos na arena: câmera e zoom não alteram as áreas seguras. Cada corte causa aproximadamente 20% da vida máxima somente se os pés de Nox estiverem na linha no instante do clarão; cruzamentos podem causar acertos independentes. A preparação e a dissipação são inofensivas, e entrar numa linha depois do corte não causa dano tardio. O padrão preserva um local alcançável sobre piso seguro. Depois do especial, o boss retoma as trocas de plataforma. Os saltos usam as poses 3 e 4 como preparação e 7 como queda, com pequeno estrondo ao pousar.

## Combate e leitura

- Base de referência atual: Nox com 60 de vida, minions (comuns e fortalecidos) com 12 e Asterion com 250.
- Asterion precisa expor janelas de vulnerabilidade no chão e anunciar o Skybreaker antes do impacto; sentado e em voo não são janelas normais de dano.
- Minotauros devem oferecer pressão de horda e ataques antecipáveis. Navegação, separação e densidade precisam preservar espaço de resposta.
- Clique esquerdo dispara a Manifestação equipada pelo Booster Shooter; o conjunto inicial usa M01. A arma acompanha todas as direções, inclusive os eixos verticais. O slime combina saída rápida, voo veloz e intervalo de aproximadamente 0,278 s (cadência 15% maior), efeito turquesa na arma e brilho branco que se dissipa no projétil. A área que recebe tiros cobre o corpo dos minions e o torso de Asterion, considerando também a largura da bala para aceitar raspões e tiros próximos; não aumenta as colisões de movimento nem permite acertar através de paredes. Disparos recebem recuo leve de câmera; acertos e eliminações recebem pulsos breves de intensidade crescente, sem mover o personagem nem mudar o tempo do jogo.
- Shift executa dash em qualquer direção, com duas cargas e 0,5 s para recuperar cada uma. Três poses sobrepostas do personagem usam recoloração branca/roxa, transição rápida, luz local e impulso de câmera. A esquerda espelha o desenho; todas as direções mantêm o personagem ereto.
- Botão direito abre uma janela de parry de 0,15 s, com recarga de 0,42 s. Acertar bloqueia o dano e contra-ataca com 30, usando corte branco, retorno gradual das cores e recuo físico. Erro de timing não dispara o efeito de sucesso.
- Multiplicidades e valores experimentais devem ser revisados antes de aprovação. Recursos de preview não são padrões finais do jogo.

## Direção visual

O mundo usa vinho, roxo e sombras profundas. Os poderes podem destoar da paleta de propósito: cor funcional forte ajuda a reconhecer origem e comportamento. A unidade vem dos contornos, tratamento de sombra, escala dos pixels, brilho contido e duração dos efeitos, não de recolorir todos os tiros como o cenário.

O tutorial mantém o chão e a trilha originais até a cadeira; sombras fracas de nuvens passam apenas pelo piso claro. No tutorial, luzes suaves acompanham as duas crateras, as correntes e Asterion; sem feixes geométricos explícitos. No mercante, o ambiente mais escuro destaca os neons da fachada e da porta, a água e Tin. Folhas são uma cobertura visual de primeiro plano, sem física e sem luz projetada própria.

A vida de Nox aparece somente na barra, sem números, com verde `#2cf7a3` e aviso vermelho ao cruzar um bloco. Com 60 de vida e seis blocos, cada bloco representa **10 pontos, ou 16,7%**, não 10% da vida total. A barra usa pixels nítidos, sem filtro bilinear. A barra de Asterion usa a moldura própria e o nome centralizado acima; a redução usa `#b14c47`, `#a0251f` e `#841f1a`.

## Abertura de boosters e ambientação

Direção para a abertura: segurar o mouse em qualquer ponto da tela e atravessar a linha pontilhada do pacote, aceitando ambos os sentidos e desenhando o rastro desde fora dele. Confirmar o gesto uma única vez, comprimir e sacudir o booster, então rasgar o pacote e fazer surgir a stack de cartas junto a uma explosão densa de partículas. Priorizar partículas atrás das cartas, com detalhes à frente e expansão luminosa local. A cena usa fundo vinho/roxo, partículas maiores em creme, dourado, lilás e rosa vivos e cursor local visível. Sem sons nesta etapa; os pontos de futura sonorização ficam mapeados no TDD. Na mesa de estudo, os três acabamentos descritos no catálogo permitem comparar a direção visual das candidatas a destaque.

Áreas de ambientação permitem posicionar aparições ocasionais fora da área jogável: olhos, bocas ou tentáculos animados. São somente visuais, sem dano, colisão ou interação. A lógica existe; os sprites e suas ligações são uma etapa separada.

Há dois modelos de câmera: gameplay centralizada, compartilhada pelo tutorial e pela arena LDtk; e a câmera lateral do mercante. Ambos adotam a distância escolhida de 25% além de suas bases anteriores; gameplay usa zoom 0,96×. O ciclo no `Backspace` está desativado, com os presets preservados como configuração, sem mudar gameplay ou cutscenes. O personagem ativo vem de `assets/characters/player`, sem sprites de costas. A mira permanece visível durante o gameplay e as explicações. Nox é 15% maior no hall, sem Shooter. A porta da antiga sala de testes não faz parte do percurso.
