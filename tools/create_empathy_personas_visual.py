"""Create the visual empathy maps and personas handout for Monster Booster."""

from html import escape
from pathlib import Path
import json

from reportlab.lib.colors import HexColor, Color
from reportlab.lib.enums import TA_LEFT, TA_CENTER
from reportlab.lib.styles import ParagraphStyle
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.pdfgen import canvas
from reportlab.platypus import Paragraph


ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "output" / "pdf"
PDF = OUT / "Monster_Booster_Empatia_e_Personas_Visual.pdf"
W, H = 1200, 800

for name, filename in (
    ("Body", "segoeui.ttf"),
    ("Bold", "segoeuib.ttf"),
    ("Light", "segoeuil.ttf"),
):
    pdfmetrics.registerFont(TTFont(name, str(Path("C:/Windows/Fonts") / filename)))

P = {
    "paper": "#F7F4F0",
    "ink": "#2D2036",
    "muted": "#746C7D",
    "wine": "#26172E",
    "wine2": "#392642",
    "line": "#E4DDE6",
    "white": "#FFFFFF",
    "lilac": "#B79AE8",
    "violet": "#76519C",
    "lavender": "#F0E9F8",
    "mint": "#82D8BB",
    "green": "#276A56",
    "greenlight": "#E6F3ED",
    "coral": "#E8AA9A",
    "rose": "#F8E8E3",
    "red": "#A24F48",
    "cream": "#F2D6A3",
}

LARA = {
    "id": "01",
    "name": "Lara Martins",
    "short": "Lara",
    "age": "22 anos",
    "profile": "Iniciante no gênero / tempo limitado",
    "focus": "Descoberta e aprendizagem",
    "accent": "violet",
    "light": "lavender",
    "quote": "Quero descobrir poderes legais e sentir que avancei, mesmo jogando pouco tempo.",
    "job": "Estudante de Design e atendente em meio período",
    "context": "Divide a rotina entre faculdade, trabalho e casa. Joga à noite e gosta de personagens expressivos e novas descobertas.",
    "devices": "Notebook Windows, mouse e smartphone.",
    "apps": "Steam, YouTube, WhatsApp e aplicativos de estudo.",
    "tech": "Intermediária no uso cotidiano; iniciante em roguelikes de ação.",
    "schedule": "3 vezes/semana  |  20 a 40 min",
    "goals": [
        "Relaxar depois dos estudos e do trabalho.",
        "Controlar Nox e vencer os primeiros desafios.",
        "Descobrir cartas e perceber seu avanço.",
    ],
    "needs": [
        "Tutorial prático, com comandos por etapas.",
        "Cartas com explicações curtas e efeitos claros.",
        "Boa leitura dos perigos e da própria vida.",
        "Clareza sobre derrota, pausa e retomada.",
    ],
    "frustrations": [
        "Muitos comandos apresentados de uma vez.",
        "Perder sem entender de onde veio o dano.",
        "Equipar uma carta e não perceber a mudança.",
        "Textos longos que consomem o tempo livre.",
    ],
    "behaviors": [
        "Joga 3 vezes por semana, por 20 a 40 minutos.",
        "Testa habilidades por tentativa e erro.",
        "Busca dicas curtas quando fica presa.",
        "Retorna ao perceber evolução e descobertas.",
    ],
    "map": {
        "think": [
            "Quer relaxar e aprender as regras jogando.",
            "Sente curiosidade por novas cartas e receio de muitos comandos.",
            "Valoriza pequenas conquistas no tempo livre.",
        ],
        "see": [
            "Steam, YouTube e clipes de jogos indicados por amigos.",
            "Interfaces com muitos comandos, inimigos e efeitos.",
            "Uma rotina com pouco tempo para jogar no notebook.",
        ],
        "hear": [
            "Amigos recomendam jogos variados e personagens interessantes.",
            "O início é difícil, mas fica mais divertido com a prática.",
            "Dicas de poderes simples e de como desviar.",
        ],
        "say": [
            "Diz que quer entender o que cada carta faz.",
            "Segue o tutorial e testa os comandos na prática.",
            "Escolhe poderes claros e busca dicas quando precisa.",
        ],
        "pain": [
            "Mirar, mover e se defender ao mesmo tempo.",
            "Perder sem reconhecer a origem do dano.",
            "Termos confusos e progresso após derrota pouco claro.",
        ],
        "gain": [
            "Aprender o básico em etapas curtas.",
            "Entender as cartas e reconhecer os perigos.",
            "Sentir evolução mesmo em sessões breves.",
        ],
    },
}

