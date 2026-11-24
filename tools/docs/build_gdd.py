"""Build and validate the paginated Monster Booster design document.

This is an editorial document builder. It does not alter gameplay or the existing
GDD/TDD. Source text and layout receipts are exported alongside the PDF.
"""
from __future__ import annotations

import html
import json
import math
from pathlib import Path

from PIL import Image
from pypdf import PdfReader
from reportlab.lib.colors import HexColor
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.utils import ImageReader
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.pdfgen import canvas
from reportlab.platypus import Paragraph


ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "output/pdf"
ASSETS = OUT / "gdd_assets"
QA = ROOT / "tmp/pdfs/gdd"
PDF = OUT / "Monster_Booster_GDD.pdf"
W, H = A4
M = 40
CW = W - 2 * M
GAP = 16
COL = (CW - GAP) / 2
INK = "#25131a"
PAPER = "#f6f1e9"
PLUM = "#533048"
PURPLE = "#795a88"
MUTED = "#766370"
LINE = "#dacdd0"
GOLD = "#e8be62"
MINT = "#007f77"
ROSE = "#ad4563"
LIGHT = "#ebe3e7"
WHITE = "#fffdf8"
PAGE = 0
RECEIPTS = []
SOURCE = ["# Monster Booster - Game Design Document", "", "Edição 1.0 - 7 de novembro de 2026.", ""]
TOC = []


def col(value):
    return HexColor(value)


def register_fonts():
    font_dir = Path("C:/Windows/Fonts")
    for name, filename in [("Body", "segoeui.ttf"), ("Bold", "segoeuib.ttf"),
                           ("Display", "bahnschrift.ttf")]:
        pdfmetrics.registerFont(TTFont(name, str(font_dir / filename)))
    pdfmetrics.registerFontFamily("Body", normal="Body", bold="Bold", italic="Body", boldItalic="Bold")


def receipt(kind, x, top, width, height, text=""):
    if kind == "text" and not (x >= 24 and top >= 20 and x + width <= W - 24.0 and top + height <= 789):
        raise ValueError(f"Out-of-bounds text on page {PAGE}: {text[:80]} at {x, top, width, height}")
    RECEIPTS.append(dict(page=PAGE, kind=kind, x=round(x, 2), top=round(top, 2),
                         width=round(width, 2), height=round(height, 2), text=text))


def txt(text, x, top, width, size=10.7, leading=None, color=INK, font="Body", max_h=None, record=True):
    style = ParagraphStyle("gdd", fontName=font, fontSize=size, leading=leading or size * 1.38,
                           textColor=col(color), spaceBefore=0, spaceAfter=0)
    p = Paragraph(text, style)
    _, height = p.wrap(width, H)
    if max_h is not None and height > max_h + 0.1:
        raise ValueError(f"Text overflow page {PAGE}, {height:.1f}>{max_h}: {text[:100]}")
    p.drawOn(C, x, H - top - height)
    receipt("text", x, top, width, height, text)
    if record:
        SOURCE.append(text.replace("<b>", "**").replace("</b>", "**").replace("<br/>", "\n").replace("<i>", "").replace("</i>", ""))
        SOURCE.append("")
    return top + height


def rect(x, top, width, height, fill, stroke=None, radius=0):
    C.setFillColor(col(fill))
    if stroke:
        C.setStrokeColor(col(stroke))
    if radius:
        C.roundRect(x, H - top - height, width, height, radius, fill=1, stroke=int(stroke is not None))
    else:
        C.rect(x, H - top - height, width, height, fill=1, stroke=int(stroke is not None))


def line(points, color=PLUM, width=1, dash=None):
    C.saveState()
    C.setStrokeColor(col(color))
    C.setLineWidth(width)
    if dash:
        C.setDash(dash)
    p = C.beginPath()
    p.moveTo(points[0][0], H - points[0][1])
    for x, y in points[1:]:
        p.lineTo(x, H - y)
    C.drawPath(p)
    C.restoreState()


def arrow(points, color=PLUM, width=1.3, dash=None):
    line(points, color, width, dash)
    a, b = points[-2], points[-1]
    angle = math.atan2(b[1] - a[1], b[0] - a[0])
    tip = 5.0
    line([(b[0] - tip * math.cos(angle - 0.5), b[1] - tip * math.sin(angle - 0.5)), b,
          (b[0] - tip * math.cos(angle + 0.5), b[1] - tip * math.sin(angle + 0.5))], color, width)


def badge(text, x, top, tint=PLUM):
    width = pdfmetrics.stringWidth(text, "Bold", 7.2) + 16
    rect(x, top, width, 18, tint, radius=3)
    txt(text, x + 8, top + 3.6, width - 16, 7.2, color=WHITE, font="Bold", record=False)
    return width


def heading(text, x, top, width=CW, tint=PLUM, size=15):
    return txt(text, x, top, width, size, font="Display", color=tint)


def block(title, body, x, top, width=CW, tint=PLUM, size=10.7):
    bottom = heading(title, x, top, width, tint)
    return txt(body, x, bottom + 7, width, size)


def note(label, body, top, tint=PLUM, height=66):
    rect(M, top, CW, height, LIGHT, radius=4)
    rect(M, top, 4, height, tint)
    txt(label, M + 14, top + 10, CW - 28, 8.3, font="Bold", color=tint)
    txt(body, M + 14, top + 28, CW - 28, 9.5, max_h=height - 35)


def picture(path, x, top, width, height, caption=None, background=INK):
    path = Path(path)
    if not path.is_absolute():
        path = ROOT / path
    if not path.exists():
        raise FileNotFoundError(path)
    im = Image.open(path)
    ratio = min(width / im.width, height / im.height)
    iw, ih = im.width * ratio, im.height * ratio
    rect(x, top, width, height, background, radius=3)
    C.drawImage(ImageReader(im), x + (width - iw) / 2, H - top - (height + ih) / 2,
                iw, ih, mask="auto")
    receipt("image", x, top, width, height, str(path.relative_to(ROOT)))
    if caption:
        txt(caption, x, top + height + 6, width, 8, color=MUTED, record=False)


def sprite(path, x, top, width, height):
    picture(path, x, top, width, height, background=PLUM)


def first_asset(directory, pattern="*.png"):
    choices = sorted(p for p in (ROOT / directory).rglob(pattern) if "old" not in p.parts)
    if not choices:
        raise FileNotFoundError(directory)
    return choices[0]


