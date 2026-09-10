# Monster Booster — estudo das 18 cartas iniciais

Estado: brainstorm para prototipação. Nenhuma carta, raridade, regra ou distribuição deste documento está aprovada ou implementada. Nomes e referências de criaturas são ilustrativos; os efeitos abaixo são propostas próprias para o jogo, sem compromisso com regras ou lore de outros sistemas.

O foco é descobrir o que as cartas fazem na Booster Shooter e no combate de Mox. A existência de um TCG dentro do universo fica para uma decisão posterior. Consulte `GDD.md` e `ITERACOES.md` para registrar aprovações e resultados.

## Leitura crítica da proposta

A lista contém **18 cartas: 7 Manifestações, 5 Infusões e 6 Mutações**. Não é necessário forçar seis de cada classe neste momento. A Cabeça de Draugr foi apresentada sem efeito; sua função abaixo é uma sugestão para avaliação.

Há variedade suficiente para investigar disparos, ataques contínuos, controle de espaço e sobrevivência. O risco é tentar construir tudo antes de validar a combinação básica: parasitismo, criaturas auxiliares, iscas e efeitos periódicos exigem comportamentos de inimigos que ainda não existem na base limpa.

Também há sobreposições que precisam ser intencionais: slime maior e explosão fazem dano em área; fungoides, espinhos e veneno causam dano ao longo do tempo; parasita e Doppelgänger desviam a atenção dos inimigos. Cada opção precisa mudar uma decisão do jogador, não apenas a aparência do dano.

Interpretação de “cartas normais, sem especialização”: cartas utilizáveis sem exigir uma coleção, elemento ou arquétipo específico. Elas ainda têm funções próprias. Os três sets são coleções de entrada variadas, sem bônus por completar coleção nesta proposta.

## Função provisória das classes

| Classe | Responsabilidade | Pergunta que responde |
| --- | --- | --- |
| Manifestação | Define a forma do ataque principal: projétil, onda, feixe ou criatura auxiliar. | Como Mox ataca? |
| Infusão | Acrescenta uma consequência ao ataque, ao acerto ou ao abate atribuído à arma. | O que esse ataque provoca? |
| Mutação | Acrescenta uma capacidade a Mox, acionada por movimento, tempo, dano recebido, abate ou botão de ação. | Que recurso adicional Mox tem no combate? |

Hipótese inicial: um slot de cada classe. A Infusão não precisa ser um elemento; essa definição mais ampla permite explosão, cura e parasitismo na mesma classe. A Mutação pode ser passiva ou ativa, e essa diferença deve ficar explícita na interface.

Se o nome “Infusão” fizer o jogador esperar somente fogo, gelo e veneno, vale revisar o nome após testar a explicação das classes. Não é necessário resolver isso antes de experimentar os efeitos.

## Distribuição ilustrativa dos três base sets

Cada set contém seis cartas e representantes das três classes. Não há raridade atribuída às demais cartas; “candidata a destaque” indica uma possibilidade futura, não uma raridade confirmada ou uma carta mais forte.

| Set | Manifestações | Infusões | Mutações | Candidata a destaque |
| --- | --- | --- | --- | --- |
| Monster Booster 1 | M01 Gotas de Slime; M02 Massa de Slime | I01 Núcleo de Golem; I03 Fragmento de Odopi | U01 Coração da Fúria; U04 Mandrágora de Bolso | Mandrágora de Bolso |
| Monster Booster 2 | M03 Grito de Banshee; M05 Brotos de Fungoide | I02 Casca Estilhaçante; I04 Ovo de Slaad | U02 Pele de Medusa; U05 Glândulas de Lesma | Ovo de Slaad |
| Monster Booster 3 | M04 Olho de Beholder; M06 Cauda de Mantícora; M07 Cabeça de Draugr | I05 Essência de Quimera | U03 Chão Carnívoro; U06 Doppelgänger | Olho de Beholder |

O terceiro set tem três Manifestações e apenas uma Infusão. Isso preserva a lista original, mas reduz sua variedade de Infusões. Se a simetria entre os packs se mostrar importante, revisar uma carta ou a composição do catálogo depois dos testes; não mudar sua classe apenas para fechar a conta.