BRUNO = {
    "id": "02",
    "name": "Bruno Oliveira",
    "short": "Bruno",
    "age": "27 anos",
    "profile": "Experiente no gênero / foco em estratégia",
    "focus": "Domínio e experimentação",
    "accent": "green",
    "light": "greenlight",
    "quote": "Quero vencer porque entendi o combate e montei uma combinação que faz sentido.",
    "job": "Auxiliar administrativo",
    "context": "Trabalha de dia e joga à noite e nos fins de semana. Tem experiência com ação e cartas; gosta de desafios e estratégias próprias.",
    "devices": "PC para jogos, teclado, mouse e smartphone.",
    "apps": "Steam, Discord, YouTube e navegador para guias e discussões.",
    "tech": "Avançada em jogos no PC, ajustes de controles e consulta a comunidades.",
    "schedule": "4 vezes/semana  |  45 a 90 min",
    "goals": [
        "Dominar inimigos, dash e parry.",
        "Explorar interações entre os três tipos de carta.",
        "Criar estratégias próprias e superar desafios.",
    ],
    "needs": [
        "Efeitos e condições de ativação bem descritos.",
        "Comparação de cartas e combinação equipada.",
        "Controles responsivos e ataques legíveis.",
        "Variedade e espaço para testar estratégias.",
    ],
    "frustrations": [
        "Efeitos com regras vagas ou inconsistentes.",
        "Uma combinação superior a todas as outras.",
        "Derrotas sem informação visual suficiente.",
        "Repetição sem decisões ou adaptações novas.",
    ],
    "behaviors": [
        "Joga 4 vezes por semana, por 45 a 90 minutos.",
        "Troca uma carta por vez para comparar efeitos.",
        "Pratica padrões e analisa suas derrotas.",
        "Consulta guias e compartilha descobertas.",
    ],
    "map": {
        "think": [
            "Quer que habilidade e escolhas influenciem o resultado.",
            "Sente satisfação ao descobrir interações entre cartas.",
            "Valoriza regras consistentes e desafios que possa dominar.",
        ],
        "see": [
            "YouTube, guias e discussões no Discord sobre estratégias.",
            "Comunidades discutindo habilidades e padrões de inimigos.",
            "Possibilidades de combinar três tipos de carta.",
        ],
        "hear": [
            "Recomendações de combinações e formas de vencer.",
            "Críticas quando uma única estratégia domina.",
            "Discussões sobre equilíbrio, variedade e regras claras.",
        ],
        "say": [
            "Pergunta quando um efeito é ativado e com o que interage.",
            "Troca cartas, observa padrões e pratica dash e parry.",
            "Repete desafios e compartilha estratégias.",
        ],
        "pain": [
            "Descrições vagas sobre efeitos e ativações.",
            "Dependência da sorte e pouca variedade entre combinações.",
            "Ataques confusos e repetição sem novas decisões.",
        ],
        "gain": [
            "Dominar o combate e compreender cada derrota.",
            "Criar combinações coerentes com seu estilo.",
            "Vencer pela aprendizagem e seguir experimentando.",
        ],
    },
}


def color(value):
    return HexColor(P.get(value, value))


def box(x, y, w, h, fill="white", stroke=None, radius=18, width=1):
    C.setFillColor(color(fill))
    C.setLineWidth(width)
    if stroke:
        C.setStrokeColor(color(stroke))
    C.roundRect(x, H - y - h, w, h, radius, fill=1, stroke=bool(stroke))


