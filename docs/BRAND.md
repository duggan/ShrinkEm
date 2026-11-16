# Brand spec

Naming and identity for Slimreel (working title "Big Videos"). It's the third app in a
family with [Subya](https://github.com/duggan/Subya) and
[NanoNeo](https://github.com/duggan/NanoNeo), and should look like their sibling.

Status: the name is chosen (Slimreel), and the artwork and website in section 4 are
built. The numbers there describe what `make_icons.py` draws. The name checks in
section 1 were done on 2026-11-16 and are quick searches, not trademark clearance.

## 1. Name

### What the family does

| | Subya | NanoNeo |
| --- | --- | --- |
| Name | Coined, 5 letters, a spoken phrase ("sub ya") | Coined, 7 letters, alliterative, names the device |
| Tagline | "Big, loud, readable captions for your memes and reaction clips. Made on your Mac." | "Plug in your AlphaSmart Neo, and your drafts appear on your Mac." |
| Tone | Loud and playful | Quiet and plain |

Both names are one word, capitalised once or twice, easy to say, and say what the app is
for once you've heard the tagline. Both taglines are a plain sentence about what
happens to the user's stuff, ending on "your Mac".

### Candidates

| Name | Rationale | Problem |
| --- | --- | --- |
| **Slimreel** | Slims down your reel of videos. Self-explanatory, covers shrink and clear-out. | "Reel" also means Instagram Reels. |
| **Sizeya** | "Size ya": it sizes up your videos. A direct pair with Subya ("sub ya"). | Needs the pronunciation hint, and copies Subya's pattern exactly. |
| **Weereel** | "Wee reel": big videos made wee. Rhymes, the way NanoNeo alliterates. | Hard to read in lowercase (`weereel`); "wee" has a second meaning. |
| **Slimfilm** | Near-rhyme, says the same as Slimreel. | A bit of a tongue-twister; "film" is less natural than "video". |
| **Stowya** | "Stow ya": stows your originals on a drive. | Only describes Move to Folder. |
| **Gigaway** | Gigabytes, away. | Sounds like "giveaway". Two small `gigaway` repos exist. |
| **Bigun** | "Big 'un": it finds the big 'uns. | Reads as "bi-gun". |
| **Gigback** | Get your gigabytes back. The best promise of the lot. | Taken, see below. |
| **Lilvid** | The opposite of Big Videos. | Taken, see below. |
| **Reelroom** | Real room for your reel. | Taken by several watch-party projects. |

### Shortlist

1. **Slimreel** (recommended). The only candidate that tells a stranger what the app
   does without the tagline. It's two syllables, has no Apple terms in it, and works as
   `Slimreel.app`, `duggan/Slimreel`, bundle ID `ie.duggan.Slimreel` and a `slimreel`
   command later. It sits with the siblings without copying either one.
2. **Sizeya**. The most "family" option, and the truest to the app's main trick (sorting
   by size). Pick it if a Subya/Sizeya pairing is wanted on purpose. Always introduce it
   as `Sizeya ("size ya")`, as Subya does.
3. **Weereel**. The most playful. Pick it only if the wordmark is always written
   `WeeReel`, which breaks the family's one-capital habit.

### Conflict checks

`gh search repos <name> --limit 5` and one web search per shortlisted name.

| Name | GitHub | Web |
| --- | --- | --- |
| Slimreel | No repos. | No app or brand of that name found. Nearest neighbours are TrimReel (a social video trimmer) and SwiftReel (a Shopify app), both different names. |
| Sizeya | No repos (one unrelated `sizeyami`). | Nothing called Sizeya. Sizey (a clothing-fit company) and Sizy (a clothing-sizes app) are close in spelling, in an unrelated field. |
| Weereel | No repos. | Nothing found. |

Rejected for conflicts:

- **Gigback**: `evojewel/gigback` is a storage cleaner for Macs with the line "Get your
  gigabytes back", and there are support and legal repos for an app called GigBack.
  Same platform, same promise. Don't use it.
- **Lilvid**: `GetTheNya/LilVid` is a video compressor.
- **Reelroom**: several watch-party projects.

Not checked: the Mac App Store, domain names, or trademark registers. Do those for the
chosen name before release.

The rest of this spec uses **Slimreel**. Sections 2 to 6 work for any of the three with
the name swapped.

## 2. Tagline and GitHub metadata

**Tagline** (README, website, and the repo description, as NanoNeo does):

> Find the big videos filling your iCloud, and get the space back without losing a thing.

Short form, for the banner and the website's `<title>`: **Your biggest videos, first.**

**Repo description:** the tagline, unchanged.

**Topics:** `macos`, `swiftui`, `photos-library`, `icloud-storage`

"iCloud" and "Photos" appear in sentences that describe what the app works with, never
in the name, icon or wordmark. The README carries a line saying the app isn't
affiliated with Apple (section 5).

## 3. Voice and tone

The person reading is slightly worried: their storage is full and these are family
videos. So the voice is calm and exact, with a little warmth. It sits between Subya
(loud) and NanoNeo (plain), closer to NanoNeo.

Do:

- Say what happens to the video, in order: "Copied to *Family NAS*, checked, then
  removed from Photos."
- Give real numbers: sizes, counts, before and after.
- Use the four verbs exactly as the buttons do: **Keep**, **Delete**, **Move to
  Folder**, **Shrink**.
- Use "you" and "your videos". Short sentences.
- Be playful only when nothing is at risk: empty states, the success summary, the
  website.

Don't:

- Don't joke in or near a delete confirmation, an error, or a progress message.
- Don't scold ("your library is bloated") or alarm ("running out of space!").
- Don't promise what Apple controls. Say "frees space once Photos empties Recently
  Deleted", not "instantly frees your iCloud".
- Don't use "clean", "junk", "clutter" or "optimize". These are people's memories, and
  those words belong to cleaner apps.
- Don't use exclamation marks in the app. One on the website is plenty.

### Sample microcopy

| Where | Copy |
| --- | --- |
| First run, before Photos access | **Let's see what's taking up the room.** Slimreel needs to read your Photos library to list your videos by size. Nothing leaves your Mac. |
| Loading | Sizing up 1,284 videos… |
| Empty: no videos at all | **No videos here.** This Photos library doesn't have any videos in it. |
| Empty: filters hide everything | **Nothing over 500 MB.** Lower the minimum size to see more. |
| Empty: everything reviewed | **That's the lot.** You've been through every video. Turn off Hide Kept to see them again. |
| Row detail | 4K · 120 fps · 0:42 · 103 MB per minute |
| Shrink preview | 72 MB → about 9 MB. 4K 120 fps becomes 1080p 60 fps. Date, location and albums stay. |
| Success: shrink | **Freed 63 MB.** 72 MB → 8.9 MB. The original is in *Videos Archive*. |
| Success: session summary | **Freed 1.2 GB.** 14 shrunk, 6 moved, 3 deleted. Nothing lost. |
| Success: moved | **Moved 6 videos (840 MB) to *Family NAS*.** Each copy was checked against the original. |
| Kept | Kept. It won't show up again unless you ask. |
| Safety line (footer, website, README) | Nothing is removed until its copy has been checked byte for byte, and Photos asks you before anything is deleted. |
| Recently Deleted note | Deleted videos stay in Recently Deleted for 30 days. The space comes back when Photos empties it, or when you do. |
| Error: copy didn't verify | **Not moved.** The copy on *Family NAS* didn't match the original, so the video is still in Photos. Check the drive and try again. |
| Error: folder unavailable | **Can't reach *Family NAS*.** Nothing was changed. |

## 4. Visual identity

### Where it sits in the family

Subya is a sticker: thick ink outlines, a hard offset shadow, a face, a yellow sunburst.
NanoNeo is a flat drawing of one object on cream, with no outlines and no face.

Slimreel takes Subya's construction (ink outline, offset sticker shadow, a small face)
and NanoNeo's restraint (one flat background colour, one idea, no text in the icon).
The shared parts are the 824 pt squircle, the ink colour, the paper DMG, and artwork
generated by `Resources/art/make_icons.py`.

### Mascot

Yes, a small one: **Snug**, a little video clip. Snug is a rounded rectangle with
film sprocket notches, two dot eyes, cheeks and a closed, contented smile. It's what a
big video looks like after Slimreel: small and fine about it.

The name: snug means small, fitting neatly and comfortable, which is the whole
character. Candidates were Snug, Skosh (a small amount; needs a pronunciation hint, and
there's a dating app of that name), Morsel (reads as food) and Titch (the Pat Hutchins
picture-book character). An earlier name was dropped because it belongs to a
character in DreamWorks' *Trolls*. Checked on 2026-11-16 with a web search and
`gh search repos snug`: no well-known mascot or cartoon character called Snug. The
nearest are Snug the joiner in *A Midsummer Night's Dream*, the British children's series
*Snug and Cozi*, "Snugs" in Sesame Workshop's *Esme & Roy*, the Snuggle fabric-softener
bear (a different name) and Snug, a UK sofa company. None is a video or software
mascot. Not a trademark search.

- Original character. Not a film reel, not a play-button logo, not a cloud, not an
  emoji, and not Bubble Buddy recoloured.
- Expression: content and relieved. Never smug, never winking, never sweating or
  crying. Subya's first mascot gave side-eye and read as smarmy; Snug only ever looks
  at the viewer, with a plain smile.
- Different from Bubble Buddy by design: closed smile (not a wide-open mouth), a 4:3
  body with sprocket notches (not a speech bubble with a tail), coral shadow (not pink).
- Where it appears: the app icon, the banner, the website hero, the About window and
  the "That's the lot" empty state.
- Where it never appears: delete confirmations, errors, progress, the DMG background.

### Colour palette

| Name | Hex | Role |
| --- | --- | --- |
| Ink | `#1F2329` | Outlines, text. Same as Subya. |
| Paper | `#F3F1EC` | DMG background, website page background. Same as Subya's DMG. |
| Mint | `#7EE0C3` | Brand colour: the icon background, freed space, the Shrink action. |
| Mint light | `#B8F0DF` | Tints, banner bars, hover states. |
| Mint deep | `#1FA588` | Mint on white where it needs contrast: links, chart bars, the "Freed" figure. |
| Coral | `#FF6B4A` | "Big": the sticker shadow, the largest bars in the chart, the full end of a storage bar. |
| Cheek | `#FF9D8A` | Snug's cheeks only. |
| Sun | `#FFD84A` | Kept. The download button. Same yellow as Subya's sunburst. |
| Sky | `#7CCBFF` | Moved to Folder. Same blue as Subya's website. |
| White | `#FFFFFF` | Snug's body, cards. |

The four actions have fixed colours on the website and in marketing art: Keep is Sun,
Move is Sky, Shrink is Mint, and Delete is the system red (never a brand colour, so it
always looks like a system warning). In the app itself, use system colours and the
accent colour; set the app's accent to Mint deep.

Mint is in Subya's website palette (`--mint: #6EE7C8`) as a minor colour, so the three
icons (yellow, cream, mint) look like a set in the Dock.

### Typography

- **Wordmark and headlines:** SF Pro Rounded, Black or Heavy. Wordmark is `Slimreel`,
  one capital, tracking -1%. On the web: `ui-rounded, "SF Pro Rounded", "Nunito",
  system-ui, sans-serif`, weight 800 to 900. In SVG art, convert the wordmark to paths
  so Inkscape renders it the same everywhere.
- **Numbers:** the same face with tabular figures. Sizes are the hero of the brand, so
  "1.2 GB" is set large and heavy wherever it appears.
- **Body:** the system font (`-apple-system, "Helvetica Neue", Helvetica, Arial,
  sans-serif`), as on the siblings' DMGs.
- **In the app:** system fonts only; `.rounded` design for the size column and the
  freed-space summary.
- Not Impact. That's Subya's caption face.

### App icon

Drawn in a 1024 square, like the siblings. Constants at the top of `make_icons.py`:
`INK`, `PAPER`, `MINT`, `MINT_LIGHT`, `CORAL`, `CHEEK`, `SUN`.

Back to front:

1. **Drop shadow:** `<rect x="100" y="112" width="824" height="824" rx="185" fill="#000"
   fill-opacity="0.18"/>`. Identical to both siblings.
2. **Squircle:** `<rect x="100" y="100" width="824" height="824" rx="185"/>` filled
   `MINT`, flat. Everything else is clipped to it.
3. **Ghost frame** (the size the video used to be), from `ghost_frame()`: a rounded
   rectangle at `x=188 y=196 width=648 height=486 rx=92` (4:3), filled white at 40%
   opacity, with a dotted outline: stroke `INK` at 50% opacity, width 16,
   `stroke-linecap="round"`, `stroke-dasharray="1 41.2"` (50 dots, which close up evenly
   around the perimeter). Rotated -4° about its centre, like Bubble Buddy's tilt.
4. **Play triangle** in the ghost frame's upper right, so the frame reads as a video:
   points `(640,306) (640,426) (742,366)`, white fill with a 26 white round-joined
   stroke to soften the corners, the whole shape at 80% opacity. Inside the same -4°
   group.
5. **Snug**, from `snug(452, 628, 1.06)`: centred at (452, 628), in the lower left,
   overlapping the ghost frame's corner, rotated +5° (leaning the other way from the
   ghost). Around its own centre, at scale 1:
   - Body: a rounded rectangle 420 × 316, `rx=80`, white, stroke `INK` 20, round joins.
   - Sticker shadow: the same shape translated `(30, 32)`, filled `CORAL`, same stroke.
     (Wider than Bubble Buddy's `(22, 24)` so the coral still shows at 32 px.)
   - Sprocket notches: four along the top edge and four along the bottom, each a
     `36 × 24` rectangle with `rx=9` filled `INK`, inset 30 from the edge, evenly spaced
     across the middle 288.
   - Eyes: two `INK` ellipses `rx=25 ry=35` at `(±62, -12)`, each with one white glint
     `r=9.5` up and to the left.
   - Cheeks: two `CHEEK` ellipses `rx=31 ry=19` at `(±112, 40)`.
   - Smile: `M-34,36 Q0,68 34,36`, no fill, stroke `INK` 16, round caps. Closed.
6. No text, no badge, no arrow.

At 32 px and below the notches and face blur away, leaving a white tile with a coral
shadow on mint in front of a paler tile. That still reads as "big one, small one". The
16 px render was checked: the dotted outline all but disappears on its own, so all
sizes come from the one SVG and there's no separate small-size drawing.

`app_icon(look)` takes the same three looks as Subya's script:

- `app`: as above.
- `site`: cropped to `viewBox="82 82 864 864"`, the soft shadow replaced by a hard `INK`
  squircle offset `(12, 14)`, plus a 20 `INK` outline on the squircle. For
  `docs/assets/icon-512.png` and `favicon.png`.
- `touch`: `viewBox="100 100 824 824"`, square corners, opaque mint. For
  `apple-touch-icon.png`.

`snug(cx, cy, scale, tilt)` draws the character around its own centre, so the banner
and the website reuse it at any size. `python3 make_icons.py snug` writes Snug alone
on a transparent background, for the About window and the empty state.

### DMG background

Same as both siblings, with only the name changed: 660 × 420, `PAPER` fill, the grey
arrow from the app at (175, 215) to Applications at (485, 215) (`M268,215 L392,215` and
`M372,197 L392,215 L372,233`, stroke `INK` at 55%, width 6, round caps), and "Drag
Slimreel to your Applications folder" centred at y 335 in the system font, 17 px, `INK`
at 70%. No character.

### README banner and social card

`Resources/art/make_banner.py`, importing `snug()` and `ghost_frame()` from
`make_icons.py`, rendered to `docs/assets/banner.png` at 1280 × 640, opaque. Same job as
Subya's banner, quieter.

- Background: `MINT`. Along the bottom, a row of 24 rounded bars in `MINT_LIGHT`, the
  app's size-by-month chart, with one pile-up just right of Snug and low bars either
  side. The three tallest are `CORAL`. This replaces Subya's sunburst.
- Left third: the ghost frame and Snug, as in the icon, about 420 px tall.
- Right two thirds: the wordmark `Slimreel` in SF Pro Rounded Black, `INK`, 160 px,
  tracking -1%. No outline and no tilt; that's Subya's look.
- Under it, a `Sun` pill with an `INK` outline and a hard `INK` shadow (the one sticker
  detail carried over), reading "Your biggest videos, first." in SF Pro Rounded Heavy.
- Under that, small, `INK`: "Everything stays on your Mac. Free & open source." This
  mirrors Subya's "Burned in, on your Mac. Free & open source."

The three lines of lettering are stored as paths in `Resources/art/lettering.py`, so
the render doesn't depend on which fonts Inkscape finds. `make_lettering.swift` writes
that file from the system's SF Pro Rounded; run it only when the words change.

### Website hero

`docs/index.html`, GitHub Pages, one page, same skeleton as Subya's site (hero, demo,
how it works, features, privacy, FAQ, final call) with this palette and SF Rounded in
place of Impact.

