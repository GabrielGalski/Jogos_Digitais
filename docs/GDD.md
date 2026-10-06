# GDD — Monster Booster

Este documento define a proposta e as regras de design. O [TDD](TDD.md) distingue essas regras do que o código já executa; o [guia](GUIA.md) reúne o fluxo de trabalho. Valores de recursos e scripts são a referência para ajustes numéricos.

## Identidade

Roguelike de ação em visão superior, com combate bullet hell e combinações de cartas de monstros. Nox usa o Booster Shooter para enfrentar os domínios dos Dark Lords. O tom combina ambição, estranheza e humor: um pequeno invasor confronta criaturas muito maiores e arrogantes.

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

M08, o lança-chamas de teste, não acrescenta por si só uma carta aprovada ao catálogo. Probabilidades dos boosters, raridades individuais e economia precisam de definição própria; não deduzir essas regras dos placeholders.

## Tutorial e Asterion

O tutorial apresenta movimentação, arma, combate, elite e recompensas em um encontro curto, de baixa dificuldade. Nox fala por símbolos; Asterion usa diálogos provocativos. As falas são mantidas nos recursos de diálogo, sem uma segunda transcrição neste documento.

Sequência de referência:

1. Explorar desarmado e conversar com Asterion.
2. Revelar o Booster Shooter e explicar os comandos.
3. Enfrentar a primeira horda; voltar a Asterion ao concluir.
4. Restaurar a vida de Nox, apresentar o Skybreaker e explicar o confronto de elite.
5. Enfrentar Asterion e seus minotauros fortalecidos.
6. Asterion se rende e permanece na cena; encerrar ataques e minions.
7. Mostrar recompensas, liberar a saída e seguir para o corredor de Tin.

Diálogos e explicações de comandos avançam com `E`. A apresentação não deve manter dano ativo enquanto tira o controle do jogador. Se Nox e Asterion chegarem à derrota juntos, a derrota de Nox tem prioridade. No tutorial, perder reinicia o encontro.

A recompensa é concedida uma vez por tentativa: as duas cartas iniciais e três boosters, um de cada coleção, com três cartas por pacote. A última posição do primeiro pacote deve garantir uma Mutação comum. Não acumular um quarto booster pela regra genérica de recompensa de elite. O TDD registra o limite atual entre essa regra e a abertura visual.

## Combate e leitura

- Base de referência atual: Nox com 60 de vida, minotauro com 18 e Asterion com 270.
- Asterion precisa expor janelas de vulnerabilidade no chão e anunciar o Skybreaker antes do impacto; sentado e em voo não são janelas normais de dano.
- Minotauros devem oferecer pressão de horda e ataques antecipáveis. Navegação, separação e densidade precisam preservar espaço de resposta.
- O disparo inicial causa 3 de dano e a Infusão inicial acrescenta uma explosão de 3. A meta de eliminar o minotauro em dois acertos não corresponde ao resultado de três acertos completos dessa base; exige decisão de balanceamento, não alteração silenciosa da documentação.
- Multiplicidades e valores experimentais devem ser revisados antes de aprovação. Recursos de preview não são padrões finais do jogo.

## Direção visual

O mundo usa vinho, roxo e sombras profundas. Os poderes podem destoar da paleta de propósito: cor funcional forte ajuda a reconhecer origem e comportamento. A unidade vem dos contornos, tratamento de sombra, escala dos pixels, brilho contido e duração dos efeitos, não de recolorir todos os tiros como o cenário.

No tutorial, luzes suaves acompanham as duas crateras, as correntes e Asterion; sem feixes geométricos explícitos. No mercante, o ambiente mais escuro destaca os neons da fachada e da porta, a água e Tin. Folhas são uma cobertura visual de primeiro plano, sem física e sem luz projetada própria.

A vida de Nox aparece somente na barra, sem números, com verde `#2cf7a3` e aviso vermelho ao cruzar um bloco. Com 60 de vida e seis blocos, cada bloco representa **10 pontos, ou 16,7%**, não 10% da vida total. A barra usa pixels nítidos, sem filtro bilinear. A barra de Asterion usa a moldura própria e o nome centralizado acima; a redução usa `#b14c47`, `#a0251f` e `#841f1a`.

## Abertura de boosters e ambientação

Direção para a abertura: um corte guiado pelo mouse sobre o lacre, aceitando ambos os sentidos. Confirmar o gesto uma única vez, então rasgar o pacote e fazer surgir a stack de cartas junto a uma explosão curta de partículas. Priorizar partículas atrás das cartas, com poucos detalhes à frente e sem flash de tela inteira. O gesto e o burst são proposta, não descrição do viewer atual.

Áreas de ambientação permitem posicionar aparições ocasionais fora da área jogável: olhos, bocas ou tentáculos animados. São somente visuais, sem dano, colisão ou interação. A lógica existe; os sprites e suas ligações são uma etapa separada.
