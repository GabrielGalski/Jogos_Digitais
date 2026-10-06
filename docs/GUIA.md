# Guia do projeto

## Onde procurar

- [README](../README.md): apresentação da ideia, sem diário de implementação.
- [GDD](GDD.md): intenção, regras, identidade e catálogo de estudo.
- [TDD](TDD.md): cenas, responsabilidades, contratos e limites reais do código.
- `docs/old`: originais preservados e estudos históricos, fora da documentação ativa e do Git.

Para decidir uma mudança, consultar o GDD; para implementá-la, conferir o TDD e os recursos reais. Se houver divergência, verificar o código e registrar a decisão no documento responsável, sem criar outra cópia do mesmo assunto.

## Abrir e trabalhar

1. Obter o repositório com `assets`, `resources`, `scenes`, `scripts`, `tools`, `tests`, `project.godot` e `monster_booster.ldtk`.
2. Abrir `project.godot` no Godot 4.7. A inspeção desta base usou 4.7.1; alinhar a versão do time antes de atualizar o projeto.
3. Executar o projeto: a entrada é o tutorial. `Tab` oferece os atalhos de desenvolvimento descritos no TDD.
4. Para mapas, instalar o [LDtk pelo site oficial](https://ldtk.io/download/) e abrir `monster_booster.ldtk`. A base usa formato JSON 1.5.3; não é necessário levar o programa instalado junto com o repositório.

O editor Godot recria `.godot` localmente. Não remover PNGs originais nem arquivos `.uid`/presets `.import` para “limpar” o projeto: são diferentes do cache gerado.

## LDtk: o que distribuir

**Recomendação:** versionar o arquivo `.ldtk`, os PNGs originais e os scripts auxiliares. Instalar o editor separadamente. As definições de tilesets, entidades, campos, camadas e a pintura já estão no arquivo do projeto, não em uma instalação personalizada do LDtk. Essa separação segue a [estrutura oficial do JSON](https://ldtk.io/docs/game-dev/json-overview/).

Um configurador/launcher portátil pode ser uma melhoria posterior: localizar Python e LDtk, conferir versões e fontes e abrir o projeto existente. Não precisa recriar mapas nem instalar outro editor em cada clone. O launcher atual ainda não é portátil; sua limitação está abaixo. Não redistribuir o `.exe` unsigned bloqueado nem desativar a segurança do Windows.

Níveis externos podem reduzir conflitos quando várias pessoas editarem salas, mas **não ativar essa opção agora**: o loader Godot atual só lê níveis internos. Antes seria necessário adaptá-lo e testar o formato [`.ldtkl` separado](https://ldtk.io/docs/game-dev/json-overview/optional-separate-levels/).

### Alterei um PNG e o editor não mudou

1. Confirmar que foi editado o original apontado pelo tileset — por exemplo `assets/tiles/wall/leaves.png`, `assets/tiles/wall/decor/column_round.png` ou `assets/tiles/wall/wall_tileset.png`.
2. Salvar e fechar o LDtk antes de executar a atualização. O helper se recusa a escrever com o editor aberto para não perder alterações da pintura.
3. Conferir com `AtualizarLDtk.cmd --dry-run`; aplicar com `AtualizarLDtk.cmd --refresh-only` e abrir novamente o mapa. Dois cliques executam a atualização e tentam abrir o editor instalado no caminho padrão.
4. Verificar dimensões e layout do atlas. Reordenar ou redimensionar sprites exige revisar o mapeamento; atualizar pixels não deve recriar a sala.

O helper [refresh_ldtk_sources.py](../tools/refresh_ldtk_sources.py) limpa o cache de imagem dos tilesets, atualiza dimensões e preserva coordenadas dos tiles. Quando precisa alterar o mapa, salva backup em `ldtk_backups`. “Atualizar” aqui significa sincronizar o **projeto com os PNGs**, não baixar uma versão nova do programa LDtk.

`AtualizarLDtk.cmd` procura o Python no runtime local do Codex. Em outra máquina, usar Python com Pillow instalado e rodar, na raiz do projeto:

```powershell
python -m pip install Pillow
python tools/refresh_ldtk_sources.py --summary --dry-run
python tools/refresh_ldtk_sources.py --summary
```

Esses comandos não dependem do Codex. Abrir o `.ldtk` manualmente se o editor estiver em um caminho diferente do padrão. Não executar os builders/configuradores para atualizar uma pintura existente: eles tratam criação ou migrações específicas, não o fluxo cotidiano.

No jogo em desenvolvimento, os PNGs são rechecados pelo runtime; alterações na pintura/JSON exigem recarregar a cena. Isso é diferente do cache de visualização do editor LDtk.

### Contratos de autoria do mapa

- Paredes: cortes 8 × 8 somente no tileset e camadas de walls; gameplay/piso continuam 16 × 16.
- Leaves: cobertura visual na frente de atores e props, sem física ou luz própria.
- DoorDash/DashGap: posição de vão atravessável com dash, com piso seguro antes e depois.
- AmbientArea: posição, temporização e referência para animação decorativa; sem sprites vinculados, nada aparece.
- Marcadores de mobs/Tin: não presumir spawn automático; verificar o suporte do loader no TDD.

## Git e documentação

| Versionar | Manter local/ignorado |
| --- | --- |
| README, GDD, TDD e este guia | `docs/old`, capturas e estudos auxiliares |
| `.ldtk`, PNGs e fontes autorais | Editor LDtk instalado, atalhos `.lnk`, backups LDtk |
| Scripts, recursos, cenas, `.uid`, presets `.import` | `.godot`, caches Python, builds e temporários |
| Regressões `.gd`, cenários `.json` e fixtures intencionais | Capturas PNG geradas na raiz de `tests` |

O `.gitignore` permite somente `GDD.md`, `TDD.md` e `GUIA.md` dentro de `docs`. Novos documentos auxiliares ali ficam locais; incorporar decisões importantes aos três arquivos canônicos. Um arquivo já rastreado não deixa de ser rastreado só por entrar no ignore: revisar o diff, não remover coisas do índice indiscriminadamente.

O arquivo `.ldtk` é fonte autoral, não cache. Revisar o diff junto dos sprites usados, evitando alterações automáticas de todo o mapa. Sem níveis externos, coordenar edições simultâneas do mesmo arquivo. Alterações de definição ou tamanho do tileset merecem revisão separada da pintura.

Preparar arquivos não significa publicá-los: commit e push exigem uma decisão explícita do responsável.

## Ciclo de atualização

1. Definir a regra no GDD e localizar o contrato correspondente no TDD.
2. Implementar somente o escopo combinado; preservar pintura, sprites e mudanças de outras pessoas.
3. Executar verificações adequadas e registrar limitações concretas, sem declarar sistemas prontos só porque existe uma cena.
4. Atualizar TDD para o comportamento real e este guia se mudou o fluxo de trabalho.
5. Revisar arquivos preparados e decidir a publicação separadamente.

Exemplo de regressão, com o executável Godot disponível no PATH:

```powershell
godot --headless --path . --script res://tools/ldtk_ambient_regression.gd
```

Escolher a regressão da alteração, não supor que todos os experimentos antigos são testes ativos.

## Resultado da revisão documental

Foram preservados 115 arquivos originais, incluindo textos, HTMLs, imagens, mapeamentos e scripts de documentação. Nenhum foi apagado. A organização do arquivo local é:

- `docs/old/documentacao`: estrutura anterior de `docs`, incluindo o GDD extenso e seus materiais.
- `docs/old/raiz`: README anterior e orientações LDtk que ficavam na raiz.
- `docs/old/arquivos`: notas de assets/cartas e documentação do sistema de diálogo, com caminhos de origem preservados.

Documentos que já estavam em pastas `old` permaneceram lá. O arquivo conserva os bytes originais; links históricos podem apontar para locais antigos e não são o fluxo ativo.

Foram consolidados os contratos ainda usados: tutorial/recompensas, cartas e previews, IA/navegação, diálogo, HUD, iluminação e mapas LDtk. Descrições de “base vazia”, mercante como cena inicial, ausência de IA integrada, duração antiga do tiro, mapas/atlas antigos e ausência de vida no boss foram substituídas por informações verificadas. Medições de sprites, capturas, estudos de câmera/projeção e catálogos extensos ficam como referência histórica; isso não remove os recursos de gameplay correspondentes.

`docs/old` não vai para o repositório. Manter backup dessa pasta em outro local se for necessário compartilhar ou preservar o histórico fora desta máquina; o Git conterá somente a documentação enxuta.
