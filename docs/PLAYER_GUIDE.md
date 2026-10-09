<!-- Source: CARBON_SPEC.md §6.2–§6.4, §7.2, §7.4, §7.5, §12, §16.1–§16.3, §17. Update verbatim if those sections change. -->

# CARBON — Controls

## Controls

> Where each control works:

| Action | Binding | Context |
|---|---|---|
| Look | Mouse | Free view |
| Move | W A S D | Standing |
| Stand / sit | Space | Free view (sit: within 1.2 m of chair) |
| Interact / click | Left mouse | All |
| Put back held item / close read view | Right mouse | Free view / read view |
| Pan to copyholder | Hold right mouse | Typing view |
| Scroll document | Mouse wheel | Read view |
| Previous / next page or document | Left/Right arrows, A/D | Read view |
| Type | Character keys, Enter, Backspace, Up/Down | Typing view |
| Exit view / open menu | Esc | Esc exits a focus view first; in free view it opens the menu folder (§16.2) |

No rebinding.

## Sitting and standing

> While seated or standing:

- **SEATED:** camera at Desk 4 seated eye position. Mouse look: yaw clamped to ±110° from north, pitch clamped −60° to +40°. No translation.
- **STANDING:** press `Space` while seated and not in a focus view.
  - WASD move at 1.6 m/s, no running, no jumping, no crouching.
- **Return to SEATED:** press `Space` while within 1.2 m of Desk 4's chair, or left-click Desk 4's chair. Camera moves over 0.8 s to the seated pose, yaw north.
- Desk 4 interactions (all items in §5.4, typewriter, tube) only work while SEATED. Standing interactions: door handles (§8.13), Desk 4 chair.

## Views

> The three views:

1. **Free view** — normal first-person (seated or standing).
2. **Typing view** — entered by left-clicking the typewriter while seated. Camera tweens over 0.5 s to a fixed pose looking down at the loaded paper (paper fills ~70% of the vertical view; copyholder visible at left). Mouse cursor visible. Keyboard input goes to the typewriter (§7). Holding **right mouse button** tweens the camera over 0.3 s to a close-up of the copyholder; releasing tweens back. `Esc` exits to free view (paper stays loaded). If no paper is loaded, clicking the typewriter does nothing.
3. **Read view** — entered by left-clicking any document (inbox tray, read stack, carbon spot, notebook, a document held in hand). The 3D view stays rendered behind; a full-screen `CanvasLayer` shows the document (§6.5) centred, 86% of window height, with a 50% black dim behind it. Mouse cursor visible. Mouse wheel scrolls documents taller than the view. `Left`/`Right` arrows (or `A`/`D`) page between pages of a multi-page document or between documents in a stack. `Esc` or right-click closes read view.

## Interacting

> In free view and at the desk:

- **Cursor:** in free view the mouse is captured; the "pointer" is the screen centre. No crosshair is drawn.
- **Interactable highlight:** none. No outlines, no prompts.
- **Held item:** the player holds at most one item. A held document is shown as a small paper quad in the lower-right of the view (3D, attached to the camera). A held stamp or marker or fluid bottle is shown similarly. **Right-click in free view** returns the held item to its home position.

### Desk items

| Click | Result |
|---|---|
| Inbox tray (with documents) | Opens read view on the top unread item. Closing read view moves that item to the read stack. |
| Read stack | Opens read view on the stack (newest first). |
| Blank paper tray | Picks up one blank sheet. If a transcription task (T-1 to T-4) is the active task, picks up a **sheet + carbon set** instead (§8.5). |
| Typewriter while holding a sheet or form | Loads it into the typewriter (0.6 s animation: paper slides in, platen turns), then enters typing view. Only one paper can be loaded at a time; if one is loaded, the click enters typing view instead and the held item stays held. |
| Copyholder while holding a document | Clips it to the copyholder (replacing and returning any previous one to the read stack). |
| Copyholder (empty hand) | Opens read view on the clipped document. |
| Stamp on rack | Picks up that stamp (§8.1). |
| Marker | Picks up the marker (§8.2). |
| Correction fluid | Picks up the bottle (§7.6). |
| Tube receiver while holding a document | Sends it (§8.4). |
| Carbon spot | Opens read view on the carbon stack. |
| Top drawer | Opens (0.4 s slide 0.30 m south). Click again to close. Notebook clickable when open. |
| Lower drawer | Opens/closes as above. While open, clicking the carbon spot **files** all carbons (§8.5) instead of reading them. |
| Lamp | Ends the day if allowed (§13.5). Otherwise toggles nothing and plays the switch click only. |

- **Documents from the inbox and read stack can be picked up** with a click-and-hold of 0.4 s instead of a click (a click opens read view; a hold picks up). While holding a document, clicking the read stack puts it there.

## The typewriter

> While typing:

| Key | Action |
|---|---|
| `Enter` | Carriage return: carriage slides back to column 0 over 0.35 s (`carriage_return` sound), line +1. At line 53, `Enter` plays `key_jam` and does nothing. |
| `Backspace` | Moves the carriage back one column (min 0). **Does not erase.** Plays `backspace_click`. |
| `Up` / `Down` | Platen knob: line −1 / +1 (clamped 0–53). Plays `platen_ratchet`. Column unchanged. |
| `Left` / `Right` | Nothing. |
| `Tab` | Nothing. |
| `Esc` | Exit typing view. |

Letters `A–Z` (lowercase input is converted to uppercase), digits `0–9`, space, and `. , - ' / ? : ; ( ) & " !`.

- **Clicking a cell inside a field** (left-click on the paper in typing view) moves the carriage to that field's start, animating the carriage over 0.4 s with `platen_ratchet` for each line passed.
- Typing inside a field is the same as on blank paper, except the carriage cannot advance past the field's last cell: extra characters play `key_jam` and do nothing. `Enter` inside a form moves to the next field's start (in reading order); from the last field, `Enter` does nothing.

## Menus and settings

> In the menus:

- Selection: the hovered/selected option is prefixed with `> ` (the other lines are indented two spaces so text does not shift). Mouse hover or Up/Down; click or Enter activates.

### Title screen

- BEGIN
- CONTINUE — {DAYNAME}
- SETTINGS
- QUIT

### Menu folder

- RESUME
- SETTINGS
- QUIT TO TITLE
- QUIT TO DESKTOP

### Settings

Each line shows `NAME [VALUE]`.

| Setting | Values | Default |
|---|---|---|
| MOUSE SENSITIVITY | 0.1–2.0 step 0.1 | 0.6 |
| INVERT MOUSE Y | OFF / ON | OFF |
| MASTER VOLUME | 0–100 step 10 (`linear_to_db(v/100)`) | 80 |
| FULLSCREEN | OFF / ON | OFF |
| INTERNAL RESOLUTION | LOW (320×240) / HIGH (640×480) | LOW |
| DITHER | ON / OFF | ON |
| REDUCE FLICKER | OFF / ON | OFF |
| TEXT ASSIST | OFF / ON | OFF |
| BACK | — | — |

## Content note

> Shown at every launch, before the title screen:

THIS IS A GAME ABOUT RECORDS, ERASURE AND COMPLICITY.

IT CONTAINS NO SUDDEN FRIGHTS.

IT MAY BE UNSETTLING.

PRESS ANY KEY.

## Accessibility

> Accessibility options in the game:

Text assist overlay (§6.5); reduce flicker (§8.12); internal resolution HIGH (§4.1); dither toggle (§4.3); mouse sensitivity and invert Y (§16.3); no time pressure or reactions required; content note at launch (§16.1).