Esta tabela distribui as cartas entre coleções. Quantidade de cartas por abertura, chances, duplicatas e garantia de acesso aos três slots continuam pendentes. A primeira combinação jogável precisa ser acessível sem depender de sorte, caso os pacotes sejam aleatórios.

## Como ler a viabilidade

- **Baixa complexidade relativa:** comportamento direto, reaproveitável após existir uma base de combate.
- **Média:** depende de estados, temporizadores, seleção de alvos ou regras de interação adicionais.
- **Alta:** altera decisões dos inimigos ou exige muitos casos de interação e validação.

Essas classificações não são estimativas de prazo. Mesmo as cartas simples precisam de movimentação, ataques, colisão, dano e derrota funcionando. Vida, cura e estados são dependências futuras, não sistemas já presentes.

## Manifestações

### M01 — Gotas de Slime

**Efeito:** dispara pequenas bolas de slime em sequência na direção da mira. Cada bola causa dano direto ao primeiro inimigo atingido.

**Papel:** ataque de referência, fácil de mirar e de comparar com outras Manifestações. A frequência de disparos é sua identidade; não precisa aplicar lentidão ou veneno por ser slime.

**Viabilidade:** baixa complexidade relativa. Requer projétil simples, cadência e colisão. É a melhor candidata para a primeira implementação.

**Limites a experimentar:** intervalo entre disparos, velocidade, alcance e dano por bola. A frequência não deve multiplicar livremente efeitos de Infusão.

**Validação:** o jogador consegue acompanhar os acertos e perceber a diferença entre disparar com e sem uma Infusão, sem perder a leitura dos inimigos.

### M02 — Massa de Slime

**Efeito:** dispara uma bola maior e menos frequente. Ao atingir um inimigo, a massa se espalha e causa dano em uma pequena área ao redor do impacto.

**Papel:** recompensar acertar grupos, trocando frequência por cobertura e impacto. A área faz parte do ataque principal.

**Viabilidade:** baixa a média. Reaproveita o projétil e acrescenta uma consulta de área. O alvo direto não deve receber o mesmo dano duas vezes por aparecer na colisão e na área.

**Limites a experimentar:** raio da área, intervalo, velocidade e dano. Com Núcleo de Golem, testar uma única área ampliada em vez de duas explosões visualmente iguais; essa combinação precisa comunicar um ganho observável.

**Validação:** tem vantagem clara contra inimigos agrupados, sem substituir Gotas de Slime em todas as situações.

### M03 — Grito de Banshee

**Efeito:** emite rajadas sonoras em um cone curto à frente da arma. Cada rajada atinge os inimigos dentro da abertura uma vez.

**Papel:** cobrir uma frente larga a curta distância, exigindo aproximação e posicionamento. Nesta primeira hipótese, não aplica medo nem empurrão automaticamente.

**Viabilidade:** média. Requer detecção de cone e correspondência entre animação e área real de dano. Pode começar com uma forma geométrica simples.

**Limites a experimentar:** alcance, abertura, intervalo e quantidade de alvos que podem ativar uma Infusão por rajada.

**Validação:** um inimigo fora do cone não recebe dano; a rajada parece um pulso próprio, não uma versão mais larga do feixe contínuo.

### M04 — Olho de Beholder

**Efeito:** mantém um feixe contínuo enquanto o disparo estiver pressionado. Na versão mínima, o feixe atinge o primeiro inimigo em sua trajetória e aplica dano em intervalos regulares.

**Papel:** sustentar a mira sobre um alvo. O feixe pode acompanhar a mira, mas não ganha perfuração ou vários raios nesta proposta.

**Viabilidade:** média. Requer consulta de colisão do feixe e dano por tempo, separado da taxa de quadros. Sua interação com Infusões é mais delicada que sua aparência.

**Limites a experimentar:** alcance, intervalo de dano, dano por segundo e intervalo próprio de ativação da Infusão. Trocar de alvo não deve reiniciar esses limites para gerar efeitos extras.

**Validação:** o dano se mantém consistente em diferentes taxas de quadros; acompanhar um alvo em movimento é interessante e a ponta visual coincide com a colisão.