def new_page(title, subtitle, status="DESIGN", section=""):
    global PAGE
    if PAGE:
        C.showPage()
    PAGE += 1
    TOC.append((PAGE, title))
    SOURCE.extend([f"## {PAGE:02d}. {title}", "", subtitle, ""])
    C.bookmarkPage(f"page_{PAGE}")
    C.addOutlineEntry(title, f"page_{PAGE}", level=0)
    rect(0, 0, W, H, INK)
    rect(14, 13, W - 28, H - 26, PAPER, radius=11)
    for y in range(40, 800, 86):
        rect(7, y, 4, 10, PLUM)
        rect(W - 11, y + 20, 4, 10, GOLD)
    C.setFillColor(col(PLUM))
    C.setFont("Display", 11)
    C.drawString(M, H - 43, "MONSTER BOOSTER")
    C.setFont("Body", 7.3)
    C.drawRightString(W - M, H - 41, "GAME DESIGN DOCUMENT  /  1.0")
    line([(M, 58), (W - M, 58)], LINE, 0.8)
    txt(section or f"CAPÍTULO {PAGE - 1:02d}", M, 73, 270, 8, font="Bold", color=MUTED, record=False)
    sw = pdfmetrics.stringWidth(status, "Bold", 7.2) + 16
    badge(status, W - M - sw, 70, MINT if status == "BASE EXISTENTE" else ROSE if status == "PROPOSTA" else PLUM)
    txt(title.upper(), M, 97, CW, 26, leading=29, font="Display", max_h=60, record=False)
    txt(subtitle, M, 134, CW, 10.8, leading=14.8, color=MUTED, max_h=42, record=False)
    line([(M, 800), (W - M, 800)], LINE, 0.7)
    C.setFont("Body", 7)
    C.setFillColor(col(MUTED))
    C.drawString(M, H - 816, "Team Galski  /  Gabriel Galski Machado  /  07.11.2026")
    C.setFont("Bold", 8)
    C.drawRightString(W - M, H - 816, f"{PAGE:02d}")


def small_card(title, body, x, top, width, height=112, tint=PLUM):
    rect(x, top, width, height, WHITE, LINE, 5)
    rect(x, top, width, 4, tint)
    end = txt(title, x + 12, top + 16, width - 24, 12.5, font="Display", color=tint)
    txt(body, x + 12, end + 7, width - 24, 10, max_h=height - (end - top) - 16)


def step(number, title, body, top, height=78):
    rect(M, top, 31, 31, PLUM, radius=4)
    txt(str(number), M + 9, top + 5, 20, 14, color=WHITE, font="Bold", record=False)
    end = txt(title, M + 46, top + 1, CW - 46, 13.2, font="Display", color=PLUM)
    txt(body, M + 46, end + 4, CW - 46, 10.3, max_h=height - 27)


def cover():
    new_page("Monster Booster", "Enfrente hordas. Abra boosters. Combine poderes.", section="DOCUMENTO DE DESIGN")
    picture(ASSETS / "chefe_final_conceito_v2.png", M, 191, CW, 344)
    txt("Arte conceitual de um confronto futuro. Silhueta do chefe final em estudo.", M, 543, CW, 8.2, color=MUTED, record=False)
    txt("UM PEQUENO MONSTRO.<br/>UMA GRANDE COLEÇÃO.", M, 581, CW, 25, leading=29, font="Display", color=PLUM)
    txt("Roguelike de ação em visão superior, com combate bullet hell e poderes construídos com cartas de monstros.", M, 663, CW, 12, leading=17)
    badge("22 PÁGINAS TEMÁTICAS", M, 730)
    badge("GRAFO DE PROGRESSÃO", M + 160, 730, MINT)
    badge("CONCEITOS VISUAIS", M + 315, 730, ROSE)


def concept():
    new_page("Conceitos", "A coleção muda o combate. O combate amplia a coleção.")
    block("Ideia do jogo", "Nox invade os domínios dos Dark Lords para conquistar suas cartas. Seu Booster Shooter transforma cada combinação equipada em uma maneira de atacar, reagir e sobreviver. A aventura alterna pressão de hordas, duelos contra chefes e preparação em pontos seguros.", M, 188)
    small_card("LEITURA E RESPOSTA", "Reconhecer o perigo, usar dash ou parry e aproveitar a abertura criada.", M, 301, COL, 100, MINT)
    small_card("DESCOBERTA E COMBINAÇÃO", "Abrir um pacote e encontrar uma nova possibilidade de jogar, além de um novo item.", M + COL + GAP, 301, COL, 100, ROSE)
    heading("Como ler este documento", M, 426)
    txt("A organização segue a referência de Dead Dudes: temas em páginas próprias, texto direto e imagens que explicam o design. As cores e a identidade pertencem a Monster Booster.", M, 454, CW, 10.4)
    left = [(3,"História e personagens"),(4,"Controles"),(5,"Combate"),(6,"Cartas e combinações"),(7,"Boosters e Tin"),(8,"Inimigos"),(9,"Área dos fantasmas"),(10,"Asterion: tutorial"),(11,"Arena dos seis pedestais"),(12,"Grafo da progressão")]
    right = [(13,"Provas dos pedestais"),(14,"Golem Elemental"),(15,"Asterion: rematch"),(16,"Chefe final"),(17,"Cenário e câmera"),(18,"HUD e interface"),(19,"Direção de arte"),(20,"Música e efeitos"),(21,"Fluxo de telas e derrota"),(22,"Escopo e próximos marcos")]
    for entries, x in [(left,M),(right,M+COL+GAP)]:
        for i,(n,label) in enumerate(entries):
            y = 520 + i * 19
            txt(f"{n:02d}", x, y, 24, 9.3, color=ROSE, font="Bold", record=False)
            txt(label, x+29, y, COL-29, 9.3, record=False)
            C.linkRect("", f"page_{n}", (x,H-y-16,x+COL,H-y+1), relative=0, thickness=0)
    txt("BASE EXISTENTE identifica conteúdo presente no projeto. PROPOSTA identifica relações, arte ou sistemas futuros. Páginas DESIGN combinam a intenção do jogo com essa distinção no texto.", M, 737, CW, 9.1, color=MUTED)


def characters():
    new_page("História e personagens", "Ambição, estranheza e humor em uma disputa por poderes.")
    txt("A premissa acompanha um invasor pequeno diante de adversários enormes. Nox quer ampliar sua coleção; os Dark Lords representam os poderes que ainda precisa conquistar. A história aparece em encontros curtos e na mudança de escala dos desafios.", M, 186, CW)
    rows = [
        ("Nox", "O protagonista", "Um pequeno monstro ambicioso. Comunica-se por símbolos e deixa a ação expressar sua personalidade. A arma traduz a coleção em poderes; o jogador reconhece Nox pela silhueta e pelo contraste com seus rivais.", "assets/characters/player/idle/player_idle_01.png"),
        ("Asterion", "O rival que apresenta as regras", "Provocativo e confiante, conduz o primeiro duelo e testa o que Nox aprendeu. Ao perder o tutorial, rende-se e permanece vivo. O reencontro proposto transforma a mesma relação em uma prova de domínio do combate.", "output/portraits/asterion/source/asterion_front_source.png"),
        ("Tin", "A pausa entre confrontos", "Mercante dos pontos seguros. Representa a preparação: abrir pacotes, rever a combinação e negociar cartas. A compra, a venda de duplicatas e a coleção persistente fazem parte do design a integrar.", "assets/merchant/character/merchant_idle1.png"),
    ]
    for i,(name,role,body,path) in enumerate(rows):
        top = 293 + i*151
        sprite(path, M, top, 108, 112)
        txt(name.upper(), M+127, top, CW-127, 17, font="Display", color=PLUM)
        txt(role, M+127, top+28, CW-127, 9.2, font="Bold", color=ROSE)
        txt(body, M+127, top+48, CW-127, 10.3, max_h=91)


