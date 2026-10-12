#!/usr/bin/env python3
"""Generate Vision Font icons (eye glyph) with Pillow.
Extension: images/icon-{48,96,128,256,512}.png (colour) and toolbar-icon-{16,19,32,38}.png (monochrome).
App: App/Assets.xcassets/AppIcon.appiconset/*.png + Contents.json.
Run: python3 tools/make_icons.py"""
import json, math, os
from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
EXT = os.path.join(ROOT, "Extension", "Resources", "images")
APPICON = os.path.join(ROOT, "App", "Assets.xcassets", "AppIcon.appiconset")
SS = 4  # supersampling

def eye_polygon(cx, cy, w, h, n=90):
    pts = []
    for i in range(n + 1):           # upper lid
        t = math.pi * i / n
        pts.append((cx - w / 2 * math.cos(t), cy - h / 2 * math.sin(t) ** 0.9))
    for i in range(n + 1):           # lower lid
        t = math.pi * i / n
        pts.append((cx + w / 2 * math.cos(t), cy + h / 2 * math.sin(t) ** 0.9))
    return pts

def draw_eye(d, size, fg, iris, pupil, bg_cut=None, stroke=None):
    s = size
    cx, cy = s / 2, s / 2
    w, h = s * 0.80, s * 0.48
    d.polygon(eye_polygon(cx, cy, w, h), fill=fg)
    r = h * 0.42
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=iris)
    pr = r * 0.48
    d.ellipse([cx - pr, cy - pr, cx + pr, cy + pr], fill=pupil)
    hr = r * 0.2
    d.ellipse([cx + r * 0.25 - hr, cy - r * 0.45 - hr, cx + r * 0.25 + hr, cy - r * 0.45 + hr], fill=fg)

def colour_icon(px, rounded=True):
    S = px * SS
    im = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    pad = S * 0.08 if rounded else 0
    # blue gradient squircle
    grad = Image.new("RGBA", (S, S))
    gd = ImageDraw.Draw(grad)
    for y in range(S):
        k = y / S
        gd.line([(0, y), (S, y)], fill=(int(20 + 30 * k), int(132 - 60 * k), int(255 - 40 * k), 255))
    mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(mask).rounded_rectangle([pad, pad, S - pad, S - pad], radius=(S - 2 * pad) * 0.225, fill=255)
    im.paste(grad, (0, 0), mask)
    inner = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    draw_eye(ImageDraw.Draw(inner), S, (255, 255, 255, 255), (16, 92, 214, 255), (10, 22, 48, 255))
    im.alpha_composite(inner)
    # small "Aa" hint: a text-size bar under the eye
    bw, bh = S * 0.30, S * 0.035
    d.rounded_rectangle([S / 2 - bw / 2, S * 0.78, S / 2 + bw / 2, S * 0.78 + bh], radius=bh / 2, fill=(255, 255, 255, 200))
    return im.resize((px, px), Image.LANCZOS)

def toolbar_icon(px):
    S = px * SS
    im = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    draw_eye(d, S, (0, 0, 0, 255), (0, 0, 0, 0), (0, 0, 0, 255))
    # punch the iris ring so it reads at 16 px: outline eye, ring iris, solid pupil
    cx = cy = S / 2; h = S * 0.48; r = h * 0.42
    ring = Image.new("L", (S, S), 0); rd = ImageDraw.Draw(ring)
    rd.ellipse([cx - r, cy - r, cx + r, cy + r], fill=255)
    rd.ellipse([cx - r * 0.72, cy - r * 0.72, cx + r * 0.72, cy + r * 0.72], fill=0)
    alpha = im.getchannel("A")
    hole = Image.new("L", (S, S), 0); ImageDraw.Draw(hole).polygon(eye_polygon(cx, cy, S * 0.66, h * 0.70), fill=255)
    alpha = Image.composite(Image.new("L", (S, S), 0), alpha, hole)
    alpha = Image.composite(Image.new("L", (S, S), 255), alpha, ring)
    pr = r * 0.42
    ImageDraw.Draw(alpha).ellipse([cx - pr, cy - pr, cx + pr, cy + pr], fill=255)
    out = Image.new("RGBA", (S, S), (0, 0, 0, 255)); out.putalpha(alpha)
    return out.resize((px, px), Image.LANCZOS)

def main():
    os.makedirs(EXT, exist_ok=True); os.makedirs(APPICON, exist_ok=True)
    for px in (48, 96, 128, 256, 512):
        colour_icon(px).save(os.path.join(EXT, f"icon-{px}.png"))
    for px in (16, 19, 32, 38):
        toolbar_icon(px).save(os.path.join(EXT, f"toolbar-icon-{px}.png"))
    images = []
    for pt in (16, 32, 128, 256, 512):
        for scale in (1, 2):
            px = pt * scale
            name = f"icon_{pt}x{pt}{'@2x' if scale == 2 else ''}.png"
            colour_icon(px).save(os.path.join(APPICON, name))
            images.append({"idiom": "mac", "scale": f"{scale}x", "size": f"{pt}x{pt}", "filename": name})
    with open(os.path.join(APPICON, "Contents.json"), "w") as f:
        json.dump({"images": images, "info": {"author": "xcode", "version": 1}}, f, indent=2)
    with open(os.path.join(ROOT, "App", "Assets.xcassets", "Contents.json"), "w") as f:
        json.dump({"info": {"author": "xcode", "version": 1}}, f, indent=2)
    acc = os.path.join(ROOT, "App", "Assets.xcassets", "AccentColor.colorset"); os.makedirs(acc, exist_ok=True)
    with open(os.path.join(acc, "Contents.json"), "w") as f:
        json.dump({"colors": [{"idiom": "universal", "color": {"color-space": "srgb", "components": {"red": "0.039", "green": "0.518", "blue": "1.000", "alpha": "1.000"}}}], "info": {"author": "xcode", "version": 1}}, f, indent=2)
    print("icons written")

if __name__ == "__main__":
    main()
