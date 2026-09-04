from PIL import Image, ImageDraw

SIZE = 1024
BLUE = (29, 78, 216, 255)          # Katisha primary #1D4ED8
WHITE = (255, 255, 255, 255)
BUS_PATH = "assets/images/school-bus.png"

def rounded_square_mask(size, radius):
    mask = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle([0, 0, size - 1, size - 1], radius=radius, fill=255)
    return mask

def load_white_bus():
    # school-bus.png is a pure black silhouette; recolor all opaque pixels to
    # white by keeping only its alpha channel and filling with solid white.
    bus = Image.open(BUS_PATH).convert("RGBA")
    alpha = bus.split()[3]
    white = Image.new("RGBA", bus.size, WHITE)
    white.putalpha(alpha)
    return white

# Scale the bus to a width that keeps it centered within the ~66% safe zone
# (same visual size for both the full-bleed icon and the adaptive foreground).
BUS_WIDTH = 560
bus = load_white_bus()
ratio = BUS_WIDTH / bus.size[0]
bus_h = round(bus.size[1] * ratio)
bus = bus.resize((BUS_WIDTH, bus_h), Image.LANCZOS)

def paste_centered(canvas, img):
    x = (SIZE - img.size[0]) // 2
    y = (SIZE - img.size[1]) // 2
    canvas.paste(img, (x, y), img)

# 1) Primary launcher icon: rounded blue square (full bleed) with white bus
img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
base = Image.new("RGBA", (SIZE, SIZE), BLUE)
base.putalpha(rounded_square_mask(SIZE, 180))
img.paste(base, (0, 0), base)
paste_centered(img, bus)
img.save("assets/images/app_icon.png")
print("wrote app_icon.png")

# 2) Adaptive icon foreground: transparent bg, white bus centered in safe zone
fg = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
paste_centered(fg, bus)
fg.save("assets/images/app_icon_foreground.png")
print("wrote app_icon_foreground.png")
