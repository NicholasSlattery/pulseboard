# Design handoff: SpeedCoach live screen (PulseBoard)

Paste this whole file into Claude Design as the brief.

## 1. Ask

Redesign the **SpeedCoach live screen** of PulseBoard, a rowing coach's iPhone app (Flutter, Material 3). The current screen is a setup form with a small tile grid underneath. Design two things:

1. **Full Data view** — the workout-start and in-workout screen showing every value the SpeedCoach sends, organised so a coach can read it at a glance on a launch or at the dock.
2. **Simple view (lite)** — a minimal version with only what matters mid-piece, readable from 2–3 m away.

Also design the **pre-workout state** (connect, pair, waiting for the SpeedCoach, start) and the states that follow it. Section 6 lists the states.

Deliver: iPhone portrait and landscape for both views, light and dark, plus the state variants. Include a component spec (sizes, type scale, colour tokens) that a Flutter developer can build from.

## 2. Who uses it and where

- A coach or athlete standing or sitting in a boat or on a launch. The phone is in a sun-exposed, wet, bouncing environment. Glare is common; hands are wet or gloved.
- Glances last about 1 s. Numbers must be huge, high-contrast, and in stable positions (no layout jump when digits change width; use tabular figures).
- Colour is never the only signal (existing app rule — pair it with a number, arrow or label).
- Touch targets are at least 48 pt, and ideally much larger for the few in-workout controls.
- Landscape matters: a phone in a mount is often landscape.
- Keep the screen awake while streaming.

## 3. Data available (real, decoded from the device)

The device is an NK SpeedCoach GPS Pro. Live data arrives in two packet types. The values below are decoded and were verified against the SpeedCoach's own display. **Design only with these, plus the derived values in section 4.**

### Every stroke (one packet per stroke, about 0.4–0.6 Hz at 20–36 spm)

| Field | Unit / format | Notes |
|---|---|---|
| Stroke rate | spm, steps of 0.5 (e.g. 28.5) | |
| Split (current) | m:ss.s per 500 m | From boat speed. Shows `--` when the boat is stopped or has no GPS. |
| Boat speed | m/s | Same source as split. |
| Distance per stroke | m (e.g. 9.6) | |
| Average split (piece) | m:ss.s per 500 m | |
| Average speed (piece) | m/s | |
| Stroke count | integer | Counter for the piece. It wraps at 256, so handle that in the UI and allow "strokes since reset". |
| Piece running | yes/no | No = SpeedCoach is idle or between pieces. |

### About 5 times a second (status)

| Field | Unit / format | Notes |
|---|---|---|
| Elapsed time | m:ss.t (tenths) | Pauses when the piece pauses. |
| Distance | m (whole metres) | GPS distance within the piece. |
| GPS position | lat/lon | Optional, only for a small "GPS OK" indicator or a future map. No map in this design. |
| Reset | all zero | Piece was reset. |

### Session metadata

| Field | Notes |
|---|---|
| Piece start time | The SpeedCoach's local clock time when the piece started. |
| SpeedCoach serial | e.g. 2226780. |
| Boat name | Editable; the app sends it to the SpeedCoach. |
| Connection | Waiting / Receiving / Stopped / Error, last packet age, packet count. |

### NOT available (don't design for these)

The protocol decode doesn't cover these, so don't put them in the UI, even as disabled placeholders:

- Power, drag factor, stroke length or angle, force curve, catch/finish slip.
- Heart rate from the SpeedCoach (a byte that is probably HR is always "none" so far).
- Temperature, battery, or workout interval structure (set/rest, target splits).

If the coach wants HR, the app already shows it separately from Bluetooth straps elsewhere; the design can leave one optional slot for an athlete's HR in the boat, but it is not SpeedCoach data.

## 4. Derived values the app can compute

These are allowed and encouraged if they help. Mark them visually as "calculated" where space allows.

- Split trend: last 5 or 10 strokes, as an up/down arrow plus a small delta (e.g. ▲ 0.8s).
- 500 m split: average split for each completed 500 m (or 250 m), as a list or bar strip.
- Rate trend: a sparkline of the last about 60 seconds.
- Split sparkline: the same for split, about 60 seconds.
- Stroke consistency: range of the last 10 strokes' split and of their distance per stroke.
- Projected finish: for a piece with a target distance, the projected time at the current average split.
- Distance remaining: if the coach enters a target distance or time.
- Average rate for the piece.
- Target split with a colour band: the coach enters a target split, and the display shows ahead, on, or behind it.

Targets are coach input (distance or time target, target split). They are optional and can be set on the pre-workout screen.

## 5. The two views

### 5a. Full Data view

Purpose: the coach sees everything, prioritised. Build a clear hierarchy with three tiers, not a wall of equal tiles.

