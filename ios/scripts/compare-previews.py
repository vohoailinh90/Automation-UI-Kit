#!/usr/bin/env python3
"""Says which preview screenshots changed between two renders.

    ios/scripts/compare-previews.py <before-dir> <after-dir> [--label <name>]

Writes CHANGES.md into <after-dir>. For every screen that changed it also
copies the old shot to before/<name>.png and draws the new one with its
changes tinted red as diff/<name>.png, so the published branch shows all
three side by side. Needs `sips`, which ships with macOS, to shrink and
convert the PNGs; the rest is the standard library.

A screen changed when, both shrunk to 150 pixels wide, some pixel differs by
more than 48 in a colour channel, or more than 2 % of them by more than 16.
Shrinking averages away what the simulator draws a little differently from
run to run, such as a blurred photo (up to 37 once shrunk, in the runs this
was tuned on), while a new button, a moved label or a recoloured background
stays well above it. Only a report: a change is often the point of the
pull request.
"""
import argparse
import os
import re
import shutil
import struct
import subprocess
import sys
import tempfile

SMALL_WIDTH = 150
PIXEL_LIMIT = 48
AREA_LEVEL = 16
AREA_LIMIT = 0.02


def to_bmp(png, bmp, width=None):
    """Converts `png` to a BMP with sips, shrunk to `width` pixels if given."""
    command = ["sips", "-s", "format", "bmp"]
    if width:
        command += ["--resampleWidth", str(width)]
    subprocess.run(command + [png, "--out", bmp], check=True, stdout=subprocess.DEVNULL)


