# Hei Feel Pass Design

Date: 2026-11-21
Status: approved 2026-11-21
Builds on: `2026-11-20-hei-player-controller-design.md`. Where the two disagree,
this document wins.

## Intent

The controller has Celeste's move logic, and the user wants to keep that logic.
It does not yet have the feel of `docs/references/hei-animation/`: big launches,
long hangs, and speed that carries from move to move. This pass closes that gap
by changing physics and controller rules, and adds wall kicks like the
trunk-to-trunk kicks in `jump reference 1.mp4`.

## Goals

- Every dash, in any direction, adds to Hei's current velocity.
- Speed survives in the air until the player chooses to stop by squatting.
- On the ground, speed bleeds slowly, so staying fast requires chaining moves.
- Speed can go above a soft limit and gets pulled back, as in Celeste.
- Jumps hang for about as long as they do in the clips.
- Wall kicks rebound with the speed Hei hit the wall at and refill the air dash.

## Non-goals

- Character model, poses, or animation. The capsule stays (user decided).
- Camera behavior. It keeps following Hei (user decided). The only camera edit is
  the FOV speed ratio described under Speed limits.
- Wall slide, grab, or a climbing state. Repeated wall kicks are allowed (user
  decided), and they are the only way to scale a wall.
- Audio, gamepad, new visual effects, and combat.

## Anti-goals

- Landing kills the speed that the air preserved.
- Floaty dashes. Arcs get longer, but the dash burst stays sharp.
- Reaching top speed by mashing dash on flat ground or by hopping.

## Constraints

- Godot 4.7, Jolt, GDScript, 120 physics ticks per second, keyboard and mouse.
- Keep the current input bindings, which are uncommitted in `project.godot`:
  left mouse is dash and Left Shift is squat. The original design's control table
  is out of date on these two.
- `levels/test_level.tscn` has uncommitted node ID changes. Edit that working
  copy and do not revert it.
- All new values are inspector exports, so they can be tuned while playing.

## Approaches

1. **Extend the current controller in two playable stages (chosen).** The user
   judges momentum and hang before wall kicks land, so a bad feel is easy to trace.
2. **Extend the current controller in one pass.** Same code and faster, but three
   feel changes land at once.
3. **Replace `move_and_slide` with a custom mover.** More control at walls and
   ledges, but it rewrites working code. At 60 m/s Hei moves 0.5 m per tick, which
   swept collision should handle. Revisit only if play shows speed being lost.

## Stage 1: Momentum, limits, and hang

### Additive dashes (user decided)

At dash start, store the current velocity as the **base**. During and after the
burst, velocity is `base + direction * dash_speed`.

- Moving forward at 25 m/s and dashing sideways at 20 m/s gives about 32 m/s
  diagonally. Dashing backward leaves 5 m/s forward.
- The full added speed stays after the burst, with no end-of-dash trim. Remove
  `end_dash_up_mult` and the trim in `_end_dash`.
- Re-aiming with Space mid-dash recomputes from the same base.
- **Plain dashes stop adding at `soft_speed` (user decided).** After the add,
  horizontal speed is limited to `max(soft_speed, horizontal speed before the dash)`.
  This covers air dashes, ground dashes, and the low slide. A dash at 50 m/s can bend
  Hei's path and keeps the 50, but does not add to it. Only supers, hypers, and
  wavedashes can build speed past `soft_speed`, and wall rebounds carry it onward.

*Builder-proposed calls, confirmed by the user at review:*

- **Vertical:** a flat dash keeps current vertical speed. If a dash's vertical
  direction opposes current vertical speed, the base's vertical speed becomes 0
  first, so an up-dash always rises and a down-dash always falls. Gravity stays
  off during the burst, as it is today.
- **Ground dashes:** the first ground dash after touching down adds its full
  speed. Further ground dashes before Hei next leaves the ground only raise speed
  along the dash direction to `dash_speed`. Without this, mashing dash reaches the
  ceiling in about 0.6 s.
- **Plain jump boost:** `jump_h_boost` cannot raise horizontal speed above
  `max_run + jump_h_boost`. With low drag, it would otherwise build speed by
  hopping.
