# PoolPacer

A pool-swim data field for Garmin Connect IQ. PoolPacer tells you how the
length you just swam compares to your target pace — a colour-coded arc and a
distinct vibration pattern per zone — so you can hold a pace without stopping
to read numbers.

Built for 87 Connect IQ products (143 device binaries), including the whole
Descent, fenix, Forerunner and epix range.

## How it works

Garmin reports pool distance in wall-touch increments, so PoolPacer works per
length: every time you touch the wall it takes the split, converts it to a
per-100 pace, and compares that against your target.

Everything on screen describes that same completed length. The arc's
highlighted band and the big number are driven by one source and cannot
disagree with each other.

## Features

- **Free-form target pace** — enter a time over a distance: 20:00 for 1000m,
  1:45 for 100m, 10:00 for 1000y. The watch shows the per-100 pace it derives.
- **Three-band gauge** — red (slow), green (on pace), orange (fast). The band
  edges sit exactly at your tolerance and fast-threshold settings, the same
  two numbers that drive the buzzes, so what you see and what you feel always
  agree. Whichever band you are in renders thicker.
- **Configurable haptics** — independent buzz counts per zone (0 disables that
  zone), adjustable pulse gap and vibration intensity. The on-pace buzz is a
  single longer pulse so it is distinguishable before you have counted.
- **Every pool size** — all eight Garmin presets (20/25/33⅓/50, metric and
  imperial) auto-detected, or set explicitly. Custom lengths pass through
  untouched.
- **Readable footer** — total distance, elapsed time, or both stacked, drawn
  in a large number face sized to stay legible through goggles.
- **FIT export** — per-record pace delta, per-lap average delta and a
  session-level percentage of lengths on pace, for analysis in Garmin Connect.

## Pausing and rest

There is deliberately no rest detection. Pausing the timer stops the clock —
`timerTime` freezes, so a paused break never lands in a split. Stop without
pausing and that time counts against the split, exactly as it counts against
you in a set.

## Project structure

```
PoolPacer/
├── manifest.xml         # Datafield type, target devices, permissions
├── monkey.jungle        # Build configuration
├── sim.sh               # One-command simulator run (harness on, restored on exit)
├── switch-app-id.sh     # Swap the manifest between the beta and public listings
├── source/
│   ├── PoolPacerApp.mc  # AppBase entry point
│   ├── PoolPacerView.mc # compute(), gauge and footer rendering, haptics, FIT
│   ├── PaceMath.mc      # Pure pace/zone/formatting math, no UI dependencies
│   ├── Debug.mc         # (:debug) dry-land length simulator
│   └── Tests.mc         # (:test) unit tests for PaceMath
├── resources/
│   ├── drawables/       # Launcher icon
│   ├── settings/        # properties.xml / settings.xml
│   └── strings/         # UI and settings strings
└── store_assets/        # Connect IQ Store icon assets
```

## Building

Requires the [Connect IQ SDK](https://developer.garmin.com/connect-iq/sdk/)
and a developer signing key (`monkeyc --generate-key`).

Store distribution package, all manifest devices:

```
monkeyc -e -f monkey.jungle -o bin/PoolPacer.iq -y ~/developer_key -w
```

Single device, for sideloading:

```
monkeyc -d descentmk351mm -f monkey.jungle -o bin/sim.prg -y ~/developer_key
```

Check the app ID matches the listing you are building for before packaging:

```
./switch-app-id.sh status      # beta | public
./switch-app-id.sh public
```

## Testing

```
monkeyc -d descentmk351mm -f monkey.jungle -o bin/test.prg -y ~/developer_key --unit-test
monkeydo bin/test.prg descentmk351mm -t
```

For the simulator, `./sim.sh` enables the dry-land harness, builds, launches
the simulator and loads the app, restoring release state on exit — including
on Ctrl+C. Note that `monkeydo` holds the terminal, so use a second tab if you
need a prompt while it runs.

`Debug.mc` has a `startM` offset for jumping the simulated swim forward, so
five- and six-digit distance readouts can be checked without hours of
simulator time.

## Settings

Exposed via the Connect IQ mobile app or Garmin Express:

- Target time (minutes, seconds) and target distance, in your chosen units
- Units — metres or yards
- Pool length — auto-detect or an explicit preset
- Tolerance (slow side) and fast threshold — these set both the gauge band
  edges and the buzz thresholds
- Gauge range — how many seconds either side of target the arc spans
- Footer — distance, time, or both
- Haptics on/off, on-pace haptics on/off, buzz count per zone, pulse gap,
  vibration intensity

## Status

Published. The per-length maths, zone logic and layout have been exercised in
the simulator and on-device; behaviour across a full training session is still
being confirmed in the water.

## License

MIT — see [LICENSE](LICENSE).

## Store identity

The Connect IQ store keys updates off the manifest's `id`, so it must never
change for a published listing or existing users stop receiving updates.
PoolPacer has two, because Connect IQ cannot convert a beta-flagged app into a
public one:

- **Public listing:** `8ca92568669844049358da7b3fb94cd6`
- **Beta listing:** `36e4cb1ee7da4f5a9a27283984123a5e`

Both are in use — beta for testing, public for release. `switch-app-id.sh`
swaps the manifest between them; always rebuild after switching, since the ID
is compiled into the `.iq`.
