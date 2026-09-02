# Monster Booster — Game Design Document

**Versão:** 0.1 — base de pré-produção  
**Data de referência:** 31 de agosto de 2026  
**Engine atual:** Godot 4.7.1, renderer `gl_compatibility`  
**Estado:** conceito em consolidação + MVP visual funcional  
**Escopo deste documento:** registrar as decisões tomadas, a base aprovada do MVP e as definições que ainda precisam ser fechadas.

## 1. Convenções do documento

As marcações abaixo distinguem decisão de intenção, implementação e hipótese:

- **[DEFINIDO]**: decisão de design confirmada.
- **[BASE APROVADA]**: comportamento visual ou interativo do MVP que deve ser preservado; ajustes futuros serão de acabamento.
- **[MVP ATUAL]**: estado técnico existente no repositório, ainda não necessariamente uma regra final do jogo.
- **[RECOMENDAÇÃO]**: proposta de direção, ainda sujeita a aprovação.
- **[EM ABERTO]**: decisão necessária que ainda não foi tomada.

> **Regra de leitura:** a implementação atual não transforma automaticamente uma solução temporária em regra definitiva. A exceção é o visualizador de boosters e cartas, cuja base foi explicitamente aprovada.

## 2. Visão do jogo

### 2.1 High concept

**[DEFINIDO]** Monster Booster é um roguelike híbrido de **Bullet Heaven** com **Twin-Stick Shooter**. O jogador controla um pequeno monstro que invade dungeons, derrota hordas e Senhores das Trevas e obtém boosters temáticos para fortalecer sua Booster Shooter e completar sua coleção de cartas.

Cada carta é simultaneamente:

1. uma peça colecionável;
2. um upgrade de combate;
3. uma parte modular da build da arma;
4. um recurso econômico quando aparece além do limite de uso.

### 2.2 Fantasia do jogador

O jogador começa como um monstro ainda pouco equipado e transforma a arma ao combinar cartas obtidas dos próprios inimigos e chefes. Derrotar um chefe não encerra apenas um obstáculo: abre o acesso consistente ao conjunto de cartas daquele chefe, preparando a build para o desafio seguinte.

### 2.3 Pilares

1. **Abrir boosters deve ser satisfatório.** A antecipação, a abertura física do pacote e a revelação individual das cartas são parte central da recompensa.
2. **Eliminar hordas deve ser prazeroso.** As câmaras comuns existem para combate fluido, ganho de ouro e farm de boosters, e não para bloquear o jogador com dificuldade excessiva.
3. **A arma deve mudar de forma perceptível.** Núcleo, modificador, catalisador e stacks precisam produzir alterações claras no disparo e na leitura da build.
4. **Chefes são testes de domínio e progressão.** Eles concentram a dificuldade, usam padrões de bullet hell e incentivam o jogador a voltar mais preparado.
5. **Coleção e combate formam o mesmo ciclo.** O jogador não coleciona cartas apenas por completismo; a coleção é o sistema de progressão da run.

## 3. Gênero, câmera e apresentação

### 3.1 Estrutura de combate

- **[DEFINIDO] Câmaras comuns:** Twin-Stick Shooter com enxames e pressão de posicionamento. Não devem ser bullet hell completo.
- **[DEFINIDO] Chefes:** confrontos individuais com padrões de bullet hell legíveis, aprendizado e execução.
- **[DEFINIDO] Perspectiva:** câmera 2D ortogonal, com leitura semelhante a dungeon crawlers como *Enter the Gungeon*.
- **[DEFINIDO] Direção visual:** pixel art, arena clara sobre fundo externo escuro, sem molduras ou comandos sobre a área de jogo no MVP.

### 3.2 Plataforma e entrada

- **[MVP ATUAL]** Windows/desktop, teclado e mouse.
- **[MVP ATUAL]** resolução de saída 1920×1080 em fullscreen, com viewport lógico de 480×270.
- **[EM ABERTO — IMPORTANTE]** plataformas finais de lançamento.
- **[EM ABERTO — IMPORTANTE]** suporte a controle e comportamento do segundo analógico.
- **[EM ABERTO]** remapeamento, acessibilidade, assistência de mira, redução de flashes e opções de contraste.

## 4. Loop principal

### 4.1 Loop de curto prazo

1. Entrar em uma câmara.
2. Eliminar hordas e coletar pequenas quantidades de ouro.
3. Sobreviver à infestação até o surgimento do elite.
4. Derrotar o elite e obter o booster garantido.
5. Coletar, quando ocorrer, até um booster adicional dos inimigos comuns.
6. Escolher uma das três saídas disponíveis.

### 4.2 Loop de médio prazo

1. Passar por câmaras de combate.
2. Visitar o mercador.
3. Abrir boosters.
4. Reorganizar a Booster Shooter.
5. Vender excedentes e comprar oportunidades de coleção.
6. Enfrentar um chefe.
7. Obter boosters da coleção do chefe.
8. Usar esse novo conjunto para preparar a luta seguinte.

### 4.3 Loop da run

**[DEFINIDO]** Tudo obtido permanece no save da run até o jogador derrotar todos os chefes. Cartas, stacks e recursos não são descartados ao trocar de sala.

**[EM ABERTO — CRÍTICO]** ainda é necessário definir:

- o que acontece ao morrer;
- se existe perda total, parcial ou retomada do último ponto;
- se há metaprogressão permanente entre runs;
- se “completar a coleção” existe apenas dentro da run ou também em um álbum permanente;
- condição exata de vitória depois do último chefe.

