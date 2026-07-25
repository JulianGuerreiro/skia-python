# gd-renderer skparagraph line-height patch

`gd-renderer-skparagraph-lineheight.diff`

## What it does

Removes the integer rounding of each line's height in Skia's `skparagraph` module, at one site:

- `modules/skparagraph/src/Run.h` — `InternalLineMetrics::height()`

Upstream returns `::round((double)fDescent - fAscent + fLeading)`, snapping every line's
height to a whole pixel (a Flutter-ism; the Skia source comment itself says *"another of
those flutter changes. To be removed"*). With gd's text-style height override,
`fDescent - fAscent + fLeading == fontSize * lineSpacing` exactly, so `ParagraphLayout`'s
line pitch became `round(fontSize * lineSpacing)` while cr-renderer positions lines at the
exact fractional `line_index * fontSize * lineSpacing`. The per-line error `round(x) - x`
(≤ 0.5px) **accumulates** down a block, so long multi-line bodies drift and spill out the
box bottom.

The patch returns the raw fractional `(double)fDescent - fAscent + fLeading` (no round), so
the line pitch matches cr exactly. Verified: Rokkitt 13 × lineSpacing 1.5 pitch 20.0 → 19.5;
Montserrat 66.849 × 1.43 pitch 96.0 → 95.594; design `5f34de6fa637ee11e3307980` renders
line-for-line with cr (was ~12px of drift over ~24 lines).

This is a **global** text-metrics change (all paragraphs, not gated on a flag) and is the
correct match to cr / the browser preview. It is independent of and complementary to
`gd-renderer-skparagraph-hinting.diff` (that one is horizontal advances; this one is
vertical line pitch). Apply both.

## Reapply after a fresh skia checkout

```bash
cd skia-python/skia
git apply ../patch/gd-renderer-skparagraph-hinting.diff
git apply ../patch/gd-renderer-skparagraph-lineheight.diff
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
