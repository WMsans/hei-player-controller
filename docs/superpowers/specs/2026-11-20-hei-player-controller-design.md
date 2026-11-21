# Hei Player Controller Design

Date: 2026-11-20
Status: approved 2026-11-20

## Intent

Build a third-person 3D player controller that recreates the *feel* of Hei's
movement in `docs/references/hei-animation/Full Hei Animation.mp4`: fast
movement, powerful jumps, and full control in the air. Celeste's movement tech
(supers, hypers, wavedashes) is the closest existing model, so its numbers and
state logic are the starting point. Celeste64 is a cautionary reference: its
controls are considered bad, and it has no real wavedash.

The signature move is the **air brake**: launch at high speed, then hold squat
to kill the speed and drop quickly. It must reproduce the effect in
`jump reference 3.mp4` and `jump reference 4.mp4`.

## Goals

- Dash-run, super, hyper, wavedash, directional air dash, and air brake all work
  and chain into each other.
- Supers are easy to perform, because dash is held instead of timed.
- The first playable looks punchy: a juiced-up capsule, not a bare one.
- All feel values can be tuned in the inspector while the game runs.

## Non-goals

- Grab, climbing, or auto-grab (explicitly excluded by the user).
- Character model, rig, or animation. The capsule is the character for now.
- *Builder-proposed, not requested:* wall jumps, gamepad, audio, combat, moving
  platforms, menus. Add them only when asked.

## Anti-goals

- Controls that feel like Celeste64's: floaty dashes, or a fixed upward tilt on
  air dashes that the player did not choose.
- Free flight. Holding Shift in the air must never extend a dash.
- Losing momentum on landing, which would break chaining.

## Constraints

- Godot 4.7, Jolt physics, Forward+ (the existing project, otherwise empty).
- GDScript. The project has no C# setup.
- Keyboard and mouse only.

## Approaches

1. **One `CharacterBody3D` script with a state enum (chosen).** Mirrors Celeste's
   `Player.cs`. Godot handles collisions, slopes, and floor snapping. All feel
   logic and tunables stay in one readable file.
2. **Node or script per state.** Scales to many moves, but spreads super and
   wavedash logic across files, since those moves live in state handoffs.
3. **Custom shape-cast mover.** Exact control at high speed, far more code. Only
   worthwhile if option 1 demonstrably loses momentum on ledges or slopes. The
   movement logic could be kept and the mover swapped later.

The user picked option 1 because it allows the fastest feel tuning.

## Controls

| Key | Action |
|---|---|
| WASD | Move, relative to camera |
| Space | Jump; aims dash up in the air |
| Left Shift | Dash (hold to dash-run on the ground) |
| Left Ctrl | Squat; aims dash down; air brake when held in the air |
| Mouse | Orbit camera |
| Esc | Release mouse (click to recapture) |

## Behavior

### Dash aiming (user decided)

WASD sets the horizontal direction. Space aims up. Ctrl aims down. In the air,
Space aims up **whenever it is down**, including when still held from the jump
and when pressed mid-dash.

| Held with Shift | In the air | On the ground |
|---|---|---|
| WASD only | Flat dash | Dash-run; Space from here is a super |
| WASD + Space | Diagonal up | Jump into an up-diagonal air dash |
| WASD + Ctrl | Diagonal down; touching ground becomes a wavedash | Low slide; Space from here is a hyper |
| Space or Ctrl, no WASD | Straight up or down | Straight up, or a squat-dash in place |
| Nothing | Flat, toward facing | Same |

Space and Ctrl both down when a dash starts cancel into a flat dash.

**Exception (user decided):** during a down-dash with Ctrl held, Space does not
re-aim. It buffers the jump, which fires as a hyper on landing.

On the ground, Space pressed *after* a dash-run has started is a super, not an
up-aim. Space already down at the moment Shift is pressed takes the "WASD +
Space" row.

*Builder's calls:* pressing Space mid-air-dash re-aims the remaining burst
upward at the same speed. A hyper from a squat-dash in place launches along
facing.

### Air dash (user decided)

- Fixed burst of about 0.15 s. One per airtime, refilled on landing.
- Afterward Hei keeps momentum and falls normally, even if Shift is still held.
- If Shift is still held on landing, Hei enters the dash-run immediately at the
  carried speed, with no re-press.

### Dash-run

Holding Shift on the ground starts with the dash burst, then sustains the
dash-run speed while WASD is held. Releasing Shift or WASD returns to normal
movement, decelerating from the current speed. Ground dashes do not consume the
air dash.

### Super and hyper

- **Super:** Space during a ground dash-run. Horizontal speed becomes
  `max(current, super_jump_h)` along the movement direction, vertical
  `jump_speed`.
- **Hyper:** Space while squatting in a ground dash or slide. Horizontal speed
  becomes `max(current, super_jump_h) * hyper_h_mult`, vertical
  `jump_speed * hyper_v_mult`.
- **Wavedash:** a down-diagonal air dash that touches the ground becomes a slide
  at x1.2 speed and refills the dash. Space from that slide is a hyper.

### Momentum (user decided)

Moves never slow Hei down, and chains can build speed up to `max_speed`
(35 m/s), which caps every horizontal speed. On the ground, speed above
`dash_run_speed` bleeds off at `run_reduce`, so landing into a dash-run keeps the
carried speed briefly and rewards chaining quickly. Slides use `duck_friction`
instead.

### Air control