## 5. Estrutura da dungeon

### 5.1 Salas e portas

- **[DEFINIDO]** Cada sala possui quatro portas cardeais.
- **[DEFINIDO]** Ao concluir a sala, o jogador pode escolher três saídas; a porta pela qual entrou fica excluída.
- **[DEFINIDO]** As portas informam o tipo da próxima sala quando ela for de mercador ou chefe.
- **[DEFINIDO]** Para salas comuns, a porta pode informar a recompensa do elite, bônus de chance de booster ou outro modificador relevante.
- **[MVP ATUAL]** A visualização da arena exibe somente a plataforma de piso. Paredes e portas foram retiradas da cena; os respectivos assets permanecem preservados para uma futura etapa de construção das salas.
- **[MVP ATUAL]** O limite de movimentação continua retangular e ainda não permite transição entre salas.

**[EM ABERTO]** geração do mapa: procedural, sequência parcialmente dirigida ou grafo pré-montado.  
**[EM ABERTO]** quantidade de salas antes de cada chefe.  
**[EM ABERTO]** regras que impedem sequências injustas ou repetitivas.  
**[EM ABERTO]** forma de representar no mapa salas visitadas, não visitadas e recompensas conhecidas.

### 5.2 Câmara de infestação

- **[DEFINIDO]** Inimigos começam a surgir em ondas ou fluxo contínuo.
- **[DEFINIDO]** Por volta de 40 segundos, a câmara invoca um elite.
- **[DEFINIDO]** O elite funciona como miniboss da sala.
- **[DEFINIDO]** A fase termina quando o elite morre.
- **[DEFINIDO]** Inimigos normais entregam pouco ouro e têm chance de booster.
- **[DEFINIDO]** O elite entrega exatamente um booster garantido por sala comum.
- **[DEFINIDO]** A meta econômica é aproximadamente **1,5 booster por sala**: 1 garantido + 0,5 esperado dos inimigos.
- **[DEFINIDO]** Depois de um drop aleatório na sala, novos drops sofrem redução forte de chance.

**[EM ABERTO — BALANCEAMENTO]** fórmula da chance inicial e da redução após cada drop.  
**[EM ABERTO]** se o cronômetro de 40 segundos é fixo ou varia por sala/ato.  
**[EM ABERTO]** se o elite interrompe os spawns comuns ou luta junto à horda.  
**[EM ABERTO]** quantidade máxima simultânea de inimigos e projéteis.

#### Minotauro — inimigo corpo a corpo do MVP atual

- **[MVP ATUAL]** A arena começa com exatamente três Minotauros, posicionados em três lados do personagem e já visíveis pela câmera.
- **[MVP ATUAL]** Cada sprite-fonte mede 32×32 px e é renderizado em escala 1,0, sem interpolação.
- **[MVP ATUAL]** A caminhada usa os quatro frames fornecidos a 6 FPS; o ataque usa os seis frames fornecidos a 10 FPS e não entra em loop por conta própria.
- **[MVP ATUAL]** O Minotauro persegue o Player a 38 px/s até alcançar 44 px de distância, metade do alcance usado na versão anterior.
- **[MVP ATUAL]** Dentro dessa distância, para de caminhar, executa a animação e lança um ataque a cada 2 s.
- **[MVP ATUAL]** Existe histerese de alcance: ele só abandona o ataque quando a distância ultrapassa 51 px. Isso impede alternância visual causada por variação de um pixel na borda da faixa.
- **[MVP ATUAL]** Se o Player ultrapassar 51 px durante o preparo, o golpe pendente e a animação de ataque são interrompidos imediatamente; a caminhada e a perseguição retornam no mesmo frame físico.
- **[MVP ATUAL]** O golpe é ativado 0,38 s após o início da animação, usando os quatro frames `minotaur_attack_effect` a 12 FPS e escala 0,5 para o sprite e sua colisão.
- **[MVP ATUAL]** O efeito é estacionário e permanece preso à frente do Minotauro; não é mais um projétil e não atravessa a arena.
- **[MVP ATUAL]** O degradê é reproduzido somente uma vez e chega ao quarto quadro laranja.
- **[MVP ATUAL]** O modelo do golpe causa 2 pontos de dano, colide somente com o Player e desaparece imediatamente ao acertá-lo. Sem contato, expira 0,45 s após ser ativado.
- **[MVP ATUAL]** O raio de separação entre Minotauros é 13 px; seus corpos não devem ocupar o mesmo espaço durante a aproximação.
- **[MVP ATUAL]** A resistência estrutural provisória é 6. Como a Booster Shooter ainda não dispara, esse valor existe apenas como gancho técnico.
- **[MVP ATUAL]** O dano mantém o feedback aprovado: o frame corrente do Player fica branco por 0,13 s; o modelo antigo está arquivado em `assets/old/player/damage/player_damage_legacy.png`.

**[EM ABERTO — BALANCEAMENTO]** distância final de combate, velocidade, resistência, dano e duração do preparo.  
**[EM ABERTO]** se o Minotauro recua quando o jogador se aproxima demais; no MVP ele apenas permanece parado dentro do alcance corpo a corpo.  
**[EM ABERTO]** telegraphing, áudio, efeito de impacto, morte e recompensa.

#### Spirit Ghost e Spirit Ghost Elite — projeção de teste do MVP

