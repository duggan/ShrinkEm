"""Generates Slimreel's artwork as SVG. `make icons` renders these into the files in
Resources/.

The icon is Snug: a little video clip with sprocket notches, dot eyes, cheeks and a
closed, contented smile, sitting in front of the dotted ghost of the size it used to be,
on flat mint. A big video, made small, and fine about it. No text.

    python3 make_icons.py          # writes AppIcon.svg and DMGBackground.svg here
    python3 make_icons.py site     # the website's sticker icon, on stdout
    python3 make_icons.py touch    # the square, opaque apple-touch-icon, on stdout
    python3 make_icons.py snug   # Snug alone, transparent, on stdout

The website's copies in docs/assets/ are made from those:

    cp Resources/art/AppIcon.svg docs/assets/icon.svg
    python3 Resources/art/make_icons.py site > site.svg
    inkscape site.svg -o docs/assets/icon-512.png -w 512 -h 512
    inkscape site.svg -o docs/assets/favicon.png -w 64 -h 64
    python3 Resources/art/make_icons.py touch > touch.svg
    inkscape touch.svg -o docs/assets/apple-touch-icon.png -w 180 -h 180 -b "#7EE0C3" -y 1

make_banner.py draws the README and social-card banner with the same character.
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))

INK = "#1F2329"
PAPER = "#F3F1EC"
MINT = "#7EE0C3"
MINT_LIGHT = "#B8F0DF"
CORAL = "#FF6B4A"
CHEEK = "#FF9D8A"
SUN = "#FFD84A"

# Snug's body, around its own centre.
SNUG_W, SNUG_H, SNUG_R = 420, 316, 80


def snug(cx=0, cy=0, scale=1.0, tilt=5):
    """Snug, drawn around its own centre and then placed at (cx, cy): a 4:3 rounded
    clip, 420 x 316 at scale 1, with a coral copy peeking out behind it like a sticker's
    shadow, sprocket notches along the top and bottom, dot eyes, cheeks and a closed
    smile. It looks straight at the viewer. Everything is outlined in thick ink."""
    w, h, r = SNUG_W, SNUG_H, SNUG_R
    body = f'x="{-w / 2:g}" y="{-h / 2:g}" width="{w}" height="{h}" rx="{r}"'

    # Four notches along the top and four along the bottom, evenly spaced.
    nw, nh, inset, span = 36, 24, 30, 288
    step = (span - nw) / 3
    notches = "".join(
        f'<rect x="{-span / 2 + i * step:g}" y="{y:g}" width="{nw}" height="{nh}" rx="9"/>'
        for y in (-h / 2 + inset, h / 2 - inset - nh) for i in range(4))

    def eye(x):
        return (f'<ellipse cx="{x}" cy="-12" rx="25" ry="35" fill="{INK}"/>'
                f'<circle cx="{x - 7}" cy="-25" r="9.5" fill="#FFF"/>')

    def cheek(x):
        return f'<ellipse cx="{x}" cy="40" rx="31" ry="19" fill="{CHEEK}"/>'

    return f'''<g transform="translate({cx:g} {cy:g}) scale({scale:g}) rotate({tilt:g})">
      <rect {body} transform="translate(30 32)" fill="{CORAL}" stroke="{INK}" stroke-width="20" stroke-linejoin="round"/>
      <rect {body} fill="#FFF" stroke="{INK}" stroke-width="20" stroke-linejoin="round"/>
      <g fill="{INK}">{notches}</g>
      {cheek(-112)}{cheek(112)}
      {eye(-62)}{eye(62)}
      <path d="M-34,36 Q0,68 34,36" fill="none" stroke="{INK}" stroke-width="16" stroke-linecap="round"/>
    </g>'''


def ghost_frame(dotted=True):
    """The size the video used to be, in the icon's 1024 square: a pale 4:3 frame with
    a dotted outline and a play triangle, tilted the other way from Snug."""
    dots = (f'<rect x="188" y="196" width="648" height="486" rx="92" fill="none" stroke="{INK}" '
            f'stroke-opacity="0.5" stroke-width="16" stroke-linecap="round" stroke-dasharray="1 41.2"/>'
            if dotted else "")
    return f'''<g transform="rotate(-4 512 439)">
      <rect x="188" y="196" width="648" height="486" rx="92" fill="#FFF" fill-opacity="0.4"/>
      {dots}
      <path d="M640,306 L640,426 L742,366 Z" fill="#FFF" stroke="#FFF" stroke-width="26" stroke-linejoin="round" opacity="0.8"/>
    </g>'''


def app_icon(look="app"):
    """Snug in front of its ghost frame, on mint.

    `look` is "app" (the macOS icon: a squircle with a soft drop shadow), "site" (the
    website's sticker: an ink outline and a hard offset shadow, cropped close) or "touch"
    (mint filling the whole square, opaque, for the apple-touch-icon)."""
    box, radius, shadow, outline = "0 0 1024 1024", 185, "", ""
    if look == "app":
        shadow = '<rect x="100" y="112" width="824" height="824" rx="185" fill="#000" fill-opacity="0.18"/>'
    elif look == "site":
        box = "82 82 864 864"
        shadow = f'<rect x="112" y="114" width="824" height="824" rx="185" fill="{INK}"/>'
        outline = f'<rect x="100" y="100" width="824" height="824" rx="185" fill="none" stroke="{INK}" stroke-width="20"/>'
    else:
        box, radius = "100 100 824 824", 0
    return f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="{box}" width="1024" height="1024">
  <defs>
    <clipPath id="frame"><rect x="100" y="100" width="824" height="824" rx="{radius}"/></clipPath>
  </defs>
  {shadow}
  <g clip-path="url(#frame)">
    <rect x="100" y="100" width="824" height="824" fill="{MINT}"/>
    {ghost_frame()}
    {snug(452, 628, 1.06)}
  </g>
  {outline}
</svg>
'''


def snug_alone():
    """Snug on a transparent background, cropped close, for the website and the app."""
    return f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="-250 -200 520 420" width="520" height="420">
  {snug()}
</svg>
'''


def dmg_background():
    """660x420 window, with an arrow from the app (175, 215) to Applications (485, 215)."""
    return f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 660 420" width="660" height="420">
  <rect width="660" height="420" fill="{PAPER}"/>
  <g fill="none" stroke="{INK}" stroke-opacity="0.55" stroke-width="6" stroke-linecap="round" stroke-linejoin="round">
    <path d="M268,215 L392,215"/>
    <path d="M372,197 L392,215 L372,233"/>
  </g>
  <text x="330" y="335" text-anchor="middle" font-family="-apple-system, Helvetica Neue, Helvetica, Arial, sans-serif"
        font-size="17" fill="{INK}" fill-opacity="0.7">Drag Slimreel to your Applications folder</text>
</svg>
'''


if __name__ == "__main__":
    if len(sys.argv) > 1:
        sys.stdout.write(snug_alone() if sys.argv[1] == "snug" else app_icon(sys.argv[1]))
        sys.exit()
    for name, svg in (("AppIcon.svg", app_icon()), ("DMGBackground.svg", dmg_background())):
        with open(os.path.join(HERE, name), "w") as f:
            f.write(svg)
        print("wrote", name)
