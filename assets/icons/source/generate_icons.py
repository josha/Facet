#!/usr/bin/env python3


from __future__ import annotations

import math
import pathlib

from PIL import Image, ImageDraw


SIZE = 128
SS = 8
INK = (240, 240, 242, 255)
STROKE = 13

OUT = pathlib.Path(__file__).resolve().parent.parent


def _canvas() -> tuple[Image.Image, ImageDraw.ImageDraw]:
    img = Image.new("RGBA", (SIZE * SS, SIZE * SS), (0, 0, 0, 0))
    return img, ImageDraw.Draw(img)


def _dot(draw: ImageDraw.ImageDraw, x: float, y: float, r: float) -> None:

    cx, cy, cr = x * SS, y * SS, r * SS
    draw.ellipse([cx - cr, cy - cr, cx + cr, cy + cr], fill=INK)


def _stroke(draw: ImageDraw.ImageDraw, pts: list[tuple[float, float]], w: float = STROKE) -> None:

    scaled = [(x * SS, y * SS) for x, y in pts]
    draw.line(scaled, fill=INK, width=int(w * SS))
    for x, y in pts:
        _dot(draw, x, y, w / 2)


def _poly(draw: ImageDraw.ImageDraw, pts: list[tuple[float, float]]) -> None:
    draw.polygon([(x * SS, y * SS) for x, y in pts], fill=INK)


def _ring(draw: ImageDraw.ImageDraw, cx: float, cy: float, r: float, w: float = STROKE) -> None:

    draw.ellipse(
        [(cx - r) * SS, (cy - r) * SS, (cx + r) * SS, (cy + r) * SS],
        outline=INK,
        width=int(w * SS),
    )


def _save(img: Image.Image, name: str) -> pathlib.Path:
    out = img.resize((SIZE, SIZE), Image.LANCZOS)
    path = OUT / f"{name}.png"
    out.save(path, "PNG", optimize=True)
    return path









def chevron(direction: str) -> Image.Image:
    img, d = _canvas()


    pts = {
        "left": [(80, 26), (46, 64), (80, 102)],
        "right": [(48, 26), (82, 64), (48, 102)],
        "up": [(26, 80), (64, 46), (102, 80)],
        "down": [(26, 48), (64, 82), (102, 48)],
    }[direction]
    _stroke(d, pts)
    return img


def chevron_up_down() -> Image.Image:

    img, d = _canvas()
    _stroke(d, [(36, 52), (64, 26), (92, 52)])
    _stroke(d, [(36, 76), (64, 102), (92, 76)])
    return img


def check() -> Image.Image:
    img, d = _canvas()


    _stroke(d, [(28, 68), (52, 92), (100, 38)])
    return img


def close() -> Image.Image:
    img, d = _canvas()
    _stroke(d, [(34, 34), (94, 94)])
    _stroke(d, [(94, 34), (34, 94)])
    return img


def plus() -> Image.Image:
    img, d = _canvas()
    _stroke(d, [(64, 28), (64, 100)])
    _stroke(d, [(28, 64), (100, 64)])
    return img


def minus() -> Image.Image:
    img, d = _canvas()
    _stroke(d, [(28, 64), (100, 64)])
    return img


def menu() -> Image.Image:
    img, d = _canvas()
    for y in (40, 64, 88):
        _stroke(d, [(28, y), (100, y)])
    return img


def more() -> Image.Image:
    img, d = _canvas()


    for x in (34, 64, 94):
        _dot(d, x, 64, STROKE / 2 + 1)
    return img


def edit() -> Image.Image:

    img, d = _canvas()

    _poly(d, [(26, 102), (34, 74), (54, 94)])

    _poly(d, [(38, 70), (82, 26), (102, 46), (58, 90)])

    _poly(d, [(86, 22), (96, 12), (116, 32), (106, 42)])
    return img


