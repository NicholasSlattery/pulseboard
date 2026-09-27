# SpeedCoach receiver (experimental)

PulseBoard can receive live data from an NK SpeedCoach by taking the place
of NK LiNK Logbook's live-streaming receiver.

**Status:** stroke rate, split (speed), distance, elapsed time and stroke
count are decoded. Rate, split and stroke count were checked stroke-by-stroke
against a video of the SpeedCoach display (9 of 9 strokes exact). Verified
only against one SpeedCoach GPS Pro on firmware 2.25.

## Using it

1. Close NK LiNK Logbook - only one receiver can stream at a time.
2. PulseBoard → Settings → **SpeedCoach receiver** → **Start**. Keep
   PulseBoard open.
3. On the SpeedCoach: **Live Streaming → Phone Pairing → Find New** the first
   time. PulseBoard remembers the unit's serial and advertises it from then
   on, so later you only turn Live Streaming on.
4. A blue **SPEEDCOACH** strip on the dashboard shows rate, split, distance
   and time.
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

### 0100 - piece start

| Bytes | Meaning |
|---|---|
| 0-4 | second, minute, hour, day, month (SpeedCoach local time) |
| 5-6 | year, uint16 LE |
| 10 | 3 in every capture - unknown (piece type?) |

### 0103 - live status (20 bytes, ~5 per second)

| Bytes | Meaning |
|---|---|
| 0-3 | latitude, int32 LE, degrees ×1e-7 |
| 4-7 | longitude, int32 LE, degrees ×1e-7 |
| 8-11 | **distance in the piece, uint32 LE, centimetres** |
| 12-15 | always zero so far |
| 16-19 | **elapsed piece time, uint32 LE, milliseconds** |

All-zero distance and time = piece reset / no piece.

### 0203 - stroke (20 bytes, one per stroke)

| Bytes | Meaning |
|---|---|
| 0 | **stroke rate × 2** (half-stroke steps: 57 = 28.5, shown as "28½") |
| 1 | `FF` in every capture - probably heart rate with no belt paired (unconfirmed) |
| 2-3 | **boat speed, uint16 LE, cm/s**; split = 50000 / speed seconds; `FFFF` = no speed |
| 4-5 | `FFFF` when no piece is running, otherwise 0 |
| 6-7 | distance per stroke, uint16 LE, cm |
| 10-11 | average speed for the piece, uint16 LE, cm/s (→ average split) |
| 14 | **stroke count** (uint8) |

### 0102 and 0302 (every 6 s)

Always `FF`/`80` "no value" markers so far - possibly Empower Oarlock or
interval fields. Unknown.

### Verification

PulseBoard's raw packet log was recorded while filming the SpeedCoach. For
strokes 14-22 of the piece, the decoded rate and split equal what the
SpeedCoach displayed, e.g. stroke 19: byte 0 = 41 → 20.5 ("20½"), speed
38 cm/s → 21:55 /500m (display "21:55"). Test data: 
`test/speedcoach/speedcoach_protocol_test.dart`.

### Still unknown

Byte 1 and bytes 4-5 of the stroke packet in detail, byte 10 of the piece
start, and the 6-second packets. The receiver's raw packet log (Share CSV)
is enough to investigate them.

## Caveats

- NK may change this in a firmware update; the receiver shows raw packets so
  changes are visible.
- The phone must stay in the foreground (iOS stops advertising local names in
  the background).
- One SpeedCoach at a time for now.