- **[DEFINIDO]** Inimigo corpo a corpo frágil, usado em grande quantidade.
- **[DEFINIDO]** Persegue diretamente o personagem.
- **[DEFINIDO]** Seu ataque acontece ao chegar próximo/encostar no jogador.
- **[DEFINIDO]** Depois do ataque de contato, o Spirit Ghost desaparece.
- **[MVP ATUAL]** A arena inicia no modo dos três Minotauros; `Espaço` troca para a projeção de Spirit Ghosts e um segundo acionamento restaura os Minotauros.
- **[MVP ATUAL]** A projeção cria um ghost imediatamente e mantém spawns a cada 0,42 s, com limite provisório de 42 simultâneos.
- **[MVP ATUAL]** Os spawns usam uma heurística que procura posições dentro da arena e fora do retângulo visível da câmera, preservando ao menos o raio de separação dos corpos.
- **[MVP ATUAL]** Antes do elite, cada ghost possui 1 ponto estrutural, causa 1 de dano e recebe velocidade aleatória entre 38 e 50 px/s.
- **[MVP ATUAL]** Após exatamente 10 s de projeção, surge um Spirit Ghost Elite. Ele usa quatro frames a 7 FPS, escala 2,1, resistência provisória 16 e velocidade 34 px/s.
- **[MVP ATUAL]** O elite foge do Player escolhendo trajetórias que ampliam a distância, mas permanece delimitado pela área útil da arena.
- **[MVP ATUAL]** A presença do elite transforma todos os ghosts ativos e todos os novos spawns: o sprite muda para a família visual menor do elite, a escala passa a 1,15, a velocidade é multiplicada por 1,5, o dano passa a 2, a resistência mínima passa a 2 e o raio de separação passa de 10 para 12 px.
- **[MVP ATUAL]** O elite não ataca diretamente nesta projeção; sua função é fugir e manter o estado fortalecido da horda enquanto está presente.

**[EM ABERTO]** resistência, dano, velocidade, cadência de spawn e limite simultâneo definitivos.  
**[EM ABERTO]** se a transformação permanece enquanto o elite vive, se reverte com a morte dele ou se é permanente até o fim da sala.  
**[EM ABERTO]** condição de derrota do elite, recompensa, animação de morte, telegraphing e áudio.

#### Mimic — implementação anterior preservada

- **[IMPLEMENTAÇÃO PRESERVADA — INATIVA]** O Mimic não está presente na arena atual; a cena e o script continuam disponíveis para reutilização.
- **[DEFINIDO]** Elites possuem leitura visual muito maior, em torno de 2,5× a dimensão percebida dos mobs normais.
- **[DEFINIDO]** O Mimic foge do personagem continuamente, escolhendo direções que aumentem a distância sem sair da arena.
- **[DEFINIDO]** Todos os seus oito sprites pertencem à animação de corrida; não existe estado visual separado de ataque.
- **[DEFINIDO]** Enquanto foge, dispara rajadas de três projéteis retos em direção ao jogador a cada 1,5 s.
- **[DEFINIDO]** Cada projétil fixa a direção ao nascer, não possui homing e interage somente com o Player, atravessando todos os inimigos.
- **[IMPLEMENTAÇÃO PRESERVADA — INATIVA]** O sprite-fonte mede 32×32 px e usa escala 1,6.
- **[IMPLEMENTAÇÃO PRESERVADA — INATIVA]** Possui oito frames de corrida a 8 FPS, move-se a 31 px/s e separa as três balas da rajada por 0,12 s.
- **[IMPLEMENTAÇÃO PRESERVADA — INATIVA]** O projétil usa sprite 16×16 px, move-se a 112 px/s, causa 2 pontos de dano e expira após 5 s.
- **[IMPLEMENTAÇÃO PRESERVADA — INATIVA]** Usa 12 pontos estruturais de resistência e raio de separação de 25 px.

**[EM ABERTO]** vida, velocidade de fuga, velocidade/dano do projétil e recompensa definitivos do Mimic.  
**[EM ABERTO]** efeito de morte, telegraphing da rajada, stagger e drop garantido do elite.

### 5.3 Sala do mercador

**[DEFINIDO]** É o espaço seguro para:

- abrir boosters;
- organizar a Booster Shooter;
- vender cartas excedentes;
- gastar ouro;
- trocar excedentes por boosters de coleções específicas;
- seguir para outra fase.

**[EM ABERTO — IMPORTANTE]** preços, estoque, número de ofertas e frequência do mercador.  
**[EM ABERTO]** taxa de conversão de cartas excedentes em ouro ou boosters.  
**[EM ABERTO]** possibilidade de reroll, remoção de cartas ou melhoria direta de stacks.

### 5.4 Chefes

- **[DEFINIDO]** O protótipo terá dois chefes: **a Múmia** e **Drácula**.
- **[DEFINIDO]** Drácula é o chefe final do protótipo.
- **[DEFINIDO]** Chefes são mais difíceis que câmaras comuns e podem exigir mais de uma tentativa.
- **[DEFINIDO]** Cada chefe entrega **2 ou 3 boosters garantidos** de sua própria coleção.
- **[DEFINIDO]** Farmar a coleção de um chefe deve ajudar a vencer o chefe seguinte.