def controls():
    new_page("Controles", "Poucos comandos sustentam movimentação, ataque, defesa e interação.", "BASE EXISTENTE")
    rows = [
        ("W A S D", "Mover Nox", "Movimentação livre pelo plano da arena."),
        ("MOUSE", "Mirar", "O Shooter acompanha a direção da mira em 360 graus."),
        ("CLIQUE ESQ.", "Atacar", "Dispara a Manifestação equipada; ataques contínuos mantêm o botão pressionado."),
        ("SHIFT", "Dash", "Duas cargas permitem escapar e corrigir a posição em sequência."),
        ("CLIQUE DIR.", "Parry", "Uma janela curta bloqueia o ataque no timing correto e permite contra-atacar."),
        ("E", "Interagir", "Ativa pedestais, atravessa warps e avança diálogos quando a interação está disponível."),
    ]
    for i,(key,title,body) in enumerate(rows):
        y = 192+i*76
        rect(M,y,104,45,PLUM,radius=4)
        txt(key,M+9,y+14,86,9.2,font="Bold",color=WHITE,record=False)
        txt(title,M+122,y,CW-122,13,font="Display",color=PLUM)
        txt(body,M+122,y+24,CW-122,10.4,max_h=43)
    note("APRENDIZADO EM CAMADAS", "A área dos fantasmas ensina movimento, disparo e dash. Asterion apresenta o parry, a leitura do ataque forte e as janelas de resposta.", 680, height=74)


def combat():
    new_page("Combate", "Sair do perigo deve criar a próxima oportunidade de atacar.")
    picture("output/procedural_weapons/gallery.png", M, 188, CW, 245,
            "Estudo de apresentação dos ataques no projeto.")
    w = (CW - 24)/3
    for i,(title,body,tint) in enumerate([
        ("LER", "Sinais de chão, preparação do inimigo e trajetória dos projéteis comunicam o risco.", PLUM),
        ("RESPONDER", "Mover, usar o dash duplo ou acertar o parry, conforme espaço e timing.", MINT),
        ("PUNIR", "Atacar na recuperação do inimigo e transformar a defesa bem executada em vantagem.", ROSE),
    ]):
        small_card(title,body,M+i*(w+12),467,w,124,tint)
    heading("Base de combate atual", M, 617)
    txt("<b>Vida:</b> 60 pontos em seis blocos. <b>Dash:</b> duas cargas, com recuperação de 0,5 s por carga. <b>Parry:</b> janela de 0,15 s, recarga de 0,42 s e contra-ataque de 30 de dano. São referências de ajuste, sujeitas ao balanceamento.", M, 646, CW, 10.4)
    note("REGRA DE LEITURA", "Aviso, impacto e recuperação precisam ser distinguíveis. Um efeito vistoso só comunica uma regra se ela realmente existir no combate.", 718, height=62)


def cards():
    new_page("Cartas e combinações", "Uma Manifestação, uma Infusão e uma Mutação compõem o conjunto de poderes.")
    w = (CW-24)/3
    entries = [
        ("MANIFESTAÇÃO", "A forma do ataque", "Define como o poder é lançado: tiros, feixes ou invocações.", "assets/cards/manifestacao/gotas_de_slime M01/gotas_de_slime M01.png", MINT),
        ("INFUSÃO", "A consequência", "Adiciona efeitos ao atacar, acertar ou eliminar inimigos.", "assets/cards/infusao/nucleo_de_golem I01/nucleo_de_golem I01.png", ROSE),
        ("MUTAÇÃO", "A reação de Nox", "Altera habilidades e reações do próprio personagem.", "assets/cards/mutacao/coracao_da_furia U01/coracao_da_furia U01.png", PLUM),
    ]
    for i,(name,role,body,path,tint) in enumerate(entries):
        x=M+i*(w+12)
        picture(path,x,191,w,144,background=LIGHT)
        txt(name,x,350,w,10.1,font="Bold",color=tint)
        txt(role,x,372,w,12,font="Display",color=PLUM)
        txt(body,x,400,w,10,max_h=77)
    note("CONJUNTO INICIAL", "Gotas de Slime (M01) + Núcleo de Golem (I01), com o slot de Mutação vazio. A Mutação ilustrada acima é um exemplo do catálogo, não parte do equipamento inicial.", 489, height=76)
    heading("Coleção inicial",M,588)
    lists=[
        "M01 Gotas de Slime<br/>M02 Massa de Slime<br/>M04 Olho de Beholder<br/>M05 Fragmentos de Basilisco<br/>M06 Cauda de Manticora<br/>M07 Coração de Efreeti<br/>M08 Garganta de Dragão",
        "I01 Núcleo de Golem<br/>I02 Casca Estilhaçante<br/>I03 Fragmento de Odopi<br/>I04 Ovo de Slaad<br/>I05 Essência de Quimera",
        "U01 Coração da Fúria<br/>U02 Pele de Medusa<br/>U03 Chão Carnívoro<br/>U04 Mandrágora de Bolso<br/>U05 Espada do Herói<br/>U06 Doppelganger",
    ]
    for i,text in enumerate(lists):
        txt(text,M+i*(w+12),619,w,8.8,leading=15)
    txt("A divisão da coleção inicial em pacotes e raridades está em docs/CARTAS.md.",M,747,CW,9,color=MUTED)


def boosters():
    new_page("Boosters e Tin", "A recompensa prolonga a descoberta; a pausa permite escolher o que fazer com ela.")
    picture("assets/merchant/merchant_hall.png",M,188,CW,193,
            "Arte existente do espaço do mercante. A economia completa ainda faz parte do design.")
    step(1,"Conquistar", "Encontros entregam cartas e boosters. O pacote pertence a uma coleção temática e contém três cartas.",411,69)
    step(2,"Abrir", "O jogador segura o mouse e cruza a linha pontilhada. O pacote comprime, sacode e rasga; as cartas aparecem em uma apresentação curta.",488,75)
    step(3,"Combinar", "Em um ponto seguro, comparar o que foi obtido, rever os três slots e preparar o próximo confronto. Tin concentra a proposta de compra e venda de duplicatas.",570,82)
    note("RECOMPENSA DO TUTORIAL", "Duas cartas iniciais e três boosters, um por coleção, com três cartas em cada. A última carta do primeiro pacote deve garantir uma Mutação comum. Essa é a regra de design; a abertura visual ainda usa conteúdo de protótipo.",674,height=102)