**Destaque:** candidata a representar o set 3. A mudança de controle já a diferencia; não precisa ter maior dano que todas as outras armas.

### M05 — Brotos de Fungoide

**Efeito:** lança pequenos cogumelos que avançam até um inimigo próximo. Ao alcançá-lo, permanecem junto dele por um período curto, causando dano em intervalos até desaparecer.

**Papel:** manter pressão enquanto Mox se reposiciona. O dano depende de os brotos chegarem ao alvo; não é um projétil de impacto imediato nem uma área de veneno.

**Viabilidade:** média a alta. Requer busca de alvo, perseguição simples, duração e limite de criaturas. Começar sem navegação complexa e sem vida própria para os brotos.

**Limites a experimentar:** número de brotos ativos e por inimigo, velocidade, alcance de busca e duração. Para a primeira versão, um broto desaparece quando seu alvo morre; procurar outro alvo fica para uma iteração posterior.

**Validação:** o jogador entende quem os brotos estão atacando e percebe o atraso entre disparar e causar dano. Muitos brotos não escondem ameaças nem geram ativações ilimitadas de Infusão.

### M06 — Cauda de Mantícora

**Efeito:** dispara espinhos que ficam cravados no inimigo por um tempo curto e causam dano periódico antes de desaparecer.

**Papel:** acertar, mudar de alvo e deixar o dano terminar. Diferencia-se dos fungoides porque exige um acerto direto e não persegue o inimigo.

**Viabilidade:** média. Requer projétil e um estado temporário de espinhos no alvo. Não precisa ser veneno: o efeito pode ser apenas dano dos espinhos cravados.

**Limites a experimentar:** duração, intervalo dos ticks e limite de espinhos por alvo. Ao atingir o limite, substituir o espinho mais antigo é uma hipótese simples; evitar acúmulo sem teto.

**Validação:** os espinhos permanecem legíveis no alvo e o jogador consegue estimar quando vale parar de atirar nele. Os ticks posteriores não contam automaticamente como novos impactos da arma.

### M07 — Cabeça de Draugr

**Efeito proposto, ainda sem definição do autor:** dispara uma cabeça em linha reta que atravessa uma quantidade limitada de inimigos antes de desaparecer.

**Papel:** premiar o alinhamento dos inimigos. Preenche um espaço diferente da área circular de slime, do cone sonoro e do feixe que para no primeiro alvo.

**Viabilidade:** baixa a média. Requer projétil perfurante, limite de alvos e registro de quem já foi atingido para não repetir o dano na mesma passagem.

**Limites a experimentar:** velocidade, alcance, quantidade de alvos e cadência. Sem retorno, perseguição ou ricochete na versão mínima.

**Validação:** alinhar inimigos traz uma vantagem perceptível. Se a aparência de uma cabeça não comunicar o ataque ou o disparo não acrescentar uma decisão própria, substituir ou retirar a proposta.

## Infusões

### I01 — Núcleo de Golem

**Efeito:** um impacto elegível provoca uma explosão que causa dano ao redor do inimigo atingido.

**Papel:** acrescentar cobertura de área a ataques concentrados. A associação entre golem e explosão é uma escolha visual provisória; pode ser um núcleo instável ou receber outro nome depois.

**Viabilidade:** média. A área é simples; o desafio é limitar sua ativação em feixes, rajadas e ataques com múltiplos alvos.

**Limites a experimentar:** raio, dano, intervalo entre ativações e regra para acertos simultâneos. A explosão não ativa outra explosão. Para brotos, testar ativação na chegada; para espinhos, no impacto inicial; para feixe, no intervalo próprio da Infusão.

**Validação:** amplia a capacidade contra grupos sem fazer o ataque mais rápido ser sempre a melhor combinação. Massa de Slime precisa de uma regra explícita para sua área já existente.

### I02 — Casca Estilhaçante

**Efeito:** um impacto elegível libera fragmentos que viajam por uma distância curta e podem atingir outros inimigos.

**Papel:** espalhar dano por trajetórias, com espaços entre elas. A explosão cobre uma região; os estilhaços podem alcançar um alvo mais distante, mas também errar.

**Viabilidade:** média. Requer projéteis secundários e limite de fragmentos. O nome e a criatura de origem ficam abertos para criação própria.