def line(x1, y1, x2, y2, stroke="line", width=1):
    C.setStrokeColor(color(stroke))
    C.setLineWidth(width)
    C.line(x1, H - y1, x2, H - y2)


def text(value, x, y, size=14, font="Body", fill="ink", align="left", spacing=0):
    C.saveState()
    C.setFillColor(color(fill))
    C.setFont(font, size)
    rendered_width = pdfmetrics.stringWidth(value, font, size) + spacing * max(0, len(value) - 1)
    if align == "center":
        x -= rendered_width / 2
    if align == "right":
        x -= rendered_width
    obj = C.beginText(x, H - y - size)
    obj.setCharSpace(spacing)
    obj.textOut(value)
    C.drawText(obj)
    C.restoreState()


def para(value, x, y, w, size=14, leading=None, fill="ink", font="Body", maxh=None, align=TA_LEFT):
    leading = leading or size * 1.36
    style = ParagraphStyle(
        "text", fontName=font, fontSize=size, leading=leading,
        textColor=color(fill), alignment=align, spaceAfter=0,
    )
    p = Paragraph(escape(value).replace("\n", "<br/>"), style)
    _, h = p.wrap(w, H)
    if maxh is not None and h > maxh + 0.1:
        raise ValueError(f"Overflow on page {C.getPageNumber()}: {h:.1f}>{maxh}: {value}")
    p.drawOn(C, x, H - y - h)
    CHECKS.append({"page": C.getPageNumber(), "y": y, "h": round(h, 2), "bottom": round(y + h, 2)})
    return h


def bullets(items, x, y, w, maxh, size=14, leading=19, gap=7, fill="ink", dot="violet"):
    start = y
    for item in items:
        C.setFillColor(color(dot))
        C.circle(x + 3, H - y - 8, 2.1, fill=1, stroke=0)
        h = para(item, x + 16, y, w - 16, size, leading, fill)
        y += h + gap
    used = y - start - gap
    if used > maxh + 0.1:
        raise ValueError(f"Bullet overflow on page {C.getPageNumber()}: {used:.1f}>{maxh}: {items}")
    return used


