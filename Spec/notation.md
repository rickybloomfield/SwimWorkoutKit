# SwimText Notation v0.1

SwimText is the human-readable companion to the Open Swim Workout JSON format: type it like a coach writes it, paste it into iMessage, feed it to a parser or an LLM. The reference parser/printer lives in `SwimWorkoutKit`; the canonical subset round-trips losslessly.

## Document

```
# Friday — Sprint                      ← title
date: 2026-06-05                       ← metadata (before any content)
course: scy                            ← scy | scm | lcm
categories: sprint                     ← comma-separated
groups: A "Lanes 1-2" 1:15; B "Lanes 3-4" 1:25; C "Lanes 5-6" 1:40
total: 3200                            ← stated total (checksum)

== Warmup: 300                         ← section, optional stated distance
3x100 as swim/kick/pull
== Main Set: 2800
3x300 free descend to 80% @4:40/4:50/5:00 (ideally :40 rest)
2x {                                   ← repeat block (nestable)
  round 2: back                        ← per-round variation
  6x25 choice sprint @:35 (max :40 rest)
  100 kick easy r1:00
}
rest 2:00 | between sets               ← standalone rest
> remember your fins                   ← note item
== Cool Down: 100
100 choice easy
```

Metadata keys: `date`, `author`, `team`, `course`, `categories`, `tags`, `total`, `groups`, `notes` — recognized only before the first content line, so `Warmup: 800` can never be eaten as metadata.

## Set lines

```
[REPS x] DISTANCE [descriptors…] [@SENDOFFS] [rREST] [(hints)] [| note]
```

| Element | Examples | Meaning |
|---|---|---|
| Reps × distance | `4x50`, `8 x 25`, `300` | bare distance = 1 rep |
| Stroke | `free fr back bk breast br fly fl im imo rimo stroke stk choice ch` | |
| Activity | `swim sw kick k pull pu drill dr scull` | orthogonal to stroke: `fly drill` |
| Equipment | `w/fins`, `fins`, `paddles`, `buoy`, `snorkel`, `board` | |
| Effort level | `easy ez smooth moderate strong fast sprint max race`, `all out`, `blast`, `asap` | last three → `max` |
| Effort shape | `build`, `descend`/`desc`, `ascend`, `ns`, `vs` | `descend 1-4`, `descend to 90%`, `build by 50` |
| Percent | `90%`, `75-80%` | |
| Breathing | `bp 3/4/4/5`, `be3`, `be4-5` | |
| Segments | `(25 kick/25 drill/25 swim)` | distances must sum to the rep distance |
| Per-rep / segments | `as swim/kick/pull` | count = reps → per-rep; divides distance → equal segments |
| Send-off | `@1:30`, `@:35`, `@1:30/1:45/2:00`, `@1:15/1:20/1:25+`, `@1:30 (+1:00)`, `@Lane` | list maps to groups in order; sparse lists fall back to the nearest faster group; `+` = floor; `(+T)` extends cumulatively |
| Rest interval | `r:20`, `r20s`, `r1m`, `r1:00` | rest between reps; alongside a send-off it becomes the designed rest |
| Rest hints | `(~:15 rest)`, `(ideally 15s rest)`, `(max :30 rest)` | target / max rest |
| Note | `| free text` | always preserved |

Anything unrecognized inside a line lands in the set's `note`; whole lines that don't parse become note items and are reported to the caller — **input is never rejected, and nothing is silently dropped**.

## Repeat blocks

```
3x {            ← 3 rounds
4/3x {          ← per-group rounds, in group order (A=4, B=3, others resolve sparsely)
2x { | odd rounds favorite stroke      ← block note
  round 2: back and free               ← per-round note or stroke
  …
}
```

## Grammar (EBNF, abridged)

```ebnf
document   = { title | metadata | section | item | blank } ;
title      = "# " text ;
metadata   = key ":" text ;            (* before first content line *)
section    = "==" name [ ":" integer ] ;
item       = repeat-open | repeat-close | per-round | rest | note | set ;
repeat-open  = counts "x" "{" [ "|" text ] ;
counts       = integer { "/" integer } ;
repeat-close = "}" [ "|" text ] ;
per-round  = "round" selector ":" text ;
rest       = "rest" time [ "|" text ] ;
note       = ">" text ;
set        = [ integer "x" ] integer { descriptor } [ sendoff ] [ rest-tok ]
             { hint } [ "|" text ] ;
sendoff    = "@" ( time { "/" time } [ "+" ] | "Lane" ) ;
rest-tok   = "r" ( time | integer ( "s" | "m" ) ) ;
hint       = "(" text "rest" text ")" | "(+" time ")" | "(" segments ")" ;
segments   = integer descriptor { "/" integer descriptor } ;
time       = [ integer ] ":" digit digit | integer ;
```
