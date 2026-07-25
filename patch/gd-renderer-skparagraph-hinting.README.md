# gd-renderer skparagraph hinting patch

`gd-renderer-skparagraph-hinting.diff`

## What it does

Changes the shaping/painting `SkFont` hinting in Skia's `skparagraph` module from
`kSlight` to `kNormal` at three sites:

- `modules/skparagraph/src/OneLineShaper.cpp` — the shaping font (glyph **advances** used for line wrapping)
- `modules/skparagraph/src/TextLine.cpp` — the painting font (glyph **positions**)
- `modules/skparagraph/src/TextStyle.cpp` — `getFontMetrics` (vertical metrics)

`kSlight` leaves glyph advances **unrounded** (fractional), which makes `ParagraphLayout`
lay text out ~5% wider than cr-renderer's `SkFont`/`TextBlob` path (which uses `kNormal`,
whole-pixel advances). Because the Crello dataset's text boxes were sized to the hinted
widths, the fractional advances overflowed tight boxes (e.g. small numeric columns) and
triggered spurious wraps/overflows. `kNormal` rounds advances to whole pixels so
`ParagraphLayout` widths match cr and the box sizing. Verified: Raleway `"$20.00"` @12px
goes 37.98 → 36.0 (== cr).

> **Broken-font note.** `kNormal` runs each font's own TrueType hinting bytecode, and three
> Crello fonts — **Sunday, Kumar One, Kumar One Outline** — ship *buggy* bytecode that zeroes
> every glyph advance under `kNormal`, so their text collapses to x=0 and renders invisibly.
> This is deliberately **not** fixed here (a global `setForceAutoHinting` fixes them but
> widens ~260 normal fonts a few px off cr — e.g. Raleway `"$20.00"` 36→41 — re-introducing
> overflow). Instead gd de-hints just those broken fonts at load (`BaseRenderer._dehint_if_broken`
> in `gd_renderer/renderer.py`), so `kNormal` stays exact for every other font. Keep this patch
> to `kNormal` only.

## Reapply after a fresh skia checkout

```bash
cd skia-python/skia
git apply ../patch/gd-renderer-skparagraph-hinting.diff
# rebuild just the module:
../depot_tools/ninja -C out/Release libskparagraph.a
# relink the extension. build_ext will NOT notice the static lib changed, so remove
# the stale .so first to force a relink:
cd .. && rm -f build/lib.*/skia.*.so
CC=g++ CXX=g++ python setup.py build_ext
cp build/lib.*/skia.*.so <your-venv>/lib/python3.12/site-packages/
```

Note: this environment builds with system `g++` (`cc`/`c++`); `setup.py`'s default
`clang++` is not installed here, hence the `CC=g++ CXX=g++` override.
