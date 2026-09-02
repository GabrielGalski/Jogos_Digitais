# Mapeamento de `wall_tileset.png`

> **Estado atual:** atlas preservado para uso futuro, mas não instanciado na visualização atual da arena. A cena exibe somente a plataforma de piso.

O atlas atual mede **78×78 px**. Ele funciona como um nine-slice assimétrico, com uma área central transparente que representa a região utilizável da arena.

## Cortes exatos do atlas

| Região | Retângulo-fonte `(x, y, largura, altura)` |
|---|---|
| Canto superior esquerdo | `(0, 0, 8, 17)` |
| Parede superior | `(8, 0, 62, 17)` |
| Canto superior direito | `(70, 0, 8, 17)` |
| Parede esquerda | `(0, 17, 8, 46)` |
| Centro transparente/utilizável | `(8, 17, 62, 46)` |
| Parede direita | `(70, 17, 8, 46)` |
| Canto inferior esquerdo | `(0, 63, 8, 15)` |
| Parede inferior | `(8, 63, 62, 15)` |
| Canto inferior direito | `(70, 63, 8, 15)` |

Linhas de corte: `x = 8`, `x = 70`, `y = 17` e `y = 63`.

## Referência da implementação anterior

Antes de ser retirada da visualização, a parede era desenhada integralmente para fora do piso de `688×384 px`, sem cobrir seu tileset. Os retângulos abaixo permanecem registrados apenas como referência para uma possível retomada.

| Região | Retângulo-destino |
|---|---|
| Canto superior esquerdo | `Rect2(-352, -222.4, 8, 30.4)` |
| Parede superior | `Rect2(-344, -222.4, 688, 30.4)` |
| Canto superior direito | `Rect2(344, -222.4, 8, 30.4)` |
| Parede esquerda | `Rect2(-352, -192, 8, 384)` |
| Centro/piso | `Rect2(-344, -192, 688, 384)` |
| Parede direita | `Rect2(344, -192, 8, 384)` |
| Canto inferior esquerdo | `Rect2(-352, 192, 8, 30.4)` |
| Parede inferior | `Rect2(-344, 192, 688, 30.4)` |
| Canto inferior direito | `Rect2(344, 192, 8, 30.4)` |

O contorno externo completo usado nessa versão era `Rect2(-352, -222.4, 704, 444.8)`.

## Portas e void — referência anterior

Na implementação retirada, as quatro portas reservavam `32 px`, mesmo que as laterais ainda não possuíssem sprites. Todos os vãos eram centralizados. O void da visualização atual continua usando a cor **`#25131a`**.

| Lado | Área sem parede |
|---|---|
| Superior | `Rect2(-16, -222.4, 32, 30.4)` |
| Inferior | `Rect2(-16, 192, 32, 30.4)` |
| Esquerdo | `Rect2(-352, -16, 8, 32)` |
| Direito | `Rect2(344, -16, 8, 32)` |

Os sprites frontais usavam escala `0.95`. A parede superior mantinha a região-fonte de `17 px` e a inferior, `15 px`; ambas eram ampliadas verticalmente para `30.4 px`, usando as portas abertas como referência. Fechadas, as portas descartavam os `5 px` transparentes do topo e ampliavam os `27 px` visíveis. Cada lado usava o mesmo retângulo nos dois estados: `Rect2(-15.2, -222.4, 30.4, 30.4)` no topo e `Rect2(-15.2, 192, 30.4, 30.4)` na base.