*Builder's call, since Celeste's 1D model does not translate directly:*

- Below run speed, accelerate toward the input at `run_accel * air_mult`.
- Above run speed, WASD **rotates** the velocity toward the input at
  `air_turn_rate` without losing speed, so a super can be steered. Speed bleeds
  slowly at `run_reduce * air_mult`.
- Input pointing mostly opposite the velocity (dot < -0.5) brakes instead.
- Near the apex, while Space is held, gravity is halved (Celeste's hang).
- Variable jump height: holding Space sustains upward speed for up to 0.2 s.

### Air brake (user decided)

Holding Ctrl in the air sharply reduces horizontal speed and makes Hei fall
faster, up to `fast_max_fall`. It does not apply during a dash burst. While
braking, WASD does not add horizontal speed. Pressing Shift while braking gives
a down-dash, so the brake flows straight into a wavedash.

The brake needs a **fresh Ctrl press in the air**. Ctrl held from the ground or
through a down-dash does nothing until released and pressed again, so hypers
keep their full speed.

### Slide and retrigger rules (builder's calls)

- **Slide:** lasts while Ctrl is held and steerable at `air_turn_rate`. Ctrl
  means control (user decided), so it stops Hei fairly quickly: `duck_friction`
  brings a wavedash slide to rest in about 0.3 s. A hyper still launches at
  `max(current, super_jump_h) * hyper_h_mult`, so the quick stop never weakens it.
  Releasing Ctrl goes to dash-run if Shift and WASD are held, otherwise normal
  movement. Running off a ledge keeps the speed and grants coyote time.
- **Wavedash trigger:** ground contact during a down-dash burst, or within 0.1 s
  after it ends. A straight-down dash becomes a slide only if WASD is held at
  contact, in that direction. Otherwise it is a normal landing with a dash refill.
- **Ground retrigger:** a new burst and hit-freeze require a fresh Shift press,
  with a 0.2 s cooldown (Celeste's DashCooldown). Releasing and re-pressing WASD
  with Shift held resumes dash-run with no burst.
- **Shift + Space from the ground** is an air dash and consumes the air dash.

### Forgiveness timers

Coyote time 0.1 s. Jump buffer 0.1 s. Dash buffer 0.08 s.

## Starting values

Celeste's values converted at **12 px = 1 m**, which makes its character about
capsule height. These are starting points for tuning.

| Export | Value | Celeste source |
|---|---|---|
| `max_run` | 7.5 m/s | MaxRun 90 |
| `run_accel` | 83 m/s² | RunAccel 1000 |
| `run_reduce` | 33 m/s² | RunReduce 400 |
| `air_mult` | 0.65 | AirMult |
| `gravity` | 75 m/s² | Gravity 900 |
| `max_fall` | 13.3 m/s | MaxFall 160 |
| `fast_max_fall` | 20 m/s | FastMaxFall 240 |
| `half_grav_threshold` | 3.3 m/s | HalfGravThreshold 40 |
| `jump_speed` | 8.75 m/s | JumpSpeed 105 |
| `jump_h_boost` | 3.3 m/s | JumpHBoost 40 |
| `var_jump_time` | 0.2 s | VarJumpTime |
| `dash_speed` | 20 m/s | DashSpeed 240 |
| `dash_run_speed` | 13.3 m/s | EndDashSpeed 160 |
| `dash_time` | 0.15 s | DashTime |
| `end_dash_up_mult` | 0.75 | EndDashUpMult |
| `super_jump_h` | 21.7 m/s | SuperJumpH 260 |
| `hyper_h_mult` | 1.25 | DuckSuperJumpXMult |
| `hyper_v_mult` | 0.5 | DuckSuperJumpYMult |
| `slide_mult` | 1.2 | DodgeSlideSpeedMult |
| `duck_friction` | 80 m/s² | new (Celeste's DuckFriction 500 is 41.7, too soft) |
| `max_speed` | 35 m/s | new |
| `air_turn_rate` | 270°/s | new |
| `air_brake_decel` | 90 m/s² (27 m/s to rest in 0.3 s) | new |
| `air_brake_gravity_mult` | 1.5 | new |

As in Celeste, a dash never slows Hei if they are already moving faster in the
dash direction.

## Presentation (user decided: juiced-up capsule)

- Capsule mesh with squash and stretch: stretch on jump (Celeste uses 0.6 x 1.4),
  squash on landing, recovering quickly. Visual only, never the collider.
- Dash trail.
- 0.05 s hit-freeze on dash start.
- Third-person orbit camera whose FOV widens with speed.
- The capsule visibly differs when the dash is spent, so the player can read it.

## Test level

One scene with long runways, gaps, and tall ledges, sized so that supers, hypers,
wavedashes, and the air brake all have room. Set as the project's main scene.

## Done means

- A scripted headless check drives the controller and asserts: a super exceeds
  dash-run speed, a hyper travels faster and lower than a super, a wavedash
  refills the dash, one air dash per airtime, Shift held in the air does not
  extend the dash, the air brake stops horizontal travel faster than no input,
  Ctrl held through a hyper does not brake, an early Space in a down-dash fires
  a hyper on landing, and chained speed never exceeds `max_speed`.
- The user plays it and judges the feel against the references. Automated checks
  cannot verify feel.

## Left to the builder

File layout, how to implement the hit-freeze, trail technique, camera
collision handling, physics tick rate and interpolation, and test-level layout.
