# Voxel base

Seleção mínima extraída dos packs `VoxelDungeonSet` e `RuinsGLB` para uso posterior no projeto Godot.

## Estrutura

```text
voxel base/
├── enemies/
│   ├── skeleton/    # OBJ + MTL + paleta PNG
│   └── zombie/      # OBJ + MTL + paleta PNG
└── ruins/
    ├── floor/       # piso normal, rachado e com musgo
    └── walls/
        ├── Gate, WallNormalXL, WallBrokenXL e terminações
        └── destructible/  # paredes divididas em fragmentos
```

## Inimigos — VoxelDungeonSet

| Asset | Tamanho original (X × Y × Z) | Vértices | Triângulos |
| --- | ---: | ---: | ---: |
| Skeleton | 1,4 × 3,0 × 0,7 | 1.316 | 896 |
| Zombie | 1,4 × 3,0 × 0,7 | 946 | 650 |

- Os dois modelos usam Y como eixo vertical e têm a base em Y = 0.
- Cada OBJ é uma malha única, sem armature, rig, animações, colisores ou LOD.
- O MTL de cada modelo depende somente do PNG de mesmo nome.
- Os PNGs são paletas de 256 × 1 pixels; os nomes e a proximidade entre OBJ, MTL e PNG devem ser preservados.
- Os arquivos `.vox` originais não foram copiados porque são fontes editáveis do MagicaVoxel, não dependências de execução do Godot.
- Para aproximar a altura do jogador atual (1,8 m), uma escala inicial de `0.6` deixa cada inimigo com 1,8 unidade de altura.

## Ambiente — RuinsGLB

### Piso

| Asset | Tamanho original aproximado (X × Y × Z) |
| --- | ---: |
| BlockNormalXS | 6,6 × 0,5 × 6,6 |
| BlockCrackXS | 6,6 × 0,5 × 6,6 |
| BlockMossXS | 6,9 × 0,8 × 7,0 |

O piso com musgo ultrapassa ligeiramente a célula por causa da vegetação. A malha deve continuar alinhada em uma grade de 6,6 unidades.

### Paredes

| Asset | Uso | Tamanho original aproximado (X × Y × Z) |
| --- | --- | ---: |
| WallNormalXL | parede principal | 1,0 × 6,5 × 6,6 |
| WallBrokenXl | variação danificada | 1,0 × 6,5 × 6,6 |
| WallEnd / WallEnd2 | terminações de corredor | comprimentos parciais |
| Gate | abertura/portão estático | 1,0 × 6,5 × 6,6 |
| WallNormalXLdes | parede em 6 fragmentos | cerca de 1,05 × 5,81 × 4,48 por limites combinados |
| WallBrokenXLdes | parede em 3 fragmentos | cerca de 1,03 × 5,31 × 7,34 por limites combinados |

- Todos os GLBs são versão 2.0 e autocontidos: malha, material e PNG estão incorporados.
- Não há buffers, imagens ou outros arquivos externos referenciados.
- Não há animações, colisores ou física prontos.
- `Gate.glb` é estático; a abertura futura precisa ser implementada na cena Godot.
- As versões `des` mantêm fragmentos em nós separados, mas a física de destruição ainda precisa ser criada.
- As paredes têm o volume local em X aproximadamente entre -0,8 e 0,2; o centro visual fica deslocado cerca de -0,3 no eixo normal da parede.

## Escala para a base atual

O mapa atual usa células de 1 × 1 unidade. Para encaixar os módulos de ruína nessa grade, use escala uniforme aproximada de `0.151515` (`1 / 6.6`). Nessa escala:

- o piso ocupa uma célula de 1 × 1;
- a parede XL fica com aproximadamente 0,98 unidade de altura;
- o piso normal fica com aproximadamente 0,076 unidade de espessura.

Os inimigos vêm de outro pack e não compartilham essa escala. Use escala `0.6` como ponto inicial para altura humana.

Para desempenho e comportamento previsível, crie colisões simples no Godot com `BoxShape3D` para o cenário e `CapsuleShape3D` para os inimigos, sem usar a malha detalhada como colisão dinâmica.
