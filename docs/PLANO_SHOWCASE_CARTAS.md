# Monster Booster · Plano de showcase das cartas

Prévia curta acima da carta ao passar o mouse na coleção ou nas recompensas do booster. A tomada mostra Nox, a Booster Shooter e um Minotauro comum. O gatilho e o resultado precisam ser legíveis no tamanho final do pop-up.

## Referência e enquadramento

O pitch original está arquivado em `old/mvp_2026-09-09`. Os GIFs têm 1024 × 416 e mostram Nox à esquerda, os efeitos saindo da arma e o alvo à direita, com espaço livre entre eles e fundo simples. A composição é a referência para as novas capturas. [Tiros rápidos](../old/mvp_2026-09-09/pitch/pitch_01_tiros_rapidos.gif) · [Morcegos](../old/mvp_2026-09-09/pitch/pitch_02_morcego.gif) · [Sopro](../old/mvp_2026-09-09/pitch/pitch_03_flamethrower.gif) · [Cena antiga](../old/mvp_2026-09-09/scenes/pitch/weapon_pitch_showcase.tscn)

- **Tomada padrão:** câmera fixa, sem tremor de câmera, piso roxo fosco com pouca textura, iluminação suave e a mesma escala dos personagens entre cartas. Nox à esquerda; Minotauro à direita. Manter recuo, flashes, fumaça, sombras e partículas dos efeitos atuais. Preservar as silhuetas e os contrastes do pitch.
- **Largura:** abrir o quadro somente para feixes longos, dispersão, investida, trajetos contornando parede ou múltiplos alvos. O painel tem proporção fixa; o preset largo muda o enquadramento da captura, sem esticar a imagem.
- **Elenco:** usar a [cena do Minotauro comum](../scenes/enemies/minotaur.tscn), inclusive como agressor. A é o alvo principal; B, C e D são cópias da mesma cena. Manter os ataques, o dano e as reações reais. Guiar posições e tempos da tomada para reduzir variação.
- **Leitura:** começar com cerca de 0,3 s para ver as posições, mostrar a ação e segurar o resultado por cerca de 0,4 s. Exibir a barra de vida de Nox apenas para cura, redução de dano e salvamento letal. Quando uma diferença pequena não alterar um segmento visível, usar um indicador compacto de antes/depois a partir da variação real. Usar uma indicação discreta de **F** ou **Shift** apenas quando o comando explicar o efeito.

## Preparação das tomadas

Criar futuramente uma cena isolada de gravação com Nox, arma, controlador de efeitos, piso e marcadores de posição. Usar os recursos de cartas e o fluxo de combate do jogo. Cada tomada guarda ID da carta, cenário, posições, vida inicial, semente quando aplicável, ações e duração. Configurar esses valores antes da gravação e deixar que disparos, ataques, abates, cura e recompensas aconteçam pela lógica normal. Reiniciar o estado entre tomadas, incluindo efeitos, recargas, cargas, projéteis, aliados e recompensas isoladas da sessão.

| Preset | Montagem |
| --- | --- |
| **Duelo** | A resistente a vários acertos. Varia entre parado, cruzando o quadro e vindo para um golpe real. |
| **Linha** | A e B alinhados com espaço entre as silhuetas. Para feixe, B fica atrás de A e deve permanecer intacto até liberar a linha. |
| **Grupo** | A no centro, B e C nas laterais. Ajustar vida e espaçamento para o raio real de cada carta. Para I01, ensaiar os centros das hitboxes no quadro do impacto e aproximar os minotauros por entradas marcadas se a separação normal desfizer a cadeia. |
| **Parede** | Um obstáculo do jogo, extremo visível e colisão real. Testar o percurso sem disparar antes de gravar. |
| **Vida baixa** | Começar com vida faltando, abaixo de 50% para I09, e preparar vida suficiente para o golpe letal de U06. Fixar ângulo e dano do ataque quando houver comparação. |

As Manifestações são capturadas com Infusão e Mutação vazias. Nas demais, usar M01 como disparo de referência, salvo quando a tomada pede uma variante específica; o terceiro espaço fica vazio. Para passivas, Nox evita atirar até o momento em que o roteiro exige um disparo. Fixar ou preparar a seleção aleatória da tomada usando os meios do banco de gravação, sem trocar a lógica de sorteio do jogo.

## Roteiro por carta

