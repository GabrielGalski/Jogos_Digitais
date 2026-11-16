# Insects — Sack_Pixel

Fonte: https://sack-pixel.itch.io/pack-enemies-v1

Os diretórios `Tall-Enemy`, `Fly-Enemy` e `Little-Enemy` são as fontes autorais e permanecem intactos. Os PNGs de gameplay estão em `<tall|fly|little>/<idle|idle_blink|walk|attack|hit|death>/`, com nomes numerados a partir de 01. Fly usa idle também para voar; não possui uma folha walk.

Todos os recortes têm **48×48**, pivô de pés **(24,32)** e filtro Nearest. O desenho e o alpha são preservados, inclusive o espaço necessário para as armas. Não há recorte por silhueta de cada pose, evitando deslocamentos de pivô. `sprite_map.json` guarda os hashes das folhas e os retângulos de cada frame. Fly e Little aparecem em escala 1,0; Tall usa escala 1,2 somente no nó visual do jogo, com colisão proporcional. As propostas de paleta são aplicadas em tempo de execução, sem alterar estes PNGs.

| Modelo | Idle | Blink | Walk | Attack | Hit | Death |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Tall | 5 | 5 | 4 | 6 | 3 | 6 |
| Fly | 5 | 5 | — | 6 | 3 | 6 |
| Little | 4 | 4 | 4 | 7 | 3 | 6 |

Total: **82 PNGs**. Os recursos prontos ficam em `resources/enemies/insects/*_frames.tres`.

Para reconstruir: executar `tools/prepare_insect_sprites.gd`, importar os novos PNGs no Godot e executar novamente com `-- --resources`. O preparador recusa sobrescrever frames alterados manualmente e preserva perfis de balanceamento existentes. `-- --resources --reset-profiles` restaura explicitamente os valores iniciais dos três perfis.

Uso, balanceamento e algoritmos: [docs/INSECTS.md](../../../docs/INSECTS.md).