def icon(kind, x, y, size=28, ink="violet", bg="lavender"):
    if bg:
        box(x, y, size, size, bg, radius=9)
    C.saveState()
    C.translate(x + size / 2, H - y - size / 2)
    C.scale(size / 32, size / 32)
    C.setStrokeColor(color(ink))
    C.setFillColor(color(ink))
    C.setLineWidth(1.65)
    C.setLineCap(1)
    C.setLineJoin(1)
    if kind == "eye":
        p = C.beginPath()
        p.moveTo(-10, 0)
        p.curveTo(-4, 8, 4, 8, 10, 0)
        p.curveTo(4, -8, -4, -8, -10, 0)
        C.drawPath(p)
        C.circle(0, 0, 3, stroke=1, fill=0)
    elif kind == "think":
        C.circle(-3, 3, 5, stroke=1, fill=0)
        C.circle(4, 3, 5, stroke=1, fill=0)
        C.circle(0, 7, 5, stroke=1, fill=0)
        C.circle(-4, -6, 2, stroke=0, fill=1)
        C.circle(-8, -10, 1, stroke=0, fill=1)
    elif kind == "ear":
        p = C.beginPath()
        p.moveTo(-7, 1)
        p.curveTo(-8, 14, 9, 13, 9, 3)
        p.curveTo(9, -3, 3, -3, 3, -8)
        p.curveTo(3, -13, -5, -12, -5, -6)
        C.drawPath(p)
        p = C.beginPath()
        p.moveTo(-2, 2)
        p.curveTo(-3, 8, 4, 7, 4, 3)
        p.lineTo(0, -1)
        C.drawPath(p)
    elif kind == "talk":
        C.roundRect(-10, -4, 20, 14, 4, fill=0, stroke=1)
        p = C.beginPath()
        p.moveTo(-5, -4)
        p.lineTo(-6, -9)
        p.lineTo(0, -4)
        C.drawPath(p)
        for xx in (-5, 0, 5):
            C.circle(xx, 3, .8, fill=1, stroke=0)
    elif kind in ("pain", "needs"):
        if kind == "pain":
            p = C.beginPath()
            p.moveTo(2, 11)
            p.lineTo(-8, -1)
            p.lineTo(-1, -1)
            p.lineTo(-3, -11)
            p.lineTo(9, 3)
            p.lineTo(2, 3)
            p.close()
            C.drawPath(p, fill=0, stroke=1)
        else:
            C.circle(0, 3, 7, stroke=1, fill=0)
            C.line(-3, -3, -3, -8)
            C.line(3, -3, 3, -8)
            C.line(-3, -8, 3, -8)
            C.line(-2, -11, 2, -11)
    elif kind in ("gain", "goal"):
        C.circle(-1, 0, 9, stroke=1, fill=0)
        C.circle(-1, 0, 5, stroke=1, fill=0)
        C.line(-1, 0, 10, 11)
        C.line(6, 11, 10, 11)
        C.line(10, 7, 10, 11)
    elif kind == "behavior":
        C.line(-7, -7, 7, 7)
        for xx, yy in ((-7, -7), (0, 0), (7, 7)):
            C.circle(xx, yy, 3, fill=1, stroke=0)
    elif kind == "cards":
        C.roundRect(-9, -7, 12, 18, 2, stroke=1, fill=0)
        C.roundRect(-2, -11, 12, 18, 2, stroke=1, fill=0)
        C.line(1, 1, 7, 1)
        C.line(1, -3, 7, -3)
    elif kind == "tech":
        C.roundRect(-10, -4, 20, 14, 2, stroke=1, fill=0)
        C.line(-12, -8, 12, -8)
        C.line(-6, -4, -8, -8)
        C.line(6, -4, 8, -8)
    C.restoreState()


def avatar(person, x, y, size):
    """A native vector illustration representing a fictional persona."""
    C.saveState()
    C.translate(x + size / 2, H - y - size / 2)
    C.scale(size / 100, size / 100)
    mask = C.beginPath()
    mask.circle(0, 0, 49)
    C.clipPath(mask, stroke=0, fill=0)
    C.setFillColor(color("#DECFF0" if person is LARA else "#BCE5D6"))
    C.rect(-50, -50, 100, 100, fill=1, stroke=0)
    # Soft geometric background, all art remains vector in the PDF.
    C.setFillColor(color("#C7AFE2" if person is LARA else "#93CBB8"))
    C.circle(38, 34, 29, fill=1, stroke=0)
    C.circle(-44, -32, 32, fill=1, stroke=0)
    hair = "#352535" if person is LARA else "#342F32"
    skin = "#EBC0A6" if person is LARA else "#C08E6C"
    C.setFillColor(color(hair))
    if person is LARA:
        C.roundRect(-25, -26, 50, 62, 22, fill=1, stroke=0)
    else:
        C.roundRect(-24, -3, 48, 40, 17, fill=1, stroke=0)
    C.setFillColor(color("#735298" if person is LARA else "#2A715D"))
    C.ellipse(-44, -77, 44, -14, fill=1, stroke=0)
    C.setFillColor(color(skin))
    C.roundRect(-8, -24, 16, 22, 5, fill=1, stroke=0)
    C.circle(-21, 4, 5, fill=1, stroke=0)
    C.circle(21, 4, 5, fill=1, stroke=0)
    C.ellipse(-21, -13, 21, 33, fill=1, stroke=0)
    C.setFillColor(color(hair))
    p = C.beginPath()
    p.moveTo(-22, 16)
    if person is LARA:
        p.curveTo(-27, 43, 25, 47, 24, 16)
        p.curveTo(15, 18, 10, 26, 9, 30)
        p.curveTo(1, 15, -12, 16, -22, 16)
    else:
        p.curveTo(-31, 37, -7, 48, 1, 35)
        p.curveTo(16, 43, 29, 30, 23, 16)
        p.lineTo(17, 28)
        p.curveTo(6, 24, -6, 26, -18, 22)
    p.close()
    C.drawPath(p, fill=1, stroke=0)
    C.setFillColor(color("#352937"))
    C.circle(-8, 7, 1.6, fill=1, stroke=0)
    C.circle(8, 7, 1.6, fill=1, stroke=0)
    C.setStrokeColor(color("#88564D" if person is LARA else "#795341"))
    C.setLineWidth(1.3)
    C.arc(-6, -5, 6, 1, 200, 140)
    if person is BRUNO:
        C.setStrokeColor(color("#403343"))
        C.setLineWidth(1.5)
        C.roundRect(-17, 2, 14, 11, 3, stroke=1, fill=0)
        C.roundRect(3, 2, 14, 11, 3, stroke=1, fill=0)
        C.line(-3, 8, 3, 8)
    else:
        C.setFillColor(color("cream"))
        C.circle(-23, -4, 2, fill=1, stroke=0)
        C.circle(23, -4, 2, fill=1, stroke=0)
    C.restoreState()