O [catálogo jogável](../scripts/cards/card_effect_catalog.gd) tem **36 cartas**: 10 Manifestações, 13 Infusões e 13 Mutações. Os seis grupos abaixo seguem o [catálogo editorial](CARTAS.md). M03 fica separada por ser uma carta de estudo. Os tempos são metas de edição, não mudanças de recarga ou duração de gameplay.

### Monster Booster Vol. 1

| Carta | Preparação e ação | O que precisa aparecer |
| --- | --- | --- |
| **M01 · Gotas de Slime** | Duelo. Dar dois tiros espaçados em A. | Gota saindo do cano, trajetória reta e impacto no primeiro alvo. |
| **I01 · Núcleo de Golem** | Grupo. A morre com M01, B e C têm vida ajustada para tombar nas explosões sucessivas. Se possível, posicionar D fora do alcance inicial e dentro do alcance de uma explosão posterior. | Explosão no ponto de cada abate e avanço da cadeia de um Minotauro ao outro. |
| **U01 · Coração da Fúria** | Duelo. Nox dá alguns passos sem bônus, elimina A e continua andando com o mesmo comando, sem dash. | Mudança de velocidade após o abate. Usar marcas discretas no piso para a distância ficar evidente. |
| **M02 · Massa de Slime** | Linha. Um tiro em A e B; para separar a leitura, colocar B além da área da primeira explosão, dentro da distância do projétil. | Primeiro impacto explode e a bala segue, atravessando até acertar B. |
| **I03 · Fragmento de Odopi** | Vida baixa. Finalizar A com M01. | O abate devolve uma parcela da vida de Nox. A barra ou um pequeno sinal de cura precisa mudar no quadro. |
| **U06 · Doppelgänger** | Tomada principal: A avança, Nox pressiona **F** com direção livre. Variante: começar com vida letal e recarga pronta, deixar A golpear sem apertar **F**. | Na principal, cópia fica no ponto de partida, A se volta para ela e Nox avança translúcido com a arma oculta. Na variante, o golpe letal dispara o efeito e Nox reaparece com vida. Juntar as duas tomadas em um clipe curto com corte visível. |

### Monster Booster Vol. 2

| Carta | Preparação e ação | O que precisa aparecer |
| --- | --- | --- |
| **M05 · Fragmentos de Basilisco** | Quadro largo. A e B deslocados na frente de Nox. Disparar duas vezes com semente reproduzível que produza padrões diferentes. | Cinco fragmentos azuis independentes por disparo, com espalhamento irregular visível antes dos impactos. |
| **I02 · Casca Estilhaçante** | Grupo. A está prestes a morrer, B e C ocupam direções radiais diferentes, fora da linha do tiro de Nox. | O golpe letal origina seis flechas de luz e algumas acertam os vizinhos. |
| **U02 · Pele de Medusa** | Vida baixa. A acerta um golpe real em Nox e sobrevive. Depois, Nox recua e deixa a cobra agir sozinha. | Cobra sai dos pés de Nox, persegue e morde. Estender até a terceira mordida e derrota da cobra se couber; guardar a variante de expiração por tempo no mestre. |
| **M06 · Caçaluz** | Duelo. Mirar ao lado de A, que fica perto e visível para a arma. | Clarão parte na direção da mira e curva para atingir A. Se o arco parecer reto, abrir o ângulo da tomada. |
| **I04 · Ovo de Slaad** | Grupo. A e B sobrevivem aos tiros portadores; C é hostil e resistente. Acertar A, esperar os 3 s reais de recarga e acertar B. | Parasita grudado, A ou B atacando C e os dois aliados coexistindo. O fim do controle de A pode entrar por corte a partir da tomada longa; não encurtar os 12 s no jogo. Validar a transferência também com M07 em tomada auxiliar. |
| **U05 · Espada do Herói** | Nox se move brevemente, depois para de atirar. A se aproxima ou fica a média distância. Tomada auxiliar com três alvos próximos para o corte longo. | Espada flutua ao lado de Nox, sai por conta própria e ataca. Enquadrar estocada ou corte e a volta à posição de repouso. Mostrar o corte longo só se a tomada principal continuar clara. |

### Monster Booster Vol. 3