def enemies():
    new_page("Inimigos", "Cada família pressiona uma decisão diferente do jogador.")
    data=[
        ("Fantasmas", "Pressão de aproximação", "Chegam de fora da câmera e atravessam o terreno. Ensinam a manter distância, mirar em movimento e abrir espaço com dash. Na abertura atual, um disparo de M01 elimina um fantasma.", "assets/enemies/spirit/normal/spirit_ghost_move_01.png"),
        ("Minotauros", "Pressão de grupo", "Acompanham Asterion em versões comuns e fortalecidas. Seus ataques precisam de preparação legível; navegação e densidade preservam espaço para resposta.", first_asset("assets/enemies/minotaur")),
        ("Flying Eye", "Risco na exploração", "Bandos ocupam zonas do mapa aberto e interrompem deslocamentos previsíveis. O spawn é suspenso durante eventos de pedestal para não misturar duas fontes de pressão sem controle.", first_asset("assets/enemies/flying eye")),
        ("Chefes", "Síntese de aprendizado", "Asterion testa timing; o Golem testa deslocamento entre plataformas e leitura elemental. O rematch e o chefe final ampliam essas exigências em confrontos próprios.", first_asset("assets/enemies/golem/frames/ice/idle")),
    ]
    for i,(title,role,body,path) in enumerate(data):
        y=190+i*143
        sprite(path,M,y,92,102)
        txt(title,M+111,y,CW-111,16,font="Display",color=PLUM)
        txt(role.upper(),M+111,y+28,CW-111,8.3,font="Bold",color=ROSE)
        txt(body,M+111,y+49,CW-111,10.3,max_h=86)


def ghosts():
    new_page("Abertura: os fantasmas", "O começo do jogo ensina combate e dash antes do primeiro boss.", "BASE EXISTENTE", "NÍVEL 01 / APRENDIZADO")
    picture("output/spirit_horde/horde.png",M,188,CW,245,
            "Captura do encontro inicial de fantasmas no protótipo.")
    step(1,"Entrar e reconhecer", "A sala apresenta espaço de movimento, o pedestal e a direção de saída. A horda só começa quando Nox sobe no pedestal e pressiona E.",467,76)
    step(2,"Mover, disparar e usar dash", "Os fantasmas cercam o jogador. O ritmo cresce ao longo do encontro; aprender a reposicionar é mais importante que ficar parado causando dano.",550,80)
    step(3,"Concluir e seguir", "Na configuração atual, 40 eliminações completam o anel do pedestal e abrem a saída. O warp leva ao encontro de Asterion, segunda parte do tutorial.",637,79)
    txt("Critério de design: o jogador termina entendendo como iniciar um encontro, mirar em movimento, usar as duas cargas de dash e reconhecer que a saída foi liberada.",M,743,CW,9.6,color=MUTED)


def tutorial_boss():
    new_page("Asterion: tutorial", "O primeiro boss transforma os comandos básicos em um duelo com leitura e resposta.", "BASE EXISTENTE", "NÍVEL 02 / PRIMEIRO BOSS")
    picture("output/asterion_tutorial/portrait_dialogue.png",M,188,CW,245,
            "Captura do diálogo com Asterion. As falas completas permanecem nos recursos do jogo.")
    block("Estrutura do encontro", "A conversa apresenta o Shooter e a defesa. Uma horda de minotauros permite praticar; ao concluir, Nox retorna a Asterion, recupera a vida e conhece o Skybreaker. O duelo mistura ataques do boss e pressão dos minions fortalecidos.",M,470)
    block("O que precisa ser aprendido", "Asterion anuncia o impacto antes de cair. O jogador evita ou responde ao ataque e aproveita a vulnerabilidade no chão. Enquanto o boss está sentado ou em voo, não há uma janela normal de dano. O parry oferece uma resposta de precisão.",M,576)
    note("DESFECHO E CONTINUIDADE", "Asterion se rende e permanece vivo. A recompensa encerra a introdução; a continuação de campanha leva à arena dos seis pedestais. Essa ligação após o tutorial ainda precisa ser integrada.",693,height=83)


def map_diagram(top=188, height=343):
    x=M
    rect(x,top,CW,height,PLUM,radius=5)
    # Topological overview; positions preserve the user's six-pedestal arrangement.
    rect(x+17,top+15,CW-34,103,"#65445f",radius=4)
    txt("CASTELO / NORTE",x+29,top+24,220,8.1,font="Bold",color="#d4b7d1",record=False)
    rect(x+370,top+118,39,height-132,"#195b69")
    txt("RIO",x+374,top+227,31,7.1,font="Bold",color="#b9e3e7",record=False)
    # Walkable paths and the two river bridges.
    path_color="#9b7e94"
    line([(x+91,top+82),(x+91,top+187),(x+439,top+187),(x+439,top+82)],path_color,7)
    line([(x+257,top+82),(x+257,top+291)],path_color,7)
    line([(x+91,top+187),(x+91,top+291)],path_color,7)
    line([(x+439,top+187),(x+439,top+291)],path_color,7)
    line([(x+257,top+268),(x+439,top+268)],path_color,7)
    for yy in [187,268]:
        rect(x+365,top+yy-7,50,14,"#c9a66a")
    labels=[
        ("P1",91,82,"PROVA DE CERCO",MINT),
        ("P2",257,82,"CHEFE FINAL",ROSE),
        ("P3",439,82,"PROVA DE TRAVESSIA",MINT),
        ("P4",91,291,"ASTERION / REMATCH",ROSE),
        ("P5",257,291,"PROVA DE CONVERGÊNCIA",MINT),
        ("P6",439,291,"GOLEM ELEMENTAL",ROSE),
    ]
    for name,px,py,label,tint in labels:
        C.setFillColor(col(tint))
        C.setStrokeColor(col(GOLD if tint==ROSE else "#a8e0ce"))
        C.setLineWidth(1.4)
        C.circle(x+px,H-top-py,17,fill=1,stroke=1)
        txt(name,x+px-10,top+py-6,23,9.5,font="Bold",color=WHITE,record=False)
        lw=151 if px!=257 else 168
        lx=max(x+4,min(x+px-lw/2,x+CW-lw-4))
        txt(label,lx,top+py+25,lw,6.9,font="Bold",color=WHITE,record=False)
    rect(x+209,top+172,96,28,INK,radius=4)
    txt("CHEGADA / HUB",x+219,top+180,80,7.4,font="Bold",color=WHITE,record=False)
    txt("FLORESTA / SUL",x+18,top+228,160,8.1,font="Bold",color="#d4b7d1",record=False)
    SOURCE.extend(["Mapa esquemático: P1 superior esquerdo = prova de cerco; P2 superior central = chefe final; P3 superior direito = prova de travessia; P4 inferior esquerdo = rematch de Asterion; P5 inferior central = prova de convergência; P6 inferior direito = Golem Elemental.",""])


