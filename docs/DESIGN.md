# Design

The look in one line: soft raised and pressed-in surfaces on a warm
off-white ground by day, charcoal by night, with the sport's colour used
almost nowhere. The source of truth is `PickleBall/DesignSystem/CourtTheme.swift`.

## Rules

1. **Sport colour appears in exactly two places.** The selected tab and the
   active page dot. Pickleball is yellow `#FFFC00`, padel is blue `#0EADFF`.
   It never goes on buttons, the sport switch, Start match, text or charts.
2. **Buttons don't have to match each other.** Each screen uses what suits
   it. Only a few pieces share the signature look: the court on Home, the tab
   bar and the sport switch pill. Every button must be readable in light and
   dark.
3. **Light and dark follow the iPhone.** Use the `Court.*` colours (they adapt
   on their own) instead of fixed colours. Don't force a colour scheme on a
   pushed screen. Full-screen dark experiences are the exception: the live
   scoreboard, following a live match, Replays, Watch performance and the
   season recap.
4. **Glass is opt-in.** Settings → Appearance → Glass swaps the solid
   surfaces for frosted ones. Standard is the default.
5. **Never use the word "Snap"** anywhere: app, code, store text or web.

## Tokens

| Token | Day | Night | Use |
|---|---|---|---|
| `Court.ground` | `#ECECE8` | `#1C1D1F` | Page background |
| `Court.raised` | `#F6F6F3` | `#26282B` | Cards, buttons, pills, list rows |
| `Court.plate` | `#F3F3EF` | `#2A2C2F` | The court frame |
| `Court.sunken` | `#E2E2DD` | `#17181A` | Court boxes, fields, wells |
| `Court.pressed` | `#E6E6E1` | `#1F2023` | Selected tile at night |
| `Court.text` | `#161616` | `#F2F2F0` | Text and icons |
| `Court.muted` | `#3B3B39` | `#C9CACB` | Secondary text, hints |
| `Court.dim` | `#4A4A47` | `#A9AAAB` | Small mono labels ("HOME") |
| `Court.dotOff` | `#C4C4BF` | `#4A4C50` | Inactive page dot |
| `Court.onAccent` | `#111111` | `#111111` | Icon on a solid sport-colour tile |

Active page dot: the text colour for pickleball by day (yellow vanishes on
the light ground); the sport colour otherwise.

**Shadows** (SwiftUI radius, about half the mockups' CSS blur):

- Raised: dark `rgba(70,70,60,.16)` at 5,7 (r7), plus white `.95` at −4,−4 (r5)
- Sunken: inner shadows at `.20` and white `.90`
- Court: drop at 12,18 (r14), `rgba(60,60,50,.18)`
- Night: dark is black `.55–.60`, light is white `.05–.06`

## Metrics

- **Court plate:** full width minus 12pt each side, 380pt tall, 12pt padding,
  12pt gaps, radius 34. Boxes have radius 22. The kitchen (pickleball, by the
  net) and the back court (padel, away from the net) are 100pt tall. The far
  half is mirrored 6pt above the net and fades from 85% to 0 over 136pt.
- **Header:** an 11pt mono label (tracking 1.8), then a 38pt semibold title
  (tracking −1.1). The switch pill is 44pt tall and fully rounded.
- **Tab bar:** five 56×56 tiles, radius 18, centred with 8pt gaps, 26pt
  from the screen's bottom edge (14pt on iPhones with a Home button), icons about 24pt.
  - Selected by day: solid sport colour with a `#111111` icon.
  - Selected at night: pressed in, with a 3pt sport-colour line along the
    inside bottom edge.
  - Me shows your photo or a neutral silhouette, with no ring.
- **Type:** SF Pro for text, SF Mono for labels.

## Helpers

| Modifier | What it does |
|---|---|
| `.courtGround()` | Page background behind the safe areas |
| `.courtRaised(cornerRadius:)` / `.courtRaisedCapsule()` | Raised surface (frosted in Glass) |
| `.courtSunken(cornerRadius:)` / `.courtField()` | Pressed-in well or field |
| `.courtList()` + `.courtRows()` | Lists on the ground, rows on the raised surface |
| `.courtEyebrow()` | The small mono label |
| `.courtBigButton()` | Big soft raised button (Start match) |
