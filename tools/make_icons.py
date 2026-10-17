#!/usr/bin/env python
"""make_icons.py - app icons (Android launcher + adaptive, Windows .ico) from the game's own artwork.

  (cd port && flutter test test/icon_render_test.dart --dart-define=ICON=true)   renders build/icon/bar_8x.png (vector art at 8x)
  python tools/make_icons.py                                                     crops Miguel's face and writes every icon size

The picture is Miguel (the barman) in front of the bar, cropped square from the game's vector art.
"""
import os

from PIL import Image, ImageDraw, ImageEnhance, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, '..'))
SRC = os.path.join(ROOT, 'build', 'icon', 'bar_8x.png')
RES = os.path.join(ROOT, 'port', 'android', 'app', 'src', 'main', 'res')
ICO = os.path.join(ROOT, 'port', 'windows', 'runner', 'resources', 'app_icon.ico')
SCALE = 8
CROP = (440, 40, 600, 200)  # stage pixels: Miguel's face, square


def rounded(img, radius_frac=0.18):
    mask = Image.new('L', img.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0) + img.size, radius=int(img.width * radius_frac), fill=255)
    out = img.copy()
    out.putalpha(mask)
    return out


def main():
    src = Image.open(SRC).convert('RGBA')
    master = src.crop(tuple(v * SCALE for v in CROP)).resize((1024, 1024), Image.LANCZOS)
    os.makedirs(os.path.join(ROOT, 'docs'), exist_ok=True)
    master.save(os.path.join(ROOT, 'docs', 'icon.png'))

    # Android: legacy launcher icons (rounded square), adaptive icon (full-bleed foreground + solid background)
    for dpi, px in (('mdpi', 48), ('hdpi', 72), ('xhdpi', 96), ('xxhdpi', 144), ('xxxhdpi', 192)):
        d = os.path.join(RES, 'mipmap-' + dpi)
        os.makedirs(d, exist_ok=True)
        rounded(master.resize((px, px), Image.LANCZOS)).save(os.path.join(d, 'ic_launcher.png'))
    # adaptive icon: the launcher shows only the middle 72/108 of each layer through a circle / squircle / ..., so the face is
    # drawn at 80% on the foreground layer and the background layer is a blurred, darkened copy of the same picture
    backdrop = ImageEnhance.Brightness(master.filter(ImageFilter.GaussianBlur(40))).enhance(0.55)
    for dpi, px in (('mdpi', 108), ('hdpi', 162), ('xhdpi', 216), ('xxhdpi', 324), ('xxxhdpi', 432)):
        d = os.path.join(RES, 'mipmap-' + dpi)
        fg = Image.new('RGBA', (px, px), (0, 0, 0, 0))
        inner = int(px * 0.80)
        fg.alpha_composite(master.resize((inner, inner), Image.LANCZOS), ((px - inner) // 2, (px - inner) // 2))
        fg.save(os.path.join(d, 'ic_launcher_foreground.png'))
        backdrop.resize((px, px), Image.LANCZOS).convert('RGB').save(os.path.join(d, 'ic_launcher_background.png'))
    any_dir = os.path.join(RES, 'mipmap-anydpi-v26')
    os.makedirs(any_dir, exist_ok=True)
    adaptive = ('<?xml version="1.0" encoding="utf-8"?>\n'
                '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
                '    <background android:drawable="@mipmap/ic_launcher_background"/>\n'
                '    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>\n'
                '</adaptive-icon>\n')
    for name in ('ic_launcher.xml', 'ic_launcher_round.xml'):
        open(os.path.join(any_dir, name), 'w', encoding='utf-8', newline='\n').write(adaptive)
    colors = os.path.join(RES, 'values', 'colors.xml')
    if os.path.exists(colors):
        os.remove(colors)

    # Windows: multi-size .ico (the exe icon and the window icon)
    os.makedirs(os.path.dirname(ICO), exist_ok=True)
    master.save(ICO, format='ICO', sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])
    print('icons written: android mipmaps + adaptive, windows app_icon.ico, docs/icon.png')


if __name__ == '__main__':
    main()