def arena():
    new_page("Arena dos seis pedestais", "Depois de Asterion, começa o núcleo da aventura: explorar, escolher uma prova e voltar mais preparado.", section="NÍVEL 03 / NÚCLEO DO JOGO")
    map_diagram()
    txt("Mapa esquemático da organização de design, sem escala. O hub de chegada é um ponto de circulação e não conta como um sétimo pedestal.",M,541,CW,8.5,color=MUTED)
    block("Três provas, três chefes", "P1, P3 e P5 são provas de horda. P4, P2 e P6 são os pedestais de chefes: rematch de Asterion no inferior esquerdo, chefe final no superior central e Golem Elemental no inferior direito. O vínculo do Golem com a região inferior direita já existe no projeto.",M,589)
    note("ORGANIZAÇÃO PROPOSTA", "Exploração livre entre os caminhos; ativação deliberada por E. Os papéis dos pedestais e suas condições de desbloqueio formam a proposta de campanha desta edição. O mapa atual já contém seis eventos, ainda sem essa progressão completa.",699,height=81)


GRAPH_NODES = [
    ("ghosts",205,183,185,42,["FANTASMAS", "Combate e dash"],PLUM),
    ("tutorial",205,243,185,42,["ASTERION", "Boss do tutorial"],PLUM),
    ("hub",205,309,185,44,["ARENA / HUB", "Seis pedestais"],PLUM),
    ("h1",40,397,158,51,["P1 / CERCO", "Prova de horda"],MINT),
    ("h3",219,397,158,51,["P5 / CONVERGÊNCIA", "Prova de horda"],MINT),
    ("h2",398,397,157,51,["P3 / TRAVESSIA", "Prova de horda"],MINT),
    ("b2",40,485,158,51,["P4 / ASTERION", "Rematch"],ROSE),
    ("seal",219,485,158,51,["SELO DA PROVA", "P5 concluído"],MINT),
    ("b1",398,485,157,51,["P6 / GOLEM", "Boss elemental"],ROSE),
    ("gate",156,582,283,41,["REUNIR AS TRÊS CONDIÇÕES", "Golem + rematch + prova P5"],PLUM),
    ("final",205,648,185,44,["P2 / CHEFE FINAL", "Pedestal superior central"],ROSE),
    ("end",205,715,185,34,["VITÓRIA / FIM DO ARCO"],PLUM),
    ("tin",40,307,145,48,["PREPARAÇÃO", "Boosters / cartas / Tin"],MUTED),
]
GRAPH_EDGES = [
    ([(297,225),(297,243)],False), ([(297,285),(297,309)],False),
    ([(297,353),(297,375),(119,375),(119,397)],False),
    ([(297,353),(297,397)],False),
    ([(297,353),(297,375),(476,375),(476,397)],False),
    ([(119,448),(119,485)],False), ([(297,448),(297,485)],False),
    ([(476,448),(476,485)],False),
    ([(119,536),(119,559),(216,559),(216,582)],False),
    ([(297,536),(297,582)],False),
    ([(476,536),(476,559),(378,559),(378,582)],False),
    ([(297,623),(297,648)],False), ([(297,692),(297,715)],False),
    ([(205,330),(185,330)],True),
]


def graph():
    new_page("Grafo da progressão", "Abertura linear, exploração em três ramos e convergência para o confronto final.", "PROPOSTA")
    for points,dashed in GRAPH_EDGES:
        arrow(points,MUTED if dashed else PLUM,1.3,[3,3] if dashed else None)
        if dashed:
            arrow(list(reversed(points)),MUTED,1.3,[3,3])
    for name,x,y,w,h,lines,tint in GRAPH_NODES:
        rect(x,y,w,h,tint,radius=5)
        if len(lines)==1:
            txt(lines[0],x+10,y+11,w-20,8.6,font="Bold",color=WHITE,record=False)
        else:
            txt(lines[0],x+10,y+9,w-20,8.3,font="Bold",color=WHITE,record=False)
            txt(lines[1],x+10,y+25,w-20,8.1,color=WHITE,record=False)
    txt("Os três ramos são cumulativos e podem ser alternados. Tin representa um desvio de preparação com retorno ao hub. As setas entre pedestais são condições propostas de liberação.",M,762,CW,8.1,leading=10.7,color=MUTED)
    SOURCE.extend(["```mermaid", "flowchart TD", "  Fantasmas --> AsterionTutorial --> Hub", "  Hub --> P1_Cerco --> P4_AsterionRematch --> Condicoes", "  Hub --> P3_Travessia --> P6_Golem --> Condicoes", "  Hub --> P5_Convergencia --> Selo --> Condicoes", "  Hub <--> Tin", "  Condicoes --> P2_ChefeFinal --> Vitoria", "```", "", "A convergência exige as três condições, não apenas uma das entradas.", ""])
    export_graph_svg()


def export_graph_svg():
    parts=[f'<svg xmlns="http://www.w3.org/2000/svg" width="1190" height="1684" viewBox="0 0 {W} {H}"><defs><marker id="arrow" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="5" markerHeight="5" orient="auto-start-reverse"><path d="M0 0 L10 5 L0 10" fill="{PLUM}"/></marker></defs><rect width="100%" height="100%" fill="{PAPER}"/><g font-family="Segoe UI,Arial,sans-serif">',f'<text x="40" y="75" fill="{PLUM}" font-weight="700" font-size="25">MONSTER BOOSTER</text><text x="40" y="110" fill="{INK}" font-size="17">Grafo da progressão</text><text x="40" y="136" fill="{MUTED}" font-size="10">Proposta de campanha / 07.11.2026</text>']
    for points,dashed in GRAPH_EDGES:
        pts=" ".join(f"{x},{y}" for x,y in points)
        dash=' stroke-dasharray="3 3" marker-start="url(#arrow)"' if dashed else ''
        parts.append(f'<polyline points="{pts}" fill="none" stroke="{PLUM}" stroke-width="1.4" marker-end="url(#arrow)"{dash}/>')
    for name,x,y,w,h,lines,tint in GRAPH_NODES:
        parts.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="5" fill="{tint}"/>')
        for i,t in enumerate(lines):
            yy=y+20+i*15 if len(lines)>1 else y+22
            parts.append(f'<text x="{x+10}" y="{yy}" font-size="{8.8 if i==0 else 8.3}" fill="{WHITE}" font-weight="{700 if i==0 else 400}">{html.escape(t)}</text>')
    for i,t in enumerate(["Os três ramos são cumulativos; a convergência exige Golem, rematch e P5.","Tin é um desvio de preparação com retorno ao hub. Relações entre pedestais são propostas."]):
        parts.append(f'<text x="40" y="{780+i*15}" font-size="8.3" fill="{MUTED}">{html.escape(t)}</text>')
    parts.append('</g></svg>')
    (OUT/"Monster_Booster_Progressao.svg").write_text("\n".join(parts),encoding="utf-8")