def brand(dark=False):
    ink = "paper" if dark else "wine"
    for xx, yy, cc in ((0, 0, "lilac"), (8, 0, "mint"), (0, 8, "mint"), (8, 8, "lilac")):
        box(48 + xx, 34 + yy, 5, 5, cc, radius=0)
    text("MONSTER BOOSTER", 73, 31, 12, "Bold", ink, spacing=1.6)
    text("DESIGN CENTRADO NO JOGADOR", 1152, 32, 10, "Bold", "lilac" if dark else "muted", align="right", spacing=1)


def footer(number, detail, dark=False):
    ink = "#CBBBD4" if dark else "muted"
    stroke = "#523A5D" if dark else "line"
    line(48, 749, 1152, 749, stroke)
    text(detail, 48, 762, 10, fill=ink)
    text(f"{number:02d} / 05", 1152, 760, 12, "Bold", ink, align="right")


def background(dark=False):
    C.setFillColor(color("wine" if dark else "paper"))
    C.rect(0, 0, W, H, fill=1, stroke=0)
    brand(dark)


def cover_profile(person, x, y):
    box(x, y, 430, 148, "wine2", "#5A4267", radius=20)
    avatar(person, x + 19, y + 25, 98)
    text(f"PERFIL {person['id']}", x + 136, y + 22, 10, "Bold", "mint" if person is BRUNO else "lilac", spacing=1.5)
    text(person["name"], x + 136, y + 42, 25, "Bold", "white")
    text(person["age"], x + 136, y + 79, 13, fill="#E2D8E8")
    para(person["focus"], x + 136, y + 103, 274, 15, 19, "mint" if person is BRUNO else "lilac")