- **Tier 1 (hero, always largest):** Split (current) and Stroke rate. Side by side in portrait, or left and right in landscape.
- **Tier 2 (large):** Distance, Elapsed time, Distance per stroke.
- **Tier 3 (medium, compact grid):** Average split, Speed, Stroke count, Average rate, Average speed, Split trend.
- **Trend strip:** split and rate sparklines over the last minute, aligned on the same time axis.
- **Per-500 m list:** completed 500 m splits (scrollable, newest on top).
- **Status bar (small, top):** connection dot and label, piece running or idle, serial, last packet age, GPS OK.
- **Bottom:** a single obvious control row (Stop, Switch to Simple view, Lap/mark if you propose one, but only if it can be done without SpeedCoach support; otherwise omit).

Consider two layout options and recommend one: (A) fixed hierarchy as above, (B) user-arrangeable tiles. Prefer A.

### 5b. Simple view (lite)

Purpose: readable from across the boat. Four values maximum.

- Split, Rate, Distance, Elapsed time. Split and rate are the heroes.
- Optional: one tiny status dot for connection, and one "behind/on/ahead target" cue if a target is set.
- No scrolling, no sparklines, no lists. One tap switches to Full Data; one large tap-and-hold (to avoid accidental taps) to stop.
- Portrait and landscape.

Also show a variation with only two values (Split + Rate) as a "glance mode", if you think it's worth it.

## 6. States to design

1. **Not started:** explains how to connect. Today's steps: (1) close NK LiNK Logbook; (2) tap Start and keep PulseBoard open; (3) on the SpeedCoach choose Live Streaming > Phone Pairing > Find New the first time, or just switch Live Streaming on once paired. Include the boat name field, the paired SpeedCoach (serial and Forget), and "Pair a new SpeedCoach".
2. **Starting / waiting for SpeedCoach:** advertising as "NK LiNKp" while pairing.
3. **Connected, no piece running:** the SpeedCoach is streaming but idle. Values show `--` with a clear "Start a piece on the SpeedCoach" hint.
4. **Streaming:** the main views.
5. **Piece paused.**
6. **Stale data:** no packet for more than 3 s. Dim the numbers and show "last update Ns ago" so nobody trusts frozen values.
7. **Disconnected / error:** with a one-tap Reconnect.
8. **Not supported on this device** (Android or Windows can't act as the stream host).
9. **Piece complete:** a summary card (total distance and time, average split, average rate, distance per stroke, best 500 m, per-500 m list). Include Save or Export (existing CSV share) and Done.

Also a small **Advanced / raw packets** sheet. The raw packet log (time, characteristic, hex) currently sits on the main screen. Move it behind an "Advanced" disclosure with Copy CSV, Share CSV and Clear.

## 7. Existing visual system (match it, then push it)

- Material 3, seed colour `#0B6E99` (deep teal-blue). Light and dark themes are generated from the seed.
- Status colours: connected `#2E9E5B`, warning `#E0A100`, danger `#D64545`, neutral `#7A8794`, info `#3B82C4`.
- Heart-rate zone colours exist elsewhere: Z1 `#8FA3B3`, Z2 `#2F80ED`, Z3 `#27AE60`, Z4 `#F2994A`, Z5 `#EB3B3B`. Don't reuse them for SpeedCoach data, so nobody confuses split colour with HR zone.
- Numbers use heavy weight (w900) and tabular figures. Labels are small, uppercase, letter-spaced (e.g. `SPLIT`, `RATE`, with unit `/500m`, `spm`).
- Cards with no outer margin, clipped corners (Material card defaults).
- Current screen title: "SpeedCoach (experimental)".

You may propose a darker, high-contrast "on the water" theme for the live views specifically (near-black background, white and amber numerals, sunlight-readable). The setup screen can stay on the regular theme.

## 8. Formatting rules (so the mockups use realistic values)

- Split: `1:58.4` (m:ss.t). Stopped or no GPS: `--:--`.
- Rate: `28` or `28.5` (drop the `.0`). Unit `spm`.
- Distance: whole metres, `1,240` or `1240 m`. Distance per stroke: `9.6 m` (one decimal).
- Elapsed: `7:12.3`. Speed: `4.23 m/s`.
- Sample realistic mid-piece values: split 1:58.4, rate 28.5, distance 1,240 m, elapsed 7:12.3, distance per stroke 9.6 m, average split 1:59.1, speed 4.23 m/s, strokes 203, average rate 28.1.

## 9. Constraints for implementation

- Flutter and Material 3. Keep widgets composable: one reusable "metric tile" with size variants (hero, large, compact), and one sparkline widget.
- The state comes from a single live-state object that has the fields in section 3. The UI must tolerate any field being null (shown as `--`).
- Screen wakes must be locked on while streaming.
- Accessibility: Dynamic Type for the setup screen; the live views use fixed, very large sizes but must not clip at any supported iPhone width (SE to Pro Max).

## 10. What I want back

- The two views in portrait and landscape, light and dark.
- The state variants from section 6.
- A short spec: type scale, spacing, colour tokens, tile size variants, and the rule for which values stay in Simple view.
- A recommendation on anything in section 4 that is not worth the screen space.
