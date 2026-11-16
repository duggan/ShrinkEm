# Draws the README and social-card banner as SVG on stdout. Render with:
#   python3 Resources/art/make_banner.py > Resources/art/Banner.svg
#   inkscape Resources/art/Banner.svg -o docs/assets/banner.png -w 1280 -h 640 -b '#7EE0C3' -y 1
# (-b and -y keep the PNG opaque, so it looks the same on GitHub's light and dark themes.)
#
# Snug, the ghost frame and the colours come from make_icons.py, next to this file.
# The words are SF Pro Rounded, already turned into paths in lettering.py (see
# make_lettering.swift), so the render doesn't depend on which fonts Inkscape can find.
import math

from lettering import FOOTER, TAGLINE, WORDMARK
from make_icons import CORAL, INK, MINT, MINT_LIGHT, SUN, ghost_frame, snug


def words(lettering, cx, baseline, fill=INK):
    """Lettering from lettering.py, centred on cx with its baseline at the given y."""
    width, d = lettering
    return f'<path transform="translate({cx - width / 2:.1f} {baseline})" d="{d}" fill="{fill}"/>'


def chart(count=24, left=40, pitch=50, width=34, peak=9, tallest=150):
    """The app's size-by-month chart along the bottom edge: one big pile-up, in coral,
    falling away to the right."""
    bars = []
    for i in range(count):
        spread = 3.6 if i < peak else 3.0
        h = max(24, tallest * math.exp(-((i - peak) / spread) ** 2))
        fill = CORAL if abs(i - peak) <= 1 else MINT_LIGHT
        bars.append(f'<rect x="{left + i * pitch}" y="{640 - h:.0f}" width="{width}" height="{h + 20:.0f}" rx="12" fill="{fill}"/>')
    return "\n".join(bars)


PILL = TAGLINE[0] + 80   # the pill hugs the tagline, with 40 px either side


print(f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1280 640" width="1280" height="640">
<rect width="1280" height="640" fill="{MINT}"/>
{chart()}
<g transform="translate(-62 -52) scale(0.66)">
{ghost_frame()}
{snug(452, 628, 1.06)}
</g>
{words(WORDMARK, 884, 292)}
<rect x="{884 - PILL / 2 + 7:.0f}" y="345" width="{PILL:.0f}" height="84" rx="42" fill="{INK}"/>
<rect x="{884 - PILL / 2:.0f}" y="338" width="{PILL:.0f}" height="84" rx="42" fill="{SUN}" stroke="{INK}" stroke-width="6"/>
{words(TAGLINE, 884, 392)}
{words(FOOTER, 884, 482)}
</svg>''')