def cover():
    background(True)
    text("PESQUISA DE PÚBLICO", 48, 94, 12, "Bold", "mint", spacing=2)
    para("Mapa de empatia\n& personas", 45, 128, 630, 59, 63, "white", "Bold", maxh=135)
    para("Quem joga Monster Booster?", 48, 276, 590, 25, 32, "lilac", "Bold")
    para(
        "Domínio: jogos digitais de entretenimento. Um roguelike de ação que combina exploração de masmorras, combate contra hordas e cartas de monstros.",
        48, 326, 585, 18, 26, "#E2D8E8", maxh=90,
    )
    box(48, 432, 253, 34, "#43304D", radius=17)
    text("PC / TECLADO E MOUSE", 65, 440, 11, "Bold", "white", spacing=.5)
    box(316, 432, 258, 34, "#43304D", radius=17)
    text("2 PERFIS / 2 MAPAS / 2 PERSONAS", 332, 440, 10, "Bold", "white")
    cover_profile(LARA, 722, 123)
    cover_profile(BRUNO, 722, 294)

    text("NOX COMBINA TRÊS TIPOS DE CARTA PARA MUDAR SEUS PODERES", 48, 505, 12, "Bold", "cream", spacing=.8)
    for i, (title, desc, cc, kind) in enumerate((
        ("Manifestação", "Define a forma e o comportamento do ataque.", "lilac", "cards"),
        ("Infusão", "Acrescenta efeitos ao atacar, acertar ou eliminar.", "mint", "pain"),
        ("Mutação", "Altera habilidades e reações do próprio Nox.", "coral", "behavior"),
    )):
        x = 48 + i * 376
        box(x, 540, 352, 133, "wine2", "#5A4267", radius=18)
        icon(kind, x + 18, 557, 31, cc, None)
        text(title, x + 63, 555, 21, "Bold", "white")
        para(desc, x + 22, 600, 308, 15, 21, "#E2D8E8", maxh=52)
    para(
        "Base: documentação do jogo. Mapas organizados pelos seis campos do enunciado. Perfis, ilustrações e falas são fictícios: hipóteses a validar com jogadores.",
        48, 698, 1104, 12, 17, "#CBBBD4", maxh=38,
    )
    footer(1, "Monster Booster / Mapa de Empatia e Personas / Proposta acadêmica", True)
    C.showPage()


def map_tile(title, kind, items, x, y, w=468, h=184, index=None, fill="white", accent="violet", light="lavender", small=False):
    box(x, y, w, h, fill, "line", radius=18)
    icon(kind, x + 18, y + 16, 32, accent, light)
    text(title, x + 63, y + 19, 16, "Bold", accent)
    if index:
        text(index, x + w - 19, y + 21, 11, "Bold", "muted", align="right")
    bullets(items, x + 22, y + 63, w - 44, h - 76, size=13.7 if small else 14, leading=18.3, gap=6, dot=accent)


def empathy(person, page):
    background()
    text("Mapa de empatia", 48, 75, 37, "Bold")
    text(person["profile"], 49, 124, 16, fill="muted")
    box(895, 83, 257, 39, person["light"], radius=19)
    text(f"{person['id']} / {person['name'].upper()}", 1023.5, 93, 12, "Bold", person["accent"], align="center")

    # Four observation quadrants surround the persona; pains and gains form the base.
    for endpoint in ((516, 267), (684, 267), (516, 464), (684, 464)):
        line(600, 354, *endpoint, stroke="#CFC2D7", width=1.4)
    mm = person["map"]
    map_tile("O QUE PENSA E SENTE?", "think", mm["think"], 48, 166, index="01", accent=person["accent"], light=person["light"])
    map_tile("O QUE VÊ?", "eye", mm["see"], 684, 166, index="02", accent=person["accent"], light=person["light"])
    map_tile("O QUE OUVE?", "ear", mm["hear"], 48, 373, index="03", accent=person["accent"], light=person["light"])
    map_tile("O QUE FALA E FAZ?", "talk", mm["say"], 684, 373, index="04", accent=person["accent"], light=person["light"])

    box(524, 275, 152, 152, person["light"], radius=76)
    avatar(person, 533, 284, 134)
    text(person["short"], 600, 435, 23, "Bold", person["accent"], align="center")
    text(person["age"], 600, 467, 13, fill="muted", align="center")
    text("O JOGADOR", 600, 247, 9.5, "Bold", "muted", align="center", spacing=1.5)

    map_tile("DORES", "pain", mm["pain"], 48, 582, w=540, h=147, fill="rose", accent="red", light="#F0D2C8", small=True)
    map_tile("GANHOS", "gain", mm["gain"], 612, 582, w=540, h=147, fill="greenlight", accent="green", light="#CAE8DA", small=True)
    footer(page, "Perfil e falas fictícios / Hipóteses de público a validar com jogadores")
    C.showPage()


