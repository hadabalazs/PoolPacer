# PoolPacer — Pool Test Feedback Log

Running notes from real pool testing, to work through with Claude.

## Pool test — 2026-09-10

- Single ("on-pace") buzz should be longer and more distinct from the slow/fast pattern.
- Add a setting for the interval (gap) between pulses in the 2-buzz and 3-buzz patterns — currently fixed.
- BUG: the pace gauge/needle wasn't visible while actually swimming — couldn't tell green vs red mid-swim. Needs investigation (possibly compute()/onUpdate() not rendering as expected under real timer/activity state, vs. simulator).
- The per-100m pace readout wasn't visible either during the swim.
- Note (unclear, needs follow-up): "where is the voice note?" — possibly referring to Garmin audio prompts / alerts feature, not yet clarified.

