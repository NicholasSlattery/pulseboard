# SpeedCoach receiver (experimental)

PulseBoard can receive live data from an NK SpeedCoach by taking the place
of NK LiNK Logbook's live-streaming receiver.

**Status:** elapsed time and stroke count are decoded; stroke rate is
calculated from stroke timing; split, speed and distance are not decoded yet
(they need a capture with a GPS fix). Verified only against one SpeedCoach
GPS Pro on firmware 2.25.

## Using it

1. Close NK LiNK Logbook - only one receiver can stream at a time.
2. PulseBoard → Settings → **SpeedCoach receiver** → **Start**. Keep
   PulseBoard open.
3. On the SpeedCoach: **Live Streaming → Phone Pairing → Find New** the first
   time. PulseBoard remembers the unit's serial and advertises it from then
   on, so later you only turn Live Streaming on.
4. A blue **SPEEDCOACH** strip on the dashboard shows rate, time and strokes.
   The receiver screen also keeps a raw packet log (copy/share as CSV) to help
   decode more fields.

Requires the Training Pack and firmware 2.19+ (NK's requirement for live
streaming). Works on iPhone/iPad only: Windows cannot advertise the name the
SpeedCoach looks for.

## Is there documentation or a standard?

No. NK publishes CSV/FIT exports and its own apps, not a protocol. The
standard Bluetooth rowing profile (Fitness Machine Service "Rower", used by
rowing machines) is not used by the SpeedCoach. Neither NK characteristic UUID
appears in any public source we could find (September 2026).

## Protocol (as reverse-engineered)

Captured with Apple's Bluetooth logging profile on the phone running NK LiNK,
decoded from the PacketLogger file.

### Roles

The **phone is the Bluetooth peripheral**. It advertises service
`3291ddee-0889-409c-b993-24ec00009970` with a local name:

| Local name | Meaning |
|---|---|
| `NK LiNKp` | accepting a new SpeedCoach ("Find New") |
| `2226780` (a serial) | waiting for that specific, already-paired unit |

The SpeedCoach scans, connects, discovers the service (Find Information
requests), then reads and writes characteristics. It never subscribes to
notifications.

### Characteristics

All 18 are `3291ddee-0889-409c-b993-24ecXXYY9970`, read + write:
`0100 0101 0201 0301 0102 0202 0302 0402 0502 0103 0203 0303 0403 0104 0005 1005 2005 0002`.

| XXYY | Direction | When | Content |
|---|---|---|---|
| 1005 | SC writes | on connect | serial number, ASCII |
| 0005 | SC reads | on connect | boat name, ASCII (NK LiNK's Boat ID) |
| 2005 | SC reads | every ~10 s | `01 00 00 …` (20 bytes) while streaming is on |
| 0103 | SC writes | ~5 Hz | live status (below) |
| 0203 | SC writes | once per stroke | stroke packet (below) |
| 0102, 0302 | SC writes | every 6 s | only `FF`/`80` "no value" markers indoors |

The GAP Device Name is also read once.

### 0103 - live status (20 bytes)

| Bytes | Meaning |
|---|---|
| 0-7 | looks like last GPS position (two int32 LE, ×1e-7 degrees) - unconfirmed |
| 8-15 | zero indoors - probably speed / distance - **unknown** |
| 16-19 | **elapsed piece time, milliseconds, uint32 LE** (pauses with the piece) |

### 0203 - stroke (20 bytes)

| Bytes | Meaning |
|---|---|
| 14 | **stroke count** (uint8, +1 per stroke) |
| 2-3 and 6-7 = `FF FF` | **idle marker** (rower stopped) |
| 0 | changes every stroke, correlates ~0.6 with rate - **unknown** |
| others | zero indoors |

### Next captures needed

1. Steady rate with a metronome (e.g. 45 s at 20, 45 s at 30), noting the
   SpeedCoach's displayed rate - to find a rate field.
2. Outdoors with GPS, noting split / distance at known times - to decode bytes
   8-15 of 0103 and the 6-second packets.

The receiver's **raw packet log** (Share CSV) is enough for both - no
sysdiagnose needed any more.

## Caveats

- NK may change this in a firmware update; the receiver shows raw packets so
  changes are visible.
- The phone must stay in the foreground (iOS stops advertising local names in
  the background).
- One SpeedCoach at a time for now.
