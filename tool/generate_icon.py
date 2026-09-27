from PIL import Image, ImageDraw

SIZE = 1024
BLUE = (29, 78, 216, 255)          # Katisha primary #1D4ED8
WHITE = (255, 255, 255, 255)
TICKET_PATH = "assets/images/ticket.png"

def rounded_square_mask(size, radius):
    mask = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle([0, 0, size - 1, size - 1], radius=radius, fill=255)
    return mask

def load_white_ticket():
    # ticket.png is a ticket icon; make it white by keeping only its alpha
    # channel and filling with solid white.
    ticket = Image.open(TICKET_PATH).convert("RGBA")
    alpha = ticket.split()[3]
    white = Image.new("RGBA", ticket.size, WHITE)
    white.putalpha(alpha)
    return white

# Scale the ticket to a width that keeps it centered within the ~66% safe zone
# (same visual size for both the full-bleed icon and the adaptive foreground).
TICKET_WIDTH = 560
ticket = load_white_ticket()
ratio = TICKET_WIDTH / ticket.size[0]
ticket_h = round(ticket.size[1] * ratio)
ticket = ticket.resize((TICKET_WIDTH, ticket_h), Image.LANCZOS)

def paste_centered(canvas, img):
    x = (SIZE - img.size[0]) // 2
    y = (SIZE - img.size[1]) // 2
    canvas.paste(img, (x, y), img)

# 1) Primary launcher icon: rounded blue square (full bleed) with white ticket
img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
base = Image.new("RGBA", (SIZE, SIZE), BLUE)
base.putalpha(rounded_square_mask(SIZE, 180))
img.paste(base, (0, 0), base)
paste_centered(img, ticket)
img.save("assets/images/app_icon.png")
print("wrote app_icon.png")

# 2) Adaptive icon foreground: transparent bg, white ticket centered in safe zone
fg = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
paste_centered(fg, ticket)
fg.save("assets/images/app_icon_foreground.png")
print("wrote app_icon_foreground.png")
