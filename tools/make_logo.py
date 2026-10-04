"""Draws logo.png (CurseForge/GitHub avatar): an infinity loop over three talent-tree columns."""
import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

SIZE, SS = 512, 4  # final size, supersampling factor
S = SIZE * SS
GOLD, TEAL, BLUE = (255, 200, 51), (127, 224, 208), (115, 184, 255)
OFF = (58, 58, 66)


def px(v):
    return int(v * SS)


base = Image.new("RGBA", (S, S), (0, 0, 0, 0))

# rounded dark tile with a vertical gradient
bg = Image.new("RGBA", (S, S))
for y in range(S):
    t = y / S
    c = tuple(int(a + (b - a) * t) for a, b in zip((26, 26, 34), (10, 10, 13)))
    ImageDraw.Draw(bg).line([(0, y), (S, y)], fill=c + (255,))
mask = Image.new("L", (S, S), 0)
ImageDraw.Draw(mask).rounded_rectangle([0, 0, S - 1, S - 1], radius=px(96), fill=255)
base.paste(bg, (0, 0), mask)
ImageDraw.Draw(base).rounded_rectangle([px(6), px(6), S - px(6), S - px(6)], radius=px(90), outline=GOLD + (90,), width=px(4))

# shapes and their glow on separate layers: background, glow, shapes
img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
d = ImageDraw.Draw(img)
glow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
g = ImageDraw.Draw(glow)

# infinity loop ("Forever")
cx, cy, a = S / 2, px(128), px(122)
pts = []
for i in range(721):
    t = 2 * math.pi * i / 720
    den = 1 + math.sin(t) ** 2
    pts.append((cx + a * math.cos(t) / den, cy + a * math.sin(t) * math.cos(t) / den))
for x, y in pts:  # stamped dots give a smooth, even stroke
    r = px(9)
    d.ellipse([x - r, y - r, x + r, y + r], fill=GOLD + (255,))
    g.ellipse([x - 2 * r, y - 2 * r, x + 2 * r, y + 2 * r], fill=GOLD + (60,))

# three talent trees: columns of nodes, learned ones lit and linked
cols = [(px(136), TEAL, 3), (px(256), GOLD, 4), (px(376), BLUE, 2)]  # x, colour, nodes learned
rows = [px(250), px(318), px(386), px(454)]
node = px(46)
for x, colour, learned in cols:
    for r in range(len(rows) - 1):
        lit = r + 1 < learned
        d.line([(x, rows[r]), (x, rows[r + 1])], fill=(colour if lit else OFF) + (255,), width=px(8))
        if lit:
            g.line([(x, rows[r]), (x, rows[r + 1])], fill=colour + (120,), width=px(20))
    for r, y in enumerate(rows):
        lit = r < learned
        box = [x - node / 2, y - node / 2, x + node / 2, y + node / 2]
        d.rounded_rectangle(box, radius=px(10), fill=(18, 18, 22, 255),
                            outline=(colour if lit else OFF) + (255,), width=px(7))
        if lit:
            inner = [box[0] + px(13), box[1] + px(13), box[2] - px(13), box[3] - px(13)]
            d.rounded_rectangle(inner, radius=px(4), fill=colour + (255,))
            g.rounded_rectangle(box, radius=px(10), fill=colour + (110,))

glow = glow.filter(ImageFilter.GaussianBlur(px(10)))
glow.putalpha(Image.composite(glow.getchannel("A"), Image.new("L", (S, S), 0), mask))
out = Image.alpha_composite(Image.alpha_composite(base, glow), img)
out = out.resize((SIZE, SIZE), Image.LANCZOS)
target = Path(__file__).resolve().parent.parent / "logo.png"
out.save(target)
print(target)
