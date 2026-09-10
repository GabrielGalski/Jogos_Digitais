# Mapeamento do tileset atual de paredes

Revisão: 10 de setembro de 2026 — **conexão esquerda revisada; 64 px úteis + 1 px opcional; QE/QD confirmados como extremidades de IE/ID**. Escopo: dimensões, recortes e composição visual; não implementa mapas ou colisões.

- [Atlas anotado](tileset_paredes_atlas.png) · [SVG](tileset_paredes_atlas.svg)
- [Demonstração das emendas e da borda exposta](tileset_paredes_encaixes.png) · [SVG](tileset_paredes_encaixes.svg)
- [Catálogo de recortes em JSON](tiles/wall_tileset_mapping.json)

## Fonte atual e revisão

O arquivo de referência desta revisão é `assets/tiles/wall/wall_tileset.png`, com **256×256 px**. As quatro variantes retas tiveram o desenho atualizado, incluindo a conexão. As coordenadas permanecem: borda opcional em x=191 e corpo útil de x=192 a x=255. Foram detectados 1.064 pixels alterados desde o levantamento anterior, todos nas quatro variantes retas.

**O arquivo `wall_tileset.ase` não acompanha essa revisão:** seu hash permanece igual ao levantamento anterior e a coluna x=191 não contém a nova borda. Não reexportar esse arquivo sobre o PNG atualizado antes de sincronizá-lo. Nenhuma das duas fontes foi alterada por este mapeamento.

As quinas, modelos internos, laterais e terminais do PNG não mudaram em relação ao levantamento anterior. Os arquivos em `assets/tiles/wall/old/` continuam sendo históricos.

## Regras confirmadas pelo autor

1. O corpo útil de cada variante reta mede **64 px**, equivalente a quatro células de 16 px. A altura do recorte continua em 48 px.
2. A borda extra de **1 px** aparece somente em quebras, como portas e outras passagens. Não aparece em emendas contínuas.
3. O avanço de um modelo reto é **64 px**, com ou sem acabamento exposto. A borda é margem visual, não uma unidade adicional do mapa.
4. Os cortes do corpo respeitam **16×16 px**. Comprimentos de 16, 32, 48 e 64 px mantêm a grade.
5. Nas junções internas com paredes laterais vistas de cima, preservar o modelo interno correspondente ao lado.
6. Nas paredes externas, combinar W01–W04 sem repetir o mesmo sprite em duas instâncias consecutivas.
7. QE e QD são acabamentos sobrepostos ao extremo correspondente da parede, alinhados ao seu pixel extremo. A arte é a mesma presente nas extremidades dos modelos internos IE e ID. Não acrescentam um módulo nem substituem a junção interna com a lateral.
8. A referência de Mox permanece em **aproximadamente 16–18 px de altura**, perto da terceira faixa de ladrilhos de cima para baixo. Não existe regra de escala 4×.

## Dimensões principais

| Elemento | Dimensão da fonte/recorte | Medida útil ou visível |
| --- | --- | --- |
| Atlas de paredes | 256×256 px | limite alfa total (0,19)–(256,256), fim exclusivo |
| Variante reta com borda | 65×48 px | 65×45 px visíveis, a partir da linha local 3 |
| Corpo de variante reta | 64×48 px | 64×45 px visíveis; avanço horizontal de 64 px |
| Borda opcional | 1×48 px | 1×45 px visíveis; cor #25131a |
| Junção interna IE/ID | 64×48 px cada | contém sua própria intersecção com a lateral |
| Célula lateral vista de cima | 16×16 px | faixa com 8 px de largura visível |
| Quinas/terminais | células nominais de 16 px; alguns recortes têm 17 px | preservar margens próprias, sem deslocar a grade |
| Piso | atlas de 64×48 px | 4×3 células de 16×16 |
| Borda inferior de plataforma | atlas de 128×32 px | arte até y=22 inclusive; recurso independente |
| Portas frontais | 32×32 px | abertas: bbox completo; fechadas: (0,5,32,32) |
| Coluna redonda decorativa | 32×64 px | bbox (10,11,22,54): 12×43 px |
| Coluna quadrada decorativa | 32×64 px | bbox (9,11,24,54): 15×43 px |

A origem dos retângulos é o canto superior esquerdo. A notação `(x,y,w,h)` usa largura e altura; bboxes usam coordenadas finais exclusivas.

## Recortes das quatro variantes