| Carta | Preparação e ação | O que precisa aparecer |
| --- | --- | --- |
| **M07 · Coração de Efreeti** | A próximo e B na borda do leque. Disparar um único tiro com espaço livre à frente do cano. | Cinco brasas saem com separação visível e várias podem atingir A. |
| **U03 · Chão Carnívoro** | A entra no alcance com a passiva pronta. Nox fica parado; B pode cruzar a borda da área quando a mordida abre. | Mordida brota do chão e atinge o Minotauro. O intervalo até o impacto vem da mecânica e a tomada usa o visual atual, sem recolocar o círculo antigo. |
| **U04 · Mandrágora de Bolso** | A e B se aproximam por lados diferentes. Pressionar **F** com espaço atrás de ambos. | Mandrágora sobre a cabeça, feedback branco translúcido e os dois minotauros repelidos. |
| **M04 · Olho de Beholder** | Linha. Sustentar a mira em A com B atrás e depois desviar a mira ou soltar. | Feixe contínuo termina no primeiro alvo e cessa ou muda de direção com Nox. |
| **I05 · Essência de Quimera** | A resistente, espaço para empurrão. Disparar três tiros de M01 conforme a sequência real da carta, preparando a rotação antes de gravar. | Distinguir o tiro de fogo pelo contorno, o de veneno pelo efeito no alvo e o de empurrão pelo deslocamento. Reservar variante com ataque contínuo para conferência. |
| **I11 · Carapaça de Gárgula** | Parede. M01 mira obliquamente na parede; A só pode ser atingido pelo retorno. Gravar também M04 e M08 neste preset. | Clipe principal: um ricochete e impacto fora da linha reta de Nox. Variantes: feixe e sopro refletem pelo alcance restante; mostrar interseção com a parede e alvo depois da quina. Se as três tomadas ficarem apertadas no pop-up, manter apenas a principal e uma contínua. |

### Elementais de Calimshan

| Carta | Preparação e ação | O que precisa aparecer |
| --- | --- | --- |
| **M09 · Prisma Fendido** | Colocar A e B fora do eixo central, depois do ponto de divisão. Variante curta: A perto o bastante para receber o cristal inteiro. | Cristal viaja inteiro e abre em dois estilhaços. Usar uma segunda tomada perto apenas se a distância for difícil de inferir. |
| **U07 · Passo de Cinza** | Marcar a rota do dash. A cruza a área depois do movimento. | Faixa vermelha discreta fica no piso; A entra, sofre dano e recebe queimadura. Manter o visual atual da área. |
| **I06 · Núcleo de Eletricidade** | A começa como único alvo elegível; B entra depois que A recebe o raio. Ajustar A para sobreviver ao raio e morrer com M01 durante o atordoamento. | Raio automático, A interrompido, abate e descarga até B. Gravar as duas variantes visuais do raio em mestres separados; usar a mais legível na prévia. |
| **I07 · Núcleo de Fogo** | A resistente com até dois vizinhos próximos; acertar A uma vez com recarga pronta e esperar a propagação. | Fumaça cinza por trás do sprite de A, depois nos vizinhos. A fica vivo enquanto transmite o efeito. |
| **I08 · Núcleo de Gelo** | A se aproxima em piso válido. Deixar a passiva ativar e atirar durante a imobilização. | Espinhos, indicador de gelo acima do alvo e interrupção do movimento. O bônus pequeno de dano fica na descrição da carta; o clipe privilegia o congelamento. |
| **U08 · Convergência Primordial** | **F**, deslocamento, **F**. A cruza a ligação. Gravar em piso livre e com uma quina curta como variante. | Duas runas, feixe, A tomando dano e parando. Usar a variante com quina se os dois extremos e a rota continuarem claros; mostrar o terceiro **F** no final se couber. |

### Set do Vampiro

