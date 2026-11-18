"""Build the concise design overview without changing any game files.

Content: docs/ONE_PAGE.md. Layout: one A4 page, original pitch palette/fonts,
native project sprites. Output: output/pdf/Monster_Booster_One_Page.pdf.
"""
from __future__ import annotations

import argparse
import base64
import html
import io
import json
import re
from pathlib import Path

from PIL import Image
from pypdf import PdfReader
from reportlab.lib import colors
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.utils import ImageReader
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.pdfgen import canvas
from reportlab.platypus import Paragraph


ROOT = Path(__file__).resolve().parents[2]
PALETTE = {
    "background": "#170f1b", "panel": "#0f0b15", "border": "#694052",
    "foreground": "#f6ede5", "muted": "#c9b5c0", "gold": "#f5d976",
    "rose": "#ee8397", "lilac": "#91a3ff", "green": "#b5c883",
    "wine": "#5b2038", "world_purple": "#24132e", "world_dark": "#25131a",
    "turquoise": "#00baa7", "violet": "#8157c6",
}
PAGE_W, PAGE_H = A4
MARGIN = 30
CONTENT_W = PAGE_W - MARGIN * 2
GAP = 12
HALF_W = (CONTENT_W - GAP) / 2
LAYOUT_RECEIPTS: list[dict] = []


def color(name: str):
    return colors.HexColor(PALETTE.get(name, name))


def sections(source: Path) -> dict[str, str]:
    result = {}
    heading = ""
    for line in source.read_text(encoding="utf-8").splitlines():
        if line.startswith("## "):
            heading = line[3:].strip()
            result[heading] = []
        elif heading:
            result[heading].append(line)
    return {key: "\n".join(lines).strip() for key, lines in result.items()}


def markdown_text(text: str) -> str:
    escaped = html.escape(text)
    return re.sub(r"\*\*(.*?)\*\*", r"<b>\1</b>", escaped)


def register_fonts() -> tuple[str, str, str]:
    """Reuse the pitch's embedded families; Windows fonts are the portable fallback."""
    archived = ROOT / "docs/old/documentacao/GDD/Monster_Booster_Pitch_atualizado.html"
    if archived.exists():
        raw_fonts = re.findall(
            r"data:font/ttf;base64,([A-Za-z0-9+/=]+)",
            archived.read_text(encoding="utf-8"),
        )
        if len(raw_fonts) >= 2:
            for name, encoded in zip(("PitchDisplay", "PitchText"), raw_fonts):
                pdfmetrics.registerFont(TTFont(name, io.BytesIO(base64.b64decode(encoded))))
            return "PitchDisplay", "PitchText", "Bahnschrift / Segoe UI from the original pitch"
    system_fonts = Path("C:/Windows/Fonts")
    paths = [system_fonts / "bahnschrift.ttf", system_fonts / "segoeui.ttf"]
    if all(path.exists() for path in paths):
        for name, path in zip(("PitchDisplay", "PitchText"), paths):
            pdfmetrics.registerFont(TTFont(name, str(path)))
        return "PitchDisplay", "PitchText", "Bahnschrift / Segoe UI from Windows"
    return "Helvetica-Bold", "Helvetica", "Sans-serif fallback (original fonts unavailable)"


DISPLAY, TEXT, FONT_SOURCE = register_fonts()
pdfmetrics.registerFontFamily(TEXT, normal=TEXT, bold=DISPLAY, italic=TEXT, boldItalic=DISPLAY)


def paragraph(c, text: str, x: float, top: float, width: float,
              max_height: float, size: float = 10.6, leading: float = 13.9,
              tint: str = "foreground", font: str | None = None, name: str = ""):
    style = ParagraphStyle(
        "body", fontName=font or TEXT, fontSize=size, leading=leading,
        textColor=color(tint), spaceAfter=0, spaceBefore=0,
    )
    p = Paragraph(text, style)
    _, height = p.wrap(width, max_height)
    if height > max_height + 0.01:
        raise ValueError(f"Overflow in {name!r}: {height:.1f} > {max_height:.1f} pt")
    p.drawOn(c, x, PAGE_H - top - height)
    LAYOUT_RECEIPTS.append({"block": name, "top": top, "height": height, "max_height": max_height})
    return height


def line_text(c, text: str, x: float, top: float, size: float, tint="foreground", font=None):
    c.setFillColor(color(tint))
    c.setFont(font or TEXT, size)
    c.drawString(x, PAGE_H - top - size, text)