**Limites a experimentar:** quantidade, direções, alcance e dano dos fragmentos. Na primeira versão, eles não acertam o alvo que os originou nem geram novos estilhaços ou outros efeitos de Infusão.

**Validação:** posicionamento e distribuição dos inimigos alteram seu resultado. Se funcionar apenas como uma explosão menos clara, redesenhar antes de manter as duas cartas.

### I03 — Fragmento de Odopi

**Efeito:** recupera uma pequena quantidade de vida de Mox ao derrotar um inimigo com dano atribuído à Booster Shooter.

**Papel:** oferecer sustentação em troca de abrir mão de uma Infusão ofensiva. “Fragmento” é um nome temporário; a parte da criatura ainda pode ser escolhida.

**Viabilidade:** baixa após existir vida, cura e atribuição de abates. Depende de sistemas que ainda precisam ser prototipados.

**Limites a experimentar:** cura por abate, teto da vida máxima e frequência de recuperação. Contar cada inimigo derrotado uma única vez; dano tardio de espinhos ou brotos precisa preservar sua origem.

**Validação:** ajuda a recuperar erros ocasionais, mas não permite ignorar ataques ou tornar grupos de inimigos fracos uma fonte ilimitada de segurança. A escolha deve competir com dano e controle sem se tornar obrigatória.

### I04 — Ovo de Slaad

**Efeito:** um acerto elegível parasita temporariamente um inimigo simples. Durante o efeito, ele procura e ataca outros inimigos próximos; ao terminar, volta ao comportamento normal.

**Papel:** converter uma ameaça em distração ofensiva temporária.

**Viabilidade:** alta. Exige troca de alvo e equipe, ataques capazes de atingir monstros e restauração segura do comportamento. Inimigos sem ataque apropriado podem precisar de uma resposta própria.

**Limites a experimentar:** um parasitado por vez, duração curta e intervalo entre ativações. Na versão mínima, o efeito não se renova continuamente no mesmo alvo, não afeta chefes e o parasitado continua vulnerável à arma de Mox. Seu dano não aplica cartas de Mox; abates dele não ativam cura ou outros efeitos de abate nesta hipótese.

**Validação:** a mudança de lealdade é imediatamente visível, o inimigo retorna ao estado correto e parasitar não paralisa o encontro inteiro. Se não houver outro alvo, testar que ele espere o efeito terminar, sem atacar Mox nesse período.

**Destaque:** candidata a representar o set 2, mas deve entrar tarde na prototipação. A raridade não resolve uma IA confusa ou um efeito sem limites.

### I05 — Essência de Quimera

**Efeito:** alterna entre três consequências, em ordem visível: fogo, veneno e empurrão.

**Papel:** oferecer um ciclo previsível que permita preparar o próximo efeito. Proposta mínima: fogo acrescenta dano imediato, veneno aplica dano ao longo do tempo e empurrão afasta o alvo. Assim, fogo e veneno não começam como duas versões do mesmo estado periódico.

**Viabilidade:** média a alta. Depende de estados, resistência a empurrão e uma regra de ciclo compartilhada por todas as Manifestações.

**Limites a experimentar:** avançar o ciclo por ataque emitido nos disparos discretos; todos os alvos daquele ataque recebem a mesma fase. No feixe, cada janela de ataque definida por tempo conta como uma emissão. Brotos e espinhos guardam a fase de seu disparo; cada tick não avança o ciclo. Infusão e efeitos derivados continuam limitados para múltiplos alvos.

**Validação:** o jogador identifica e pode antecipar a próxima fase. Em cadência alta, o ciclo pode ficar rápido demais para decisões; nesse caso, testar várias emissões por fase antes de aumentar a complexidade visual.

**Destaque:** manter como carta experimental por enquanto. Três efeitos não a tornam automaticamente uma boa lendária; primeiro precisa provar que a alternância acrescenta uma decisão.

## Mutações

### U01 — Coração da Fúria

**Efeito:** derrotar um inimigo concede velocidade de movimento temporária. Novos abates renovam a duração, sem acumular velocidade indefinidamente.

**Papel:** incentivar reposicionamento e continuidade do combate. “Velocidade” foi interpretada como movimento; velocidade de ataque seria outra proposta, com consequências maiores para as Infusões.