**[EM ABERTO — CRÍTICO]** decidir entre 2 e 3 boosters por vitória, ou criar uma regra que varie a quantidade.  
**[EM ABERTO]** acesso a revanche/farm depois da primeira vitória.  
**[EM ABERTO]** padrões, fases, vida, dano e telegraphing de cada chefe.  
**[EM ABERTO]** ordem obrigatória ou flexível entre os chefes em versões maiores.

## 6. Combate e dificuldade

### 6.1 Filosofia

- **[DEFINIDO]** Câmaras comuns devem ser viáveis para a maioria das builds funcionais.
- **[DEFINIDO]** O objetivo delas é sustentar diversão, farm e experimentação, não punir severamente.
- **[DEFINIDO]** Chefes concentram o teste de habilidade e de qualidade da build.
- **[DEFINIDO]** Itens lendários e coleções de chefe devem produzir uma sensação concreta de aumento de poder.

### 6.2 Booster Shooter

**[DEFINIDO]** A Booster Shooter possui inicialmente três espaços funcionais:

| Espaço | Função | Exemplos confirmados |
|---|---|---|
| Núcleo | Define o projétil ou ataque principal | bala, raio, chama, morcego |
| Modificador | Altera o comportamento do ataque | ricochete, perfuração, órbita, fragmentação |
| Catalisador | Adiciona efeito especial | roubo de vida, explosão, congelamento, maldição |

**[EM ABERTO — CRÍTICO]** modelo de disparo: clique individual, fogo contínuo ao segurar ou combinação por Núcleo.  
**[EM ABERTO]** o componente “Bullet Heaven”: ataques automáticos, efeitos orbitais, invocações autônomas ou apenas densidade de inimigos.  
**[EM ABERTO]** cadência base, dano base, crítico, alcance, velocidade, recarga e munição.  
**[EM ABERTO]** prioridade e ordem de resolução quando cartas produzem interações conflitantes.  
**[EM ABERTO]** limite de slots em progressões posteriores e como novos slots seriam adquiridos.

### 6.3 Jogador

**[MVP ATUAL]** movimentação em oito direções com `WASD`, normalizada para não acelerar em diagonal.  
**[MVP ATUAL]** velocidade de 82 pixels lógicos por segundo.  
**[MVP ATUAL]** mira contínua em 360 graus pelo mouse.  
**[MVP ATUAL]** clique esquerdo produz apenas o feedback de recuo; ainda não cria projétil.

**[EM ABERTO — CRÍTICO]** vida, dano recebido, invulnerabilidade e condição de morte.  
**[EM ABERTO]** dash, esquiva, stamina, habilidades próprias do monstro e dano de contato.  
**[EM ABERTO]** coleta automática ou manual de ouro/boosters.  
**[EM ABERTO]** escolha de personagens ou apenas um protagonista no protótipo.

## 7. Sistema de cartas

### 7.1 Regras estruturais

- **[BASE APROVADA]** Cada booster contém exatamente três cartas aleatórias.
- **[BASE APROVADA]** Duplicatas são permitidas, inclusive entre as três cartas do mesmo booster.
- **[BASE APROVADA]** Cada booster contém pelo menos uma carta rara ou lendária.
- **[BASE APROVADA]** Uma mesma carta pode ser equipada em stack de até três cópias.
- **[BASE APROVADA]** Cada stack aumenta os atributos do efeito daquela carta.
- **[BASE APROVADA]** Cópias acima do terceiro nível tornam-se excedentes vendáveis.
- **[BASE APROVADA]** Raridades atualmente previstas: comum, rara e lendária.
- **[DEFINIDO]** Cada coleção deve conter ao menos uma carta de Núcleo, uma de Modificador, uma de Catalisador e uma lendária.
- **[DEFINIDO]** O jogador pode carregar até três boosters de uma mesma coleção e até três coleções diferentes simultaneamente, resultando em capacidade máxima teórica de nove pacotes fechados.
- **[DEFINIDO]** Os boosters coletados permanecem fechados durante as câmaras de combate e são abertos na câmara do mercador.

**[EM ABERTO — CRÍTICO]** curva exata de ganho do stack 1 → 2 → 3.  
**[EM ABERTO]** eventual proteção contra sequências excessivas de duplicatas entre boosters diferentes.  
**[EM ABERTO]** pesos de raridade por coleção, sala, chefe e estágio da run.  
**[EM ABERTO]** comportamento ao tentar coletar um quarto booster da mesma coleção ou uma quarta coleção: permanecer no chão, substituir um pacote ou impedir o drop.  
**[EM ABERTO]** se uma carta pode ocupar mais de uma categoria.  
**[EM ABERTO]** nomenclatura final de “excedentes”, atualmente também chamados de “bulks”.

### 7.2 Coleções previstas para o protótipo

Existem seis coleções planejadas:

| Coleção | Papel | Direção mecânica |
|---|---|---|
| Monster Booster — Edição 1 | Básica | cartas iniciais e builds simples |
| Monster Booster — Edição 2 | Básica | expansão das combinações fundamentais |
| Monster Booster — Edição 3 | Básica | terceira linha de cartas acessíveis |
| Elementais de Calimshan | Temática | fogo, gelo e eletricidade |
| Comemoração 2667 anos do faraó Imhotep | Coleção da Múmia | moscas, rãs, gafanhotos, maldições, veneno e dano por tempo |
| Todos saúdem o príncipe da Valáquia | Coleção de Drácula | roubo de vida e efeitos vampíricos |

