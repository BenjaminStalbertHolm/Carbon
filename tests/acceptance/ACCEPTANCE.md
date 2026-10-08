# Acceptance record (spec 20), milestone M11

Record of the thirteen acceptance tests of CARBON_SPEC.md section 20, checked against the code
as of 2026-10-08. Results: PASS = every part is automated and passes; PARTIAL = the automated
part passes and a named part is not automated (the runner prints it as MANUAL); FAIL = a check fails.

## How to run

| What | Command | Result shape |
|---|---|---|
| Acceptance runner (all headless tests, text check, spec 1 to 13) | `godot --headless --path . --script res://tests/acceptance/acceptance_runner.gd` | one PASS, FAIL or MANUAL line per spec test; exit 0 only when every automatable test passes |
| Text fidelity (spec test 13) | `python3 tools/check_text.py` | `TEXT FIDELITY: N checked, 0 failed` |
| Release strip (spec 21) | `GODOT=<godot> tests/acceptance/release_strip_check.sh [project_dir] [work_dir]` | PASS, FAIL or NOT RUN; exports the Linux preset in release mode (needs `~/.local/share/godot/export_templates/4.3.stable/linux_release.x86_64`) |

The runner finds the headless tests under `tests/` at run time (files named `test_*.gd`, `*_test.gd`
or `run_tests.gd` that extend SceneTree; shot scripts and the scene-based `psx_test.gd` are not
headless tests). Each runs as its own Godot process.

## Current results (2026-10-08)

- Runner: **PASS** (exit 0). 19 headless test files and `tools/check_text.py` all pass. Spec tests:
  3 PASS, 10 MANUAL (PARTIAL in the table below), 0 FAIL.
- Text fidelity: `TEXT FIDELITY: 331 checked, 0 failed`.
- Release strip: **FAIL on the repository as it stands**. The Linux preset in `export_presets.cfg`
  excludes only `tests/*`, so the eight `scripts/debug/` entries are in the `.pck`. This file is
  outside the M11 brief and was not changed. The fix is one line for the lead: add `scripts/debug/*`
  to `exclude_filter` in the Linux preset (and the Windows and macOS presets). Checked on a scratch
  copy with only that change: **PASS** (282 entries, 0 hits; the 74 compiled scripts contain none of
  the needles; the binary is byte-identical to the stock release template).

## The thirteen tests

