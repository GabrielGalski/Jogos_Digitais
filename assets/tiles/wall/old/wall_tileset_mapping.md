> Histórico: estas artes não são usadas pela arena atual. O recurso e as quatro camadas de parede foram retirados; veja ../inferior/inferior_tileset_mapping.md.

# Mapeamento do conjunto de paredes

## Arquivos

| Arquivo | Dimensões | Finalidade |
|---|---:|---|
| wall_tileset.png | 48×60 px | fonte original completa, com parede externa e moldura de buraco |
| wall_tileset_outer.png | 48×60 px | máscara da parede externa usada pela arena |
| wall_tileset_hole.png | 48×60 px | máscara isolada da moldura interna para buracos |
| wall_tileset_old.png | 78×78 px | modelo anterior preservado |

O arquivo-fonte contém dois componentes desconectados no mesmo espaço. Ele não deve ser usado diretamente como um atlas regular: a moldura de buraco começa em y=11 e invade os recortes de 12 px da fileira superior. Isso causava os pequenos traços repetidos abaixo da parede. As duas máscaras derivadas mantêm as coordenadas e cores originais, mudando somente os pixels do outro componente para transparência.

## Componentes detectados

| Componente | Limites inclusivos | Tamanho do limite | Pixels visíveis |
|---|---:|---:|---:|
| Parede externa | (0,0) até (47,59) | 48×60 px | 1210 |
| Moldura de buraco | (11,11) até (36,36) | 26×26 px | 506 |

Paleta: #25131a, #3d253b, #4c2f49, #6e4a48 e #78514f.

## Parede externa

A textura wall_tileset_outer.png usa uma grade lógica de 6 colunas por 5 linhas, com células de 8×12 px. Para a célula (coluna, linha), use:

~~~text
Rect2i(coluna × 8, linha × 12, 8, 12)
~~~

| Função | Célula | Região (x,y,w,h) |
|---|---:|---:|
| Canto superior esquerdo | (0,0) | (0,0,8,12) |
| Superior A | (1,0) | (8,0,8,12) |
| Superior B | (2,0) | (16,0,8,12) |
| Superior C | (3,0) | (24,0,8,12) |
| Superior D | (4,0) | (32,0,8,12) |
| Canto superior direito | (5,0) | (40,0,8,12) |
| Lateral esquerda A | (0,1) | (0,12,8,12) |
| Lateral esquerda B | (0,2) | (0,24,8,12) |
| Lateral esquerda C | (0,3) | (0,36,8,12) |
| Lateral direita A | (5,1) | (40,12,8,12) |
| Lateral direita B | (5,2) | (40,24,8,12) |
| Lateral direita C | (5,3) | (40,36,8,12) |
| Canto inferior esquerdo | (0,4) | (0,48,8,12) |
| Inferior A | (1,4) | (8,48,8,12) |
| Inferior B | (2,4) | (16,48,8,12) |
| Inferior C | (3,4) | (24,48,8,12) |
| Inferior D | (4,4) | (32,48,8,12) |
| Canto inferior direito | (5,4) | (40,48,8,12) |

## Moldura interna para buracos

A moldura de buraco não segue a grade 8×12. Ela é um quadro compacto de 26×26 px dentro da fonte e deve ser tratada como uma divisão assimétrica de nove partes.

Cortes exatos:

- eixo X: 11, 16, 32 e 37; larguras 5, 16 e 5 px;
- eixo Y: 11, 28, 32 e 37; alturas 17, 4 e 5 px.

| Parte | Região (x,y,w,h) |
|---|---:|
| Canto superior esquerdo | (11,11,5,17) |
| Superior | (16,11,16,17) |
| Canto superior direito | (32,11,5,17) |
| Lateral esquerda | (11,28,5,4) |
| Centro transparente | (16,28,16,4) |
| Lateral direita | (32,28,5,4) |
| Canto inferior esquerdo | (11,32,5,5) |
| Inferior | (16,32,16,5) |
| Canto inferior direito | (32,32,5,5) |

Para variar o tamanho de um buraco, repetem-se ou estendem-se somente as partes Superior, Laterais e Inferior. Os quatro cantos permanecem sem escala.

## Encaixe aplicado na arena

O piso ocupa Rect2(-344,-192,688,384). O contorno externo está salvo diretamente em quatro TileMapLayer, sem geração por script e sem portas.

| Camada | Retângulo visual | Encaixe |
|---|---|---|
| Superior | Rect2(-348,-200,696,12) | sobrepõe 4 px do piso e vaza 8 px para cima |
| Inferior | Rect2(-348,188,696,12) | sobrepõe 4 px do piso e vaza 8 px para baixo |
| Esquerda | Rect2(-348,-188,8,384) | sobrepõe 4 px do piso e vaza 4 px para fora |
| Direita | Rect2(340,-188,8,384) | sobrepõe 4 px do piso e vaza 4 px para fora |

A parede inferior é desenhada acima das laterais para fechar as quinas. Colisão e navegação continuam independentes das camadas visuais.
