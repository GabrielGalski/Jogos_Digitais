# Sistema de diálogo — Godot

Componente reutilizável inspirado na estrutura da referência em GameMaker. A cena principal é `dialogue_box.tscn`; `dialogue_demo.tscn` demonstra texto progressivo, efeitos contínuos, escolhas, desvios e eventos ligados às falas.

## Fluxo

- `E` completa o texto atual e, no próximo toque, avança.
- `W/S` ou as setas mudam a escolha; `E` confirma.
- Vírgulas e pontos criam pausas curtas durante a escrita.
- BBCode pode manter partes do texto em movimento: `[wave]`, `[shake]`, `[rainbow]` e `[pulse]`.
- O nome do personagem aparece acima da caixa, no canto esquerdo.
- O indicador inferior esquerdo usa `E` no lugar da seta.

## Dados

- `DialogueSpeaker`: nome, cores, voz e retrato opcional.
- `DialogueLine`: texto, velocidade, escolhas, próximo índice e evento opcional.
- `DialogueChoice`: resposta, desvio e evento opcional.
- `DialogueSequence`: conjunto reutilizável de falas.

O retrato fica oculto quando `DialogueSpeaker.portrait` está vazio. Para adicioná-lo depois, basta atribuir uma textura ao perfil; a caixa reserva automaticamente a coluna esquerda.

## Uso

Instancie `dialogue_box.tscn`, monte uma `DialogueSequence` e chame `start_dialogue(sequence)`. Conecte `dialogue_event_requested` para transformar identificadores das falas em ações da cena e `dialogue_finished` para devolver o controle ao jogador.

## Fonte

O sistema usa diretamente **Fixedsys Excelsior 3.01**, disponível em `assets/font/Fixedsys Excelsior 3.01.ttf`. As duas cenas compartilham o mesmo arquivo, mantendo o desenho do modelo original em qualquer máquina.
