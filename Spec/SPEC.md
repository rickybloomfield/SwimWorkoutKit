# Open Swim Workout Format — Specification v0.2

**Status:** Draft · **File extension:** `.swimworkout` · **Encoding:** JSON (UTF-8) · **Media type:** `application/vnd.openswimworkout+json`

Open Swim Workout (OSW) is an open, JSON-based interchange format for *prescribed* swimming workouts — the workout a coach writes, not the activity a watch records. It is designed around what coaches actually put on whiteboards and printouts: sections with totals, nested repeats, stroke/activity/effort descriptors, and — crucially — **per-lane send-off variants**, which no existing format expresses.

A companion human-readable notation, **SwimText**, round-trips to and from this model (see [notation.md](notation.md)).

## 1. Design principles

1. **Faithful** — represent real coach notation (per-lane intervals `@1:30/1:40/1:50`, brace repeats, footnotes), not an idealized model.
2. **Layered semantics** — structure everything that has meaning; keep verbatim free text (`note`, `sourceText`) at every level so nothing is ever lost to parsing.
3. **Computable** — per-group distances and duration estimates derive mechanically; stated totals act as checksums (useful for OCR validation).
4. **Open** — versioned spec, JSON Schema, MIT-licensed reference implementation (`SwimWorkoutKit`, Swift).

## 2. Document structure

```json
{
  "format": "open-swim-workout",
  "version": "0.2",
  "workout": { … }
}
```

- `format` (required): always `"open-swim-workout"`.
- `version` (required): `MAJOR.MINOR`. Readers MUST reject unknown majors and SHOULD accept unknown minors, ignoring unrecognized fields.

### 2.1 `workout`

| Field | Type | Notes |
|---|---|---|
| `title` | string? | |
| `date` | string? | ISO-8601 calendar date (`2026-06-10`) |
| `author`, `team` | string? | |
| `description` | string? | Coach-authored summary of the session (its focus, intent, or theme). Distinct from `notes`. |
| `location` | object? | Where it took place. `{ "name", "latitude"?, "longitude"?, "address"? }` |
| `course` | object | `{ "length": 25, "unit": "yd" \| "m" }`. SCY = 25 yd, SCM = 25 m, LCM = 50 m |
| `categories` | string[] | Open list. Recommended: `sprint`, `distance`, `im`, `stroke`, `kick`, `basic`, `triathlon`, `openwater`, `lowvolume`, `test` |
| `tags` | string[] | Free-form |
| `groups` | SpeedGroup[] | **Ordered fastest → slowest.** Empty = single unnamed group |
| `sections` | Section[] | |
| `notes` | string? | |
| `source` | object? | `{ "kind": "manual"\|"ocr"\|"generated"\|"ai"\|"imported", "attribution"?, "imageRef"? }` |
| `statedTotal` | int? | Total distance as printed on the original |

#### `location` (since 0.2)

Where the workout took place — a pool or facility.

```json
{ "name": "Community Aquatic Center", "latitude": 0.0, "longitude": 0.0, "address": "123 Main St, Anytown" }
```

- `name` (required): display name. The only required field, so a hand-typed name with no map entry is valid.
- `latitude`, `longitude` (optional): WGS-84 decimal degrees; present together when the location was picked from a map.
- `address` (optional): human-readable address line.

### 2.2 Speed groups

A **speed group** is a lane/pace cohort. One workout serves all groups; sets carry per-group send-offs.

```json
{ "id": "A", "label": "Lanes 1–2", "basePace100": "1:15", "note": "…" }
```

- `id` (required): short stable key (`"A"`, `"B"`, …) referenced by send-off maps.
- `basePace100`: pace per 100 (free swim) used for duration estimates and interval tools.

### 2.3 Sections

```json
{ "name": "Main Set", "note": "…", "statedDistance": 2000, "items": [ … ] }
```

`statedDistance` is the distance as printed; validators compare it against the computed distance (§4).

### 2.4 Items

Every item carries `"type"`: `"set"`, `"repeat"`, `"rest"`, or `"note"`.

**`set`** — the workhorse: `reps × distance` plus descriptors.

