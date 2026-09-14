# YatraCanvas UX and motion polish

Reviewed: 2026-09-14

This pass is a presentation-only refinement. It does not change backend
contracts, providers, persistence, migrations, or trip-planning rules.

## Audit before implementation

### High impact

- `[IMPLEMENTED]` Home and Explore already establish the strongest visual
  identity. Their layouts and imagery remain protected.
- `[PARTIAL]` Motion exists in isolated components, but route changes still mix
  default `MaterialPageRoute`, custom fades, and abrupt replacements.
- `[PARTIAL]` Home controls have ripple-free press compression, while planning
  cards and chips still rely on `InkWell`; tactile feedback and focus treatment
  are inconsistent.
- `[PARTIAL]` Trip creation exposes a button/linear progress state but lacks a
  contextual transition from completed setup into the discovery canvas.
- `[PARTIAL]` Map markers open a strong POI sheet, but the tapped marker does not
  remain visually selected while the sheet is active.

### Medium impact

- `[IMPLEMENTED]` Loading, empty, and safe product errors exist across the main
  flow; several compact busy states still use circular indicators.
- `[IMPLEMENTED]` Itinerary days preserve logical empty and REST days, but
  expansion and result replacement use mostly stock component motion.
- `[PARTIAL]` Bottom sheets use safe areas and draggable POI content; animation
  timing is not yet centralized across every sheet and dialog.

### Low impact

- Selection borders, icons, and checks do not all resolve with the same timing.
- Some cards animate color but not physical response, while others compress on
  press. Focus rings also vary by component family.
- A few older global Material defaults can still produce inappropriate splash
  feedback outside the locally themed planning shell.

## Design direction

1. Help Indian travellers build and understand a trip without feeling like
   they are completing a form.
2. Tone: premium, calm, playful only in direct response to user input.
3. Preserve the existing open mobile layouts and use the current hierarchy,
   imagery, cream-to-blue canvas, and compact bottom actions.
4. Keep HomeInter as the functional voice and Inria Serif only as an existing
   editorial accent; do not introduce a new type system.
5. Use solid working surfaces and reserve glass for floating navigation and map
   controls already designed for it.
6. Use 130 ms press feedback, 220 ms component morphs, 320 ms navigation, and a
   maximum 380 ms coordinated journey transition; respect reduced motion.
7. Signature differentiator: a restrained journey thread that connects setup,
   processing, routes, and map state rather than decorative AI motifs.

## Motion patterns

- Standard navigation: short fade plus 5.5% horizontal travel.
- Detail opening: fade plus a subtle scale from the lower visual plane.
- Modal action: native bottom-sheet movement with the existing 28 px surface.
- Major journey transition: slightly longer fade and vertical settling.
- Direct manipulation: compression to 0.98, visible selection border/check,
  quick recovery, no Material splash blob.

## Current scope

- `[IMPLEMENTED]` Shared durations, easing, reduced-motion handling, page
  transitions, and ripple-free press surfaces.
- `[IMPLEMENTED]` Contextual trip-create experience with destination imagery,
  an animated route thread, honest non-percentage status text, and a live-region
  announcement.
- `[IMPLEMENTED]` Selected map marker emphasis while its POI sheet is active.
- `[PARTIAL]` A later physical-device pass should tune camera movement, sheet
  snap positions, and performance on low-end Android hardware.

The supplied X post could not be fetched in this environment (public fetch was
forbidden and no connected browser was available). No unsupported claim is made
about its exact frames; the stated qualities in the product brief were used as
the interaction benchmark.
