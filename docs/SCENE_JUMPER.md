# Tab como jumper de cenas

`SceneJumper` é um autoload dedicado ao atalho de navegação. Consome Tab antes da navegação por foco da interface, ignora repetição de tecla e delega os skips aos controladores da cena ativa.

| Cena/etapa | Tab |
| --- | --- |
| Mapa aberto, Room_2 | Vai ao tutorial dos fantasmas, Room_1 |
| Room_1, requisito ainda não concluído | Conclui as 40 eliminações, preenche o pedestal e libera a passagem |
| Room_1, requisito concluído | Vai à arena do Asterion, sem precisar caminhar até o warp |
| Asterion, antes da luta com o chefe | Preserva o skip existente para a fase do chefe |
| Asterion, fase do chefe ou tutorial finalizado | Volta ao mapa aberto, na chegada do warp central |
| Outras cenas/previews abertos individualmente | Volta ao mapa aberto |

As três cenas jogáveis usam o feixe e o fade de teletransporte existentes. Pedidos durante a chegada ficam pendentes até a chegada terminar. Depois do skip para o chefe, o Tab seguinte já pode sair, inclusive durante a entrada do chefe ou o diálogo de vitória. O atalho também fecha os avisos de tutorial pausados; se o personagem estiver derrotado, permite avançar para a próxima cena com uma nova instância.

Cada cena carrega seus próprios inimigos, condições e tempos desde o início. As trocas com o personagem vivo conservam vida, vida máxima, cartas equipadas e estado das cargas de rolagem pelo contrato `entry_player_state` já existente. A cura da fase do chefe continua pertencendo ao tutorial do Asterion. O jumper não implementa o futuro pedestal de boosters nem a arena final.

Os controladores usam o grupo `scene_jump_controllers` e o método `request_scene_jump`. Isso também permite reconhecer a arena do Asterion dentro de uma cena contêiner. Cenas sem esse contrato usam o retorno padrão ao mapa. O antigo Tab do corredor do mercante encaminha a solicitação ao mesmo autoload.

`tools/scene_jumper_regression.gd` percorre o ciclo real por teclado e verifica repetição, preservação de estado, chegada no warp elevado e retorno de previews pausados. Os testes locais `room_1_skip_regression.gd` e `tutorial_tab_skip_regression.gd` foram atualizados para os novos passos.