def trials():
    new_page("Provas dos pedestais", "Os três encontros de horda dão função aos caminhos e preparam respostas para os chefes.", "PROPOSTA")
    specs=[
        ("P1 / CERCO", "Superior esquerdo", "Pressão de aproximação em espaço aberto. Reaplica o que os fantasmas ensinaram, exigindo manter uma rota de fuga e escolher prioridades no grupo.", "Conclusão libera o pedestal P4: rematch de Asterion."),
        ("P3 / TRAVESSIA", "Superior direito", "Pressão durante deslocamento em uma área recortada pelo terreno. Incentiva dash para reposicionamento e leitura de espaços seguros, preparando o Golem.", "Conclusão libera o pedestal P6: Golem Elemental."),
        ("P5 / CONVERGÊNCIA", "Inferior central", "Combina densidade e alternância de direções de ataque. O jogador testa a combinação atual sem introduzir um novo comando obrigatório.", "Conclusão fornece a terceira condição para abrir o chefe final."),
    ]
    for i,(title,where,body,reward) in enumerate(specs):
        y=190+i*155
        rect(M,y,CW,138,WHITE,LINE,4)
        txt(title,M+14,y+13,CW-28,14,font="Display",color=MINT)
        txt(where.upper(),M+14,y+39,CW-28,8.1,font="Bold",color=MUTED)
        txt(body,M+14,y+60,CW-28,10.3,max_h=46)
        txt(reward,M+14,y+112,CW-28,9.2,font="Bold",color=PLUM)
    note("BASE ATUAL E EVOLUÇÃO", "O protótipo já oferece eventos por E, limite de arena enquanto o encontro está ativo e conclusão por eliminações. As identidades das provas, recompensas e dependências acima são a evolução proposta; não exigem exatamente 40 inimigos no balanceamento final.",676,height=103)


def golem():
    new_page("Golem Elemental", "Pedestal inferior direito. O cenário vira parte central do combate.", "BASE EXISTENTE", "P6 / BOSS ELEMENTAL")
    picture("output/elemental_golem/flashes/element_2_03_active.png",M,188,CW,245,
            "Captura do especial elétrico na arena atual do Golem Elemental.")
    block("Arena e deslocamento", "Nove plataformas separadas por vãos curtos. O dash conecta o piso seguro; cair retira um dos seis blocos da vida e devolve Nox ao último ponto seguro, sem reiniciar o boss. Uma queda não letal concede um segundo de proteção contra ataques.",M,469)
    block("Padrão e resposta", "O Golem troca de plataforma antes de novas rajadas e alterna gelo, fogo e raio. As bolas podem ser evitadas ou devolvidas por parry. Em 75%, 50% e 25% de vida, pula ao centro, recebe um escudo e prepara sete cortes elementais que acendem em sequência.",M,576)
    note("PAPEL NA CAMPANHA", "A vitória demonstra domínio do dash, do parry de projéteis e das áreas seguras. O acesso pelo altar inferior direito já funciona; exigir a prova P3 e registrar a vitória para abrir P2 são conexões propostas de campanha.",692,height=87)


def rematch():
    new_page("Asterion: rematch", "Pedestal inferior esquerdo. Reconhecer o rival já não basta: é preciso dominar sua resposta.", "PROPOSTA", "P4 / REENCONTRO")
    picture(ASSETS/"asterion_rematch_conceito_v2.png",M,188,CW,287,
            "Conceito gerado para estudo. A arte e os padrões deste rematch ainda não estão implementados.")
    block("Identidade do confronto", "Preservar a silhueta, a provocação e o Skybreaker de Asterion. O rematch reaproveita a linguagem aprendida no tutorial e aumenta a exigência por sequências mais ricas, com pausas claras para atacar.",M,511)
    small_card("FASE 1 / RECONHECER", "Ataques familiares com reposicionamento mais frequente. As janelas continuam visíveis e alcançáveis.",M,610,COL,105,PLUM)
    small_card("FASE 2 / ADAPTAR", "Skybreaker seguido de pressão de minions em momentos alternados. Evitar sobreposição que elimine rotas de fuga.",M+COL+GAP,610,COL,105,ROSE)
    txt("Entrada proposta: concluir P1. Vitória: registrar o triunfo no pedestal e satisfazer uma das condições de P2. Vida, tempos, recompensas e quantidade de fases são parâmetros a validar em protótipo.",M,741,CW,9.5,color=MUTED)


def final_boss():
    new_page("Chefe final", "Pedestal superior central. A última prova reúne as decisões aprendidas ao longo do jogo.", "PROPOSTA", "P2 / CONVERGÊNCIA FINAL")
    picture(ASSETS/"chefe_final_conceito_v2.png",M,188,CW,287,
            "Conceito exploratório de um Dark Lord. Nome, aparência final e narrativa ainda em definição.")
    block("Proposta de identidade", "Um Dark Lord associado à disputa pelos poderes da coleção. A imagem explora uma silhueta monumental e três sinais de poder, em contraste com Nox. Ela orienta escala, atmosfera e leitura; não fixa uma nova identidade canônica.",M,511)
    block("Estrutura do desafio", "Alternar padrões de projéteis, marcações de área e janelas curtas de vulnerabilidade. Cada etapa retoma uma habilidade conhecida antes de combiná-la com outra. A dificuldade vem da decisão e da execução, sem exigir uma carta rara específica.",M,614)
    note("ABERTURA E VITÓRIA", "P2 abre após derrotar o Golem e o rematch de Asterion e concluir P5; P1 e P3 já são pré-requisitos desses chefes. A vitória encerra o arco. Recompensa final e continuação após os créditos ficam para definição posterior.",694,height=86)


def environment():
    new_page("Cenário e câmera", "A composição protege a leitura do combate e dá sentido à exploração.")
    picture("output/room_2/overview.png",M,188,246,254,
            "Vista existente do mapa aberto; o esquema da p. 11 define os papéis de design.")
    block("Três regiões", "Castelo elevado ao norte, floresta ao sul e floresta ribeirinha a leste. Os caminhos fazem os pedestais legíveis; as duas pontes organizam a passagem pelo rio.",M+265,190,CW-265,size=10.4)
    block("Terreno e obstáculos", "Árvores, bordas e água orientam circulação. Elementos decorativos fora da área jogável podem sugerir criaturas, sem dano ou interação. O Golem usa vãos atravessáveis por dash como regra específica da arena.",M,492)
    block("Câmera de gameplay", "Visão superior centrada no jogador, compartilhada pelo tutorial e pelo mapa aberto. O enquadramento precisa mostrar preparação de ataques e espaço de resposta. O mercante usa uma composição lateral própria, voltada à fachada e a Tin.",M,595)
    note("APRESENTAÇÃO", "Sombras, folhas e brilhos dão profundidade sem esconder o piso. Recuo de câmera e efeitos de impacto reforçam os eventos sem mover o personagem ou mudar a regra de colisão.",706,height=70)