- **Wavedash from a straight-down dash:** with WASD held at contact, add
  `_move * dash_speed * sqrt(0.5)` to the carried horizontal speed, then apply
  `slide_mult`. Without WASD it is a normal landing that keeps carried speed.
- **Ground squat-dash (low slide):** this counts as a ground dash. Horizontal
  velocity becomes `base + flat_direction * dash_speed * slide_mult`, so `slide_mult`
  scales only the added part. When the ground-dash add is already spent, it only
  raises speed along the dash direction to `dash_speed * slide_mult`.

Supers and hypers keep their existing formulas, using the new ceiling.

### Route balance (user decided at the Stage 1 play check)

This section overrides the 35 m/s plain-dash limit and the 21 m/s² air pull-back
stated elsewhere in this document. Harder routes now pay off:

- A dash adds only up to the current launch's limit: `dash_limit` 28 m/s on the
  ground and after a plain jump or super, `hyper_dash_limit` 42 after a hyper, and
  `wave_dash_limit` 50 after a hyper out of a wavedash. Landing resets it to 28.
  Speed already above the limit is kept, as before.
- A hyper out of a wavedash launches `wave_hyper_mult` (1.2) times faster.
- Air speed above `soft_speed` drains at `air_pull` (8 m/s²).
- One real dash press pays for one multiplied hyper (user decided). A hyper chained
  by holding dash launches at carried speed, with no multiplier and the plain dash limit.

### Speed limits (user decided)

- `soft_speed` is 35 m/s. Above it, horizontal speed is pulled back at
  `run_reduce * air_mult` (about 21 m/s²) in the air and `run_reduce` (33 m/s²) on
  the ground, whatever the input. When a stronger deceleration applies at the same
  time (slide friction, air brake, or braking against motion), it replaces the
  pull-back instead of stacking with it.
- `max_speed` becomes the hard horizontal ceiling at 60 m/s. It is required because
  additive dashes and multiplying hypers would otherwise outrun the pull-back.
- `max_rise` is 18 m/s and limits the upward speed a dash can produce. The uphill
  compensation in `_launch` is exempt, or fast hypers would be swallowed by ramps.
- The camera's FOV ratio uses `soft_speed` instead of `max_speed`, so FOV keeps its
  current range.

### Drag (user decided: minimal in air, slow bleed on ground)

| Situation | Air | Ground |
|---|---|---|
| Above `soft_speed` | Pull back at about 21 m/s² | Pull back at 33 m/s² |
| Up to `soft_speed`, WASD held | `air_drag` 1 m/s², steering as today | `ground_bleed` 10.8 m/s² toward run or dash-run speed |
| Up to `soft_speed`, no WASD | `air_drag` only | `ground_bleed` down to run speed, then stops at `run_accel` |
| WASD mostly opposite motion | Brakes as today | Accelerates toward input as today |
| Squat | Air brake | Slide friction, unchanged |

`ground_bleed` takes speed from 35 to dash-run speed (13.3 m/s) in about 2 s.
Above run speed on the ground, WASD steers using `_steer`, so turning does not
wait on the slower bleed. Below run speed, acceleration is unchanged.

*Builder's call:* releasing WASD at speed coasts instead of stopping, so a landing
never throws away carried speed. Squat is the quick stop, as the user specified.
Walking still stops crisply because the fast stop applies at or below run speed.

### Long hang (user decided)

Target: about 0.6 s to the top and 1.2 s in the air on a full jump, matching the
clips. Simulated at 120 Hz, the values below give a held jump of 4.6 m, 0.63 s to
apex, and 1.22 s of airtime. A tapped jump rises about 1.95 m.

Because gravity drops, the air brake's gravity multiplier rises so squat still
drops Hei hard.

### Tight slow jumps (user decided at the Stage 1 play check)

The long hang felt light and soft at low speed. Below `hang_start_speed`
(10.8 m/s), jumps use `tight_gravity` 70 and `tight_jump_speed` 15, which keeps
about the same height (4.7 m) with 0.46 s to apex and 0.88 s of airtime. Gravity
and plain-jump force blend smoothly to the long-hang values (36 and 12) at
`hang_full_speed` (21.7 m/s). Gravity follows current horizontal speed during
flight. The air brake keeps using the long-hang `gravity` as its base.