| # | Test | Checked by | Result | Not covered |
|---|---|---|---|---|
| 1 | Compliant run | `unit/test_playthrough_compliant.gd` (Days 1 to 5 at logic level: memos, T-1 to T-4, batches, RO-2 to RO-5, desks 7 and 8, F4 off, F5 on, quota 8/12, RO-5 Desk 4 redacted); `unit/test_playthrough_day1.gd`; `unit/test_acceptance_logic.gd` (defaults); `endings/endings_test.gd` (Ending A sequence; `hall: the final shot reads 0413`) | PARTIAL | The final shot, the fixtures, the removed desks and Ending A as seen and heard. The compliant run drives DayDirector with the typewriter model, not the typewriter view. |
| 2 | Refusal run with carbons | `endings/endings_test.gd` (refusal, Ending C with carbons, refused without carbons); `unit/test_acceptance_logic.gd` (Ending C lines, carbon count rule); `world/room_test.gd` (Ending C steps 4 and 5); `unit/test_logic.gd` (RO-2 carry-forward wording and counts) | PARTIAL | The RO-4 rows 08 to 11 for carried RO-2 entries are not asserted by any test. The F-3 Q3 memo for a wrong answer is not run (the compliant run gives the correct answer). The carbon stack and the Desk 7 figure turning, on screen. |
| 3 | Refusal run without carbons | `endings/endings_test.gd` (refusal, exit unlock and Ending B, duplicate-hall timeout, no Ending C without carbons); `player/hooks_test.gd` (exit handle and typing lock hooks) | PARTIAL | Ending B seen on screen; the duplicate hall showing the typed name at Desk 4. |
| 4 | Mixed run for the Ending C list | `unit/test_acceptance_logic.gd` (lines `RECORD RESTORED`, `DOBRA, KASIMIR`, `J. ABEL`, next of kin, player name, in order; availability at 2 and 3 carbons; Desk 7 restored); `world/room_test.gd` (silence stops clerk typing, clock and key sounds; restore rebuilds desks) | PARTIAL | Silence after typing, heard and seen; the Desk 7 figure facing Desk 4 on screen. |
| 5 | Retired word | `unit/test_acceptance_logic.gd` (LANTERN in C-22 on Day 2; barred on Day 3 including N-3; THE becomes QUIET); `unit/test_typewriter.gd` and `typewriter/m5_test.gd` (typing the fond word jams, locks and X-outs; nothing before Day 3) | PARTIAL | The jam and the X-out seen and heard in the typing view. |
| 6 | Defaults | `unit/test_acceptance_logic.gd` (CLERK 0412, M. ALDER, QUIET, OTHER, the signature line, nameplate 0412, the Day 2 memo line) | PASS | The on-screen nameplate. The text itself is covered by test 13. |
| 7 | Day 5 substitution | `acceptance/test_spec_extras.gd` (P-1D field 1 shows H. VANCE; the bar when VANCE is redacted; no substitution elsewhere) | PARTIAL | The carbon showing the typed name, and the original on screen. |
| 8 | Unseen rule | `unit/test_unseen.gd` (apply rule: 1.5 s, 2.0 m, the distance waiver; the twelve 9.3 ids and their triggers; the 6.0 s ghost trigger; Gaze frustum planes) | PARTIAL | The Desk 12 apparition hide rule (D3-U1), the door silhouette (D4-U2) and the clock revert (D2-U2) have no test of their effects. In the running game nothing applies: see the wiring finding below. The 60 s stare, in play. |
| 9 | Ghost typing | `unit/test_unseen.gd` (6.0 s trigger, the stop when the typewriter is seen, resume at the same character, line order and end); `unit/test_typewriter.gd` (X-outs before the ghost line) | PARTIAL | The look-away on Day 3 in play. Same wiring gap as test 8. |
| 10 | Free mail | `unit/test_acceptance_logic.gd` (blank sheet with no task is a free sheet; sent to the removed store; back in the Day 3 canister; NO SUCH ADDRESSEE in red); `tube/m6_test.gd` | PASS | The stamp artwork (the word and colour are checked). |
| 11 | No startle audit | `unit/test_audio.gd` (34 files: Rule A and B; 4 problems, all documented exemptions: `tube_thunk` for all, and the attack only for `fixture_off`, `fixture_on`, `door_unlock`; 0 not exempt); `unit/test_unseen.gd` (frustum planes); `world/room_test.gd` (no clerk key or clock tick after silence) | PARTIAL | The zero-violation result over a full playthrough: no test plays a day with the checker on. "No object enters the frustum by appearing" depends on Gaze, which is not wired in the game. |
| 12 | Save and continue | `unit/test_save.gd` (save, has_save, load, day 3 round trip); `acceptance/test_spec_extras.gd` (after a quit mid Day 3, the continue restarts Day 3 at time 0 with the Day 2 results intact) | PARTIAL | Continue from the title on a real window (`main.gd` `_on_continue`). The check writes and then deletes `user://save.json`. |
| 13 | Text fidelity | `tools/check_text.py`: 331 checked, 0 failed | PASS | Nothing: the checker covers every string in `data/` against the spec text. |

## Integration findings (blocking for tests 8, 9, 11 in play)

These are outside the M11 brief (main.gd got only the debug block). They were found by grep and
checked again at the end of this run:

- `Gaze.set_camera` is never called, so Gaze computes nothing in the game.
- `UnseenChanges.bind_hall` is never called, so no hall node is tracked.
- `UnseenChanges.apply_day_start` and `flush_pending` are never called, so the day-start changes
  (D2-U1, D5-U1) and the end-of-day flush do not run. The `day N` command calls `apply_day_start`
  for the day it starts, which the game flow does not do.
- `Gaze.overlay_open` is never called, so the read view and typing view do not hide the world from Gaze.
- `AudioDirector.set_spatial_parent` is never called, so the positional sounds are not parented to
  the 3D world of the pipeline's SubViewport.