| ID | Fonte com acabamento | Corpo usado na montagem | Borda opcional |
| --- | --- | --- | --- |
| W01 | (191,16,65,48) | (192,16,64,48) | (191,16,1,48) |
| W02 | (191,80,65,48) | (192,80,64,48) | (191,80,1,48) |
| W03 | (191,144,65,48) | (192,144,64,48) | (191,144,1,48) |
| W04 | (191,208,65,48) | (192,208,64,48) | (191,208,1,48) |

O corpo começa em x=192, que já está alinhado à grade do atlas. **Não recortar em x=193:** isso removeria um pixel útil.

Para uma variante com origem vertical `Y`:

- colunas de 16 px: x=192, 208, 224 e 240;
- linhas de 16 px: y=Y, Y+16 e Y+32;
- primeira célula superior: `(192,Y,16,16)`;
- última célula superior: `(240,Y,16,16)`;
- terceira faixa vertical: `(192,Y+32,64,16)`;
- topo transparente: 3 px, preservados para alinhamento;
- altura visível: 45 px; altura do recorte: 48 px.

O recorte completo de 65 px não é uma célula regular do mapa. Ele serve para extrair o corpo e seu acabamento separadamente.

## Montagem em grade

### Emendas contínuas

Desenhar apenas os corpos, sem sobreposição e sem coluna extra:

```text
origem do trecho: X
W01: X
W02: X + 64
W03: X + 128
W04: X + 192
fim exclusivo: X + 256
```

Para `m` modelos completos:

```text
comprimento útil = 64 × m
```

| Modelos | Células de 16 px | Comprimento útil |
| --- | --- | --- |
| 1 | 4 | 64 px |
| 2 | 8 | 128 px |
| 3 | 12 | 192 px |
| 4 | 16 | 256 px |
| 8 | 32 | 512 px |
| 12 | 48 | 768 px |

Não subtrair pixels de emendas, não avançar 65 px e não sobrepor corpos. A borda opcional não participa dessa conta.

### Borda em interrupções

Para uma quebra à esquerda de um corpo cuja origem é `X`:

```text
corpo: começa em X e tem 64 px úteis
borda opcional: desenhada em X − 1, com largura de 1 px
origem do próximo corpo contínuo: X + 64
```

Também é possível desenhar a fonte completa de 65 px em `X−1`, desde que o posicionamento lógico continue referenciado ao corpo em `X`. As duas formas são equivalentes; não desenhar a borda duas vezes.

A borda aparece porque existe uma extremidade exposta, não porque chegou o primeiro módulo de uma lista. Um trecho que começa ligado a uma quina ou junção não recebe borda extra automaticamente.

A fonte fornece a borda à esquerda. Acabamentos do lado direito, portas superiores/inferiores e passagens devem ser compostos conforme sua orientação e testados com os sprites existentes; não espelhar a parede inteira nem inventar deslocamentos da porta.

Uma borda exposta à esquerda faz a extensão visual de um corpo de 64 px ser 65 px; sua extensão útil continua sendo 64 px. Ao medir um vão, considerar se os acabamentos ocupam espaço visual dentro dele e definir a colisão separadamente.

### Cortes

A origem dos cortes é o corpo em x=192, nunca a coluna extra em x=191.

Para um corte de `k` células, a partir da coluna `c` da variante:

```text
source_rect = (192 + 16c, Y, 16k, 48)
0 ≤ c < 4
1 ≤ k ≤ 4 − c
avanço = 16k
```

Cada trecho também pode ser decomposto nas três linhas de 16 px da face. A borda opcional continua um acabamento separado, inclusive quando o corte começa no interior de um modelo.

Exemplos de comprimento reto, antes de aplicar as junções específicas:

- 256 px: 64 + 64 + 64 + 64.
- 272 px: 64 + 64 + 64 + 64 + 16.
- 320 px: cinco corpos de 64 px.
- 384 px: seis corpos de 64 px.

Assim, o preenchimento reto pode atender qualquer comprimento positivo múltiplo de 16 px com os cortes permitidos. A possibilidade de fechar uma sala inteira ainda depende das quinas, portas e junções.

### Alternância

Excluir o ID da instância anterior ao escolher W01–W04 no mesmo trecho contínuo. Cortar uma única instância em várias células não transforma essas células em repetições proibidas.

Exemplo válido: `W01 → W03 → W02 → W04 → W01`.

