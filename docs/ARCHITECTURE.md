# PulseBoard architecture

This document explains how the app is put together and why. It is written
for whoever maintains the code next (probably you, six months from now).

## 1. Layers

```
┌──────────────────────────────────────────────────────────────┐
│ UI  (lib/screens, lib/widgets)                                │
│   Widgets only read state and call actions. No BLE, no SQL.   │
├──────────────────────────────────────────────────────────────┤
│ State  (lib/providers, Riverpod 3)                            │
│   Notifiers exposing immutable state; effects.dart wires      │
│   settings/assignments/session changes to side effects.       │
├──────────────────────────────┬───────────────────────────────┤
│ Bluetooth (lib/bluetooth)     │ Session (lib/session)          │
│  BluetoothManager             │  SessionRecorder (batched)     │
│   └ HeartRateSensorConnection │  SessionStatsCalculator (pure) │
│     × N (one per strap)       │  CsvExporter (streamed)        │
│  BleAdapter (interface)       │                               │
│   ├ UniversalBleAdapter       │                               │
│   └ SimulatedBleAdapter       │                               │
├──────────────────────────────┴───────────────────────────────┤
│ Persistence (lib/storage) - SQLite via sqflite_common_ffi     │
│   AthleteRepository, SensorRepository, SessionRepository,     │
│   SettingsRepository                                          │
└──────────────────────────────────────────────────────────────┘
```

Rules that keep it maintainable:

* Only `universal_ble_adapter.dart` imports the BLE plugin. Everything else
  talks to the `BleAdapter` interface, so the plugin can be swapped and all
  connection logic is unit-testable with `test/support/fake_ble_adapter.dart`.
* Only `lib/storage` contains SQL.
* Models (`lib/models`) are immutable value objects with `copyWith`.
* Branding lives only in `lib/app/app_info.dart` (+ `CFBundleDisplayName`).

## 2. Dependencies and why

| Package | Why |
|---|---|
| `universal_ble` (BSD-3) | Mature, actively maintained BLE plugin with multi-device support, per-device command queues, and **Windows support** - so BLE logic can be tried with real straps on a Windows laptop, not only on iOS. |
| `flutter_riverpod` 3 | Well-supported state management without code generation (nothing extra to run on Windows). `select` + `family` providers give per-card rebuilds. |
| `sqflite_common_ffi` + `sqflite_common` | SQLite with a background isolate. The FFI factory is used on **every** platform, so iOS, Windows and unit tests run the exact same database code. SQLite itself is bundled by `package:sqlite3` build hooks. |
| `path_provider`, `share_plus` | Where to store the DB / temporary CSV, and the iOS share sheet. |
| `wakelock_plus` | Keep the screen on during sessions. |
| `url_launcher` | "Open Settings" button when Bluetooth permission is denied. |
| `uuid`, `logging`, `clock` | Stable internal ids, structured logs, injectable time for deterministic tests. |
| `fake_async` (dev) | Drives reconnect/backoff/stale timers in tests without waiting. |

### Why not flutter_blue_plus?

It was the suggested default, but since v1.35 it is distributed under the
non-OSI *FlutterBluePlus License* (commercial licence required for for-profit
use - which would include e.g. a paid club coach) and it performs license
telemetry during builds. That conflicts with this project's goals (open
source, no tracking). `flutter_reactive_ble` (BSD-3, Philips Hue) was the
runner-up; it supports iOS/Android only. `universal_ble` was chosen because
it adds Windows. Because of the `BleAdapter` interface, switching is a
one-file change.

## 3. File structure

```
lib/
  main.dart                      bootstrap: open DB, load state, pick adapter
  app/        app.dart, app_info.dart, theme.dart
  models/     athlete, known_sensor, sensor_state, heart_rate_measurement,
              heart_rate_reading, connection_event, hr_zones, app_settings,
              training_session (+ SessionAthlete, HeartRateSample, ...)
  bluetooth/  ble_adapter (interface), universal_ble_adapter, simulated_ble_adapter,
              ble_uuids, heart_rate_parser, reconnect_policy,
              heart_rate_sensor_connection, bluetooth_manager
  session/    session_recorder, session_stats, csv_exporter
  storage/    app_database (schema + migrations), *_repository
  providers/  core, settings, athletes, sensors, session, dashboard,
              navigation, effects
  screens/    dashboard/, sensors/, athletes/, sessions/, settings/,
              home_shell, bluetooth_intro_screen
  widgets/    common (EmptyState, ZoneBadge, BatteryIndicator, ...),
              bluetooth_status_banner, hr_chart
  utils/      app_logger, formatters, grid_layout
test/         mirrors lib/; support/ has the fake adapter and app harness
```

## 4. Bluetooth strategy

### Standard services only

* Heart Rate Service `0x180D`, Heart Rate Measurement `0x2A37` (notify).
* Battery Service `0x180F`, Battery Level `0x2A19` (read, optional).

No vendor SDKs. Any strap that implements the Bluetooth SIG Heart Rate
Profile works.