**[EM ABERTO — CRÍTICO] Quantidade de cartas:** cada coleção foi estimada em **6 a 9 cartas**, resultando em **36 a 54 cartas** no protótipo. O número final ainda não foi decidido.

**[RECOMENDAÇÃO]** Para o primeiro protótipo jogável, começar com seis cartas por coleção — 36 no total — usando uma distribuição inicial de duas cartas por categoria e ao menos uma lendária por conjunto. Expandir apenas quando o loop de combinação provar que precisa de mais variedade.

**[EM ABERTO]** lista completa, nome, categoria, raridade e valores de cada carta.  
**[EM ABERTO]** quais cartas básicas o jogador recebe no início e em que quantidade.  
**[EM ABERTO]** identidade visual das três edições básicas.  
**[EM ABERTO]** se os conjuntos dos chefes têm raridades melhores ou são mais fortes pelo desenho dos efeitos.

## 8. Economia e recompensas

### 8.1 Fontes

| Recurso | Origem confirmada |
|---|---|
| Ouro | pequenas quantidades de inimigos comuns |
| Booster comum | elite garantido e chance reduzida nos inimigos |
| Booster de coleção de chefe | 2 ou 3 por vitória contra o chefe |
| Cartas iniciais | edições básicas, quantidade ainda indefinida |

### 8.2 Sumidouros

- compras do mercador;
- boosters de coleção específica;
- possíveis serviços futuros do mercador.

**[EM ABERTO — CRÍTICO]** preço médio de booster comparado ao ouro por sala.  
**[EM ABERTO]** preço por raridade ao vender excedentes.  
**[EM ABERTO]** pity system para lendárias ou cartas ainda não descobertas.  
**[EM ABERTO]** possibilidade de inflação ou escalonamento de preços ao longo da run.

## 9. Experiência de abrir boosters e cartas

### 9.1 Decisão de produto

> **[BASE APROVADA] O fluxo do booster e das cartas descrito abaixo é a base definitiva do sistema.** No futuro serão feitos apenas ajustes finos de dimensões, espaçamentos, velocidades, curvas e acabamento visual. A sequência de interação e a apresentação fundamental devem ser preservadas.

### 9.2 Fluxo aprovado

1. O jogador abre a visualização de boosters.
2. A partida fica pausada.
3. Um booster de tamanho médio aparece centralizado sobre fundo verde claro.
4. O booster flutua e reage ao mouse com elevação, escala e inclinação em perspectiva.
5. Ao clicar no booster, a abertura começa.
6. O corpo restante do pacote cai para baixo.
7. O rasgo superior reproduz três frames e congela no terceiro.
8. O rasgo recebe um “kick” e é lançado para o canto superior direito.
9. Três cartas surgem atrás do pacote como uma pilha.
10. Primeiro clique na pilha: a carta verde vai para a direita e revela a segunda.
11. Segundo clique: a segunda carta vai para a esquerda e a terceira permanece no centro.
12. As três cartas ficam disponíveis para arraste livre dentro da tela.

### 9.3 Fundo

- **[BASE APROVADA]** verde claro, sem estética completa de televisão antiga.
- **[BASE APROVADA]** apenas linhas horizontais discretas, espaçadas e subindo lentamente.
- **[BASE APROVADA]** sem ruído pesado, distorção de bordas, moldura CRT ou aberração cromática obrigatória.

### 9.4 Estado técnico atual da visualização

| Item | Valor atual |
|---|---|
| Canvas dos boosters | 128×128 px |
| Escala-base do booster | 1,34 |
| Multiplicador de hover | 1,055 |
| Elevação de hover | 10 px |
| Flutuação idle | amplitude vertical de 2,2 px |
| Perspectiva | distância focal lógica de 520 px |
| Fundo | `#13612E`, aproximadamente |
| Linhas | espaçamento 18 px, velocidade 3,5, força 0,10 |
| Duração total da abertura | 1,45 s |
| Frames do rasgo | 3 frames, 0,10 s por frame |
| Início do kick | 0,38 s |
| Velocidade inicial do rasgo | `(285, -205)` px/s |
| Gravidade do corpo | 310 px/s² |
| Gravidade do rasgo | 36 px/s² |
| Escala-base das cartas | 1,34 |
| Posições abertas | direita `(94, 8)`, esquerda `(-94, 8)`, centro `(0, 0)` |
| Hover da pilha | elevação de 6 px e escala adicional de 4,5% |

**[MVP ATUAL]** `Tab` abre/fecha o visualizador.  
**[MVP ATUAL]** `Espaço` restaura um booster novo para repetir a demonstração. Essa é uma função de depuração e não define como boosters serão consumidos no jogo final.  
**[MVP ATUAL]** As três imagens de carta são placeholders visuais e ainda não possuem dados de gameplay.

**[EM ABERTO]** integração com inventário e consumo real de um booster.  
**[EM ABERTO]** apresentação de nome, texto, raridade, coleção e status de duplicata.  
**[EM ABERTO]** ação final depois de revelar as cartas: guardar automaticamente, confirmar ou escolher uma. Pelas regras atuais, o jogador recebe as três; portanto, a confirmação não deve virar escolha de apenas uma sem nova decisão de design.  
**[EM ABERTO]** som, partículas, brilho de raridade, vibração e acessibilidade da animação.

## 10. Relatório técnico do MVP

Esta seção preserva medidas e decisões necessárias para reconstrução ou evolução futura da base atual.

### 10.1 Projeto e câmera