def panel(c, x: float, top: float, width: float, height: float, title: str, index: str):
    bottom = PAGE_H - top - height
    c.setFillColor(color("panel"))
    c.setStrokeColor(color("border"))
    c.setLineWidth(0.6)
    c.rect(x, bottom, width, height, fill=1, stroke=1)
    c.setStrokeColor(color("gold"))
    c.setLineWidth(1.0)
    for points in (
        [(x, bottom + height - 9), (x, bottom + height), (x + 9, bottom + height)],
        [(x + width - 9, bottom), (x + width, bottom), (x + width, bottom + 9)],
    ):
        p = c.beginPath()
        p.moveTo(*points[0])
        for point in points[1:]:
            p.lineTo(*point)
        c.drawPath(p)
    line_text(c, title, x + 14, top + 12, 14.4, "gold", DISPLAY)
    c.setFont(TEXT, 7.8)
    c.setFillColor(color("muted"))
    c.drawRightString(x + width - 14, PAGE_H - top - 22, index)


def sprite(c, relative: str, x: float, top: float, max_w: float, max_h: float):
    im = Image.open(ROOT / relative).convert("RGBA")
    bounds = im.getbbox()
    if bounds is None:
        raise ValueError(f"Empty sprite: {relative}")
    im = im.crop(bounds)
    factor = min(max_w / im.width, max_h / im.height)
    width, height = im.width * factor, im.height * factor
    # Keep the source pixel edges explicit inside the vector document.
    reader = ImageReader(im.resize((im.width * 8, im.height * 8), Image.Resampling.NEAREST))
    c.drawImage(reader, x + (max_w - width) / 2, PAGE_H - top - height,
                width=width, height=height, mask="auto")


def bullet_rows(c, raw: str, x: float, top: float, width: float, max_height: float):
    y = top
    for i, bullet in enumerate(raw.splitlines()):
        bullet = bullet.removeprefix("- ")
        c.setFillColor(color("rose"))
        c.rect(x, PAGE_H - y - 7, 3, 3, fill=1, stroke=0)
        height = paragraph(c, markdown_text(bullet), x + 10, y, width - 10,
                           max_height - (y - top), size=10.15, leading=13.5, name=f"combat_{i}")
        y += height + 4
    return y