Manter a escolha estável por semente no futuro gerador. Ao reparar ou unir regiões, revalidar as duas pontas da sequência. A regra não exige distribuição uniforme das quatro variantes.

## Quinas, junções e laterais preservadas

| ID | Identificação | Recorte (x,y,w,h) | Encaixe nominal / observação |
| --- | --- | --- | --- |
| QE | Mesmo acabamento dos últimos 16 px de IE | (48,16,16,48) | primeira célula superior: (48,16,16,16) |
| QD | Mesmo acabamento dos primeiros 17 px de ID | (127,16,17,48) | nominal (128,16,16,48), com 1 px à esquerda |
| IE | Junção interna à lateral esquerda | (0,128,64,48) | preservar célula (0,128,16,16) |
| ID | Junção interna à lateral direita | (112,128,64,48) | preservar célula (160,128,16,16) |
| TSE | Terminal superior da lateral esquerda | (0,64,17,48) | 1 px de margem à direita |
| TSD | Terminal superior da lateral direita | (160,64,16,48) | recorte nominal de 16 px |
| TIE | Terminal inferior da lateral esquerda | (0,208,17,48) | 1 px de margem à direita |
| TID | Terminal inferior da lateral direita | (160,208,16,48) | recorte nominal de 16 px |
| LE | Lateral esquerda repetível verticalmente | (0,176,16,16) | faixa visível x=0..7 |
| LD | Lateral direita repetível verticalmente | (160,176,16,16) | faixa visível x=168..175 |

As posições são medidas da arte. A função compartilhada de QE/QD foi confirmada pelo autor e pela comparação exata dos pixels. Os IDs QE/QD seguem a identificação do atlas; não devem ser interpretados isoladamente como uma ordem automática de colocação na tela. O Aseprite não nomeia semanticamente essas peças.

### Correspondência exata entre acabamentos e modelos internos

| Acabamento isolado | Região idêntica na parede interna | Resultado |
| --- | --- | --- |
| QE: (48,16,16,48) | IE: (48,128,16,48), seus últimos 16 px | zero pixels diferentes, incluindo alfa |
| QD: (127,16,17,48) | ID: (112,128,17,48), seus primeiros 17 px | zero pixels diferentes, incluindo alfa |

Na referência IE, QE aparece na extremidade livre à direita; na referência ID, QD aparece na extremidade livre à esquerda. Isso descreve o desenho medido, não renomeia as peças.

A aplicação deve alinhar a silhueta da quina ao pixel extremo da parede e sobrepor o acabamento na posição correspondente, preservando a largura útil existente. **A referência ao pixel extremo é de alinhamento: a quina não deve ser recortada para ter só 1 px de largura.** Seus recortes continuam com 16 ou 17 px, incluindo a face vertical.

Na demonstração, QE é sobreposto em IE no deslocamento local (48,0), e QD é sobreposto em ID no deslocamento local (0,0). O resultado é visualmente idêntico aos modelos internos originais. Para outros comprimentos, transportar o acabamento para a nova extremidade equivalente, sem esticar a arte nem criar um módulo adicional.

Preservar a distinção entre **a junção com a lateral** e **a extremidade livre**: IE/ID já contêm ambas; QE/QD reaproveitam a arte da extremidade livre. A borda reta opcional de 1 px em x=191 também continua sendo outro elemento, reservado às quebras.

- As quinas ocupam a célula de extremidade: não acrescentam uma célula de 16 px ao comprimento.
- O excedente de QD/TSE/TIE é próprio do acabamento; não é a nova borda opcional das variantes retas.
- A seleção da quina atua na célula superior, mas o recorte completo preserva a face abaixo dela quando necessária.
- Uma sobreposição com transparência precisa respeitar a silhueta: não deixar o canto da base aparecendo por trás.
- IE é obrigatório na junção interna à esquerda; ID é obrigatório na junção interna à direita. O miolo pode continuar com variantes retas.
- Não subtrair uma coluna de IE/ID por associação com a regra antiga: esses recortes não são módulos de 65 px.
- TSE/TSD têm 6 px transparentes acima da arte; IE/ID e TIE/TID já contêm pixels da lateral no topo. Não alinhar tudo pelo primeiro pixel visível.
- Encontros curtos precisam comportar as duas junções sem colisão visual; não esticar quinas para resolver falta de espaço.

## Escala de Mox

Os dez frames atuais de idle/run usam canvas de **16×16 px**.