| Field | Type | Notes |
|---|---|---|
| `reps`, `distance` | int (required) | `distance` is per rep, in course units |
| `stroke` | enum? | `free, back, breast, fly, im, imo, rimo, stroke, choice, mixed` (`imo`/`rimo` rotate IM order across reps/rounds; `stroke` = swimmer's specialty; `mixed` = see `segments`/`perRep`) |
| `activity` | enum? | `swim, kick, pull, drill, scull, mixed` — orthogonal to `stroke` ("fly drill" = `stroke: fly, activity: drill`) |
| `drillName` | string? | Named drill |
| `equipment` | enum[]? | `fins, paddles, buoy, snorkel, board` |
| `effort` | object? | §2.5 |
| `breath` | object? | `{ "pattern": "3/4/4/5" }` or `{ "every": 3 }` |
| `interval` | object? | §2.6 |
| `segments` | Segment[]? | Intra-rep structure; distances MUST sum to `distance` |
| `perRep` | PerRep[]? | Per-rep variations (`selector`: `"odd"`, `"even"`, `"3"`, `"1-4"`) |
| `perGroup` | map? | Per-group overrides `{ "B": { "reps"?, "distance"?, "sendoff"? } }` |
| `groupFilter` | string[]? | Item applies only to these groups |
| `label`, `note`, `sourceText` | string? | `sourceText` = verbatim original line |

**`repeat`** — nested rounds.

```json
{ "type": "repeat", "rounds": 3, "roundsPerGroup": { "A": 4, "B": 3 },
  "items": [ … ], "perRound": [ { "selector": "2", "stroke": "back", "note": "…" } ] }
```

**`rest`** — standalone rest: `{ "type": "rest", "duration": "2:00", "note"? }`.

**`note`** — flow annotation: `{ "type": "note", "text": "…" }`.

### 2.5 Effort

```json
{ "shape": "descend", "level": "sprint", "percent": 90, "percentMax": 95, "detail": "1-4" }
```

- `shape`: `steady, build, descend, ascend, negative-split, variable-sprint`
- `level`: `easy, smooth, moderate, strong, fast, sprint, max, race`
- `percent` / `percentMax`: "% effort", optionally a range. With `shape: descend`, `percent` is the target ("descend to 90%").
- `detail`: free-form shape detail (`"1-4"`, `"by 25"`, `"by round"`).

### 2.6 Intervals

```json
{ "mode": "sendoff",
  "sendoffs": { "A": "1:30", "B": "1:45", "C": "2:00" },
  "targetRest": ":15", "maxRest": ":30", "openEnded": true, "note": "…" }
```

- `mode`: `sendoff` (leave on a clock time), `rest` (fixed rest between reps, in `rest`), or `open` (no clock).
- `sendoffs`: map group id → time. **Sparse maps are legal**: a group without an entry resolves to the nearest *faster* (earlier-listed) specified group, then the nearest slower one. This encodes lines like `@1:30/1:45/2:00` in a four-group workout.
- `targetRest` / `maxRest`: the rest the send-off is designed to yield ("ideally :15 rest" / "max :30 rest").
- `openEnded`: the slowest listed send-off is a floor ("@1:25+").

### 2.7 Times

All times are strings: `"m:ss"` (`"1:30"`), `":ss"` (`":35"`), or bare seconds (`"35"`). Canonical emission is `"m:ss"` with `":ss"` for sub-minute values.

## 3. Semantics

- **Distance** for group *g* = Σ over sections of Σ over items, where a `set` contributes `reps × distance` (after `perGroup` overrides; zero if excluded by `groupFilter`) and a `repeat` multiplies its items by its round count for *g* (`roundsPerGroup` resolves sparsely like send-offs).
- **Duration estimate** for *g*: send-off sets contribute `reps × sendoff`; rest-mode sets contribute `reps × (estimatedSwimTime + rest)` using the group's `basePace100` and published activity/stroke multipliers; `rest` items contribute their duration. Implementations MUST report whether the estimate is complete.
- **Reconciliation**: a stated total "matches" when **any** group's computed distance equals it (printed totals usually describe one cohort).

## 4. Validation

Errors: non-positive `reps`/`distance`/`rounds`; segment sums ≠ rep distance; references to undefined group ids; duplicate group ids.
Warnings: stated section/workout totals matching no group; distances not divisible by the course length; send-offs implausibly shorter than estimated swim time.

## 5. Versioning & extension

Semantic versioning of the spec. Unknown fields MUST be ignored (and SHOULD be preserved on rewrite). New enum values only in minor versions; readers treat unknown enum values as their `note`-carrying neighbors (e.g., unknown `stroke` → keep raw string in `note`).

**Changelog**

- **0.2** — added optional `workout.location` (`{ name, latitude?, longitude?, address? }`). Backward-compatible: 0.1 readers ignore it.

## 6. Interoperability

OSW is the source of truth; exports are intentionally lossy:

- **Garmin FIT workout files**: choose one group; descriptors → step `notes`; send-off → `repetition_time`; `im_by_round`/`rimo` map directly; "drill of a stroke" collapses to FIT's `drill` + note.
- **Apple WorkoutKit** (watchOS 11+): one group; send-off → `poolSwimDistanceWithTime` goals; stroke/activity → step display names.
- **SwimText**: human notation, round-trips (lossless for the canonical subset).

## 7. Reference implementation

`SwimWorkoutKit` (Swift package, this repository): model + Codable, SwimText parser/printer, calculators, validator, and the `swimtext` CLI (`to-json`, `to-text`, `check`). Test corpus: a collection of representative swim workouts covering the format's features.