def build(output: Path):
    source = ROOT / "docs/ONE_PAGE.md"
    content = sections(source)
    output.parent.mkdir(parents=True, exist_ok=True)
    c = canvas.Canvas(str(output), pagesize=A4, pageCompression=1)
    c.setTitle("Monster Booster - One-page de design")
    c.setAuthor("Gabriel Galski Machado / Team Galski")
    c.setSubject("Conceito, cartas, combate, progressão, personagens e direção artística")
    c.setFillColor(color("background"))
    c.rect(0, 0, PAGE_W, PAGE_H, fill=1, stroke=0)
    c.saveState()
    c.setStrokeColor(color("wine"))
    c.setStrokeAlpha(0.16)
    c.setLineWidth(0.35)
    for x in range(0, int(PAGE_W), 32):
        c.line(x, 0, x, PAGE_H)
    for y in range(0, int(PAGE_H), 32):
        c.line(0, y, PAGE_W, y)
    c.restoreState()

    line_text(c, "MONSTER BOOSTER", MARGIN, 16, 8.0, "muted")
    c.setFillColor(color("muted"))
    c.setFont(TEXT, 8.0)
    c.drawRightString(PAGE_W - MARGIN, PAGE_H - 24, "GDD / VISÃO GERAL")
    line_text(c, "Monster", MARGIN, 40, 38, "foreground", DISPLAY)
    line_text(c, "Booster", MARGIN, 79, 38, "gold", DISPLAY)
    line_text(c, "Roguelike de ação · Dungeon crawler · Bullet hell", MARGIN, 130, 9.8, "muted")

    hook = content["Experiência do jogador"].split(". ")
    for index, text in enumerate(hook):
        line_text(c, text.rstrip(".") + ".", 275, 51 + index * 23, 17.0,
                  "gold" if index == 1 else "foreground", DISPLAY)
    for i, pack in enumerate(("core/booster_core_01.png", "elemental/booster_elemental.png", "dracula/booster_dracula.png")):
        sprite(c, "assets/boosters/sets/" + pack, 473 + i * 23, 50, 22, 51)
    c.setStrokeColor(color("border"))
    c.setLineWidth(0.6)
    c.line(MARGIN, PAGE_H - 157, PAGE_W - MARGIN, PAGE_H - 157)

    panel(c, MARGIN, 171, CONTENT_W, 91, "Ideia do jogo", "01")
    paragraph(c, markdown_text(content["Ideia do jogo"]), MARGIN + 14, 205,
              CONTENT_W - 28, 47, size=10.8, leading=14.2, name="premise")

    panel(c, MARGIN, 274, CONTENT_W, 139, "Cartas e combinações", "02")
    aspect_lines, summary = content["Cartas e combinações"].split("\n\n")
    col_w = (CONTENT_W - 28) / 3
    for i, (entry, tint) in enumerate(zip(aspect_lines.splitlines(), ("rose", "lilac", "green"))):
        label, text = re.match(r"- \*\*(.+?):\*\* (.+)", entry).groups()
        x = MARGIN + 14 + i * col_w
        c.setFillColor(color(tint))
        c.rect(x, PAGE_H - 314, col_w - 12, 2, fill=1, stroke=0)
        line_text(c, label, x, 320, 11.8, tint, DISPLAY)
        paragraph(c, html.escape(text[0].upper() + text[1:]), x, 340, col_w - 15,
                  44, size=10.2, leading=13.4, name=f"aspect_{label}")
    paragraph(c, markdown_text(summary), MARGIN + 14, 390, CONTENT_W - 28,
              15, size=9.5, leading=12, tint="muted", name="aspect_summary")

    panel(c, MARGIN, 425, HALF_W, 141, "Combate", "03")
    bullets, closer = content["Combate"].split("\n\n")
    end = bullet_rows(c, bullets, MARGIN + 14, 461, HALF_W - 28, 68)
    paragraph(c, markdown_text(closer), MARGIN + 14, end + 2, HALF_W - 28,
              555 - (end + 2), size=9.7, leading=12.3, tint="muted", name="combat_closer")
    panel(c, MARGIN + HALF_W + GAP, 425, HALF_W, 141, "Boosters e progressão", "04")
    x = MARGIN + HALF_W + GAP + 14
    paragraph(c, markdown_text(content["Boosters e progressão"]).replace("\n\n", "<br/><br/>"),
              x, 461, HALF_W - 28, 95, size=10.3, leading=13.5, name="progression")

    panel(c, MARGIN, 578, CONTENT_W, 129, "Personagens", "05")
    characters = content["Personagens"].splitlines()
    images = (
        "assets/characters/player/idle/player_idle_01.png",
        "assets/enemies/minotaur/elite/animation/propulsion/standing.png",
        "assets/merchant/character/merchant_idle1.png",
    )
    for i, (entry, image) in enumerate(zip(characters, images)):
        name, description = re.match(r"- \*\*(.+?):\*\* (.+)", entry).groups()
        x = MARGIN + 14 + i * col_w
        line_text(c, name, x, 615, 12.0, "foreground", DISPLAY)
        sprite(c, image, x, 642, 40, 54)
        paragraph(c, html.escape(description[0].upper() + description[1:]), x + 49, 641,
                  col_w - 60, 59, size=9.2, leading=11.6, tint="muted", name=f"character_{name}")

    panel(c, MARGIN, 719, CONTENT_W, 83, "Direção artística", "06")
    paragraph(c, markdown_text(content["Direção artística"]), MARGIN + 14, 753,
              355, 42, size=10.0, leading=13.3, name="art_direction")
    for i, tint in enumerate(("world_purple", "wine", "world_dark")):
        c.setFillColor(color(tint))
        c.rect(423 + i * 32, PAGE_H - 774, 27, 16, fill=1, stroke=0)
    for i, tint in enumerate(("turquoise", "violet", "gold")):
        c.setFillColor(color(tint))
        c.rect(423 + i * 32, PAGE_H - 795, 27, 10, fill=1, stroke=0)
    line_text(c, "Mundo / poderes", 423, 741, 7.6, "muted")

    line_text(c, "Gabriel Galski Machado", MARGIN, 819, 8.4, "muted")
    c.setFont(DISPLAY, 8.5)
    c.setFillColor(color("gold"))
    c.drawRightString(PAGE_W - MARGIN, PAGE_H - 827.5, "TEAM GALSKI")
    c.showPage()
    c.save()

    pdf = PdfReader(str(output))
    if len(pdf.pages) != 1:
        raise AssertionError("The overview must fit on one page")
    extracted = pdf.pages[0].extract_text()
    for label in ("Ideia do jogo", "Manifestação", "Infusão", "Mutação", "Asterion", "Tin", "Direção artística"):
        if label not in extracted:
            raise AssertionError(f"Missing text in final PDF: {label}")
    if any(token in extracted for token in ("Godot", "LDtk", "0,278", "250", "A*", "res://")):
        raise AssertionError("Technical implementation details leaked into the one-page")
    receipt = {
        "ok": True, "pdf": str(output), "pages": 1,
        "source": str(source), "font_source": FONT_SOURCE,
        "palette": PALETTE, "content_words": len(source.read_text(encoding="utf-8").split()),
        "layout_checks": LAYOUT_RECEIPTS,
        "game_files_modified": False,
    }
    qa_dir = ROOT / "tmp/pdfs/one_page_qa"
    qa_dir.mkdir(parents=True, exist_ok=True)
    (qa_dir / "layout_report.json").write_text(json.dumps(receipt, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps({"output": str(output), "pages": 1, "font_source": FONT_SOURCE, "words": receipt["content_words"]}, ensure_ascii=False))


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, default=ROOT / "output/pdf/Monster_Booster_One_Page.pdf")
    args = parser.parse_args()
    build(args.output)
