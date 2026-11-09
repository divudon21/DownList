#!/usr/bin/env python3
"""Generate Android launcher resources from the checked-in app logo (requires Pillow)."""
from pathlib import Path
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
RES = ROOT / 'android/app/src/main/res'
source = Image.open(ROOT / 'assets/images/downlist_logo.png').convert('RGB')
if source.width != source.height:
    raise ValueError('The launcher source must be square.')

# Adaptive icons use a 108 dp canvas with a 72 dp safe region. Keep the symbol
# inset so that circular, squircle and other launcher masks do not crop it.
foreground = Image.new('RGBA', (source.width, source.height), (0, 0, 0, 0))
size = round(source.width * .80)
image = source.resize((size, size), Image.Resampling.LANCZOS).convert('RGBA')
pos = (source.width - size) // 2
foreground.alpha_composite(image, (pos, pos))

# The monochrome layer is derived from the green mark, excluding the near-black
# background and facial cut-outs, for Android's themed icons.
green = source.getchannel('G').point(lambda value: max(0, min(255, round((value - 60) * 255 / 70))))
mono_image = Image.new('RGBA', source.size, 'white')
mono_image.putalpha(green)
mono = Image.new('RGBA', source.size, (0, 0, 0, 0))
mono.alpha_composite(mono_image.resize((size, size), Image.Resampling.LANCZOS), (pos, pos))

for density, legacy, adaptive in [('mdpi', 48, 108), ('hdpi', 72, 162), ('xhdpi', 96, 216), ('xxhdpi', 144, 324), ('xxxhdpi', 192, 432)]:
    dest = RES / f'mipmap-{density}'
    dest.mkdir(parents=True, exist_ok=True)
    icon = source.resize((legacy, legacy), Image.Resampling.LANCZOS).convert('RGBA')
    icon.save(dest / 'ic_launcher.png', optimize=True)
    # Antialias the circular legacy icon edge on pre-adaptive launchers.
    mask = Image.new('L', (legacy * 4, legacy * 4), 0)
    ImageDraw.Draw(mask).ellipse((0, 0, legacy * 4 - 1, legacy * 4 - 1), fill=255)
    icon.putalpha(mask.resize((legacy, legacy), Image.Resampling.LANCZOS))
    icon.save(dest / 'ic_launcher_round.png', optimize=True)
    Image.new('RGB', (adaptive, adaptive), (0, 0, 0)).save(dest / 'ic_launcher_background.png', optimize=True)
    foreground.resize((adaptive, adaptive), Image.Resampling.LANCZOS).save(dest / 'ic_launcher_foreground.png', optimize=True)
    mono.resize((adaptive, adaptive), Image.Resampling.LANCZOS).save(dest / 'ic_launcher_monochrome.png', optimize=True)