**Viabilidade:** baixa após existir atribuição de abates e modificadores temporários de movimento.

**Limites a experimentar:** intensidade, duração e fontes de abate aceitas. Começar apenas com abates atribuídos à arma, incluindo seu dano tardio e efeitos derivados, sem abates de criaturas parasitadas.

**Validação:** o ganho ajuda a reposicionar sem prejudicar o controle preciso nem tornar Mox permanentemente rápido durante qualquer encontro.

### U02 — Pele de Medusa

**Efeito:** quando Mox recebe dano, surgem pequenas cobras que perseguem o agressor e aplicam veneno ao alcançá-lo.

**Papel:** reação defensiva ao erro. A associação com Medusa é visual; não implica petrificação.

**Viabilidade:** média a alta. Requer evento de dano recebido, identificação do agressor, criaturas auxiliares e veneno. A perseguição simples pode ser compartilhada com os brotos.

**Limites a experimentar:** intervalo de ativação, número de cobras e duração. Ativar por perda efetiva de vida, sem reagir a dano bloqueado. Se o agressor morrer ou não existir, buscar um inimigo próximo uma vez; sem alvo, as cobras desaparecem ao fim da duração. Cobras não recebem Infusão.

**Validação:** um único ataque não cria várias ondas de cobras e impactos rápidos respeitam o intervalo. Verificar se o efeito oferece proteção útil sem tornar receber dano a melhor estratégia de ataque.

### U03 — Chão Carnívoro

**Efeito:** periodicamente marca o chão sob alguns inimigos próximos. Após um aviso curto, bocas se abrem nas posições marcadas, causam dano em área uma vez e desaparecem.

**Papel:** pressão automática sobre grupos que permanecem em uma região.

**Viabilidade:** média. Requer seleção de posições, aviso visual e área de dano. Na versão mínima, as bocas não seguem o alvo nem permanecem mordendo.

**Limites a experimentar:** intervalo, quantidade de bocas, raio de busca, atraso e dano. Não sobrepor várias bocas no mesmo ponto; escolher um único dano por ativação para inimigos em áreas sobrepostas. Sem inimigos, aguardar o próximo intervalo, sem acumular ativações.

**Validação:** o aviso permite entender de onde veio o dano. Observar se a carta muda posicionamento ou ritmo; se apenas adiciona dano automático invisível à decisão, ela pode ser uma das primeiras candidatas a revisão ou corte.

**Destaque:** reservar o potencial visual para avaliação posterior. Não precisa ser lendária nesta seleção.

### U04 — Mandrágora de Bolso

**Efeito:** segurar o botão de ação carrega um pulso ao redor de Mox; soltar emite o pulso e empurra inimigos próximos. A carga aumenta o alcance até um limite.

**Papel:** criar espaço em um momento escolhido pelo jogador. “Carregável” foi interpretado como segurar e soltar, seguido de um tempo de recarga.

**Viabilidade:** média. Requer estados de carga, soltura, recarga e resposta ao empurrão. Não exige dano, invulnerabilidade ou atordoamento na primeira versão.

**Limites a experimentar:** duração máxima de carga, raio mínimo e máximo, força e recarga. Começar permitindo movimento durante a carga; interrupções e restrições ao disparo devem ser testadas separadamente. Chefes podem resistir ao deslocamento.

**Validação:** carregar traz um benefício compreensível e soltar rapidamente ainda é útil numa emergência. O jogador consegue distinguir a área prevista do pulso real.

**Destaque:** candidata a representar o set 1. Introduz uma decisão ativa clara e tem menos dependências que parasitismo ou isca com invulnerabilidade.

### U05 — Glândulas de Lesma

**Efeito:** enquanto Mox se move, deixa pequenas áreas temporárias de rastro que envenenam inimigos que passam por elas.

**Papel:** transformar o caminho percorrido em controle de espaço e recompensar conduzir inimigos pelo cenário.

**Viabilidade:** média. Requer rastro por distância percorrida, áreas com duração e veneno. Criar trechos por distância evita que a quantidade dependa da taxa de quadros.