### Scanning

* Scans filter on `0x180D` at the OS level (CoreBluetooth `withServices`).
  A "Show all Bluetooth devices" toggle scans unfiltered for straps that
  don't put 0x180D in their advertisement; the service is then verified on
  connect.
* Scans stop automatically after 30 s. There is **no background scan loop**:
  assigned sensors are reconnected by id (below), not by scanning.
* Duplicates are impossible by construction: everything is a map keyed by
  device id. RSSI updates come from repeated advertisements.
* Straps already connected to the phone by another app don't advertise;
  `getSystemDevices(withServices: [0x180D])` adds them to the list.
* iOS may not expose a name until connection; such devices are shown as
  "Unnamed sensor" with their id, and the name is filled in when it appears.

### One state machine per strap

`HeartRateSensorConnection` owns one strap:

```
 discovered/disconnected ──connect──▶ connecting ──link up──▶ connected
 connected ──0x180D/0x2A37 found──▶ subscribing ──first packet──▶ receiving
 connected ──no HR service (new device)──▶ failed   (no retry)
 connecting ──timeout/error──▶ reconnecting (backoff) ──▶ connecting
 connected|subscribing|receiving ──link lost──▶ reconnecting (DISCONNECTED shown at once)
 any ──user disconnect──▶ disconnected
```

* **Independence:** each connection has its own timers, subscriptions and
  retry counter. `BluetoothManager` holds a `Map<id, connection>`; nothing
  anywhere assumes a single strap. Tests cover 20 simultaneous straps and
  verify that dropping one never touches the others.
* **Race safety:** every async continuation captures an `epoch` and aborts if
  it changed (user disconnected, link dropped, Bluetooth off...).
* **Per-device GATT queues:** universal_ble defaults to one global queue; we
  switch to per-device so one slow strap can't stall the others.
