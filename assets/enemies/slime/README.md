# Slime

`dungeon_slime.png` é a folha original preservada, 384×128, células de 32×32 e pivô dos pés (16,23). Fileiras: idle/walk (6), ataque (12), hit (2), morte (6). O trecho aéreo do salto usa os frames 6, 7 e 8 da segunda fileira; o impacto ocorre na aterrissagem. O último frame da quarta fileira forma a poça.

Os frames são regiões do atlas em `resources/enemies/slime/frames.tres`. O material usa as cores do perfil de água do mundo aberto, sem regravar o PNG. Integração e medidas: `docs/BIOME_ENEMIES.md`.