| Propriedade | Estado atual |
|---|---|
| Viewport lógico | 480×270 px, proporção 16:9 |
| Saída de referência | 1920×1080 fullscreen |
| Stretch | `canvas_items` |
| Filtro padrão | nearest/pixel art |
| Renderer | `gl_compatibility` |
| Fundo externo | `Color(0.027, 0.018, 0.035, 1)` |
| Camera2D | filha do Player |
| Offset da câmera | `(0, -5)` px |
| Suavização | habilitada, velocidade 5,0 |

### 10.2 Personagem

| Propriedade | Estado atual |
|---|---|
| Canvas de cada frame | 16×16 px |
| Escala do corpo | 1,05 |
| Tamanho renderizado nominal | 16,8×16,8 px lógicos |
| Filtro | nearest |
| Idle | 6 frames a 7 FPS, loop |
| Run | 4 frames a 10 FPS, loop |
| Velocidade | 82 px lógicos/s |
| Colisão | cápsula, raio 4 px, altura 10 px |
| Offset da colisão | `(0, 3)` |
| Direção visual | corpo espelhado horizontalmente quando mira à esquerda |

**Observação futura:** a escala 1,05 gera dimensão fracionária. Ela foi aprovada visualmente no MVP, mas deve ser verificada em movimento no pente-fino para evitar shimmer de pixel art.

### 10.3 Arena

| Propriedade | Estado atual |
|---|---|
| Grade | 43×24 tiles |
| Tile-base | 16×16 px |
| Tamanho total | 688×384 px |
| Centro | `(0, 0)` |
| Origem superior esquerda | `(-344, -192)` |
| Área limitada do jogador | `Rect2(-336, -184, 672, 368)` |
| Fim da área limitada | `(336, 184)` |
| Tileset do piso | 64×48 px, quatro colunas por três linhas |
| Implementação do piso | `TileMapLayer` nativo salvo em `scenes/arena.tscn` |
| Recurso de tiles | `resources/floor_tileset.tres` |
| Células serializadas | 1.032 |
| Paredes e portas | ausentes da visualização atual; assets preservados |
| Cor do void | `#25131a` |
| Render estático de referência | `renders/arena_ground.png`, 688×384 px |

O novo piso usa o atlas inteiro como grade 4×3. As quatro quinas ocupam os cantos da arena; os trechos superior, inferior, esquerdo e direito completam o perímetro. No interior, o tile central esquerdo `(1,1)` é a base fixa, enquanto o central direito `(2,1)` aparece em 318 das 902 células internas — 35,25% — com rotações determinísticas de 0°, 90°, 180° ou 270°. Contorno e piso padrão não são rotacionados. A composição permanece idêntica entre execuções.

Essa composição está serializada diretamente em um `TileMapLayer` do Godot. O script `arena.gd` conserva somente as dimensões e os limites usados pela movimentação e pelos spawners; ele não desenha nem gera o mapa.

Mapeamentos exatos:

- piso: `assets/tiles/floor/floor_tileset_mapping.md`;
- parede preservada para uso futuro: `assets/tiles/wall/wall_tileset_mapping.md`.

### 10.4 Booster Shooter — tamanho, posição e animação

| Propriedade | Estado atual |
|---|---|
| Sprite-fonte | 26×11 px |
| Escala | 0,55 |
| Tamanho renderizado nominal | 14,3×6,05 px lógicos |
| Filtro | bilinear |
| Ponto de empunhadura no PNG | `(7, 4)` |
| Offset local do sprite | `(-3,85, -2,2)` |
| Distância frontal do personagem | 10,5 px na direção do mouse |
| Mira | 360°, recalculada em todo frame visual |
| Flutuação horizontal | amplitude 0,3 px |
| Flutuação vertical | amplitude 0,65 px |
| Velocidade-base da flutuação | 1,8 |
| Recuo | 4,5 px no sentido oposto à mira |
| Entrada do recuo | 0,035 s |
| Sustentação | 0,10 s |
| Retorno | 0,14 s |

Comportamento aprovado da montagem atual:

- a arma flutua separada do eixo central do personagem;
- a empunhadura orbita no lado para o qual o mouse aponta;
- a arma permanece acima do corpo na posição normal;
- no recuo, apenas a área sobreposta da empunhadura passa atrás do corpo;
- o cano não deve desaparecer;
- segurar o botão esquerdo ou clicar rapidamente mantém o pequeno recuo, evitando pulsação entre tiros;
- ao terminar a sequência, a arma retorna suavemente à posição frontal;
- ao mirar à esquerda, o sprite é espelhado verticalmente para preservar sua orientação depois da rotação.

Camadas relativas do Player:

| Elemento | Camada local | Resultado |
|---|---:|---|
| Player | 1 global de base | mantém todos os elementos acima da arena |
| Arma recuada | 0 | acima do chão e atrás do corpo |
| Corpo | 1 | oculta somente a parte sobreposta da empunhadura |
| Arma normal | 2 | à frente do corpo |

### 10.5 Escopo já funcional