* **Reconnect backoff:** 1, 2, 4, 8, 16, 30, 30... seconds with ±20 % jitter
  (so a whole crew rowing out of range doesn't retry in lock-step). The
  counter resets only when data actually flows again.
* **Cheap retries on iOS:** a reconnect attempt is a pending CoreBluetooth
  connection request (radio-controller level, very low power). universal_ble
  resolves remembered ids with `retrievePeripherals(withIdentifiers:)`, so
  assigned sensors reconnect after an app restart without scanning.
  CoreBluetooth requests never time out natively; after our Dart-side timeout
  we explicitly cancel with `disconnect()` so no stray connection appears
  later.
* **Advertisement shortcut:** if a strap waiting in backoff is seen
  advertising during a scan, it is retried immediately.
* **Zombie-link watchdog:** if subscribed but no packet (valid or not)
  arrives for 30 s, the link is torn down and re-established. This matters
  after iOS suspends the app.
* **Bluetooth off/on:** all connections pause (no attempts while the radio is
  off) and resume automatically.

### Heart Rate Measurement parsing

`HeartRateParser` implements the spec exactly: flags bit 0 selects UINT8 vs
UINT16 HR; bits 1-2 sensor contact; bit 3 energy expended (UINT16 kJ); bit 4
one or more RR intervals (UINT16, 1/1024 s). RR values are stored raw
(lossless) and converted to ms for display/export. Malformed packets are
dropped and counted, never crash, and never update the display. A reading is
*valid* only if BPM > 0 and the strap does not report "no skin contact".

### Stale data - never show an old number as live

* `staleAfter` (default 5 s): BPM is greyed out and the card says
  WEAK SIGNAL.
* `signalLostAfter` (default 15 s): `--` and NO SIGNAL.
* Link lost: `--` and DISCONNECTED **immediately** (not after a timeout).
* `SensorLiveState.displayBpm` is the only value the UI shows; it returns
  null unless the sensor is `receiving` and within the lost timeout.
* A 1 Hz ticker in `BluetoothManager` re-evaluates freshness and emits only
  when a sensor's freshness category changes.

### Rebuild efficiency

* Sensor state emissions are coalesced to at most one per 100 ms.
* Each dashboard card watches `sensorLiveProvider(id)` (a `select` on the
  map), so a packet from one strap rebuilds only that card.
* The list of cards (`dashboardEntriesProvider`) only changes when the set
  of athletes/sensors changes.
* Cards are wrapped in `RepaintBoundary`; the recording timer is its own
  tiny widget.

### Background operation (deliberately off)

The app does **not** declare `UIBackgroundModes: bluetooth-central`. When the
app is in the foreground everything works; when backgrounded, iOS suspends
it, notifications stop, and stale detection shows the truth when you return
(and the resume handler recycles quiet links). For coaching, keep the app on
screen - "Keep screen awake" defaults to *during sessions*.

If you later want recording to continue while the phone is locked, add to
`ios/Runner/Info.plist`:

```xml
<key>UIBackgroundModes</key>
<array><string>bluetooth-central</string></array>
```

Be aware this also enables CoreBluetooth state restoration inside
universal_ble, and iOS may still throttle background delivery. Test it
carefully before relying on it.

## 5. Data model (SQLite)

All entity ids are random UUIDs; names are never keys.

| Table | Purpose |
|---|---|
| `athletes` | id, name, nickname, age, max_hr (manual), notes, timestamps |
| `sensors` | id (BLE id), name, **athlete_id UNIQUE → athletes ON DELETE SET NULL**, last_seen_at, battery_percent |
| `sessions` | id, started_at, ended_at, name, zone_bounds (snapshot), recovered |
| `session_athletes` | snapshot of each athlete in a session (name, sensor, max HR) - no FK, so history survives athlete deletion |
| `hr_samples` | session_id, athlete_id, sensor_id, t (ms), bpm, pct, zone, rr (raw, comma-separated) - indexed by (session, athlete, t) |
| `connection_events` | session_id, sensor_id, athlete_id, type, t, detail |
| `settings` | key/value; `app_settings` holds the JSON settings blob |

* The athlete ↔ sensor link lives on the sensor row, so athletes and sensors
  can be reassigned independently. Assigning a sensor to an athlete who
  already had one moves them in a single transaction.
* **Write efficiency:** the recorder buffers samples in memory and writes one
  transaction every 5 s (and when the app goes to background / the session
  stops). 20 athletes × 3 h ≈ 216 k rows ≈ 10-15 MB - comfortably within
  SQLite's comfort zone. Writes run on sqflite's background isolate.
* **Crash recovery:** a session left open by a crash/kill is closed on the
  next launch using its last sample time and flagged "recovered".
* **Zone snapshot:** each session stores the zone model it was recorded
  with, so later settings changes don't rewrite history.
* **Migrations:** bump `AppDatabase.schemaVersion` and add an
  `if (from < N)` block in `_migrate`.

## 6. CI / iOS build strategy

* `test.yml` (Ubuntu): format check, `flutter analyze`, all tests.
* `build-ios.yml` (macOS 26 runner): runs the tests, then
  `flutter build ios --release --no-codesign`, then packages
  `build/ios/iphoneos/Runner.app` into `Payload/Runner.app` and zips it as
  `PulseBoard-<version>-<build>-unsigned.ipa`. The step fails loudly if the
  `.app`, its executable or Flutter.framework are missing - it never
  pretends. The IPA is uploaded as an artifact and, for `v*` tags, attached
  to a GitHub Release.
* SideStore/AltStore re-sign the IPA with the user's free Apple ID on the
  phone. No certificates or Apple credentials are stored in the repository.
* Flutter is pinned (`FLUTTER_VERSION`) in both workflows for reproducible
  builds. Update both together.

## 7. Known risks and limitations

| Risk | Mitigation |
|---|---|
| Simultaneous connection limit. iOS doesn't document a hard cap; in practice ~10-20 BLE peripherals work, but more straps means longer connection intervals and more radio contention. | No artificial limit in code; tests cover 20. Test your real team size before relying on it. An iPad sitting centrally helps range. |
| A strap can only accept 1-3 connections (Polar H10: 2). If it is paired to a watch *and* another phone, it may refuse or stop advertising. | Clear "could not connect - may be connected to another device" message; "Connected to phone" entries from `getSystemDevices`. |
| CoreBluetooth ids are per-phone and can change (Bluetooth reset, strap address rotation, battery swap on some models). | The strap then appears as a new sensor; reassign it. Documented in README. |
| App backgrounded / phone locked → no data. | Foreground design, keep-awake, stale indicators, zombie-link recycling on resume, samples flushed on background. |
| `sqlite3` native library is fetched by a build hook during the CI build. | Hashes are verified by the package; failure fails the build visibly. |
| Free Apple ID signing expires after 7 days; max 3 sideloaded apps. | Refresh in SideStore (README). |
| Flutter 3.47 plans to deprecate `package:flutter/material.dart` in favour of `material_ui` in the next release. | Flutter is pinned in CI; when upgrading run `dart fix --apply --code=migrate_design_widgets`. |
| First launch of iOS build has only been verified by CI compilation, not on your specific device. | Diagnostics log (Settings → Diagnostics) shows every BLE step without needing Xcode. |

## 8. Designed-for future features

* **Boats / groups:** add a `boats` table and `athlete.boat_id`; the
  dashboard already groups by a sortable entry list.
* **Target zones & alerts:** zone logic is centralised in `ZoneModel`;
  `CardData.from` is the single place that decides card state.
* **Intervals / workouts:** `SessionRecorder` already timestamps everything;
  add interval markers as another event type.
* **HRV:** RR intervals are recorded losslessly in `hr_samples.rr`.
* **Android:** add the platform folder and Android BLE permissions;
  `universal_ble` already supports it.
* **Other sensors (ANT+ bridge, stroke rate):** implement another adapter or
  a new connection type alongside `HeartRateSensorConnection`.
* **FIT export / LAN dashboard:** add exporters next to `CsvExporter`.