- Left: headline "Your biggest videos, first." Lede: the tagline plus one sentence on
  the four actions. Buttons: "Download for Mac" (Sun, `INK` border, hard `INK` shadow,
  the same button shape as Subya's) and "Source on GitHub" (ghost). Chips: "Requires
  macOS 14", "Free & open source", "Nothing leaves your Mac".
- Right: an illustrated app window, not a screenshot. Five video rows, biggest first
  (72, 58, 42, 31 and 24 MB), each with a size in heavy rounded figures. On a loop, the
  top row's 72 MB counts down to 8.9 MB and its bar shrinks, and a "Freed 63 MB" chip
  pops in; then the second row is moved, the third shrinks from 42 MB to 7.8 MB and
  the fourth is kept, so the bar above the list eases from all coral to mostly mint
  and the chip ends on "Freed 155 MB". Delete isn't in the loop. Snug sits on the
  corner of the window. The page is written in its end state, which is what
  `prefers-reduced-motion` and no-JavaScript visitors see.
- Behind the hero, the banner's row of month bars. The wordmark in the header is live
  text in the display face, not an image.
- Section headings, in voice: "Sorted the way Photos won't." / "Four things you can do
  with a big video." / "Nothing lost." / "Everything stays on your Mac." / "Questions."
- Final call: "Go on. Make some room."

## 5. README outline

Follows Subya's README (the fuller of the two), with NanoNeo's badges and credits.

1. Centred banner: `docs/assets/banner.png`, width 760.
2. Centred bold tagline.
3. Centred links: **⬇ Download Slimreel for Mac** · Website · All releases.
4. Centred line: "Free and open source · macOS NN or later".
5. Badges (CI, latest release, GPL-3.0), as NanoNeo.
6. `---`
7. Two short paragraphs. First: the problem (iCloud is full, it's mostly videos, Photos
   can't sort by size). Second: what you do about it (see them biggest first, then keep,
   delete, move or shrink each one).
8. Demo GIF, width 800, with full alt text.
9. `## What it does`: bold-lead bullets.
   - **Biggest first.** The list and its columns.
   - **See when it piled up.** The size-by-month chart; drag to pick a date range.
   - **Keep.** Mark it reviewed and hide it.
   - **Move to Folder.** Full original to a folder or NAS, checked byte for byte, then
     removed from Photos.
   - **Shrink.** Re-encode and replace, keeping date, location and albums. Give the
     real example: a 72 MB 4K 120 fps clip became 8.9 MB.
   - **Best of both.** Archive the original, keep a small copy in Photos.
   - **Delete.** To Recently Deleted; Photos asks first.
10. `## Install`: DMG link, signed and notarized, macOS version, universal.
11. `## How to use it`: numbered steps (open, allow Photos access, sort and filter, pick
    an action). Subsections `### Shrink`, `### Move to Folder`, `### The timeline`,
    `### Settings` as needed.
12. `## Is it safe?`: the safety line, then the specifics: verified copies, Photos'
    own confirmation, Recently Deleted for 30 days, what Shrink keeps and what it
    doesn't. This section is new to the family and is the most important one here.
13. `## Privacy`: everything stays on the Mac, no network requests, no account, the one
    permission it asks for (Photos) and why.
14. `## FAQ`: when does iCloud space come back; does Shrink lose quality; what about
    Live Photos and slo-mo; shared libraries; why not just use Photos.
15. `## Development`: requirements and the `make` targets.
16. `## Credits`: "iCloud, Photos and Mac are trademarks of Apple Inc. Slimreel is an
    independent project and isn't affiliated with Apple." (NanoNeo's wording.)