**Limites a experimentar:** espaçamento, largura, duração e número máximo de trechos. Parado, Mox não gera novos trechos. Áreas sobrepostas renovam um único veneno em vez de multiplicar livremente seu dano.

**Validação:** percorrer uma rota faz diferença, mas andar em círculos não resolve sozinho qualquer encontro. O rastro precisa se distinguir de ataques perigosos do cenário.

### U06 — Doppelgänger

**Efeito:** o botão de ação deixa uma cópia temporária na posição de Mox. Inimigos simples próximos passam a persegui-la, enquanto Mox recebe uma breve janela de invulnerabilidade para sair do cerco.

**Papel:** reposicionamento por distração. Diferencia-se da Mandrágora porque muda o destino dos inimigos em vez de afastá-los fisicamente.

**Viabilidade:** alta. Junta duas capacidades fortes: troca de alvo e invulnerabilidade. Requer prioridade de alvos, expiração da isca e retorno correto à perseguição.

**Limites a experimentar:** uma cópia por vez, duração, alcance da atração, recarga e janela de invulnerabilidade. Começar com cópia imóvel, sem ataque e com duração fixa. Na versão mínima, ela não cancela projéteis nem ataques já iniciados; chefes ignoram a atração. A invulnerabilidade de Mox ainda segue sua duração definida.

**Validação:** a isca atrai de forma previsível, expira corretamente e não prende inimigos em estados inválidos. Testar primeiro a isca sozinha; adicionar invulnerabilidade em outra iteração para medir se ambas são necessárias.

**Destaque:** candidata alternativa à Mandrágora caso a distração se mostre mais interessante. Não precisa ocupar um quarto posto de lendária só por reunir sistemas complexos.

## Regras de combinação a testar antes de ampliar o catálogo

Estas são proteções propostas para os protótipos, não regras finais de balanceamento.

| Questão | Hipótese inicial | Motivo |
| --- | --- | --- |
| O que conta como ataque? | Uma emissão discreta; no feixe, uma janela de tempo explícita. | Evitar que cada quadro ou partícula seja tratado como ataque. |
| O que conta como impacto elegível? | Colisão principal, chegada de broto ou contato do feixe sujeito a intervalo próprio. | Feixes e dano periódico precisam de uma regra que não favoreça apenas a frequência. |
| Um cone ou projétil perfurante ativa efeitos em todos os alvos? | Para explosão, estilhaçamento e parasita, começar com uma ativação por emissão e um alvo de origem definido. No cone, escolher o alvo atingido mais próximo da mira. | Limitar multiplicação e tornar a origem do efeito previsível. |
| Efeito secundário pode ativar outra Infusão? | Não. Explosões, fragmentos e ticks derivados não reiniciam a cadeia. | Evitar recursão e crescimento descontrolado de dano. |
| Ticks podem receber o efeito da Infusão? | Podem carregar um estado definido na emissão, mas não geram novas ativações de impacto a cada tick. | Separar a identidade do dano da frequência de ativação. |
| Como aplicar Quimera em ataques contínuos ou com vários alvos? | Fixar a fase por emissão/janela; permitir dano do ataque nos seus alvos e limitar a aplicação adicional de estados ou empurrões por alvo e por tempo. | Preservar a alternância sem empurrões e estados ilimitados. |
| Quem recebe crédito pelo abate? | Guardar origem do dano: arma, efeito derivado, Mutação ou inimigo parasitado. Na primeira hipótese, cura e Fúria aceitam arma e seus derivados. | Evitar eventos duplicados e decisões implícitas entre sistemas. |
| Trocar de carta mantém efeitos antigos? | Se houver troca em combate, efeitos já emitidos conservam sua origem e parâmetros até expirar; não recebem a carta nova. | Evitar mudar retroativamente espinhos, brotos ou projéteis. A troca em combate ainda não está decidida. |
| Veneno de várias fontes acumula? | Começar com um estado de veneno por alvo, que renova duração e mantém a maior intensidade ativa. Preservar a origem da instância que efetivamente causa dano. | Tornar o comportamento previsível antes de testar acúmulos. |
| Várias Mutações usam o mesmo botão? | Com um slot, somente a Mutação ativa equipada recebe a ação. Passivas não recebem uma habilidade extra. | Evitar uma nova camada de comandos antes de validar o slot. |
| Como lidar com chefes? | Empurrão, parasitismo e atração precisam de respostas explícitas; não herdar automaticamente o comportamento dos inimigos simples. | Não permitir que controle temporário elimine todo o funcionamento de um chefe. |

