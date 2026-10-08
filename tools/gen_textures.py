"""Generate every texture listed in spec section 5.7 into assets/textures/.

Run from any directory:
    python3 tools/gen_textures.py

Determinism: every file draws its noise from its own RNG, seeded from
(412, file name), so the output does not depend on generation order.

Choices the spec leaves open (internal, not player-visible in content):
- "Value noise" is one random offset per pixel, applied equally to R, G and B.
- Noise is uniform in [-amp, +amp].
- Row/column positions for "every 16 px" and "every 9 px" start at 0.
"""

from __future__ import annotations

import zlib
from pathlib import Path

import numpy as np
from PIL import Image

SEED = 412
ROOT = Path(__file__).resolve().parent.parent
OUT_DIR = ROOT / "assets" / "textures"

# sRGB colours from spec section 5.2.
FLOOR_A = "#7A7464"
FLOOR_B = "#6B6555"
WALL_UPPER = "#B7B39A"
WALL_LOWER = "#5B6650"
CEILING_TILE = "#C9C6B5"
CEILING_GRID = "#8E8B7B"
DESK_TOP = "#4E5A48"
DESK_STEEL = "#5E6B5A"
CHAIR_WOOD = "#6A4E36"
PAPER = "#E6DFC8"
ONIONSKIN = "#D9D6CC"
FROSTED = "#B0B8B0"
FROSTED_ALPHA = 0.7
CHALK_BOARD = "#2C3A30"


def hex_rgb(value: str) -> np.ndarray:
    return np.array([int(value[i : i + 2], 16) for i in (1, 3, 5)], dtype=np.float64)


def rng_for(name: str) -> np.random.Generator:
    return np.random.default_rng(np.random.SeedSequence([SEED, zlib.crc32(name.encode("ascii"))]))


def flat(colour: str, h: int, w: int) -> np.ndarray:
    return np.broadcast_to(hex_rgb(colour), (h, w, 3)).copy()


def value_noise(rng: np.random.Generator, h: int, w: int, amp: float) -> np.ndarray:
    """One offset per pixel, shared by R, G and B."""
    return rng.uniform(-amp, amp, size=(h, w, 1))


def save_rgb(name: str, rgb: np.ndarray) -> None:
    arr = np.clip(np.rint(rgb), 0, 255).astype(np.uint8)
    Image.fromarray(arr, mode="RGB").save(OUT_DIR / name)


def make_floor_lino() -> None:
    rng = rng_for("floor_lino.png")
    yy, xx = np.mgrid[0:64, 0:64]
    is_a = ((xx // 32) + (yy // 32)) % 2 == 0
    base = np.where(is_a[..., None], hex_rgb(FLOOR_A), hex_rgb(FLOOR_B))
    img = base + value_noise(rng, 64, 64, 5)
    for _ in range(6):
        x = int(rng.integers(0, 64 - 3 + 1))
        y = int(rng.integers(0, 64))
        img[y, x : x + 3, :] -= 12
    save_rgb("floor_lino.png", img)


def make_wall_upper() -> None:
    rng = rng_for("wall_upper.png")
    save_rgb("wall_upper.png", flat(WALL_UPPER, 64, 64) + value_noise(rng, 64, 64, 3))


def make_wall_lower() -> None:
    rng = rng_for("wall_lower.png")
    img = flat(WALL_LOWER, 64, 64) + value_noise(rng, 64, 64, 3)
    rows = np.arange(0, 64, 16)
    img[rows, :, :] -= 6
    save_rgb("wall_lower.png", img)


def make_ceiling_tile() -> None:
    rng = rng_for("ceiling_tile.png")
    img = flat(CEILING_TILE, 64, 64) + value_noise(rng, 64, 64, 4)
    grid = hex_rgb(CEILING_GRID)
    img[0, :, :] = grid
    img[-1, :, :] = grid
    img[:, 0, :] = grid
    img[:, -1, :] = grid
    for _ in range(40):
        x = int(rng.integers(0, 64))
        y = int(rng.integers(0, 64))
        img[y, x, :] -= 20
    save_rgb("ceiling_tile.png", img)


def make_desk_top() -> None:
    rng = rng_for("desk_top.png")
    save_rgb("desk_top.png", flat(DESK_TOP, 64, 64) + value_noise(rng, 64, 64, 4))


def make_steel() -> None:
    rng = rng_for("steel.png")
    save_rgb("steel.png", flat(DESK_STEEL, 32, 32) + value_noise(rng, 32, 32, 3))


def make_wood() -> None:
    rng = rng_for("wood.png")
    img = flat(CHAIR_WOOD, 32, 32)
    streak = 6.0 * np.sin(2.0 * np.pi * np.arange(32) / 7.0)
    img += streak[:, None, None]
    img += value_noise(rng, 32, 32, 4)
    save_rgb("wood.png", img)


def make_paper() -> None:
    rng = rng_for("paper.png")
    save_rgb("paper.png", flat(PAPER, 128, 128) + value_noise(rng, 128, 128, 3))


def make_onionskin() -> None:
    rng = rng_for("onionskin.png")
    img = flat(ONIONSKIN, 128, 128) + value_noise(rng, 128, 128, 3)
    yy, xx = np.mgrid[0:128, 0:128]
    img[((xx + yy) % 9) == 0, :] += 5
    save_rgb("onionskin.png", img)


def make_frosted() -> None:
    rng = rng_for("frosted.png")
    rgb = flat(FROSTED, 32, 32) + value_noise(rng, 32, 32, 8)
    rgb = np.clip(np.rint(rgb), 0, 255).astype(np.uint8)
    alpha = np.full((32, 32, 1), int(np.rint(FROSTED_ALPHA * 255)), dtype=np.uint8)
    Image.fromarray(np.concatenate([rgb, alpha], axis=2), mode="RGBA").save(OUT_DIR / "frosted.png")


def make_chalk_board() -> None:
    rng = rng_for("chalk_board.png")
    save_rgb("chalk_board.png", flat(CHALK_BOARD, 64, 64) + value_noise(rng, 64, 64, 6))


def make_white4() -> None:
    save_rgb("white4.png", np.full((4, 4, 3), 255.0))


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    makers = [
        make_floor_lino,
        make_wall_upper,
        make_wall_lower,
        make_ceiling_tile,
        make_desk_top,
        make_steel,
        make_wood,
        make_paper,
        make_onionskin,
        make_frosted,
        make_chalk_board,
        make_white4,
    ]
    for maker in makers:
        maker()
    print(f"wrote {len(makers)} textures to {OUT_DIR.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