def persona_panel(title, kind, items, x, y, h, accent, light):
    box(x, y, 375, h, "white", "line", radius=18)
    icon(kind, x + 18, y + 17, 30, accent, light)
    text(title.upper(), x + 61, y + 21, 13.5, "Bold", accent, spacing=.5)
    bullets(items, x + 21, y + 65, 333, h - 83, size=13.7, leading=18.5, gap=9, dot=accent)


def persona(person, page):
    background()
    text(person["name"], 48, 75, 38, "Bold")
    text(person["profile"], 49, 125, 16, fill="muted")
    box(974, 86, 178, 34, person["light"], radius=17)
    text(f"PERSONA {person['id']}", 1063, 94, 12, "Bold", person["accent"], align="center", spacing=.8)

    # Persistent profile rail: identity, context and technological profile.
    box(48, 163, 304, 568, "wine", radius=22)
    avatar(person, 79, 184, 110)
    box(218, 207, 104, 32, "wine2", radius=16)
    text(person["age"].upper(), 270, 215, 12, "Bold", "mint" if person is BRUNO else "lilac", align="center")
    text("IDENTIFICAÇÃO", 73, 314, 10, "Bold", "mint" if person is BRUNO else "lilac", spacing=1.6)
    occupation_h = para(person["job"], 73, 337, 254, 16, 21, "white", "Bold", maxh=65)
    para(person["context"], 73, 349 + occupation_h, 254, 13, 18.5, "#E1D5E8", maxh=96)
    line(73, 485, 327, 485, "#5A4267")
    text("PERFIL TECNOLÓGICO", 73, 501, 10, "Bold", "mint" if person is BRUNO else "lilac", spacing=1.1)
    para(person["devices"], 73, 527, 254, 13, 18, "white", maxh=40)
    para(person["apps"], 73, 576, 254, 12.6, 17.5, "#E1D5E8", maxh=39)
    para(person["tech"], 73, 622, 254, 12.6, 17.5, "#E1D5E8", maxh=55)
    box(68, 691, 264, 25, "wine2", radius=12)
    text(person["schedule"], 200, 697, 10.7, "Bold", "white", align="center")

    # Short statement above the four actionable persona dimensions.
    box(378, 163, 774, 99, person["light"], radius=18)
    text("FRASE REPRESENTATIVA", 400, 178, 9.5, "Bold", person["accent"], spacing=1.5)
    para(f'“{person["quote"]}”', 400, 199, 728, 19, 25, person["accent"], "Bold", maxh=55)
    persona_panel("Objetivos", "goal", person["goals"], 378, 284, 204, person["accent"], person["light"])
    persona_panel("Necessidades", "needs", person["needs"], 777, 284, 204, person["accent"], person["light"])
    persona_panel("Frustrações", "pain", person["frustrations"], 378, 511, 220, "red", "rose")
    persona_panel("Comportamentos", "behavior", person["behaviors"], 777, 511, 220, person["accent"], person["light"])
    footer(page, f"Persona fictícia derivada do mapa {person['id']} / Tempos indicam disponibilidade para jogar")
    C.showPage()


if __name__ == "__main__":
    OUT.mkdir(parents=True, exist_ok=True)
    CHECKS = []
    C = canvas.Canvas(str(PDF), pagesize=(W, H), pageCompression=1)
    C.setTitle("Monster Booster | Mapas de Empatia e Personas")
    C.setAuthor("Monster Booster - Team Galski")
    C.setSubject("Dois mapas de empatia e duas personas para o projeto Monster Booster")
    cover()
    empathy(LARA, 2)
    empathy(BRUNO, 3)
    persona(LARA, 4)
    persona(BRUNO, 5)
    C.save()
    report_dir = ROOT / "tmp" / "pdfs" / "empatia_personas"
    report_dir.mkdir(parents=True, exist_ok=True)
    (report_dir / "layout_checks.json").write_text(json.dumps(CHECKS, indent=2), encoding="utf-8")
    print(json.dumps({"pdf": str(PDF), "pages": 5, "text_blocks_checked": len(CHECKS), "bytes": PDF.stat().st_size}, ensure_ascii=False))
