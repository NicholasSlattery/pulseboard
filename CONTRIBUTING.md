# Contributing

Thanks for helping! PulseBoard is used at real practices, so **reliability
beats features**.

## Ground rules

* Never show stale or fake data as live. Any change touching the dashboard
  must keep `SensorLiveState.displayBpm` as the single source of "current"
  BPM.
* Never introduce single-sensor assumptions. Everything BLE is keyed by
  device id.
* Keep the BLE plugin behind `BleAdapter`; only `universal_ble_adapter.dart`
  may import it.
* No analytics, tracking, accounts or network calls.

## Workflow

```powershell
flutter pub get
dart format lib test          # 100-column formatting (see analysis_options.yaml)
flutter analyze
flutter test
```

CI runs the same checks (`.github/workflows/test.yml`); pushes to `main`
additionally build the unsigned iOS IPA.

## Tests

* BLE logic: use `test/support/fake_ble_adapter.dart` + `fake_async` to
  script link drops, timeouts and packets deterministically.
* Widget flows: `test/support/test_app.dart` boots the real app with an
  in-memory database and the fake adapter.
* Add a test with every bug fix.

## Commits and PRs

Small, focused PRs with a clear description of the behaviour change and how
you tested it (ideally with real straps: which models, how many).
