#!/usr/bin/env python3
"""Generates chooser/winmarchy.ico, the Winmarchy application icon.

Run from the repository root:  python3 tools/make-icon.py

Why this is Python when the rest of the repo is PowerShell and C#: the icon
has to be produced on the build container, which is Linux, where
System.Drawing does not draw and no imaging library is installed. This writes
the PNG and ICO bytes itself, so it needs nothing but the standard library.
It is a one-off developer tool that produces a committed asset; nothing in
the installer or at runtime ever calls it.

The mark is the tiling layout Winmarchy puts on screen: one tall pane on the
left, two stacked on the right, inside a rounded square. Colours are the
tokyo-night palette from themes/tokyo-night.json, which is the default theme.
The icon file cannot follow the active theme, so it is fixed to that one; the
notification area icon is drawn at runtime and does follow the theme (see
TrayApplet.RefreshIcon).
"""

import binascii
import os
import struct
import zlib

# themes/tokyo-night.json: background, accent, and the focused border colour.
BACKGROUND = (0x1A, 0x1B, 0x26)
ACCENT = (0x7A, 0xA2, 0xF7)

SIZES = [16, 24, 32, 48, 64, 128, 256]
SUPERSAMPLE = 4


def rounded_square_alpha(x, y, size, radius):
    """Coverage of a rounded square at a point, 0.0 to 1.0, before scaling."""
    left, top, right, bottom = 0.0, 0.0, float(size), float(size)
    cx = min(max(x, left + radius), right - radius)
    cy = min(max(y, top + radius), bottom - radius)
    dx, dy = x - cx, y - cy
    distance = (dx * dx + dy * dy) ** 0.5
    if distance <= radius:
        return 1.0
    return 0.0


def render(size):
    """Renders one square of RGBA bytes, top row first, with supersampling."""
    big = size * SUPERSAMPLE
    radius = big * 0.22

    # Pane geometry as fractions of the square, matching the notification area
    # icon: a tall pane on the left, two stacked on the right. There is no
    # separate border ring: at 16 pixels a ring plus a gap plus a pane is more
    # edges than the space can carry, and it rendered as mush. The edge of the
    # rounded square is the only outline the mark needs.
    inset = big * 0.17
    gap = big * 0.085
    left_pane = (inset, inset, big * 0.46, big - inset)
    right_x0, right_x1 = big * 0.46 + gap, big - inset
    mid = (inset + (big - inset)) / 2.0
    right_top = (right_x0, inset, right_x1, mid - gap / 2.0)
    right_bottom = (right_x0, mid + gap / 2.0, right_x1, big - inset)
    panes = [left_pane, right_top, right_bottom]

    # Accumulate coverage per output pixel, then average the supersamples.
    pixels = bytearray(size * size * 4)
    for py in range(size):
        for px in range(size):
            field = 0.0
            pane = 0.0
            for sy in range(SUPERSAMPLE):
                for sx in range(SUPERSAMPLE):
                    x = px * SUPERSAMPLE + sx + 0.5
                    y = py * SUPERSAMPLE + sy + 0.5
                    inside = rounded_square_alpha(x, y, big, radius)
                    if inside <= 0.0:
                        continue
                    field += 1.0
                    # Inside the rounded square: is this sample one of the
                    # panes, or the dark field between them?
                    for x0, y0, x1, y1 in panes:
                        if x0 <= x <= x1 and y0 <= y <= y1:
                            pane += 1.0
                            break
            total = float(SUPERSAMPLE * SUPERSAMPLE)
            alpha = field / total
            if alpha <= 0.0:
                continue
            # Mix the accent over the dark field by how much of this pixel the
            # panes and border cover.
            mix = (pane / total) / alpha if alpha > 0 else 0.0
            mix = min(1.0, max(0.0, mix))
            red = round(BACKGROUND[0] + (ACCENT[0] - BACKGROUND[0]) * mix)
            green = round(BACKGROUND[1] + (ACCENT[1] - BACKGROUND[1]) * mix)
            blue = round(BACKGROUND[2] + (ACCENT[2] - BACKGROUND[2]) * mix)
            offset = (py * size + px) * 4
            pixels[offset] = red
            pixels[offset + 1] = green
            pixels[offset + 2] = blue
            pixels[offset + 3] = round(alpha * 255)
    return bytes(pixels)


def png_chunk(tag, payload):
    return (struct.pack('>I', len(payload)) + tag + payload
            + struct.pack('>I', binascii.crc32(tag + payload) & 0xFFFFFFFF))


def to_png(rgba, size):
    """Minimal RGBA PNG: one IHDR, one IDAT with filter byte 0, one IEND."""
    raw = bytearray()
    for row in range(size):
        raw.append(0)
        raw += rgba[row * size * 4:(row + 1) * size * 4]
    header = struct.pack('>IIBBBBB', size, size, 8, 6, 0, 0, 0)
    return (b'\x89PNG\r\n\x1a\n'
            + png_chunk(b'IHDR', header)
            + png_chunk(b'IDAT', zlib.compress(bytes(raw), 9))
            + png_chunk(b'IEND', b''))


def to_bmp(rgba, size):
    """A classic icon entry: BITMAPINFOHEADER, BGRA rows bottom-up, AND mask.

    The height in the header is doubled, which is what the icon format
    requires: it counts the colour bitmap plus the mask that follows it.
    """
    header = struct.pack('<IiiHHIIiiII', 40, size, size * 2, 1, 32, 0, 0, 0, 0, 0, 0)
    body = bytearray()
    for row in range(size - 1, -1, -1):
        for column in range(size):
            offset = (row * size + column) * 4
            body += bytes((rgba[offset + 2], rgba[offset + 1], rgba[offset], rgba[offset + 3]))
    # Every pixel carries its own alpha, so the AND mask is all zeroes; its
    # rows are padded to four bytes.
    mask_row = ((size + 31) // 32) * 4
    body += bytes(mask_row * size)
    return header + bytes(body)


def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    entries = []
    for size in SIZES:
        rgba = render(size)
        # 256 is conventionally stored as PNG; the smaller ones as bitmaps,
        # which every version of Windows reads.
        payload = to_png(rgba, size) if size >= 256 else to_bmp(rgba, size)
        entries.append((size, payload))

    header = struct.pack('<HHH', 0, 1, len(entries))
    offset = 6 + 16 * len(entries)
    directory, blobs = b'', b''
    for size, payload in entries:
        width = 0 if size >= 256 else size
        directory += struct.pack('<BBBBHHII', width, width, 0, 0, 1, 32, len(payload), offset)
        blobs += payload
        offset += len(payload)

    target = os.path.join(root, 'chooser', 'winmarchy.ico')
    with open(target, 'wb') as handle:
        handle.write(header + directory + blobs)
    print('wrote %s (%d bytes, %d sizes)' % (target, 6 + 16 * len(entries) + len(blobs), len(entries)))


if __name__ == '__main__':
    main()