17. `## Licence`: "GPL-3.0. See [LICENSE](LICENSE)."

## 6. How it relates to Subya and NanoNeo

| | Subya | NanoNeo | Slimreel |
| --- | --- | --- | --- |
| Job | Make a clip to share | Get drafts off a device | Get storage back |
| User's mood | Having fun | Wants it to just work | A bit worried |
| Voice | Loud, jokey | Plain | Calm, exact, lightly warm |
| Icon | Mascot on a sunburst, with text | One object, flat, no face | Small mascot, flat background, no text |
| Background | Yellow `#FFB400` | Cream `#F4EDD8` | Mint `#7EE0C3` |
| Display type | Impact | System | SF Rounded |
| Mascot | Bubble Buddy, everywhere | None | Snug, sparingly |

Shared across all three, and kept here:

- A one-word coined name, and a one-sentence tagline about the user's own stuff.
- "Everything stays on your Mac", no account, as few permissions as possible.
- Checked before anything is removed. NanoNeo reads a file back before clearing a
  slot; Slimreel compares a copy byte for byte before removing a video. Say it the same
  plain way.
- The icon geometry (824 squircle, `rx` 185, the 0.18 shadow), ink `#1F2329`, the paper
  DMG with an arrow and one line of text.
- Artwork drawn as SVG by `Resources/art/make_icons.py`, rendered by `make icons`, and
  committed.
- GPL-3.0, a signed and notarized DMG, GitHub Releases, a GitHub Pages site in `docs/`.

Deliberately different:

- No sunburst, no Impact, no pink, no text in the icon: those are Subya's.
- Not as bare as NanoNeo: it has a character, because the subject is personal and a
  friendly face helps. The character stays out of anything involving deletion.
