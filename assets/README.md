# Padrão de assets

```text
assets/
├── boosters/{base,opening,preview,sets}
├── cards/
├── characters/player/{idle,run}
├── enemies/{mimic,minotaur,spirit}
├── tiles/{floor,inferior,door,wall}
├── weapons/booster/
└── old/
```

A base ativa contém uma cena vazia. A pasta `tiles/wall` inclui o novo atlas de paredes; suas artes anteriores estão em `tiles/wall/old`. Consulte o [mapeamento atual de paredes](../docs/TILESET_PAREDES.md) para medidas, recortes e regras de composição. Os textos de aplicação em cenas nos mapeamentos antigos de piso e borda inferior descrevem o MVP arquivado.