## Debug console (spec 21) and what each command was checked by

The console is `scripts/debug/debug_console.gd`. F9 opens and closes it. It is added to the root by
`scripts/main.gd` only when `OS.is_debug_build()`, and frees itself unless `debug_guard.gd` says it
is a debug build. While open, the tree is paused, so the player and the day clock do not move while
a command is typed. Commands are in `scripts/debug/debug_commands.gd`.

| Command | Behaviour | Checked by |
|---|---|---|
| `day N` (1 to 5) | Starts a new game, gives Days 1 to N-1 the defaults below, runs each day's overnight resolution (`DayDirector.run_overnight`), then begins Day N. Closes open views, releases a held item, resets endings and clerk and clock silence, and syncs the clerks. | `test_debug_console.gd`: Day 3, 4 and 5 states (RO results, desks 7 and 8, desk 12 nameplate, desk 9, fixtures, quota 8, tray line, PLAYER_NAME CLERK 0412). |
| `set <var> <value>` | Sets a GameState variable or a dictionary key (dotted: `flags.x`, `accuracy.T-1`). Text keeps its spaces; `[..]` and `{..}` are parsed as JSON. It does not re-run any rule. | `test_debug_console.gd`: dotted flag, spaces, hyphen key, float, unknown variable, usage. |
| `skip` | Completes the active task with its output as-is. For a transcription: takes a blank sheet, copies the source text in (tokens substituted, as DayDirector scores it), sends it. The sheet's carbon goes to the carbon spot and is not filed. | `test_debug_console.gd`: P-1 sent, T-1 sent with accuracy 1.000, no task active. |
| `ending A`, `ending B`, `ending C` | Resets the endings controller, then starts A or B as RO-5 does (`DayDirector.ro5_sent`). C requires `carbons_kept_at_final` of at least 3, then refusal and a click on the carbon stack (seated). | `test_debug_console.gd`: C refused below 3; B sets refused; A sets the RO-5 flag; C starts at 3. |
| `gaze` | Toggles `Gaze.set_overlay`. The overlay lists tracked nodes, so it is empty until Gaze is wired (see findings). | `test_debug_console.gd`: toggles on and off. |
| `changes` | Lists the pending, applied and reverted unseen change ids from `UnseenChanges.status()`. | `test_debug_console.gd`: three lines. |
| `audio_check` | Toggles the Rule A and B loudness logger (`AudioDirector.set_checker_enabled`). The checker is enabled by default in debug builds (`loudness_checker.gd`), so the first press turns it off. | `test_debug_console.gd`: off then on. |
| `tris` | Visible triangles under the hall (`Geo.triangle_count` over visible MeshInstance3D). The count depends on state: 19674 in the fresh hall (`m2_hall_test.gd`), 19646 after `day 3` (scratch visual run), 16206 after the console test sequence (Ending A and C had started). The budget is 20000, so the fresh hall is 326 under it. | `test_debug_console.gd`: within budget; `m2_hall_test.gd` (241 checks, budget asserted). |
| anything else | `unknown command` | `test_debug_console.gd`. |

Console behaviour checked: F9 opens and closes it, the tree pauses and unpauses, a typed line runs and
returns its result. Visual check: one screenshot under Xvfb with the real main scene (scratch, not in
the repository) shows the panel at the bottom, the result lines and the input line.

### Defaults of `day N` (debug only)

Days 1 to N-1 are given the state of a compliant run, as these defaults:

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
- Result on the repository as it stands: FAIL (the debug directory is not excluded from the export).
  With `scripts/debug/*` added to the Linux preset's `exclude_filter` (scratch copy): PASS.

## Other notes

- The scene-based tests (endings, hooks, m3, room, m2) print around a thousand `ERROR: Parameter "m"
  is null` lines from the dummy renderer (`mesh_get_surface_count`). They pass. Not investigated.
- The file-level audio check passes only because of the four documented exemptions in
  `scripts/audio/loudness_checker.gd`. They are the audio agent's decisions and are listed in test 11.