def trash() -> Image.Image:

    img, d = _canvas()
    _stroke(d, [(54, 40), (54, 28), (74, 28), (74, 40)])
    _stroke(d, [(28, 40), (100, 40)])
    _stroke(d, [(36, 44), (42, 100), (86, 100), (92, 44)])
    return img


def flag() -> Image.Image:

    img, d = _canvas()
    _stroke(d, [(34, 26), (34, 102)])
    _poly(d, [(34, 30), (98, 46), (34, 62)])
    return img












def radio_off() -> Image.Image:

    img, d = _canvas()
    _ring(d, 64, 64, 40)
    return img


def radio_on() -> Image.Image:

    img, d = _canvas()
    _ring(d, 64, 64, 40)
    _dot(d, 64, 64, 15)
    return img


def check_off() -> Image.Image:

    img, d = _canvas()
    d.rounded_rectangle(
        [24 * SS, 24 * SS, 104 * SS, 104 * SS],
        radius=22 * SS,
        outline=INK,
        width=STROKE * SS,
    )
    return img


def search() -> Image.Image:

    img, d = _canvas()
    d.ellipse([22 * SS, 22 * SS, 88 * SS, 88 * SS], outline=INK, width=STROKE * SS)
    _stroke(d, [(81, 81), (103, 103)])
    return img























def status_info() -> Image.Image:

    img, d = _canvas()
    _ring(d, 64, 64, 40)
    _dot(d, 64, 46, 7)
    _stroke(d, [(64, 62), (64, 82)], w=13)
    return img


def status_success() -> Image.Image:

    return check()


def status_warning() -> Image.Image:

    img, d = _canvas()
    _stroke(d, [(64, 18), (108, 108), (20, 108), (64, 18)], w=13)
    _stroke(d, [(64, 56), (64, 80)], w=11)
    _dot(d, 64, 92, 5)
    return img


def status_error() -> Image.Image:

    img, d = _canvas()
    _ring(d, 64, 64, 40)
    _stroke(d, [(52, 52), (76, 76)], w=13)
    _stroke(d, [(76, 52), (52, 76)], w=13)
    return img


def calendar() -> Image.Image:

    img, d = _canvas()
    d.rounded_rectangle(
        [18 * SS, 40 * SS, 110 * SS, 108 * SS],
        radius=12 * SS,
        outline=INK,
        width=STROKE * SS,
    )
    _stroke(d, [(24, 60), (104, 60)], w=10)
    _stroke(d, [(40, 24), (40, 44)], w=11)
    _stroke(d, [(88, 24), (88, 44)], w=11)
    return img


def clock() -> Image.Image:

    img, d = _canvas()
    _ring(d, 64, 64, 40)
    _stroke(d, [(64, 64), (64, 44)], w=11)
    _stroke(d, [(64, 64), (76, 50)], w=11)
    return img


def thumb_up() -> Image.Image:

    img, d = _canvas()

    d.rounded_rectangle([14 * SS, 58 * SS, 34 * SS, 110 * SS], radius=6 * SS, fill=INK)

    d.rounded_rectangle([40 * SS, 56 * SS, 112 * SS, 110 * SS], radius=14 * SS, fill=INK)


    for gy in (70, 83, 96):
        d.rectangle([80 * SS, (gy - 2.5) * SS, 112 * SS, (gy + 2.5) * SS], fill=(0, 0, 0, 0))




    _stroke(d, [(58, 64), (67, 32)], w=26)
    return img


def thumb_down() -> Image.Image:

    return thumb_up().transpose(Image.FLIP_TOP_BOTTOM)


def person() -> Image.Image:

    img, d = _canvas()
    _dot(d, 64, 44, 18)
    d.pieslice([24 * SS, 66 * SS, 104 * SS, 142 * SS], 180, 360, fill=INK)
    return img


def chevron_first() -> Image.Image:

    img, d = _canvas()
    _stroke(d, [(26, 24), (26, 104)], w=STROKE)
    _poly(d, [(90, 24), (90, 104), (42, 64)])
    return img