| Grupo | Altura visível | Largura visível |
| --- | --- | --- |
| Idle | 13–15 px | 12–13 px |
| Corrida | 14–15 px | 12 px |
| Referência do autor | aproximadamente 16–18 px | ainda não especificada |

Medição por alfa: não representa o corpo de colisão. Os assets continuam um pouco abaixo da altura visual de referência e não foram redimensionados.

A base de uma parede com origem vertical `Y` está em `Y+48`, fim exclusivo. Alinhado a essa base, um personagem de 16 px teria topo em `Y+32`; um de 18 px, em `Y+30`. Isso aproxima Mox da terceira faixa vertical de 16 px.

A parede tem 45 px visíveis, cerca de 2,5–2,81 vezes a referência de altura de Mox. Essa é uma relação de projeção visual; não define altura física ou colisão.

## Planejamento das dimensões dos mapas

O piso permanece em células de 16×16:

```text
largura do piso = colunas × 16
profundidade do piso = linhas × 16
```

| Grade de piso | Dimensão em pixels | Preenchimento reto equivalente na largura |
| --- | --- | --- |
| 20×12 | 320×192 | 5 corpos de 64 px |
| 24×16 | 384×256 | 6 corpos de 64 px |
| 30×18 | 480×288 | 7 corpos + corte de 32 px |
| 40×24 | 640×384 | 10 corpos de 64 px |
| 48×32 | 768×512 | 12 corpos de 64 px |

São exemplos para planejamento, não tamanhos aprovados de arena. A última coluna considera somente um trecho reto, sem descontar regiões ocupadas por portas e junções específicas.

O montador deverá:

1. Delimitar o chão e as posições das passagens na grade de 16 px.
2. Reservar as células de quinas e junções internas.
3. Preencher os intervalos retos com corpos e cortes, avançando exatamente sua largura útil.
4. Mostrar acabamentos extras somente nas interrupções expostas.
5. Validar a união visual e o espaço disponível para navegação.

Os 48 px de altura da parede não consomem automaticamente três linhas navegáveis do piso. Face frontal, topo e apoio no chão precisam ser separados antes de criar a colisão. A faixa lateral de 8 px também é uma medida visual, não uma colisão aprovada.

A câmera atual usa viewport lógico de **480×270 px** e janela de **960×540 px**. Sem zoom adicional e com uma unidade por pixel, a largura corresponde a 30 células de piso; a altura, a 16 células e 14 px. Um piso de 30×18 células já excede essa altura, antes de incluir paredes.

A extensão visual final é a união de piso, paredes, quinas, portas e decoração. As bordas extras podem ultrapassar o retângulo lógico sem alterar o tamanho das células. O piso de 43×24 citado em documentos antigos pertence ao MVP; a cena ativa continua vazia.

## Validação desta revisão

- Atlas permanece em 256×256 px.
- Quatro recortes completos de 65×48 px e quatro corpos de 64×48 px conferidos.
- Coluna x=191 é acabamento escuro nos 45 px visíveis de cada variante.
- O corpo x=192 foi redesenhado e não é mais uma coluna escura contínua.
- As **12 combinações ordenadas entre variantes diferentes** foram reconstruídas com avanço de 64 px e sem borda extra na emenda. Não há uma dupla de pixels transparentes atravessando a emenda abaixo do topo transparente. A nova arte usa transições de cor para separar ladrilhos; igualdade entre as duas colunas vizinhas não é um critério de aprovação.
- Como diagnóstico da faixa superior, a dupla de colunas da emenda foi comparada às divisões internas de 16 px da arte: há correspondência exata ou diferença de apenas uma linha, conforme a variante. Isso é referência visual, não uma garantia isolada de qualidade.
- QE e QD foram comparados às suas regiões em IE/ID: igualdade completa dos pixels.
- Não houve mudanças no PNG fora das quatro regiões das variantes retas.
- Gerada uma demonstração visual com quatro corpos: 256 px úteis, sem borda nas emendas.
- Demonstrado separadamente o acabamento esquerdo exposto, com 1 px de margem.
- Assets PNG e Aseprite foram preservados; hashes atuais constam no JSON.

A equivalência QE/IE e QD/ID está confirmada. Ainda faltam os ensaios de contornos completos, reentrâncias e portas superiores/inferiores, além da definição de colisões. O catálogo em JSON não é um TileSet nativo do Godot e não foi conectado ao gameplay.
