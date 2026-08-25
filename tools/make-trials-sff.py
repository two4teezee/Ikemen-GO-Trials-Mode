#!/usr/bin/env python3
"""Generate external/mods/trials/trials.sff.

The module's own default artwork for the Step display's graphical layer (#53): the
panel behind the Step list, the plate under each Step in the vertical Layout, and the
tail / body / head that lead in and out of a Step in the horizontal one.

Why a generator and not a checked-in binary somebody drew: every sprite here is flat
colour and straight edges, so the source of truth is more legible as thirty lines of
Python than as an SFF nobody can diff. Change a colour below and re-run; the sizes are
load-bearing and are documented against the geometry in system.def that reads them.

    python3 tools/make-trials-sff.py

FORMAT — SFFv2, verified against Ikemen-GO-main/src/image.go at fb3750f4.

Sprites are written raw rather than PNG-compressed: `rle == 0` with `coldepth == 32`
takes the file's bytes straight to SetRaw (image.go:1195), which is the shortest path
through the loader and needs no palette section at all (NumberOfPalettes = 0, so
loadPalettes returns without reading anything).

32-bit and not 8-bit paletted, because an 8-bit sprite in a 2.0.0.0 file cannot be
translucent: ReadPalette forces index 0 transparent and every other index opaque
(image.go:2085). Per-pixel alpha is what makes a panel sit over a stage rather than
blank it out. PalFX still applies either way — the fragment shader runs add / mul /
gray / invertall after the texture fetch whatever `isRgba` is (sprite.frag.glsl:93),
which is what lets a Step Status tint its own background.

Bytes are PREMULTIPLIED. The engine's own PNG-sprite branch hands SetRaw an
`image.RGBA`, whose Pix is premultiplied by Go's definition, so that is what the
renderer is built around and what a raw sprite has to match.

Every sprite's axis is (0, 0), so its top-left corner lands on the position the element
is given. That keeps the width arithmetic in drawStepsHorizontal readable: a sprite `w`
wide drawn at `x` covers `x` to `x + w`, with no axis to subtract.
"""

import os
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
MOD = os.path.join(HERE, "..", "external", "mods", "trials")

# The palette, as straight (non-premultiplied) RGBA. Named for what they do rather than
# for the colour they are, since the point of each is its role in the layering.
PANEL_FILL = (16, 18, 26, 96)  # behind the whole Step list — dark, and mostly stage
PANEL_EDGE = (120, 130, 160, 110)  # its one-pixel border, so the panel has an edge
PANEL_TOP = (170, 185, 215, 130)  # a brighter top rule, so it reads as a surface
PLATE_FILL = (70, 76, 96, 120)  # under one Step in the vertical Layout
PLATE_MARK = (150, 165, 200, 190)  # the accent bar down its left, marking the row
CHIP_FILL = (70, 76, 96, 170)  # under one Step in the horizontal Layout
CHIP_EDGE = (120, 130, 160, 150)  # its top and bottom rules

# One Step's chip in the horizontal Layout is this tall. Paired with
# trialsteps.horizontal.spacing's second argument (11) — the row pitch — so the chips of
# one row clear the next by two units.
CHIP_H = 9


