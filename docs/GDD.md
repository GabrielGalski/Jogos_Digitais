# Monster Booster — GDD de prototipação

Início desta base: 9 de setembro de 2026.

## Estado atual

O projeto ativo contém uma cena vazia e a biblioteca de assets existente. Nenhuma mecânica de gameplay foi incorporada a esta base.

O material anterior está em `old/mvp_2026-09-09/`. Ele documenta uma demonstração visual e serve de referência, sem aprovar automaticamente suas regras, valores ou implementação.

## Processo definido

O desenvolvimento será iterativo e incremental. Cada ciclo delimita uma mecânica, sua entrega, implementação, critérios de validação e resultado. Consulte `ITERACOES.md` para o modelo de registro.

Uma implementação funcional não equivale, por si só, a uma mecânica validada. A validação técnica e a avaliação da experiência devem ser registradas separadamente.

## Mecânicas a definir

| Área | Definições necessárias | Estado |
| --- | --- | --- |
| Jogador e combate | Controle, movimentação, mira, disparo, colisões e resposta ao impacto | A definir |
| Cartas | Classes, função de cada classe, composição da arma e regras de combinação | A definir |
| Cartas iniciais | Identificador, efeito, parâmetros, restrições e critério de validação de cada carta | A definir |
| Inimigos | Comportamentos, percepção do jogador, ataques, reação a dano e condições de derrota | A definir |
| Encontros | Objetivo, composição e condições de entrada e saída | A definir |
| Recompensas e progressão | Aquisição de cartas, pacotes e persistência de recursos | A definir |

## Registro de decisões

Ainda não há decisões de gameplay aprovadas nesta base. Ao aprovar uma regra, registre sua descrição, motivação, iteração de origem e evidência de validação. Se uma decisão mudar, registre a revisão e seu motivo.

## Catálogo inicial de cartas

O estudo [CARTAS.md](CARTAS.md) reúne 18 propostas ilustrativas, uma distribuição possível entre três sets e avaliações de viabilidade. Ele é material de brainstorm; o catálogo definitivo e suas regras ainda não estão aprovados.

Para cada carta selecionada para uma iteração, registre:

- Identificador e nome.
- Classe e função.
- Comportamento observável e condições de ativação.
- Parâmetros e limites.
- Regras de combinação e casos especiais.
- Critérios de aceitação e resultado da validação.

## Catálogo inicial de inimigos

Ainda não definido. Para cada inimigo selecionado para uma iteração, registre:

- Identificador e papel no combate.
- Estados e condições de transição.
- Movimento, detecção e ataque.
- Reação a impactos e condição de derrota.
- Parâmetros e limites.
- Critérios de aceitação e resultado da validação.
