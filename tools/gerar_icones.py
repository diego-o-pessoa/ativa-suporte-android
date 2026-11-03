"""Gera os icones do Ativa Suporte a partir do simbolo da Ativa (redesenhado
em vetor a partir do logo: barra azul inclinada + triangulo verde).

Uso: python3 tools/gerar_icones.py   (requer Pillow)
"""
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

BLUE = (21, 85, 159, 255)
GREEN = (72, 174, 62, 255)
# Coordenadas medidas no logo oficial (imagem 447x447).
BAR = [(226, 95), (233, 96), (252, 131), (207, 216), (165, 216), (160, 207)]
TRIANGLE = [(259, 149), (297, 216), (222, 216)]
BOX = (160, 95, 297, 216)  # limites do simbolo

RES = Path(__file__).resolve().parents[1] / "flutter/android/app/src/main/res"
ASSETS = Path(__file__).resolve().parents[1] / "flutter/assets"
DENSITIES = {"mdpi": 1, "hdpi": 1.5, "xhdpi": 2, "xxhdpi": 3, "xxxhdpi": 4}


def shape_layer(points, color, size, scale, offset, radius):
    """Forma com cantos arredondados (desenha grande, borra e corta)."""
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).polygon([((x - BOX[0]) * scale + offset[0], (y - BOX[1]) * scale + offset[1]) for x, y in points], fill=255)
    mask = mask.filter(ImageFilter.GaussianBlur(radius)).point(lambda v: 255 if v > 128 else 0)
    layer = Image.new("RGBA", (size, size), color)
    layer.putalpha(mask)
    return layer


def symbol(size, fraction, mono=None):
    """Simbolo centralizado ocupando `fraction` do lado (desenhado 8x e reduzido)."""
    big = size * 8
    w, h = BOX[2] - BOX[0], BOX[3] - BOX[1]
    scale = big * fraction / max(w, h)
    offset = ((big - w * scale) / 2, (big - h * scale) / 2)
    radius = scale * 3.2
    img = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    img.alpha_composite(shape_layer(BAR, mono or BLUE, big, scale, offset, radius))
    img.alpha_composite(shape_layer(TRIANGLE, mono or GREEN, big, scale, offset, radius))
    return img.resize((size, size), Image.LANCZOS)


def on_background(size, round_):
    """Icone legado (Android < 8): fundo branco, quadrado arredondado ou circulo."""
    big = size * 8
    bg = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    draw = ImageDraw.Draw(bg)
    if round_:
        draw.ellipse((0, 0, big - 1, big - 1), fill=(255, 255, 255, 255))
    else:
        draw.rounded_rectangle((0, 0, big - 1, big - 1), radius=big * 0.18, fill=(255, 255, 255, 255))
    bg = bg.resize((size, size), Image.LANCZOS)
    bg.alpha_composite(symbol(size, 0.62))
    return bg


def main():
    for name, factor in DENSITIES.items():
        folder = RES / f"mipmap-{name}"
        launcher = round(48 * factor)
        # Adaptativo (Android 8+): 108dp, conteudo dentro da zona segura de 66dp.
        symbol(round(108 * factor), 0.50).save(folder / "ic_launcher_foreground.png", optimize=True)
        on_background(launcher, False).save(folder / "ic_launcher.png", optimize=True)
        on_background(launcher, True).save(folder / "ic_launcher_round.png", optimize=True)
        # Notificacao: silhueta branca em fundo transparente (24dp).
        stat = symbol(round(24 * factor), 0.92, mono=(255, 255, 255, 255))
        stat.convert("LA").save(folder / "ic_stat_logo.png", optimize=True)
    # Logo dentro do app (tela inicial).
    on_background(256, False).save(ASSETS / "ativa_logo.png", optimize=True)
    print("icones gerados em", RES, "e", ASSETS / "ativa_logo.png")


if __name__ == "__main__":
    main()
