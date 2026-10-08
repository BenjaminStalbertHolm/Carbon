# Acceptance record (spec 20), milestone M11

Record of the thirteen acceptance tests of CARBON_SPEC.md section 20, checked against the code as of
2026-10-08 (branch claude/modest-wright-oc38zd). Results: PASS = every part is automated and passes;
PARTIAL = the automated part passes and a named part is not automated (the runner prints it as MANUAL);
FAIL = a check fails. This file lives at `tests/ACCEPTANCE.md`, the path spec 20 gives.

## How to run

| What | Command | Result shape |
|---|---|---|
| Acceptance runner (every headless test under tests/, the text check, spec tests 1 to 13) | `godot --headless --path . --script res://tests/acceptance/acceptance_runner.gd` | one PASS, FAIL or MANUAL line per spec test; `RECORD: tests/ACCEPTANCE.md found`; exit 0 only when every automatable test passes and this record exists |
| Full playthrough, loudness (spec test 11) | `godot --headless --path . --script res://tests/acceptance/test_full_loudness.gd` | `RESULT: PASS, 0 failure(s)` |
| Continue in the middle of Day 3 (spec test 12) | `godot --headless --path . --script res://tests/acceptance/test_continue_day3.gd` | `RESULT: PASS, 0 failure(s)` |
| Debug console (spec 21) | `godot --headless --path . --script res://tests/acceptance/test_debug_console.gd` | `RESULT: PASS, 0 failure(s)` |
| Text fidelity (spec test 13) | `python3 tools/check_text.py` | `TEXT FIDELITY: N checked, 0 failed` |
| Release strip (spec 21) | `GODOT=<godot> tests/acceptance/release_strip_check.sh [project_dir] [work_dir]` | PASS, FAIL or NOT RUN; exports the Linux preset in release mode (needs `~/.local/share/godot/export_templates/4.3.stable/linux_release.x86_64`) |

The runner finds the headless tests under `tests/` at run time (files named `test_*.gd`, `*_test.gd`
or `run_tests.gd` that extend SceneTree; shot scripts and the scene-based `psx_test.gd` are not
headless tests). Each runs as its own Godot process. The runner's spec table (`SPEC` in
`acceptance_runner.gd`) names the tests that count for each spec test.

## Current results (2026-10-08)

- Runner, run on 2026-10-08: all 23 headless test files and `tools/check_text.py` exit 0 with `RESULT: PASS`
  (the text check: 331 checked, 0 failed). Spec tests: 3 PASS (6, 10, 13), 10 MANUAL (1 to 5, 7 to 9, 11, 12),
  0 FAIL. The runner exits 0 when this file is present (`RECORD: tests/ACCEPTANCE.md found`).
- Text fidelity: `TEXT FIDELITY: 331 checked, 0 failed`.
- Release strip: **PASS**, run on 2026-10-08: the Linux export has 282 entries (74 compiled scripts), 0 hits
  for the 7 needles, and a binary identical to the stock release template. The debug directory is excluded
  from every preset in `export_presets.cfg` (commit b2992b3).
- Loudness playthrough (`test_full_loudness.gd`): 2539 playbacks judged by the checker, 0 violations,
  27 exempt (the 27 `tube_thunk` playbacks, one per canister arrival).

## The thirteen tests