| Carta | Preparação e ação | O que precisa aparecer |
| --- | --- | --- |
| **M10 · Presas Rubras** | A posicionado na interseção. Um único disparo, câmera fixa. | Duas lâminas se cruzam e ambas atingem A. Afastar levemente a câmera se o cruzamento sumir no tamanho do painel. |
| **U09 · Manto do Crepúsculo** | Vida baixa, A agressor. Receber um golpe com proteção pronta e outro depois dos quadros de invulnerabilidade, antes da recuperação do manto. | Pulso do manto e perda menor no primeiro golpe. Capturar a proteção restaurada em variante após a janela sem dano. |
| **I09 · Sede da Cripta** | Nox abaixo de metade da vida e recarga pronta. Atirar uma vez em A com vida suficiente para sobreviver. | Nox recupera vida por acerto; A continua de pé, deixando a diferença para I03 evidente. |
| **I10 · Marca do Algoz** | Capturar o golpe de A sem marca e repetir em condições iguais após marcar A com M01. Alternativa com A e B atacando de forma alternada, fora da invulnerabilidade. | Marca visível em A e perda menor de vida quando A ataca. Comparar ataques iguais sem depender de uma diferença de cor no inimigo. |
| **U10 · Pulso Carmesim** | Começar com vida faltando e a reserva quase completa, preparada com acertos anteriores. Completar com o último acerto real, pressionar **F**, esperar os pulsos. | Carga fica pronta e Nox recupera vida em etapas. Mostrar pelo menos dois pulsos; manter o ciclo completo no mestre. |
| **U11 · Cortejo da Meia-Noite** | Vida baixa. A e B resistentes próximos; pressionar **F** e manter Nox parado. | Quatro morcegos saem, mordem e voltam a Nox. Destacar a recuperação só quando chegam de volta. |

### Set do Dragão

| Carta | Preparação e ação | O que precisa aparecer |
| --- | --- | --- |
| **M11 · Brasa em Espiral** | Quadro largo. A e B separados em profundidade. Manter o disparo por uma sequência completa, com mira fixa. | Brasas saem em sequência e a rajada abre suas curvas ao avançar. |
| **U12 · Bater de Asas Carmesim** | A no caminho da rajada e com espaço atrás; executar um dash com a direção travada para a tomada. | Rajada nasce no dash, alcança A e o empurra; Nox não precisa atirar. |
| **I12 · Meteoro de Dragão** | A prestes a morrer e B como único sobrevivente elegível próximo. Finalizar A com M01. | Abate em A, triângulo de aviso e meteoro caindo em B. |
| **I13 · Acúmulo Ígneo** | A resistente. Acertar quatro tiros consecutivos no mesmo alvo. | Acúmulo de calor e dano extra no quarto impacto. Manter a cadência real. |
| **U13 · Ganância da Fera** | Preparar contador em 99 abates na sessão de gravação e eliminar A pelo combate real. | A última eliminação registra um booster no HUD original. Encerrar na confirmação; a animação aberta com **B** não é necessária para explicar a carta. |
| **M08 · Sopro de Dragão** | Quadro largo, A e B dentro do leque e C na borda externa, se couber. Sustentar e soltar. | Sopro contínuo cobrindo múltiplos alvos enquanto Nox mantém o ataque, depois desaparece. A variante refletida pertence ao showcase de I11. |

### Carta de estudo

