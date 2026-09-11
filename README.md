# Monster Booster

Base limpa em Godot para prototipação iterativa e incremental.

## Abrir o projeto

Importe o `project.godot` desta pasta no Godot 4.7 ou compatível e execute com F6/F5. A cena inicial é vazia: sua função é confirmar que o projeto abre e executa.

A configuração inicial usa o renderizador Compatibility, viewport lógico de 480 × 270, janela de 960 × 540 e texturas sem suavização. São configurações de partida, não requisitos definitivos de gameplay.

## Organização

| Caminho | Uso |
| --- | --- |
| `project.godot` | Projeto ativo |
| `scenes/main.tscn` | Cena inicial vazia |
| `assets/` | Assets existentes, preservados para reutilização |
| `docs/GDD.md` | Decisões e definições do novo ciclo de desenvolvimento |
| `docs/ITERACOES.md` | Forma de delimitar, implementar e validar cada entrega |
| `docs/TILESET_PAREDES.md` | Dimensões atuais, recortes e regras de composição das paredes |
| `old/mvp_2026-09-09/` | MVP visual e materiais anteriores, arquivados |

O projeto ativo não carrega cenas, scripts ou dados de `old`. Essa pasta possui `.gdignore` para impedir que o Godot importe os recursos e registre as classes do MVP no projeto novo.

## Desenvolvimento

Cada iteração começa com uma mecânica delimitada, uma entrega pequena e critérios de aceitação. A implementação é validada antes de incorporar novas regras. O GDD registra as decisões resultantes da validação.

O pitch, o GDD antigo e as mecânicas demonstradas são referências do MVP. Cartas, inimigos, progressão e regras de combate serão definidos e validados no novo ciclo; não são importados automaticamente para a base ativa.

O histórico Git foi preservado. O arquivo em `old` também inclui os arquivos que estavam modificados ou ainda não tinham sido versionados.