def hud():
    new_page("HUD e interface", "Informação essencial nas bordas; perigo e resposta permanecem no mundo.")
    # Original diagram, not a claim of a fully implemented screen.
    sx,sy,sw,sh=M,188,CW,245
    rect(sx,sy,sw,sh,PLUM,radius=4)
    for i in range(6):
        rect(sx+18+i*16,sy+17,13,13,"#2cf7a3" if i<5 else "#281c2c", "#f0e8ec")
    txt("1",sx+128,sy+16,20,9,font="Bold",color=WHITE,record=False)
    # Player and warning shape intentionally schematic.
    C.setStrokeColor(col("#f5d976")); C.setLineWidth(1.5)
    C.circle(sx+355,H-sy-100,33,fill=0,stroke=1)
    C.setFillColor(col("#c9a9e3")); C.circle(sx+215,H-sy-138,9,fill=1,stroke=0)
    line([(sx+223,sy+138),(sx+238,sy+132)],"#00baa7",4)
    line([(sx+270,sy+139),(sx+282,sy+139)],WHITE,1)
    line([(sx+276,sy+133),(sx+276,sy+145)],WHITE,1)
    txt("2",sx+291,sy+131,20,9,font="Bold",color=WHITE,record=False)
    rect(sx+96,sy+211,sw-192,8,"#a0251f",GOLD)
    txt("CHEFE",sx+224,sy+191,80,8.2,font="Bold",color=GOLD,record=False)
    txt("3",sx+sw-78,sy+206,20,9,font="Bold",color=WHITE,record=False)
    txt("Esquema de leitura, sem escala. Posições finais de cada arena devem preservar os padrões de ataque.",M,443,CW,8.4,color=MUTED)
    step(1,"Vida de Nox", "Barra com seis blocos no canto superior esquerdo, sem números. Verde intenso para vida disponível e alerta vermelho ao cruzar um bloco.",482,74)
    step(2,"Mira e interação", "A mira permanece visível no gameplay. A indicação E aparece junto ao objeto utilizável; o anel do pedestal comunica conclusão sem uma contagem permanente na HUD.",568,78)
    step(3,"Barra do chefe", "Nome e barra própria identificam o confronto. Indicadores de vulnerabilidade e preparação precisam combinar com a animação do boss e com o sinal no chão.",658,78)
    txt("Evolução proposta: na tela segura de coleção, mostrar os três slots e comparar efeitos de forma direta. A apresentação de raridade depende de cartas e regras aprovadas.",M,748,CW,9.1,color=MUTED)


def art():
    new_page("Direção de arte", "Pixel art de silhuetas claras, cenário vinho e roxo e poderes de cores funcionais.")
    picture("output/asterion_tutorial/arrival_floor.png",M,188,CW,205,
            "Referência visual do próprio projeto: chão, trono, correntes e contraste de escala.")
    palette=[("SOMBRA",INK),("MUNDO",PLUM),("CAMINHO","#45283c"),("PODER","#00baa7"),("VIDA","#2cf7a3"),("DESTAQUE",GOLD)]
    pw=(CW-5*9)/6
    for i,(name,value) in enumerate(palette):
        x=M+i*(pw+9)
        rect(x,427,pw,36,value,radius=3)
        txt(name,x,472,pw,7.1,font="Bold",color=PLUM,record=False)
        txt(value.upper(),x,488,pw,7.8,color=MUTED,record=False)
    block("Unidade visual", "Contornos, escala dos pixels, desenho das sombras e duração dos efeitos unem os elementos. Os ataques podem sair da paleta do cenário para tornar origem, direção e comportamento reconhecíveis.",M,535)
    block("Conceitos futuros", "As imagens do rematch e do chefe final investigam espaço, escala e atmosfera. O piso e as silhuetas precisam continuar simples quando o conceito virar um cenário jogável. Detalhe ornamental e partículas ficam subordinados ao combate.",M,635)
    txt("Os conceitos desta edição foram gerados com a ferramenta de imagens e identificados como propostas. Sprites, cartas e capturas existentes aparecem como base do projeto, sem sugerir implementação nova.",M,744,CW,9.2,color=MUTED)


def audio():
    new_page("Música e efeitos", "O áudio reforça ritmo e timing. A direção abaixo organiza a sonorização futura.", "PROPOSTA")
    block("Música por função", "Exploração dá espaço à curiosidade; hordas acrescentam pulso; chefes sustentam tensão sem competir com os sinais de ataque. Tin oferece uma pausa reconhecível entre confrontos.",M,190)
    sections=[
        ("ABERTURA E EXPLORAÇÃO", "Texturas discretas e motivos curtos. A horda inicial cresce em intensidade, mantendo audível a confirmação do dash e dos acertos."),
        ("ASTERION E GOLEM", "Asterion recebe uma identidade rítmica que pode retornar no rematch. No Golem, gelo, fogo e raio ganham timbres distintos para ajudar a antecipar o padrão."),
        ("CHEFE FINAL", "Reapresentar a tensão dos encontros anteriores em um tema próprio. Pausas e mudanças de fase precisam respirar, em vez de manter intensidade máxima contínua."),
    ]
    for i,(title,body) in enumerate(sections):
        small_card(title,body,M,295+i*117,CW,101,PLUM if i!=2 else ROSE)
    heading("Prioridades de SFX",M,666)
    txt("<b>Alta prioridade:</b> preparação de ataque forte, impacto, parry bem-sucedido, dano e derrota. <b>Resposta de ação:</b> disparo, dash, interação e confirmação de escolha. <b>Recompensa:</b> rasgo do booster, revelação da carta e conclusão do pedestal.",M,695,CW,10.4)
    txt("A abertura de boosters atual permanece sem som; esta página define pontos de integração. A seleção de trilhas e licenças precisa ser feita antes da distribuição.",M,759,CW,8.8,color=MUTED)