| Carta | Preparação e ação | Entrega |
| --- | --- | --- |
| **M03 · Grito de Banshee** | Se for mantida na coleção como estudo, preparar A e B no cone; manter o disparo até o calor aparecer. O comportamento arquivado é um cone contínuo com superaquecimento. | Separar como **Prévia de estudo**. Antes de publicar um clipe, confirmar se o legado roda em cenário isolado ou se o design será revisto. Até lá, usar a carta estática. Nenhum clipe de M03 na abertura de boosters. [Referência legada](old/documentacao/manifestacoes_sala_porta.md#M03--grito-de-banshee) |

## Captura e exportação

1. **Produzir mestres.** Gravar offline pelo Movie Maker da Godot com relógio de captura de 60 fps, usando PNGs em sequência para preservar os pixels. Gravar um pouco antes e depois da ação. Guardar mestres e tomadas extras em `output/card_showcase/master/<ID>/`, fora dos recursos distribuídos. [Movie Maker da Godot](https://docs.godotengine.org/en/stable/tutorials/animation/creating_movies.html)
2. **Editar.** Usar base **320 × 180**, 30 fps e **3–5 s** como ponto de partida. Permitir **6–7 s** para cartas em duas etapas. Recortar com o quadro já composto; se houver escala inteira, usar nearest. Somente em efeitos rápidos que percam um quadro decisivo, comparar 60 fps ou ajustar o início da amostragem. Fazer cortes explícitos em esperas longas; manter a ordem real das ações. Fechar a tomada antes de reiniciar, sem rebobinar efeitos.
3. **Distribuir em Ogg Theora (`.ogv`) sem áudio.** Usar `VideoStreamPlayer`, que oferece reprodução nativa. Codificar offline com FFmpeg/libtheora, sem trilha de áudio. Comparar dois níveis de qualidade em bordas saturadas, partículas finas e sprites em movimento. Começar com meta de **150–250 KiB por carta**, cerca de **5,3–8,8 MiB** para os 36 clipes, sem contar pôsteres. O orçamento é uma meta para medir no lote piloto. O Theora decodifica na CPU, por isso o plano usa um player por vez. [Formatos e limites de vídeo da Godot](https://docs.godotengine.org/en/stable/tutorials/animation/playing_videos.html)
4. **Manter uma alternativa simples.** Gerar um quadro estático PNG por carta para abertura, falha de carregamento e movimento reduzido. GIF serve para revisão e compartilhamento fora do jogo. Se a compressão de um efeito com pixel fino ficar ruim no tamanho real, comparar uma sequência lossless de poucos quadros somente para aquele clipe, medindo memória e nitidez junto com o tamanho em disco.
5. **Organizar por ID.** Caminhos propostos: `assets/cards/showcase/M01/clip.ogv` e `assets/cards/showcase/M01/poster.png`. Usar o alias do catálogo para I01–I13 e U01–U13, pois alguns recursos usam nomes internos como `CARD_INF_004`. Um índice de recursos liga cada alias ao clipe, pôster e versão da captura e garante inclusão na exportação. Testar o build exportado, não só o editor.

## Reprodução na coleção e no pack

O mesmo painel é usado nas duas telas. Ele abre **acima da carta visível**, centralizado pela borda superior, sem tapar nome ou descrição. Se faltar altura, posiciona-se ao lado da carta dentro da área segura. O painel ignora o mouse, para a própria prévia não derrubar o hover nem bloquear clique ou arraste.

| Momento | Comportamento proposto |
| --- | --- |
| Cursor sobre uma carta elegível por cerca de 180 ms | Mostrar o pôster e carregar apenas o clipe da carta. Iniciar do começo quando estiver pronto e repetir enquanto o hover durar. |
| Cursor troca de carta, sai ou começa a arrastar | Parar o clipe e esconder o painel. Se um carregamento anterior terminar atrasado, descartar o resultado em vez de abrir a carta errada. |
| **Coleção** | Usar o mesmo alvo frontal que o clique já seleciona na mesa. Pilha fechada e cartas encobertas ficam sem prévia. Durante inspeção, vale apenas a carta inspecionada. O painel atualiza mesmo com o mundo pausado. |
| **Pack** | Esperar o rasgo e a revelação terminarem para a carta elegível. Na pilha, só a carta da frente. Depois de distribuir, só a carta visível sob o mouse. Fechar a prévia ao virar, avançar ou fechar o pack. |
| Sem clipe ou movimento reduzido | Mostrar o pôster quando disponível. A leitura da carta continua acessível pelo texto mesmo sem mídia. |

Mapear a integração da coleção em [card_table.gd](../scripts/cards/card_table.gd) e a elegibilidade das recompensas em [booster_card_stack.gd](../scripts/pack_opening/booster_card_stack.gd), usando o estado do [booster_viewer.gd](../scripts/pack_opening/booster_viewer.gd) para excluir a abertura e o fechamento. As duas origens consultam o mesmo índice. Cada hover tem no máximo um clipe ativo e não carrega os vídeos do catálogo inteiro.

## Ordem de produção e aceite

1. **Lote piloto:** M01 para enquadramento, I01 para explosões em cadeia e compressão, U06 para corte entre variantes, I11 para parede e I09 para leitura da vida. Conferir nitidez e tamanho no pop-up da mesa e do pack.
2. **Produção em lotes:** gravar armas primeiro, depois o conjunto de abates/controle, e por último o conjunto que depende de Nox receber dano, cura ou carga. Reaproveitar os mesmos presets de Minotauro.
3. **Aceite por clipe:** ID correto, gatilho e resultado visíveis, Minotauro reconhecível, efeito fiel à carta, sem corte de projétil decisivo e sem alteração na sessão jogável. O quadro estático também precisa explicar onde olhar.
4. **Aceite no jogo:** percorrer várias cartas rapidamente, testar pilha, arraste, inspeção, fechamento e reabertura. Conferir que não há mais de um vídeo ativo, que nenhuma prévia antiga aparece depois da troca e que o build exportado encontra os recursos. Medir tempo até o primeiro quadro, pico de memória, impacto nos frames da interface e tamanho do lote antes de bater o martelo no perfil de compressão.