- projeto Godot 4 compilável/executável;
- arena com piso, paredes, quatro aberturas e fundo escuro;
- personagem animado e movimentável;
- três Minotauros animados no início da partida, com perseguição, curto alcance e cancelamento do ataque por distância;
- golpe crescente corpo a corpo a cada 2 s, estacionário e removido por contato ou duração curta;
- alternância por `Espaço` para a projeção contínua de Spirit Ghosts;
- Spirit Ghost Elite após 10 s, com fuga delimitada pela arena e transformação/buff da horda;
- pickup visual de `booster_dropped` no ponto `(52, 24)`, coletado a 16 px e recriado após 10 s;
- câmera ortogonal com acompanhamento suave;
- Booster Shooter flutuante, mira 360° e recuo visual;
- visualizador responsivo de booster;
- animação de abertura composta por corpo e rasgo;
- revelação individual de três cartas;
- separação e arraste das cartas;
- fundo verde com linhas horizontais lentas.

### 10.6 Sombras simples das entidades

- **[MVP ATUAL]** Player, mobs e elites utilizam somente um círculo escuro desenhado sob o corpo, sem projeção lateral ou cópia da silhueta.
- **[MVP ATUAL]** O círculo fica centralizado no eixo X e preso à posição inferior de cada entidade.
- **[MVP ATUAL]** Player usa raio 4 px; Spirit Ghost, 3,5 px; Minotauro, 5,5 px; Spirit Ghost Elite, 9 px; e Mimic, 10 px.
- **[MVP ATUAL]** A opacidade provisória é 0,16. Golpes, projéteis e demais efeitos temporários não recebem esse círculo.

**[EM ABERTO — PENTE-FINO]** raio, opacidade e posição vertical finais de cada espécie.

### 10.7 Fora do MVP atual

- projéteis da Booster Shooter e sistema funcional de vida/morte;
- Mimic, cuja implementação permanece preservada, mas desativada no controlador atual;
- outros inimigos, elites e chefes;
- colisão com paredes e travessia de portas;
- geração de salas;
- cartas com dados e efeitos reais;
- inventário, arma modular e stacks funcionais;
- drops vinculados à morte de inimigos, conteúdo real dos pacotes, ouro e mercador;
- save da run;
- HUD, áudio e menus finais.

## 11. Arquitetura técnica proposta

### 11.1 Direção inicial

**[RECOMENDAÇÃO]** Manter o protótipo e a primeira vertical slice em **GDScript com tipagem estática**, usando Resources para dados de cartas, coleções, inimigos, salas e tabelas de drop.

Separações sugeridas:

- `CardDefinition`: identidade, coleção, categoria, raridade e parâmetros;
- `CardStack`: carta equipada e nível de stack;
- `WeaponBuild`: núcleo, modificador, catalisador e resolução de sinergias;
- `BoosterDefinition`: coleção e tabela de raridade;
- `RunState`: cartas, stacks, excedentes, ouro, chefes e seed;
- `RoomDefinition`: tipo, recompensa informada pela porta e regras de spawn;
- sistemas de simulação separados da apresentação visual.

O objetivo é poder trocar a implementação interna de projéteis ou enxames sem reescrever cartas, UI, saves e animações.

### 11.2 Avaliação de C++

**Decisão atual: C++ não é necessário para o MVP nem deve ser adotado preventivamente.**

Motivos:

1. O escopo atual é pequeno e dominado por interação, apresentação e regras que ainda mudarão.
2. Funções nativas da engine têm o mesmo custo independentemente da linguagem que as chama; C++ ajuda principalmente quando o projeto executa muitas operações próprias por frame.
3. GDScript tipado melhora detecção de erros, documentação, editor e também pode usar instruções otimizadas.
4. C++ aumenta custo de compilação, depuração, manutenção, compatibilidade de versão e distribuição de binários por plataforma.
5. A documentação do Godot recomenda medir gargalos antes de otimizar.

### 11.3 Mecânicas que podem justificar estudo posterior

C++ via GDExtension deve ser estudado apenas se profiling demonstrar gargalo persistente, depois das otimizações em GDScript:

| Sistema futuro | Risco | Alternativas antes de C++ |
|---|---|---|
| Milhares de projéteis simultâneos | atualização, colisão e alto número de Nodes | pooling, arrays centralizados, colisão simplificada, RenderingServer/PhysicsServer2D, MultiMesh/custom draw |
| Enxames muito numerosos | steering, separação e busca de alvo por inimigo | atualização em lotes, frequência reduzida, spatial hash/grid, navegação simplificada |
| Muitos efeitos por tempo e invocações | multiplicação de timers e sinais | scheduler central, acumulação por ticks, dados contíguos e typed arrays |
| Geração procedural pesada | cálculo de grafo/validação | gerar fora do frame crítico, cache, thread segura para dados puros |
| Simulação determinística/replays | custo de muitos agentes e estados | snapshots compactos e loop de simulação central |

Não são candidatas a C++ nas condições atuais:

- abertura de boosters;
- animação e arraste das cartas;
- inventário e mercador;
- tabelas de drop;
- lógica comum de salas;
- UI, saves e conteúdo de cartas.

### 11.4 Critério de adoção

Antes de introduzir C++:

1. definir hardware mínimo e meta de FPS;
2. criar uma sala de estresse com o máximo planejado de inimigos, projéteis, invocações e efeitos;
3. medir com Profiler e Visual Profiler do Godot;
4. identificar uma função ou subsistema dominante;
5. aplicar pooling, tipagem, redução de Nodes, atualização em lote e APIs Server;
6. medir novamente;
7. criar GDExtension somente se o gargalo continuar impedindo a meta.

**[RECOMENDAÇÃO]** Para uma meta de 60 FPS, o frame completo dispõe de 16,67 ms. Como regra interna inicial, considerar migração apenas se um subsistema autoral continuar consumindo vários milissegundos por frame no hardware mínimo depois das otimizações arquiteturais. O valor definitivo depende do orçamento de CPU/GPU ainda não definido.