class Canvas:
    """A width x height RGBA image, transparent until something is drawn on it."""

    def __init__(self, w, h):
        self.w, self.h = w, h
        self.px = [(0, 0, 0, 0)] * (w * h)

    def set(self, x, y, rgba):
        if 0 <= x < self.w and 0 <= y < self.h:
            self.px[y * self.w + x] = rgba

    def rect(self, x0, y0, x1, y1, rgba):
        """Fills the half-open rect [x0, x1) x [y0, y1)."""
        for y in range(y0, y1):
            for x in range(x0, x1):
                self.set(x, y, rgba)

    def bytes(self):
        """Premultiplied RGBA, row-major from the top-left. See the module docstring."""
        out = bytearray()
        for r, g, b, a in self.px:
            out += bytes(((r * a) // 255, (g * a) // 255, (b * a) // 255, a))
        return bytes(out)


def panel(w, h):
    """The background behind a whole Step list: a bordered slab with a lit top edge."""
    c = Canvas(w, h)
    c.rect(0, 0, w, h, PANEL_FILL)
    c.rect(0, 0, w, 1, PANEL_TOP)
    c.rect(0, h - 1, w, h, PANEL_EDGE)
    c.rect(0, 0, 1, h, PANEL_EDGE)
    c.rect(w - 1, 0, w, h, PANEL_EDGE)
    return c


def plate(w, h):
    """The background under one Step in the vertical Layout, with its row marker."""
    c = Canvas(w, h)
    c.rect(0, 0, w, h, PLATE_FILL)
    c.rect(0, 0, 2, h, PLATE_MARK)
    return c


def chip_body(w):
    """The stretching middle of a horizontal Step's background.

    Uniform along x on purpose: drawStepsHorizontal scales this sprite to the width of
    the Step it sits under, so anything that varied across it would smear. Only the
    top and bottom rules distinguish it, and those run the full width.
    """
    c = Canvas(w, CHIP_H)
    c.rect(0, 0, w, CHIP_H, CHIP_FILL)
    c.rect(0, 0, w, 1, CHIP_EDGE)
    c.rect(0, CHIP_H - 1, w, CHIP_H, CHIP_EDGE)
    return c


def chip_tail(w):
    """The lead-in: a nock cut into the left, so a Step reads as pointing forward."""
    c = Canvas(w, CHIP_H)
    mid = CHIP_H // 2
    for y in range(CHIP_H):
        # The cut narrows to nothing at the vertical middle, which is where the notch
        # bites deepest — the mirror of the head's point.
        cut = w - 1 - abs(y - mid) * (w - 1) // mid
        c.rect(cut, y, w, y + 1, CHIP_FILL)
        c.set(cut, y, CHIP_EDGE)
    c.rect(0, 0, w, 1, (0, 0, 0, 0))
    c.rect(0, CHIP_H - 1, w, CHIP_H, (0, 0, 0, 0))
    for y in (0, CHIP_H - 1):
        cut = w - 1 - abs(y - mid) * (w - 1) // mid
        c.rect(cut, y, w, y + 1, CHIP_EDGE)
    return c


def chip_head(w):
    """The lead-out: a point, so one Step's end is distinguishable from the next's start."""
    c = Canvas(w, CHIP_H)
    mid = CHIP_H // 2
    for y in range(CHIP_H):
        # Full height at the left, tapering to a single pixel at the vertical middle.
        reach = w - abs(y - mid) * (w - 1) // mid
        c.rect(0, y, reach, y + 1, CHIP_FILL)
        c.set(reach - 1, y, CHIP_EDGE)
    for y in (0, CHIP_H - 1):
        reach = w - abs(y - mid) * (w - 1) // mid
        c.rect(0, y, reach, y + 1, CHIP_EDGE)
    return c


# group, number, canvas, and the name system.def knows it by. The numbering is grouped by
# role rather than run consecutively, so a screenpack reading these numbers can tell a
# block background from a Step background without a legend.
#
# No companion .air. Every sprite here is one static image drawn by `spr = group, index`,
# and a module's own [Begin Action] blocks cannot be reached from a screenpack anyway --
# the engine's action table does not reach Lua -- so an .air beside this would be a file
# nothing ever read.
#
# The two panel sizes are the shipped windows in system.def, exactly: the vertical
# block's window is 25,34 - 295,138 and the horizontal one's is 20,34 - 300,70. Change
# a window there and this has to change with it, which is why they are spelled here
# rather than derived from a round number.
SPRITES = [
    (0, 0, panel(270, 104), "block background, vertical Layout"),
    (0, 1, panel(280, 36), "block background, horizontal Layout"),
    (0, 10, plate(250, CHIP_H), "Step background, vertical Layout"),
    (0, 20, chip_body(4), "Step background body, horizontal Layout (stretched)"),
    (0, 21, chip_tail(4), "Step background tail, horizontal Layout"),
    (0, 22, chip_head(6), "Step background head, horizontal Layout"),
]


def write_sff(path):
    """Writes SFFv2.0.0.0 with one raw 32-bit sprite per entry and no palettes."""
    header_size = 64
    n = len(SPRITES)
    # Sprite headers are fixed-width and contiguous (loadSff advances by 28), so the
    # pixel data can only start once all of them are written.
    data_start = header_size + n * 28

    headers, data = bytearray(), bytearray()
    for group, number, canvas, _ in SPRITES:
        px = canvas.bytes()
        headers += struct.pack(
            "<HHHHhhHBBIIHH",
            group,
            number,
            canvas.w,
            canvas.h,
            0,  # axis x — see the module docstring
            0,  # axis y
            0,  # index of previous, unused: every sprite here carries its own data
            0,  # format 0, meaning raw (image.go:1191)
            32,  # colour depth
            len(data),  # offset, relative to ldata
            len(px),
            0,  # palette index, unused at 32-bit
            0,  # flags: bit 0 clear, so the offset above is into ldata
        )
        data += px

    ldata = data_start
    out = bytearray()
    out += b"ElecbyteSpr\x00"
    out += bytes((0, 0, 0, 2))  # verlo3, verlo2, verlo1, verhi — 2.0.0.0
    out += struct.pack("<I", 0)  # reserved
    out += struct.pack("<IIII", 0, 0, 0, 0)  # four reserved words
    out += struct.pack("<I", header_size)  # first sprite header offset
    out += struct.pack("<I", n)
    out += struct.pack("<I", 0)  # first palette header offset
    out += struct.pack("<I", 0)  # number of palettes — none, see the module docstring
    out += struct.pack("<I", ldata)
    out += struct.pack("<I", len(data))  # ldata size
    out += struct.pack("<I", 0)  # tdata offset — unused, nothing is translated
    assert len(out) == header_size, len(out)
    out += headers
    out += data

    with open(path, "wb") as f:
        f.write(bytes(out))
    return len(out)


def main():
    sff = os.path.normpath(os.path.join(MOD, "trials.sff"))
    n = write_sff(sff)
    print("wrote %s (%d bytes, %d sprites)" % (sff, n, len(SPRITES)))
    for group, number, canvas, label in SPRITES:
        print("  %d,%d  %dx%d  %s" % (group, number, canvas.w, canvas.h, label))
    return 0


if __name__ == "__main__":
    sys.exit(main())