Um limite de ativações evita excessos, mas não garante equilíbrio. Será necessário comparar dano, cobertura, controle e sobrevivência em encontros equivalentes. Se uma combinação exigir exceções demais para ser compreendida, simplificar o efeito ou reconsiderar a carta.

## Destaques de coleção e o problema dos “must haves”

Sugestão inicial: **Mandrágora de Bolso, Ovo de Slaad e Olho de Beholder**, uma candidata por set. Representam, respectivamente, ação defensiva, controle de inimigo e uma forma diferente de atacar.

Essas cartas podem ser desejadas pela experiência que oferecem. Não devem ser necessárias para tornar uma build funcional. Uma carta obrigatória reduz o interesse das escolhas e torna a aquisição aleatória mais frustrante.

Também não usar raridade para compensar poder excessivo ou custo de implementação. Uma carta rara ainda precisa de limites, contrapartidas e leitura clara. Essência de Quimera, Chão Carnívoro e Doppelgänger permanecem hipóteses normais de avaliação; podem ganhar destaque depois se os testes justificarem.

## Ordem sugerida de prototipação

Não é um compromisso de implementar as 18 cartas. Cada etapa deve produzir uma decisão de manter, ajustar ou descartar antes de ampliar o escopo.

| Etapa | Entrega mínima | Pergunta de validação |
| --- | --- | --- |
| 1 — Combate de referência | Mox move e mira; Gotas de Slime atinge um inimigo simples que persegue, recebe dano e pode morrer. | Atirar, acertar e desviar já são claros e agradáveis? |
| 2 — Primeira combinação | Acrescentar Núcleo de Golem e Coração da Fúria em três slots fixos, sem pacotes ou coleção. | O jogador percebe separadamente o que cada classe acrescenta? |
| 3 — Trocas simples | Massa de Slime e Casca Estilhaçante, incluindo a interação entre área original e explosão. | Trocar uma carta muda a decisão no combate, além do visual? |
| 4 — Formas de ataque | Testar Banshee, Draugr e Beholder em iterações separadas. | Cone, perfuração e mira sustentada têm espaço próprio? |
| 5 — Dano por tempo | Primeiro espinhos; depois veneno e rastro; brotos apenas após limites e atribuição de dano funcionarem. | É possível entender dano tardio e evitar multiplicação de Infusões? |
| 6 — Sobrevivência e ação | Vida e dano recebido; cura; Mandrágora; depois cobras reativas, cada qual com avaliação própria. | Defesa exige decisões sem apagar as consequências dos erros? |
| 7 — Sistemas de maior risco | Parasita e isca em iterações separadas; depois avaliar Quimera e Chão Carnívoro. | O benefício de cada carta compensa sua complexidade e preserva a leitura do combate? |
| 8 — Curadoria dos sets | Selecionar cartas validadas, revisar distribuição e só então experimentar abertura e aquisição. | Os packs oferecem escolhas úteis e permitem formar combinações sem cartas obrigatórias? |

Para cada carta aprovada para teste, registrar valores iniciais mensuráveis na respectiva iteração. Não fixar dano, duração, chances ou raridade no catálogo antes de existir um encontro de referência.

## Pendências para a primeira decisão de design

- Confirmar se Manifestação / Infusão / Mutação representam as responsabilidades desejadas, especialmente cura por abate dentro de Infusão.
- Confirmar a interpretação de velocidade de movimento para Coração da Fúria e de segurar/soltar para Mandrágora.
- Escolher ou substituir o efeito provisório da Cabeça de Draugr.
- Definir a primeira entrega de combate e seus critérios, antes de implementar o sistema completo de cartas.
- Testar a legibilidade de uma combinação simples antes de produzir arte ou apresentação para todas as cartas.

O catálogo é uma lista de possibilidades a reduzir e refinar por evidência. Uma carta pode mudar de nome, efeito, set ou deixar de existir sem invalidar o restante da proposta.