| # | Test | Checked by | Result | Not covered |
|---|---|---|---|---|
| 1 | Compliant run | `unit/test_playthrough_compliant.gd` (Days 1 to 5 at logic level: memos, T-1 to T-4, batches, RO-2 to RO-5, desks 7 and 8, F4 off, F5 on, quota 8/12, RO-5 Desk 4 redacted); `unit/test_playthrough_day1.gd`; `unit/test_acceptance_logic.gd` (defaults); `endings/endings_test.gd` (Ending A sequence; `hall: the final shot reads 0413`) | PARTIAL | The final shot, the fixtures, the removed desks and Ending A as seen and heard. The compliant run drives DayDirector with the typewriter model, not the typewriter view. |
| 2 | Refusal run with carbons | `acceptance/test_refusal_carbons.gd` (Days 1 to 5 through DayDirector with four carbons kept: RO-2 entries carried into RO-4 as 08 to 11 and printed; J. ABEL and N. FERRAND face Desk 4 from Day 4, WEISS from Day 5; the refusal; the carbon stack to Ending C with `RECORD RESTORED` and the player's name only; the exit to Ending B on the same refusal); `endings/endings_test.gd` (refusal, Ending C with carbons, refused without carbons); `unit/test_acceptance_logic.gd` (Ending C lines, carbon count rule); `world/room_test.gd` (Ending C steps 4 and 5); `unit/test_logic.gd` (RO-2 carry-forward wording and counts) | PARTIAL | The carbon stack and the exit door on screen, and the Desk 7 figure turning to Desk 4 (manual). The memo lines of the run are not compared. The F-3 Q3 memo for a wrong answer is not run (the run gives the correct answer). |
| 3 | Refusal run without carbons | `acceptance/test_refusal_no_carbons.gd` (every carbon filed each day, none kept; the refusal; the carbon stack with no carbons does not start Ending C; the exit to Ending B; the duplicate hall sets Desk 4 to the player's name truncated to 14 characters, with a clerk at Desk 4 and the lamp on, on the real Hall C with the real EndingsPresentation); `endings/endings_test.gd` (refusal, exit unlock and Ending B, duplicate-hall timeout, no Ending C without carbons); `player/hooks_test.gd` (exit handle and typing lock hooks) | PARTIAL | Ending B and the duplicate hall seen on screen (the exit door, the fade, the name's pixels on the Desk 4 nameplate): manual. Found and fixed in this pass: the duplicate hall wrote the untruncated name (see Fixes below). |
| 4 | Mixed run for the Ending C list | `unit/test_acceptance_logic.gd` (lines `RECORD RESTORED`, `DOBRA, KASIMIR`, `J. ABEL`, next of kin, player name, in order; availability at 2 and 3 carbons; Desk 7 restored); `world/room_test.gd` (silence stops clerk typing, clock and key sounds; restore rebuilds desks) | PARTIAL | Silence after typing, heard and seen; the Desk 7 figure facing Desk 4 on screen. |
| 5 | Retired word | `unit/test_acceptance_logic.gd` (LANTERN in C-22 on Day 2; barred on Day 3 including N-3; THE becomes QUIET); `unit/test_typewriter.gd` and `typewriter/m5_test.gd` (typing the fond word jams, locks and X-outs; nothing before Day 3) | PARTIAL | The jam and the X-out seen and heard in the typing view. |
| 6 | Defaults | `unit/test_acceptance_logic.gd` (CLERK 0412, M. ALDER, QUIET, OTHER, the signature line, nameplate 0412, the Day 2 memo line) | PASS | The on-screen nameplate. The text itself is covered by test 13. |
| 7 | Day 5 substitution | `acceptance/test_day5_substitution.gd` (the refusal run to Day 5, then P-1D through the typewriter model with the Day 5 options: the form arrives with its carbon; the original shows H. VANCE for the first 8 typed characters and nothing after; with H. VANCE redacted every typed cell is a bar; the carbon shows exactly what was typed; the carbon goes to the carbon spot with the form); `acceptance/test_spec_extras.gd` (P-1D field 1 shows H. VANCE; the bar when VANCE is redacted; no substitution elsewhere) | PARTIAL | The letters, H. VANCE and the bars on screen, on the original and on the carbon (manual). Found and fixed in this pass: P-1D had no carbon (see Fixes below). |
| 8 | Unseen rule | `acceptance/test_apparition_unseen.gd` (Day 3 with RO-3 sent through DayDirector; the real Gaze and UnseenChanges with a fake camera, stepped at 1/60 s: the Day 1 chair change (D1-U1) applies; a 60 s stare at Desk 12, looked at in every frame, shows no figure; looking away, the figure appears at 1.5 s unseen out of the frustum; at 3.1 m it stays while unseen; while looked at it stays; within 3.0 m and unseen for 0.5 s it goes and the change is reverted; it never reappears); `unit/test_unseen.gd` (apply rule: 1.5 s, 2.0 m, the distance waiver; the twelve 9.3 ids and their triggers; the 6.0 s ghost trigger; Gaze frustum planes); `acceptance/test_wiring.gd` (in the real main scene: Gaze has the player's camera and tracks Desk 12; the unseen registry is bound to the hall; the Day 2 start applies D2-U1, the Desk 12 nameplate reads 0411) | PARTIAL | The 60 s stare and the look away with the player's camera in play (manual). The door silhouette (D4-U2) and the clock revert (D2-U2) have no automated test of their effects. |
| 9 | Ghost typing | `acceptance/test_ghost_look_away.gd` (real time: F-3 typed and sent through DayDirector; the real Gaze, UnseenChanges and GhostTyper with a fake camera; the ghost sheet loads after 1.5 s unseen (D3-U3); no key in the first 5.5 s away, the first at about 6.2 s; looking back stops it at 14 of 20 characters, with no key in the 2 s after; looking away for 6 s again resumes at the same character and completes `IS THIS HOW YOU TYPE`); `unit/test_unseen.gd` (6.0 s trigger, the stop when the typewriter is seen, resume at the same character, line order and end); `unit/test_typewriter.gd` (X-outs before the ghost line); `acceptance/test_wiring.gd` (the ghost typer watches Typewriter04 and holds the typewriter view's model; a ghost sheet placed on the typewriter loads into it) | PARTIAL | The look-away on Day 3 in play, with the player's camera and the typewriter on screen (manual). The pace of the ghost keys is not asserted (it comes from the cadence model). |
| 10 | Free mail | `unit/test_acceptance_logic.gd` (blank sheet with no task is a free sheet; sent to the removed store; back in the Day 3 canister; NO SUCH ADDRESSEE in red); `tube/m6_test.gd` | PASS | The stamp artwork (the word and colour are checked). |
| 11 | No startle audit | `acceptance/test_full_loudness.gd` (the playthrough: Days 1 to 5 through DayDirector, the typewriter model with its sound mapping, and the other sounds of the game through AudioDirector with the checker on; zero Rule A and B violations; details below); `unit/test_audio.gd` (34 files: Rule A and B; 4 problems, all documented exemptions: `tube_thunk` for all, and the attack only for `fixture_off`, `fixture_on`, `door_unlock`; 0 not exempt, and the checker's own rules); `unit/test_unseen.gd` (frustum planes); `world/room_test.gd` (no clerk key or clock tick after silence) | PARTIAL | The visual parts, pending: no object enters the frustum by appearing (Gaze is tested as planes, not as a rendered scene), and no clerk moves in view. Not in the playthrough: Ending A and the other endings' sequences (their sounds come from their own timers in `scripts/endings/`), the lamp, marker and stamp views as objects, and the clerks' and the clock's own scripts (their gains and sound names are used, their code is not run). |
| 12 | Save and continue | `unit/test_save.gd` (save, has_save, load, day 3 round trip); `acceptance/test_continue_day3.gd` (saves in the middle of Day 3 with a sheet on the read stack, a carbon on the carbon spot and a carbon on the read stack; quits to a new game; loads; continues with `DayDirector.begin_day`; checks the day, the inbox, the read stack, the read text, the carbons and their places are as at the save; Day 3 restarts at time 0 and its morning leaves the desk as it was); `acceptance/test_spec_extras.gd` (after a quit mid Day 3, the continue restarts Day 3 at time 0 with the Day 2 results intact) | PARTIAL | Continue from the title on a real window: the title's CONTINUE button, the fades and the world sync of `main.gd` `_on_continue`. Both headless tests use the logic path that `_on_continue` calls, and write a scratch save file, not the player's. |
| 13 | Text fidelity | `tools/check_text.py`: 331 checked, 0 failed | PASS | Nothing: the checker covers every string in `data/` against the spec text. |

## Test 11 in detail: `test_full_loudness.gd`

The test plays the compliant run of `test_playthrough_compliant.gd` through all five days, with the same
actions, and with the game's sound calls at the points where the game makes them:

- DayDirector runs the days: the timeline (one-second steps), canisters (tube whoosh and thunk on each
  arrival, from the `canister_arrived` signal), batches and orders, carbons, the lamp, and `start_next_day`.
- TypewriterModel takes every key. TypewriterSounds maps its events to AudioDirector as TypewriterView does:
  key clacks (player, and ghost at -20 dB), returns, bells, the platen ratchets, paper in and out, and the
  tube's send and departing canister. Ghost typing runs on Days 3 and 4 (the day's ghost lines on a free sheet).
- Other sounds, sent through AudioDirector with the gains and player flags of their scripts: stamps,
  the carbon stack (paper_shuffle), the lamp click, the clerks' key clacks and carriage returns
  (`ClerkBehaviour.KEY_DB`, `CR_DB`), the clock tick (`ClockBehaviour.TICK_DB`, once per second), the beds
  (room_tone, hum with the day's pitch and the lit fixtures, and the vent from Day 4).

The checker is on in the debug build. The test asserts that it judged playbacks (2539), that canisters
arrived (27), and that it found zero violations. Its 27 exempt playbacks are the `tube_thunk` ones, which
spec 11.1 excepts. It runs in about 2 s.

## Integration (wiring), now connected

The earlier findings (Gaze had no camera, the unseen registry was not bound, the day-start and end-of-day
changes did not run, the overlay was not opened, the positional sounds were not parented) are resolved by
commit cefc2ad. `scripts/main.gd` now calls `Gaze.set_camera`, `UnseenChanges.bind_hall`,
`AudioDirector.set_spatial_parent`, `Gaze.overlay_open`, `UnseenChanges.apply_day_start`, and
`UnseenChanges.flush_pending` (at the day end), and it restores the visuals on continue. `test_wiring.gd`
runs the real main scene into Day 2 and checks the camera, the Desk 12 tracking, the binding, the audio parent,
the listener, the ghost typer and the Day 2 nameplate. The record's tests 8 and 9 rely on it for the wiring.

## Debug console (spec 21) and what each command was checked by

The console is `scripts/debug/debug_console.gd`. F9 opens and closes it. It is added to the root by
`scripts/main.gd` only when `OS.is_debug_build()`, and frees itself unless `debug_guard.gd` says it
is a debug build. While open, the tree is paused, so the player and the day clock do not move while
a command is typed (QUESTION-72). Commands are in `scripts/debug/debug_commands.gd`.

| Command | Behaviour | Checked by |
|---|---|---|
| `day N` (1 to 5) | Starts a new game, gives Days 1 to N-1 the defaults below, runs each day's overnight resolution (`DayDirector.run_overnight`), then begins Day N. Closes open views, releases a held item, resets endings and clerk and clock silence, and syncs the clerks. | `test_debug_console.gd`: Day 3, 4 and 5 states (RO results, desks 7 and 8, desk 12 nameplate, desk 9, fixtures, quota 8, tray line, PLAYER_NAME CLERK 0412). |
| `set <var> <value>` | Sets a GameState variable or a dictionary key (dotted: `flags.x`, `accuracy.T-1`). Text keeps its spaces; `[..]` and `{..}` are parsed as JSON. It does not re-run any rule. | `test_debug_console.gd`: dotted flag, spaces, hyphen key, float, unknown variable, usage. |
| `skip` | Completes the active task with its output as it is, and types nothing. For a transcription the output is the task's sheet and carbon set. If a sheet of the task is out (in hand, on the typewriter, on the copyholder or on the read stack), it is sent with its current contents, after its carbon goes to the carbon spot as spec 7.7 removes it (not filed). If none is out, one sheet and carbon set is taken from the tray and sent blank. (QUESTION-71) | `test_debug_console.gd`: P-1 sent; a T-1 sheet with typed text sent as it is, carbon on the carbon spot, accuracy below 0.5; with no sheet out, a blank sheet from the tray, accuracy 0, carbon on the carbon spot, tray down by one; no task active. |
| `ending A`, `ending B`, `ending C` | Resets the endings controller, then starts A or B as RO-5 does (`DayDirector.ro5_sent`). C requires `carbons_kept_at_final` of at least 3, then refusal and a click on the carbon stack (seated). | `test_debug_console.gd`: C refused below 3; B sets refused; A sets the RO-5 flag; C starts at 3. |
| `gaze` | Toggles `Gaze.set_overlay`. | `test_debug_console.gd`: toggles on and off. |
| `changes` | Lists the pending, applied and reverted unseen change ids from `UnseenChanges.status()`. | `test_debug_console.gd`: three lines. |
| `audio_check` | Toggles the Rule A and B loudness logger (`AudioDirector.set_checker_enabled`). The checker is on by default in debug builds (QUESTION-69). It prints only violations (`AUDIO VIOLATION`); passing and exempt playbacks print nothing, and the counters are kept. | `test_debug_console.gd`: off then on. `test_full_loudness.gd` and `test_audio.gd` read the counters. |
| `tris` | Visible triangles under the hall (`Geo.triangle_count` over visible MeshInstance3D). The count depends on state. The budget is 20000. | `test_debug_console.gd`: within budget. `m2_hall_test.gd` (budget asserted). The count itself was not re-measured for this record. |
| anything else | `unknown command` | `test_debug_console.gd`. |

Console behaviour checked: F9 opens and closes it, the tree pauses and unpauses, a typed line runs and
returns its result (76 checks in `test_debug_console.gd`).

### Defaults of `day N` (debug only)

Days 1 to N-1 are given the state of a compliant run, as these defaults (`scripts/debug/debug_day_defaults.gd`, QUESTION-70):

- P-1: `tokens_set` true and every answer blank, so the tokens are the defaults (CLERK 0412,
  M. ALDER, QUIET, OTHER, signature matching).
- T-1 to T-4: accuracy 1.0. No transcription original or carbon is recreated, so no Day 2 or Day 3
  original comes back and no carbon is filed.
- S-1 and S-2: each page holds its batch's Correct column. S-4 approves application A (S-4 has no
  Correct column; the choice is the player's).
- RO-2 to RO-4: first impression PROCESSED; every listed entry redacted; nothing carried forward.
- F-3: Q1 `12`, Q2 `NO`, Q3 `NO`, Q4 blank.
- Filing carbons is a no-op, since none exist to file.

### Known effects of the debug commands

- `day N` and `skip` run the game's own save hook, so the debug save overwrites `user://save.json`
  (the SaveSystem autosaves on `day_started`).
- `ending C` clicks the carbon stack straight after the refusal, so Ending B's refusal timers may
  still be running and overlap C. Restart the day to clear it.
- `skip` leaves the carbon on the carbon spot, so overnight it counts as unfiled (spec 14.7).

## Release strip check (spec 21)

`tests/acceptance/release_strip_check.sh` exports the Linux preset in release mode and checks the
export. Needles: `debug_console`, `F9`, `debug_guard`, `debug_commands`, `debug_day_defaults`,
`debug_console.gd`, `scripts/debug`.

- Binary: compared with the stock release template. The export is byte-identical to the template, so
  it contains no game strings. The template itself has `F9` (the engine's key-name table), so a raw
  match on the binary would not mean anything.
- `.pck`: `tests/acceptance/pck_strings.py` reads the file table. File names are searched, and every
  compiled script (`.gdc`, zstd-compressed) is decompressed with the system libzstd and searched.
  Needles of six characters or more are searched in every entry. A two-letter needle is searched only
  in text and in the length-prefixed form Godot uses for strings, because `F9` occurs by chance in
  binary data. Positive controls: `F-3` and `res://data/corrections.json` are found in compiled game
  scripts. If libzstd is missing the check reports NOT RUN.
- Result, 2026-10-08: PASS (282 entries, 74 compiled scripts, 0 hits).

## Other notes

- The scene-based tests (endings, hooks, m3, room, m2) print many `ERROR: Parameter "m" is null` lines
  from the dummy renderer (`mesh_get_surface_count`). They pass. Not investigated.
- The file-level audio check (`test_audio.gd`) passes only because of the four documented exemptions in
  `scripts/audio/loudness_checker.gd`. They are listed in test 11.
- README.md still names `tests/acceptance/ACCEPTANCE.md`; it is outside the M11 files and was not changed.