def chevron_last() -> Image.Image:

    img, d = _canvas()
    _poly(d, [(38, 24), (38, 104), (86, 64)])
    _stroke(d, [(102, 24), (102, 104)], w=STROKE)
    return img


def settings() -> Image.Image:

    img, d = _canvas()
    body_r = 34.0
    _ring(d, 64, 64, body_r, w=20)
    root_r, tip_r = body_r, 54.0
    root_half, tip_half = 12.0, 9.0
    for index in range(8):
        angle = math.pi / 4 * index
        cos, sin = math.cos(angle), math.sin(angle)
        nx, ny = -sin, cos
        _poly(
            d,
            [
                (64 + cos * root_r + nx * root_half, 64 + sin * root_r + ny * root_half),
                (64 + cos * tip_r + nx * tip_half, 64 + sin * tip_r + ny * tip_half),
                (64 + cos * tip_r - nx * tip_half, 64 + sin * tip_r - ny * tip_half),
                (64 + cos * root_r - nx * root_half, 64 + sin * root_r - ny * root_half),
            ],
        )
    d.ellipse(
        [(64 - 17) * SS, (64 - 17) * SS, (64 + 17) * SS, (64 + 17) * SS],
        fill=(0, 0, 0, 0),
    )
    return img


ICONS = {
    "facet_icon_chevron_left": lambda: chevron("left"),
    "facet_icon_chevron_right": lambda: chevron("right"),
    "facet_icon_chevron_up": lambda: chevron("up"),
    "facet_icon_chevron_down": lambda: chevron("down"),
    "facet_icon_chevron_up_down": chevron_up_down,
    "facet_icon_check": check,
    "facet_icon_close": close,
    "facet_icon_plus": plus,
    "facet_icon_minus": minus,
    "facet_icon_menu": menu,
    "facet_icon_more": more,
    "facet_icon_edit": edit,
    "facet_icon_trash": trash,
    "facet_icon_flag": flag,
    "facet_icon_search": search,
    "facet_icon_settings": settings,
    "facet_icon_radio_off": radio_off,
    "facet_icon_radio_on": radio_on,
    "facet_icon_check_off": check_off,
    "facet_icon_info": status_info,
    "facet_icon_success": status_success,
    "facet_icon_warning": status_warning,
    "facet_icon_error": status_error,
    "facet_icon_calendar": calendar,
    "facet_icon_clock": clock,
    "facet_icon_thumb_up": thumb_up,
    "facet_icon_thumb_down": thumb_down,
    "facet_icon_person": person,
    "facet_icon_chevron_first": chevron_first,
    "facet_icon_chevron_last": chevron_last,
}


def contact_sheet(images: dict[str, Image.Image]) -> None:

    rungs = [16, 20, 24, 48]
    pad, label_w = 12, 0
    cell_h = max(rungs) + pad
    sheet = Image.new(
        "RGBA",
        (label_w + sum(r + pad for r in rungs) + pad, cell_h * len(images) + pad),
        (96, 100, 108, 255),
    )
    for row, (name, img) in enumerate(sorted(images.items())):
        x = label_w + pad
        y = row * cell_h + pad
        for r in rungs:
            sheet.alpha_composite(img.resize((r, r), Image.LANCZOS), (x, y + (max(rungs) - r) // 2))
            x += r + pad
    preview = OUT / "source" / "preview"
    preview.mkdir(parents=True, exist_ok=True)
    sheet.save(preview / "contact-sheet.png", "PNG")


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    built = {}
    for name, fn in ICONS.items():
        img = fn()
        path = _save(img, name)
        built[name] = Image.open(path).convert("RGBA")
        print(f"  {path.name}  {SIZE}x{SIZE}")
    contact_sheet(built)
    print(f"{len(built)} icons + contact sheet -> {OUT}")


if __name__ == "__main__":
    main()
