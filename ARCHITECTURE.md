# CARBON architecture (implementation reference)

The spec is CARBON_SPEC.md and is the single source of truth. This file says where
each rule lives in code, so that every milestone builds on the same APIs.

## Layers

1. **Content** (data/*.json). Every player-visible string, copied exactly from the
   spec (section 3.4). Loaded through scripts/logic/content.gd. The fidelity checker
   is tools/check_text.py (spec test 13).
2. **Pure logic** (scripts/logic/*.gd, no nodes). Preloaded with
   `const X := preload("res://scripts/logic/x.gd")`. Static functions, or RefCounted
   objects that take their RNG and clock as arguments. Unit tests live in
   tests/unit/*.gd and run headless.
3. **State and flow** (scripts/autoload/*.gd, autoloads). GameState holds every
   persistent variable (spec 14.2). DayDirector runs the day flow, the tasks, the
   canisters, the morning memos, the end of shift and the overnight resolution
   (spec 13, 14.7). TextTokens does token substitution and bar spans.
4. **Presentation** (scripts/world, scripts/doc, scripts/ui, scripts/player, ...).
   Nodes and visuals. They listen to DayDirector signals, call DayDirector and
   TypewriterModel methods, and read GameState. They hold no game rules.

## Key files and APIs

### Logic
- `text_norm.gd`: `normalise(s)`, `sanitize_name(raw)`, `title_case(s)`,
  `first_part(s)`, `accuracy(typed, source)` (spec 7.8, 14.1).
- `levenshtein.gd`: `distance(a, b)`.
- `doc_model.gd`: the document model (see its header). Functions: `new_doc`,
  `new_page`, `cell(page, line, col)`, `make_glyph`, `write_glyph`, `whiteout`,
  `cell_char`, `has_glyph`, `typed_text(page)`, `field_value(page, field)`,
  `field_values(page)`, `extract_fields`, `wrap_text`, `add_printed_lines`,
  `set_paragraphs`, `add_bar`, `add_stamp`, `first_stamp_result`, `build_doc(...)`,
  `make_carbon(original, id)`. Layout constants: COLS 64, LINES 54, PAGE_W 768,
  PAGE_H 1088, LEFT 40, TOP 48, COL_W 10.8, LINE_H 18.6, HAND_LEFT 56, HAND_LINE_H 34.
- `redaction.gd`: `find_entity_spans(text, entities, subst)`, `find_word_spans`,
  `coverage(bars, x0, x1)`, `entry_redacted(page, name)`, `name_extent(page, name)`.
  COVER_THRESHOLD = 0.8 (spec 8.2).
- `corrections.gd`: `apply_all(page, corrections, rng)` (spec 8.6).
- `morning_memo.gd`: `build(day, inputs, morning_strings)` returns memo lines
  (spec 14.6, 14.9 to 14.11).
- `clock_math.gd`: `time_after_task(k, n)`, `hand_angles("HH:MM")`.
- `fond_word.gd`: `compute(raw, reserved_words)`, `reserved_words_from(lines)` (spec 14.1).
- `cadence_model.gd`: `record(ch, now_ms)`, `delay_for(prev, ch, rng)`, intervals,
  bigram, return mean (spec 10.1, 10.2). ENTER is the "⏎" character.
- `typewriter_model.gd`: `TypewriterModel.new(cadence, rng)`. `load_sheet`,
  `unload`, `type_key(ch, now)`, `enter(now)`, `backspace(now)`, `platen(delta)`,
  `click_cell(line, col, now)`, `fluid_at(line, col, now)`, `enqueue_ghost_text`,
  `enqueue_ghost_x`, `ghost_set_running(on, now)`, `tick(now)`,
  `take_events()`. It emits events: key, jam, bell, carriage, return, ratchet,
  backspace, fluid. Times are ms from any clock the caller chooses.

### State and flow
- `GameState` (autoload): all variables, `docs` (id -> document), `loc` (location
  lists), `new_game(seed)`, `place(id, location)`, `unplace`, `location_of`,
  `remove_doc`, `add_doc(doc, location)`, `to_dict()`, `from_dict(d)`. Locations:
  inbox, read_stack, carbon_spot, drawer, removed, attached (QUESTION-8: the most
recent item is last in each stack array; the read view opens on the last element), plus the
  single-item slots copyholder, typewriter and hand.
- `TextTokens` (autoload): `token_values()`, `substitute(text)`,
  `subst_callable()`, `bar_spans(line_text)`.
- `DayDirector` (autoload): `start_new_game(seed)`, `begin_day(day)`,
  `start_next_day()` (overnight then begin_day), `tick(dt)` (virtual time),
  `take_blank_sheet()`, `paper_removed(sheet_id)`, `send_document(id)`,
  `stamp_document(id, page, result, x, y, rot, a)`, `file_carbons()`,
  `click_lamp()`, `end_day()`, `ghost_line_finished(day, index)`,
  `apply_ghost_sheet(day)`, `instantiate(doc_id)`.
  Signals: day_started, bell_rung, clock_set(time, anim_s), canister_arrived(ids),
  task_activated(id), task_completed(id), task_sent(id) (UnseenChanges listens),
  doc_sent(id), ghost_memo_arrived, ghost_sheet_due(day), end_of_shift_arrived,
  lamp_click, day_ended(day), ro5_sent(desk4_redacted).

### Timing decisions (from QUESTIONS.md, decided by the question agent)
- QUESTION-5: after the last task of a day the clock shows 17:00, then 16:58 when the
  End of Shift memo arrives. Both animate over 2.0 s.
- QUESTION-6: on Days 3 and 4 the End of Shift trigger of spec 14.9/14.10 replaces
  the 5.0 s rule of spec 13.4. The 120 s fallback still applies.

## Conventions
- No `class_name` in new scripts. Use `preload`. Reason: the global class cache is
  rebuilt only on import, and parallel agents must not run `--import`.
- Player-visible text lives only in data/*.json. Templates such as "{X}" are filled
  by logic.
- Tests: `godot --headless --path . --script res://tests/unit/<name>.gd`. Exit 0
  means every check passed.
- Dev-only scenes live under tests/ and are excluded from export
  (export_presets.cfg exclude_filter "tests/*").
- Shaders: shaders/psx_spatial.gdshader (every 3D mesh), shaders/psx_post.gdshader.
  The snap grid is the project shader global `psx_snap_grid`.
