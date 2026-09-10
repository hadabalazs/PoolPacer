# PoolPacer
PoolPacer Garmin Datafield for swim training

# PoolPacer Details

A pool-swim data field for Garmin Connect IQ. PoolPacer helps you stay on pace without looking at your watch: a color-coded gauge and configurable vibration feedback tell you if you're on pace, too fast, or too slow, and a live needle shows your speed trend as you swim.

Built for the Garmin Descent Mk3 (43mm), Mk3i (43mm), and Mk3i (51mm).

## Features

- **Pace gauge** — a wide arc gauge with a green on-pace zone and red off-pace zones. The zone boundary is tied directly to your tolerance setting, so what you see always matches what you feel.
- **Live speed needle** — shows where your current speed is trending in real time, using `Activity.Info.currentSpeed`, alongside a marker for how your last completed length landed.
- **Configurable haptics** — independent, user-set buzz counts for on-pace, too-slow, and too-fast.
- **Every pool size** — all eight Garmin pool-length presets (20/25/33⅓/50, metric and imperial) are auto-detected; custom pool lengths pass through untouched.
- **Banked seconds** — tracks how far ahead or behind pace you are across a set, shown live in the gauge.
- **Session or lap timing** — toggle between full-session and current-lap elapsed time.
- **FIT data export** — pace delta, banked seconds, lap average delta, and percentage of lengths on pace are written as custom FIT fields for post-swim analysis in Garmin Connect.

## Project structure

PoolPacer/
├── manifest.xml # App manifest — datafield type, target devices, permissions
├── monkey.jungle # Build configuration
├── source/
│ ├── PoolPacerApp.mc # AppBase entry point
│ ├── PoolPacerView.mc # compute(), gauge rendering, haptics, FIT fields
│ ├── PaceMath.mc # Pure pace/zone/formatting math, no UI dependencies
│ ├── Debug.mc # (:debug) dry-land length simulator for testing without a pool
│ └── Tests.mc # (:test) unit tests for PaceMath
├── resources/
│ ├── drawables/ # Launcher icon
│ ├── settings/ # properties.xml / settings.xml — user-configurable options
│ └── strings/ # UI and settings strings
└── store_assets/ # Connect IQ Store icon assets


## Building

Requires the [Connect IQ SDK](https://developer.garmin.com/connect-iq/sdk/) and a developer signing key (`monkeyc --generate-key` if you don't have one).

Device build (for sideloading/testing):

monkeyc -o source/PoolPacer.prg -f monkey.jungle -y /path/to/developer_key -d descentmk343mm -w


Store distribution package (all manifest devices, release-optimized, strips `(:debug)` code):

monkeyc -e -r -o source/PoolPacer.iq -f monkey.jungle -y /path/to/developer_key -w


## Testing

Run the unit test suite against the pure pace/zone math in `PaceMath.mc`:

monkeydo source/PoolPacer.prg descentmk343mm -t


All tests should pass. `Debug.mc` also provides a scripted dry-land length simulator for testing gauge/haptic behavior indoors without a pool — see the `(:debug)` build guard in `PoolPacerView.mc`.

## Settings

Exposed via the Connect IQ mobile app / Garmin Express once installed:

- Target pace (per 100m/100y)
- Pace tolerance — controls both the haptic buzz threshold and the gauge's green/red boundary
- Buzz count for on-pace, slow, and fast (independently configurable, 0–5)
- Elapsed time display: session total or current lap
- Units (metric/imperial) and pool length preset

## Status

Actively in development and testing. The live speed-needle behavior (`Activity.Info.currentSpeed` indoors, without GPS) is still being verified against real pool swims.

## License

MIT — see [LICENSE](LICENSE).
