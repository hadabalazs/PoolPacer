# Changelog

## 1.1.3 — public release

Everything below landed across three betas (1.1.1, 1.1.2, 1.1.3) after the
1.1.0 beta. This is the first public build carrying any of it.

### Fixed

- **The gauge and the pace number could contradict each other.** The arc's
  highlighted zone was driven by `Activity.Info.currentSpeed` for a live
  mid-length reading, while the number showed the last completed length. The
  two described different things: the number could read 2:22 against a 2:00
  target — slow, red — while the arc lit orange for "fast". Both now read the
  last completed length, so they cannot disagree. Live mid-length feedback is
  gone with it; `currentSpeed` was never confirmed to report anything
  meaningful during a pool swim.

- **The distance readout did not match the lengths swum.** The footer was
  assigned from raw `elapsedDistance` before the dry-land test harness could
  substitute pool-shaped distance, so the footer and the gauge ran off two
  different streams. Both now read the same one.

- **The unit letter sat below the digits instead of beside them.** Bottom-
  aligning the two text boxes does not align the glyphs: a number face
  reserves far more descender space than a small text face, so the boxes
  matched while the letter visibly dropped. Now aligned on the baseline via
  `Graphics.getFontAscent`, with a proportional fallback.

- **Long distances ran off the screen.** The font ladder returned its last
  candidate whether or not it fitted. It now steps
  `NUMBER_MEDIUM → NUMBER_MILD → LARGE → MEDIUM → SMALL → TINY`, picking the
  first that fits and falling back to the smallest.

- **Width was measured against the screen diameter.** The footer sits low on a
  round display where the available chord is much narrower than the middle —
  roughly 100px of phantom width on a 43mm. Width is now measured as the
  actual chord at the text's own bottom edge.

### Changed

- **"Both" footer mode stacks time above distance.** Two values on one line
  forced a text font small enough to be useless through goggles. Stacked,
  each line keeps a number face. The face is chosen so both lines fit
  vertically and each fits the chord width at its own height.

- **Buzz pulse gap can now be set up to 1000ms** (was 500ms). This is the
  silent interval between consecutive pulses in a 2- or 3-buzz alert; pulses
  themselves remain 200ms, so a 3-buzz alert at the maximum runs 2.6s.

### Removed

- `lengthCount`, orphaned when the footer moved to `elapsedDistance`.
- The live-speed path (`updateLiveSpeed`, `liveDelta`, `hasLiveSpeed`).
- `fitFont` / `footerFont`, superseded by the number-face ladder.

## 1.1.0 — beta

- Target pace entered as a free time over a free distance (20:00 for 1000m,
  10:00 for 1000y, 1:45 for 100m) instead of a fixed list of per-100 paces.
  Collapsed internally into a single per-100 figure.
- Target caption moved up into the crescent and lost its "TGT" prefix — it
  now reads just `2:00/100m`.
- Footer distance and time drawn in a number face rather than a text font.

## 1.0.6 — first public build

- Expanded from 2 products to 87 (143 device binaries).
- Length distance counted separately from pace statistics, so a length with
  an unusable split no longer vanished from the total.
- Footer distance read from the watch's own `elapsedDistance`.
- Rest detection removed: pausing the timer stops the clock, an unpaused
  break counts against the split.