Se necessário:

- preferir **GDExtension com `godot-cpp`** a um módulo customizado da engine;
- migrar somente o núcleo numérico do gargalo;
- manter a API pública e os dados de conteúdo acessíveis ao GDScript;
- evitar chamadas individuais GDScript ↔ C++ para cada projétil; transferir dados em lotes;
- versionar e testar os binários de todas as plataformas-alvo;
- considerar módulo C++ da engine apenas se uma API indispensável não estiver exposta por GDExtension, cenário improvável neste projeto.

### 11.5 Fontes técnicas oficiais

- [CPU optimization — Godot](https://docs.godotengine.org/en/stable/tutorials/performance/cpu_optimization.html)
- [Static typing in GDScript — Godot](https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/static_typing.html)
- [C++ / godot-cpp — Godot](https://docs.godotengine.org/en/stable/tutorials/scripting/cpp/)
- [Optimization using Servers — Godot](https://docs.godotengine.org/en/stable/tutorials/performance/using_servers.html)
- [MultiMesh — Godot](https://docs.godotengine.org/en/stable/classes/class_multimesh.html)

## 12. Metas do primeiro protótipo jogável

**[RECOMENDAÇÃO]** A vertical slice deve provar três perguntas, nesta ordem:

1. É divertido eliminar uma horda por tempo suficiente para querer farmar outra sala?
2. Abrir um booster continua prazeroso depois de várias repetições na mesma sessão?
3. Trocar e stackar cartas produz mudanças de arma claras o suficiente para motivar o farm?

Escopo mínimo sugerido para esse teste:

- uma câmara funcional;
- um pequeno conjunto de inimigos comuns;
- um elite;
- uma sala de mercador simplificada;
- um chefe, preferencialmente a Múmia;
- três slots da arma;
- subconjunto de cartas suficiente para duas ou três builds distinguíveis;
- drops e stacks reais;
- abertura aprovada integrada ao inventário;
- save local de uma run.

**[EM ABERTO]** quantidade exata de cartas da vertical slice.  
**[EM ABERTO]** se os seis packs precisam estar funcionais nessa primeira prova ou apenas representados no plano de conteúdo.  
**[EM ABERTO]** duração-alvo de uma run do protótipo.

## 13. Métricas de teste

Métricas úteis quando os sistemas existirem:

- boosters obtidos por sala e desvio em relação à meta 1,5;
- tempo entre aberturas de booster;
- duração de uma abertura e taxa de interrupção/skip;
- frequência de cartas novas, duplicatas úteis e excedentes;
- número médio de salas antes da primeira tentativa de chefe;
- tentativas por chefe;
- tempo para fechar um stack nível 3;
- uso de cada categoria e coleção;
- builds capazes de concluir salas comuns;
- frame time no pior cenário de horda e bullet hell.

**[EM ABERTO]** metas numéricas de retenção, duração, taxa de vitória e desempenho.

## 14. Pendências prioritárias

| Prioridade | Decisão pendente | Por que bloqueia |
|---:|---|---|
| 1 | Quantidade de cartas por coleção: 6, 7, 8 ou 9 | define escopo de conteúdo e probabilidade de duplicatas |
| 2 | Lista e parâmetros das cartas da vertical slice | necessária para validar a Booster Shooter |
| 3 | Modelo de disparo e definição prática do componente Bullet Heaven | orienta input, projéteis e balanceamento |
| 4 | Vida, morte e persistência entre tentativas | define a estrutura roguelike e o save |
| 5 | Fórmula de drop para atingir 1,5 booster/sala | controla ritmo de recompensa |
| 6 | Dois ou três boosters por chefe | afeta velocidade de farm das coleções especiais |
| 7 | Estrutura e duração do mapa até cada chefe | define duração da run |
| 8 | Hardware mínimo, plataforma e FPS-alvo | necessário para orçamento técnico e decisão futura sobre C++ |
| 9 | Preços e conversão de excedentes | fecha a economia do mercador |
| 10 | Regras de sinergia e conflito entre cartas | necessária antes de escalar o catálogo |
| 11 | Progressão permanente fora da run | define o sentido de “completar a coleção” |
| 12 | Áudio e feedback de combate/recompensa | fundamental para testar satisfação, embora não bloqueie a lógica |

## 15. Decisões congeladas e controle de mudança

Por solicitação de design, os seguintes pontos são tratados como base congelada:

- três cartas por booster;
- duplicatas e stacks de até três;
- excedentes vendáveis;
- três categorias iniciais da Booster Shooter;
- estrutura de revelação individual da pilha;
- carta 1 para a direita, carta 2 para a esquerda e carta 3 no centro;
- cartas arrastáveis depois da revelação;
- pacote rasgado em corpo descendente e topo lançado ao canto superior direito;
- fundo verde com linhas horizontais lentas;
- arma flutuante separada do corpo, acompanhando o mouse em 360°;
- pequeno recuo que esconde somente a empunhadura sobreposta;
- arena ortogonal com quatro portas centrais formadas por ausência de parede.

Alterações futuras nesses itens devem ser registradas como revisão explícita do GDD. Ajustes de escala, posição, tempo, easing, hitbox, espaçamento e acabamento não alteram a base e podem ser feitos durante o pente-fino visual.