def read_bmp(path):
    """Width, height and rows of (b, g, r) tuples, top row first."""
    data = open(path, "rb").read()
    if data[:2] != b"BM":
        raise ValueError(f"{path} is not a BMP")
    start, = struct.unpack_from("<I", data, 10)
    width, height = struct.unpack_from("<ii", data, 18)
    depth = struct.unpack_from("<H", data, 28)[0] // 8
    compression, = struct.unpack_from("<I", data, 30)
    if depth not in (3, 4) or compression not in (0, 3, 6):
        raise ValueError(f"{path}: {depth * 8}-bit BMP, compression {compression}")
    # Where blue, green and red sit in a pixel: B, G, R unless the header
    # gives masks (32-bit bitfields), one byte each.
    order = (0, 1, 2)
    if compression in (3, 6):
        masks = struct.unpack_from("<III", data, 54)  # red, green, blue
        if len(set(masks)) != 3 or any(mask not in (0xFF, 0xFF00, 0xFF0000, 0xFF000000) for mask in masks):
            raise ValueError(f"{path}: colour masks {[hex(mask) for mask in masks]}")
        order = tuple(mask.bit_length() // 8 - 1 for mask in reversed(masks))
    stride = (width * depth + 3) // 4 * 4
    blue, green, red = order
    rows = []
    for row in range(abs(height)):
        # A positive height stores the bottom row first.
        stored = abs(height) - 1 - row if height > 0 else row
        line = data[start + stored * stride:start + stored * stride + width * depth]
        rows.append([(line[x + blue], line[x + green], line[x + red]) for x in range(0, len(line), depth)])
    return width, abs(height), rows


def write_bmp(path, width, height, rows):
    """Writes rows of (b, g, r) tuples as a 24-bit BMP."""
    stride = (width * 3 + 3) // 4 * 4
    padding = bytes(stride - width * 3)
    pixels = b"".join(bytes(c for pixel in row for c in pixel) + padding for row in reversed(rows))
    header = struct.pack("<2sIHHI", b"BM", 54 + len(pixels), 0, 0, 54)
    info = struct.pack("<IiiHHIIiiII", 40, width, height, 1, 24, 0, len(pixels), 2835, 2835, 0, 0)
    with open(path, "wb") as out:
        out.write(header + info + pixels)


def compare(before_rows, after_rows):
    """The largest difference, how many pixels differ by more than
    AREA_LEVEL, and the mask of those pixels."""
    worst, count, mask = 0, 0, []
    for old, new in zip(before_rows, after_rows):
        mask_row = []
        for a, b in zip(old, new):
            difference = max(abs(a[0] - b[0]), abs(a[1] - b[1]), abs(a[2] - b[2]))
            worst = max(worst, difference)
            mask_row.append(difference > AREA_LEVEL)
            count += difference > AREA_LEVEL
        mask.append(mask_row)
    return worst, count, mask


def tinted(png, mask, small_width, small_height, work, out):
    """The screenshot at `png`, its pixels under `mask` tinted red and the
    rest faded, so a change stands out even on a red or dark screen."""
    bmp = os.path.join(work, "full.bmp")
    to_bmp(png, bmp)
    width, height, rows = read_bmp(bmp)
    drawn = []
    for y, row in enumerate(rows):
        mask_row = mask[min(y * small_height // height, small_height - 1)]
        drawn.append([
            (b * 4 // 10, g * 4 // 10, r * 4 // 10 + 153) if mask_row[min(x * small_width // width, small_width - 1)]
            else (b + (255 - b) * 6 // 10, g + (255 - g) * 6 // 10, r + (255 - r) * 6 // 10)
            for x, (b, g, r) in enumerate(row)
        ])
    write_bmp(os.path.join(work, "diff.bmp"), width, height, drawn)
    subprocess.run(["sips", "-s", "format", "png", os.path.join(work, "diff.bmp"), "--out", out],
                   check=True, stdout=subprocess.DEVNULL)


def rendered_from(directory):
    """The commit a published set says it was rendered from, if it says."""
    try:
        match = re.search(r"\bat ([0-9a-f]{7,40})\b", open(os.path.join(directory, "README.md")).read())
    except OSError:
        return None
    return match.group(1)[:7] if match else None


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("before")
    parser.add_argument("after")
    parser.add_argument("--label", default="lần render trước", help="what the before set is, for the report")
    args = parser.parse_args()

    def shots(directory):
        return {name[:-4] for name in os.listdir(directory) if name.endswith(".png")}

    def keep_before(name):
        os.makedirs(os.path.join(args.after, "before"), exist_ok=True)
        shutil.copy(os.path.join(args.before, name + ".png"), os.path.join(args.after, "before", name + ".png"))

    before, after = shots(args.before), shots(args.after)
    changed = []
    with tempfile.TemporaryDirectory() as work:
        for name in sorted(before & after):
            old_bmp, new_bmp = os.path.join(work, "old.bmp"), os.path.join(work, "new.bmp")
            to_bmp(os.path.join(args.before, name + ".png"), old_bmp, SMALL_WIDTH)
            to_bmp(os.path.join(args.after, name + ".png"), new_bmp, SMALL_WIDTH)
            old_width, old_height, old_rows = read_bmp(old_bmp)
            new_width, new_height, new_rows = read_bmp(new_bmp)
            if (old_width, old_height) != (new_width, new_height):
                changed.append((name, None, None))
                keep_before(name)
                continue
            worst, count, mask = compare(old_rows, new_rows)
            share = count / (new_width * new_height)
            if worst > PIXEL_LIMIT or share > AREA_LIMIT:
                changed.append((name, worst, share))
                keep_before(name)
                os.makedirs(os.path.join(args.after, "diff"), exist_ok=True)
                tinted(os.path.join(args.after, name + ".png"), mask, new_width, new_height, work,
                       os.path.join(args.after, "diff", name + ".png"))

    source = rendered_from(args.before)
    lines = ["# Ảnh giao diện đổi những gì", ""]
    lines.append(f"So với ảnh của {args.label}" + (f" (render từ `{source}`)" if source else "") + ": "
                 + f"{len(changed)} màn đổi, {len(before & after) - len(changed)} màn giữ nguyên"
                 + (f", {len(after - before)} màn mới" if after - before else "")
                 + (f", {len(before - after)} màn bỏ" if before - after else "") + ".")
    lines.append("")
    if changed:
        lines += ["| Màn | Chênh lớn nhất | Điểm chênh quá 16 | Trước | Sau | Chỗ đổi |", "| --- | ---: | ---: | --- | --- | --- |"]
        for name, worst, share in changed:
            if worst is None:
                lines.append(f"| `{name}` | cỡ ảnh khác | | [ảnh](before/{name}.png) | [ảnh]({name}.png) | |")
            else:
                percent = f"{share * 100:.1f}".replace(".", ",") + "%"
                lines.append(f"| `{name}` | {worst} | {percent} | [ảnh](before/{name}.png) | [ảnh]({name}.png) | [ảnh](diff/{name}.png) |")
        lines.append("")
    for title, names in (("Màn mới", after - before), ("Màn bỏ", before - after)):
        if names:
            lines.append(f"{title}: " + ", ".join(f"`{name}`" for name in sorted(names)) + ".")
            lines.append("")
    lines.append(f"Một màn tính là đổi khi, thu cả hai ảnh về {SMALL_WIDTH} px, có điểm ảnh chênh quá {PIXEL_LIMIT} "
                 f"ở một kênh màu, hoặc hơn {int(AREA_LIMIT * 100)}% điểm ảnh chênh quá {AREA_LEVEL}.")
    with open(os.path.join(args.after, "CHANGES.md"), "w") as report:
        report.write("\n".join(lines) + "\n")
    print(f"{len(changed)} changed, {len(after - before)} new, {len(before - after)} gone")


if __name__ == "__main__":
    sys.exit(main())
