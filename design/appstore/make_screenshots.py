"""App Store screenshots for Oryne: each app screen in the silver frame the
website uses, on near-black, with a two-line New York caption beneath (the
second line in italic, as the website's headlines accent their close).

usage: python3 design/appstore/make_screenshots.py <screens-dir> <out-dir>
<screens-dir> holds the raw simulator captures (1206x2622, iPhone 17 Pro):
tide.png, capture.png, fast-capture.png, current.png, ask.png, library.png,
detail.png. Output is 1320x2868 (the 6.9-inch size App Store Connect asks for).
"""
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
FRAME = ROOT / "website/assets/img/phone-frame.webp"
SIZE = (1320, 2868)
BACKGROUND = (5, 5, 8)            # OceanTheme abyss, as on the website
FOAM = (235, 235, 238)
ITALIC = (217, 225, 240)          # the website's italic accent
FRAME_WIDTH = 1060
FRAME_TOP = 118
CAPTION_SIZE = 94
LINE_GAP = 1.16

# Order is the listing's order: the first screen sells the app.
SHOTS = [
    ("tide", "Catch ideas before", "they drift away."),
    ("capture", "Tap to type.", "Hold to speak."),
    ("fast-capture", "One press.", "Already listening."),
    ("current", "Your ideas", "organize themselves."),
    ("ask", "Ask your ideas", "anything."),
    ("library", "Everything, in order,", "when you want it."),
    ("detail", "Grow an idea without", "losing the original."),
]


def new_york(italic: bool, size: int) -> ImageFont.FreeTypeFont:
    path = "/System/Library/Fonts/NewYorkItalic.ttf" if italic else "/System/Library/Fonts/NewYork.ttf"
    font = ImageFont.truetype(path, size)
    font.set_variation_by_axes([min(256, size), 400, 0])  # optical size, weight, grade
    return font


def phone(screen: Image.Image) -> Image.Image:
    frame = Image.open(FRAME).convert("RGBA")
    # The frame's screen opening: 5.333% in at the sides, 2.5% at top and bottom.
    w, h = frame.size
    left, top = round(w * 0.05333), round(h * 0.025)
    inner = (w - 2 * left, h - 2 * top)
    body = Image.new("RGBA", frame.size, (0, 0, 0, 0))
    body.paste(screen.convert("RGB").resize(inner, Image.LANCZOS), (left, top))
    body.alpha_composite(frame)
    scale = FRAME_WIDTH / w
    return body.resize((FRAME_WIDTH, round(h * scale)), Image.LANCZOS)


def compose(screen_path: Path, line1: str, line2: str) -> Image.Image:
    canvas = Image.new("RGB", SIZE, BACKGROUND)
    device = phone(Image.open(screen_path))
    canvas.paste(device, ((SIZE[0] - device.width) // 2, FRAME_TOP), device)

    draw = ImageDraw.Draw(canvas)
    regular, italic = new_york(False, CAPTION_SIZE), new_york(True, CAPTION_SIZE)
    block_top = FRAME_TOP + device.height
    space = SIZE[1] - block_top
    line_height = round(CAPTION_SIZE * LINE_GAP)
    y = block_top + (space - 2 * line_height) // 2
    for text, font, color in ((line1, regular, FOAM), (line2, italic, ITALIC)):
        width = draw.textlength(text, font=font)
        draw.text(((SIZE[0] - width) / 2, y), text, font=font, fill=color)
        y += line_height
    return canvas


def main() -> None:
    screens, out = Path(sys.argv[1]), Path(sys.argv[2])
    out.mkdir(parents=True, exist_ok=True)
    for index, (name, line1, line2) in enumerate(SHOTS, 1):
        image = compose(screens / f"{name}.png", line1, line2)
        target = out / f"{index:02d}-{name}.png"
        image.save(target, optimize=True)
        print(target.name, image.size)


if __name__ == "__main__":
    main()