def screens():
    new_page("Fluxo de telas e derrota", "Entrar, agir, receber retorno e retomar o jogo sem perder a orientação.")
    # Vertical screen flow with contextual branches.
    boxes=[(M,190,CW,45,"MENU PRINCIPAL / NOVO JOGO",PLUM),
           (M,257,CW,45,"FANTASMAS / ASTERION / ARENA DOS PEDESTAIS",PLUM),
           (M,324,COL,52,"COMBATE",ROSE),
           (M+COL+GAP,324,COL,52,"PONTO SEGURO / CARTAS / TIN",MINT),
           (M,409,COL,52,"DERROTA / TENTAR NOVAMENTE",ROSE),
           (M+COL+GAP,409,COL,52,"VITÓRIA / RECOMPENSA / EXPLORAÇÃO",MINT)]
    arrow([(W/2,235),(W/2,257)])
    arrow([(W/2,302),(W/2,313),(M+COL/2,313),(M+COL/2,324)])
    arrow([(W/2,302),(W/2,313),(M+COL+GAP+COL/2,313),(M+COL+GAP+COL/2,324)])
    arrow([(M+COL/2,376),(M+COL/2,409)],ROSE)
    arrow([(M+COL/2,376),(M+COL/2,390),(M+COL+GAP+COL/2,390),(M+COL+GAP+COL/2,409)],MINT)
    arrow([(M,435),(M-10,435),(M-10,350),(M,350)],ROSE)
    arrow([(W-M,435),(W-M+10,435),(W-M+10,279),(W-M,279)],MINT)
    line([(W-M,350),(W-M+10,350)],MINT,1.3)
    for x,y,w,h,label,tint in boxes:
        rect(x,y,w,h,tint,radius=4)
        txt(label,x+12,y+14,w-24,8.4,font="Bold",color=WHITE,max_h=30,record=False)
    txt("Fluxo de experiência proposto. Menu, coleção e ligações de campanha ainda precisam de integração.",M,476,CW,8.5,color=MUTED)
    block("Derrota e tentativa", "O protótipo apresenta a derrota com desaceleração e permite tentar novamente. O retorno restaura a entrada do encontro, a vida e o dash; o combate reinicia. Na arena do Golem, a saída para o mundo também é uma opção.",M,518)
    block("Checkpoint e persistência", "O estado atual é local à sessão: não há save de campanha persistente. A campanha proposta deve preservar pedestais e chefes concluídos ao tentar de novo, reiniciando apenas o encontro perdido. A persistência entre partidas é um marco de produção próprio.",M,625)
    txt("Pausas, diálogos e transições que retiram o controle não devem manter dano ativo. No tutorial, a derrota de Nox tem prioridade se ambos os personagens forem derrotados ao mesmo tempo.",M,743,CW,9.4,color=MUTED)


def scope():
    new_page("Escopo e próximos marcos", "A campanha proposta se apoia no protótipo existente e explicita o trabalho que ainda falta.")
    block("Base existente", "Combate com Shooter, dash e parry; encontro inicial de fantasmas; tutorial de Asterion com rendição; mapa aberto com seis eventos de pedestal; Golem Elemental e acesso pela região inferior direita; apresentação de boosters e derrota com nova tentativa.",M,189)
    step(1,"Conectar a campanha", "Ligar a saída do tutorial à arena aberta. Atribuir papéis aos seis pedestais e implementar as condições do grafo, com retorno consistente ao hub.",301,76)
    step(2,"Concluir a progressão de poderes", "Conectar recompensas reais, abertura de boosters, comparação de cartas, equipamento e economia de Tin. Definir raridades, duplicatas e persistência antes de prometer coleção entre partidas.",388,85)
    step(3,"Prototipar os confrontos futuros", "Construir rematch de Asterion e chefe final a partir de leitura, rotas de fuga e janelas de resposta. Testar as provas P1, P3 e P5 com diferentes combinações.",482,80)
    step(4,"Validar o arco completo", "Jogar do início à vitória sem ferramentas de debug, testar derrota e retorno em cada encontro, ajustar dificuldade, legibilidade, recompensas e áudio.",573,77)
    heading("Base editorial e referências",M,675,size=13)
    txt("Estrutura: GDD de Dead Dudes fornecido em docs. Conteúdo: GDD.md, ONE_PAGE.md, TDD.md, ROOM_2.md, HORDE_PEDESTAL.md e SPIRIT_HORDE.md, além do mapa LDtk, recursos e capturas do projeto. As orientações do autor para esta edição definem a sequência da campanha.",M,703,CW,8.9,leading=12.2)
    txt("Artes novas: conceitos de rematch e chefe final via ferramenta de geração de imagens. Imagens e prompts completos foram preservados em output/pdf/gdd_assets; texto editável em docs/GDD_EDITORIAL.md. A arte conceitual não representa conteúdo implementado.",M,756,CW,8.1,leading=10.6)


def validate():
    reader=PdfReader(PDF)
    if len(reader.pages)!=22:
        raise ValueError(f"Expected 22 pages, got {len(reader.pages)}")
    texts=[p.extract_text() or "" for p in reader.pages]
    if any(len(t)<250 for t in texts):
        raise ValueError("Unexpectedly empty page")
    all_text="\n".join(texts)
    for expected in ["Grafo da progressão","inferior direito","inferior esquerdo","superior central","PROPOSTA","Golem","Tin"]:
        if expected not in all_text:
            raise ValueError(f"Missing required text: {expected}")
    if "\ufffd" in all_text or "\u25a0" in all_text:
        raise ValueError("Broken glyphs in PDF text")
    for p in reader.pages:
        if abs(float(p.mediabox.width)-W)>0.02 or abs(float(p.mediabox.height)-H)>0.02:
            raise ValueError("Wrong page size")
    report=dict(pages=len(reader.pages),bytes=PDF.stat().st_size,text_characters=len(all_text),
                page_text_characters=[len(t) for t in texts],elements=len(RECEIPTS),
                graph=dict(nodes=len(GRAPH_NODES),edges=len(GRAPH_EDGES),final_gate="AND"),
                layout_bounds="passed",text_integrity="passed")
    (QA/"validation.json").write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding="utf-8")
    (QA/"layout_receipts.json").write_text(json.dumps(RECEIPTS,ensure_ascii=False,indent=2),encoding="utf-8")
    (QA/"extracted.txt").write_text(all_text,encoding="utf-8")
    print(json.dumps(report,ensure_ascii=False))


def main():
    global C
    OUT.mkdir(parents=True,exist_ok=True)
    ASSETS.mkdir(parents=True,exist_ok=True)
    QA.mkdir(parents=True,exist_ok=True)
    register_fonts()
    C=canvas.Canvas(str(PDF),pagesize=A4,pageCompression=1)
    C.setTitle("Monster Booster - Game Design Document")
    C.setAuthor("Gabriel Galski Machado / Team Galski")
    C.setSubject("Design do jogo, seis pedestais, progressão e conceitos visuais")
    C.setCreator("Monster Booster editorial builder / ReportLab")
    for fn in [cover,concept,characters,controls,combat,cards,boosters,enemies,ghosts,tutorial_boss,
               arena,graph,trials,golem,rematch,final_boss,environment,hud,art,audio,screens,scope]:
        fn()
    C.save()
    (ROOT/"docs/GDD_EDITORIAL.md").write_text("\n".join(SOURCE)+"\n",encoding="utf-8")
    validate()


if __name__=="__main__":
    main()