### Stage 1 values

| Export | Now | New |
|---|---|---|
| `gravity` | 75 | 36 |
| `jump_speed` | 8.75 | 12 |
| `max_fall` | 13.3 | 20 |
| `fast_max_fall` | 20 | 30 |
| `air_brake_decel` | 90 | 150 |
| `air_brake_gravity_mult` | 1.5 | 3 |
| `max_speed` | 35 | 60 |
| `soft_speed` | new | 35 |
| `max_rise` | new | 18 |
| `air_drag` | new | 1 |
| `ground_bleed` | new | 10.8 |
| `end_dash_up_mult` | 0.75 | removed |

These are starting points for the user to tune by playing.

### Stage 1 done means

- The headless suite passes, with tests updated only where this design
  intentionally changes behavior:
  `godot --headless --fixed-fps 120 --path . --script tests/test_player.gd`
- New checks cover: a sideways dash keeps forward speed, a straight-up dash keeps
  horizontal speed, an up-dash rises while falling, speed above `soft_speed` is
  pulled back with or without WASD and never exceeds `max_speed`, air speed up to
  `soft_speed` barely drops with no input, a no-WASD landing coasts instead of
  stopping, ground speed takes about 2 s to bleed, mashing ground dash does not build speed,
  a dash-and-hop loop cannot pass `soft_speed`, a sideways dash at 50 m/s keeps 50 m/s,
  a hyper can pass `soft_speed`,
  hopping does not build speed, and a full jump's airtime is about 1.2 s.
- **The user plays it and approves the feel before Stage 2 starts.**

## Stage 2: Wall kicks

### Behavior

- **Trigger:** Space, pressed or buffered, while airborne with no coyote time left
  and within `wall_kick_reach` of a wall. A floor or coyote jump takes priority.
- **Rebound (user decided):** outgoing speed along the wall normal is
  `max(impact_speed, wall_kick_speed)`. `impact_speed` is Hei's speed into the wall,
  measured before `move_and_slide` removes it and remembered for `wall_retain_time`.
  Speed along the wall carries through.
- **Rise:** vertical speed becomes `max(current, jump_speed)`, with the normal
  variable jump hold.
- **Refill (user decided):** a kick refills the air dash.
- **During a dash:** a kick can fire during an air dash and takes priority over the
  Space re-aim. The exception is a down-dash with squat held, where Space stays
  buffered for the hyper on landing.
- **Steering lock:** for `wall_kick_lock`, WASD cannot steer or accelerate Hei, so
  holding toward the wall does not cancel the rebound. Dash and squat still work.
- **Feedback:** emit `jumped(&"wall")`, which reuses the existing stretch.

- **Repeat kicks (user decided):** no limit. Any wall can be kicked any number of
  times, including the same wall twice in a row, so scaling a wall or circling a
  pillar with repeated kicks is allowed.

### Stage 2 values

| Export | Value | Source |
|---|---|---|
| `wall_kick_speed` | 10.8 m/s | Celeste WallJumpHSpeed 130 |
| `wall_kick_reach` | 0.25 m | Celeste WallJumpCheckDist 3 |
| `wall_kick_lock` | 0.16 s | Celeste WallJumpForceTime |
| `wall_retain_time` | 0.15 s | new, Celeste's 0.06 s is too tight in 3D |

### Test level

Add a wall-kick course reachable from the existing level: two parallel walls about
10 m apart and 20 m tall, plus a few offset pillars like the forest trunks. Keep all
existing geometry.

### Stage 2 done means

- The headless suite passes, with new checks for: rebound speed matches impact speed,
  a slow touch uses `wall_kick_speed`, along-wall speed carries, a kick refills the
  dash, holding toward the wall does not cancel the rebound, the same wall can be
  kicked repeatedly, alternating walls works, and a floor jump beats a wall kick.
- The user plays it and judges the feel against the references. Automated checks
  cannot verify feel.

## Left to the builder

Code structure inside `player.gd`, how wall proximity is tested, the exact course
layout, and how tests are organized.
