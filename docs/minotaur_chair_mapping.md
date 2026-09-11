# Mapeamento — `minotaur_chair`

## Fonte

- Arquivo: `assets/tiles/decor/minotaur_chair.png`
- Tela: `128 × 128 px`
- Área visível (alpha): `x=30..101`, `y=22..103`
- Área visível: `72 × 82 px`

## Conversão para a arena

A escala escolhida é `0,78×`, deixando a área visível com aproximadamente `56 × 64 px`. Os 64 px são a altura de apresentação adotada para o trono, não a altura útil do tileset de parede.

- Centro visual alinhado ao centro da escada: `x=0`.
- Topo visível: `y=-349`, cerca de 35 px abaixo do limite superior `-384` (5% da altura de 704 px).
- Cena: `scenes/minotaur_throne.tscn`, instanciada diretamente na arena em `(0, -285,04)`.
- Origem na base; `z_index=2`, com ordenação por Y na arena, compartilhada com Mox.

## Partes e colisão

Os três PNGs têm canvas de 128 × 128 px. A imagem completa permanece como referência. O objeto usa as duas partes complementares, sem desenhar a referência por cima:

| Arquivo | Área visível | Uso |
|---|---|---|
| `minotaur_chair_back.png` | x=52..79, y=22..73 | encosto alto |
| `minotaur_chair_seat.png` | x=30..101, y=74..103 | assento e degraus |
| `minotaur_chair.png` | x=30..101, y=22..103 | referência da composição |

Ambos os sprites têm posição local `(-1,56, -31,2)` e escala `0,78`. O StaticBody2D possui uma colisão de 42 × 14 px, em `(0, -9)`, concentrada na base. O espaço atrás do encosto continua caminhável, com o personagem ocultado visualmente quando passa por trás. Corpos com máscara de colisão 1 também são bloqueados pela base.
