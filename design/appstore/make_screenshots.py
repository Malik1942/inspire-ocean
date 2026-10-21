"""App Store screenshots for Oryne: each app screen in the silver frame the
website uses, on near-black, with a two-line New York caption beneath (the
second line in italic, as the website's headlines accent their close).

usage: python3 design/appstore/make_screenshots.py <screens-dir> <out-dir>
<screens-dir> holds the raw simulator captures (1206x2622, iPhone 17 Pro):
tide.png, capture.png, fast-capture.png, current.png, ask.png, library.png,
detail.png. Output is 1320x2868 (the 6.9-inch size App Store Connect asks for).

The last shot, 08-watch, needs no capture from <screens-dir>: it shows the
watch app's own screen (design/appstore/2.0/watch/en/03-in-your-ocean.png) as a
clean rounded display, with no frame, on the same background and caption.
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

# The wrist shot follows the seven above (08). Its screen is the watch app's
# own capture, committed beside it, not a phone capture from <screens-dir>.
WATCH_SCREEN = ROOT / "design/appstore/2.0/watch/en/03-in-your-ocean.png"
WATCH_WIDTH = 1000                # a little under the phone frame's width
WATCH_RADIUS = 0.20               # corner radius as a share of the display's width
# The watch app's own background is the same abyss as this canvas, so with no
# frame the display's edge cannot be seen. A flat 3px hairline in OceanTheme's
# current gray draws it, still matte; None leaves the display edgeless.
WATCH_EDGE = (38, 40, 45)
WRIST_SHOTS = [
    ("watch", WATCH_SCREEN, "Catch a whisper", "from your wrist."),
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


def wrist(screen_path: Path, line1: str, line2: str) -> Image.Image:
    """The watch's screen as a flat display where the phone sits: rounded
    corners, no bezel, no gloss. The caption sits exactly where compose()
    puts it, so the set reads as one."""
    canvas = Image.new("RGB", SIZE, BACKGROUND)
    frame_width, frame_height = Image.open(FRAME).size
    slot_height = round(frame_height * FRAME_WIDTH / frame_width)  # the phone's height

    screen = Image.open(screen_path).convert("RGB")
    width = WATCH_WIDTH
    height = round(screen.height * width / screen.width)
    display = screen.resize((width, height), Image.LANCZOS)
    # Anti-aliased rounded corners: draw the mask at 4x and scale it down.
    mask = Image.new("L", (width * 4, height * 4), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        (0, 0, width * 4 - 1, height * 4 - 1), radius=round(width * WATCH_RADIUS) * 4, fill=255)
    mask = mask.resize((width, height), Image.LANCZOS)
    left, top = (SIZE[0] - width) // 2, FRAME_TOP + (slot_height - height) // 2
    canvas.paste(display, (left, top), mask)
    if WATCH_EDGE:
        edge = Image.new("L", (width * 4, height * 4), 0)
        ImageDraw.Draw(edge).rounded_rectangle(
            (0, 0, width * 4 - 1, height * 4 - 1), radius=round(width * WATCH_RADIUS) * 4,
            outline=255, width=12)
        canvas.paste(Image.new("RGB", (width, height), WATCH_EDGE), (left, top),
                     edge.resize((width, height), Image.LANCZOS))

    draw = ImageDraw.Draw(canvas)
    regular, italic = new_york(False, CAPTION_SIZE), new_york(True, CAPTION_SIZE)
    block_top = FRAME_TOP + slot_height
    space = SIZE[1] - block_top
    line_height = round(CAPTION_SIZE * LINE_GAP)
    y = block_top + (space - 2 * line_height) // 2
    for text, font, color in ((line1, regular, FOAM), (line2, italic, ITALIC)):
        text_width = draw.textlength(text, font=font)
        draw.text(((SIZE[0] - text_width) / 2, y), text, font=font, fill=color)
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
    for index, (name, screen, line1, line2) in enumerate(WRIST_SHOTS, len(SHOTS) + 1):
        image = wrist(screen, line1, line2)
        target = out / f"{index:02d}-{name}.png"
        image.save(target, optimize=True)
        print(target.name, image.size)


if __name__ == "__main__":
    main()
