import os
import math
import shutil
from PIL import Image, ImageDraw, ImageFont, ImageFilter

CANVAS_W = 1280
CANVAS_H = 2856

FONTS_DIR = "C:/Windows/Fonts"
FONT_HEAVY_PATH = os.path.join(FONTS_DIR, "bahnschrift.ttf")
FONT_BOLD_PATH = os.path.join(FONTS_DIR, "segoeuib.ttf")
FONT_REG_PATH = os.path.join(FONTS_DIR, "segoeui.ttf")

WORKSPACE = r"C:\Users\Joel\Documents\Github\1wallet"
RAW_DARK_DIR = os.path.join(WORKSPACE, "store_assets", "raw_screenshots_dark")
RAW_LIGHT_DIR = os.path.join(WORKSPACE, "store_assets", "raw_screenshots_light")
PROMOS_MERGED_DIR = os.path.join(WORKSPACE, "store_assets", "promos_merged")
PROMOS_DARK_DIR = os.path.join(WORKSPACE, "store_assets", "promos_dark")
PROMOS_LIGHT_DIR = os.path.join(WORKSPACE, "store_assets", "promos_light")
STORE_PROMOS_DIR = os.path.join(WORKSPACE, "store_assets", "phone_screenshots")

for d in [PROMOS_MERGED_DIR, PROMOS_DARK_DIR, PROMOS_LIGHT_DIR, STORE_PROMOS_DIR]:
    os.makedirs(d, exist_ok=True)

def get_font(path, size):
    try:
        return ImageFont.truetype(path, size)
    except Exception:
        return ImageFont.load_default()

def create_background(accent_rgb, layout="A"):
    """
    Creates an ultra-clean, luxury background matching Pixel Material You:
    Soft off-white / light slate gradient with flowing organic pastel curves.
    """
    scale = 2
    w, h = CANVAS_W * scale, CANVAS_H * scale
    bg = Image.new("RGBA", (w, h), (250, 252, 255, 255))
    draw = ImageDraw.Draw(bg)

    r, g, b = accent_rgb

    # Base subtle vertical gradient
    for y in range(0, h, 8):
        factor = y / h
        cr = int(252 - factor * 8)
        cg = int(253 - factor * 7)
        cb = int(255 - factor * 5)
        draw.rectangle([0, y, w, y + 8], fill=(cr, cg, cb, 255))

    # Flowing gentle organic pastel waves
    step = 40
    wave1_pts = [(0, 0)]
    for x in range(0, w + step, step):
        t = x / w
        if layout == "A":
            y = int(h * 0.44 + math.sin(t * math.pi * 1.5) * (h * 0.12) + math.cos(t * math.pi * 0.8) * 110)
        else:
            y = int(h * 0.34 + math.cos(t * math.pi * 1.4) * (h * 0.10) + math.sin(t * math.pi * 0.7) * 90)
        wave1_pts.append((x, y))
    wave1_pts.extend([(w, h), (0, h)])
    draw.polygon(wave1_pts, fill=(r, g, b, 24))

    wave2_pts = [(0, 0)]
    for x in range(0, w + step, step):
        t = x / w
        if layout == "A":
            y = int(h * 0.52 + math.sin((t + 0.3) * math.pi * 1.3) * (h * 0.14))
        else:
            y = int(h * 0.40 + math.sin((t + 0.2) * math.pi * 1.2) * (h * 0.12))
        wave2_pts.append((x, y))
    wave2_pts.extend([(w, h), (0, h)])
    draw.polygon(wave2_pts, fill=(r, g, b, 30))

    # Ambient glowing orb behind phone center
    orb = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    orb_draw = ImageDraw.Draw(orb)
    orb_center_y = int(h * 0.62) if layout == "A" else int(h * 0.36)
    orb_draw.ellipse(
        [int(w * 0.10), orb_center_y - int(h * 0.22), int(w * 0.90), orb_center_y + int(h * 0.22)],
        fill=(r, g, b, 28)
    )
    orb = orb.filter(ImageFilter.GaussianBlur(200))
    bg = Image.alpha_composite(bg, orb)

    return bg.resize((CANVAS_W, CANVAS_H), Image.Resampling.LANCZOS)

def create_split_screen(light_path, dark_path, w, h):
    """
    Seamlessly merges Light and Dark theme screens with 100% geometric continuity.
    Left side: Pristine Light Mode
    Right side: Obsidian AMOLED Dark Mode
    """
    im_l = Image.open(light_path).resize((w, h), Image.Resampling.LANCZOS).convert("RGBA")
    im_d = Image.open(dark_path).resize((w, h), Image.Resampling.LANCZOS).convert("RGBA")

    # Diagonal cut across the screen
    mask = Image.new("L", (w, h), 0)
    md = ImageDraw.Draw(mask)
    split_top = int(w * 0.44)
    split_bot = int(w * 0.56)
    md.polygon([(split_top, 0), (w, 0), (w, h), (split_bot, h)], fill=255)

    split_img = Image.composite(im_d, im_l, mask)

    # Clean luminous divider line
    overlay = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    od = ImageDraw.Draw(overlay)
    od.line([(split_top, 0), (split_bot, h)], fill=(255, 255, 255, 190), width=3)

    return Image.alpha_composite(split_img, overlay)

def create_pixel_pro_mockup(screen_img, phone_w=940):
    """
    Creates an authentic Google Pixel Pro flagship device frame:
    - Zero stretching: screen_w and screen_h maintain EXACT 1280:2856 ratio.
    - Symmetrical ultra-thin aerospace aluminum chassis.
    - Pixel signature centered circular front camera punch-hole.
    - Smooth flagship rounded corners.
    """
    bezel = 14
    screen_w = phone_w - (bezel * 2) # 912px
    # Exact proportional height: 912 * (2856 / 1280) = 2034.9 -> 2035px
    screen_h = int(screen_w * (2856.0 / 1280.0))
    phone_h = screen_h + (bezel * 2) # 2063px

    radius_outer = 52
    radius_screen = 40

    phone_layer = Image.new("RGBA", (phone_w, phone_h), (0, 0, 0, 0))
    phone_draw = ImageDraw.Draw(phone_layer)

    # Pixel Pro titanium / aluminum chassis
    phone_draw.rounded_rectangle(
        [0, 0, phone_w, phone_h],
        radius=radius_outer,
        fill=(18, 22, 28, 255),
        outline=(62, 72, 88, 255),
        width=3
    )

    # Inner viewport
    screen_resized = screen_img.resize((screen_w, screen_h), Image.Resampling.LANCZOS)

    # Pixel Pro Centered Camera Punch-hole
    cam_draw = ImageDraw.Draw(screen_resized)
    cam_cx = screen_w // 2
    cam_cy = 38
    cam_r = 13
    # Camera outer ring
    cam_draw.ellipse([cam_cx - cam_r - 2, cam_cy - cam_r - 2, cam_cx + cam_r + 2, cam_cy + cam_r + 2], fill=(24, 28, 36, 255))
    # Camera aperture
    cam_draw.ellipse([cam_cx - cam_r, cam_cy - cam_r, cam_cx + cam_r, cam_cy + cam_r], fill=(0, 0, 0, 255))
    # Camera reflection dot
    cam_draw.ellipse([cam_cx + 3, cam_cy - 4, cam_cx + 6, cam_cy - 1], fill=(45, 55, 75, 255))

    # Rounded screen corner mask
    screen_mask = Image.new("L", (screen_w, screen_h), 0)
    mask_draw = ImageDraw.Draw(screen_mask)
    mask_draw.rounded_rectangle([0, 0, screen_w, screen_h], radius=radius_screen, fill=255)

    phone_layer.paste(screen_resized, (bezel, bezel), screen_mask)
    return phone_layer, phone_w, phone_h

def draw_floating_badge(canvas, center_x, center_y, text, accent_rgb):
    """Draw frosted glass pill badge."""
    font = get_font(FONT_BOLD_PATH, 28)
    bbox = font.getbbox(text)
    tw = bbox[2] - bbox[0]
    th = bbox[3] - bbox[1]

    pad_x = 30
    pad_y = 16
    bw = tw + (pad_x * 2) + 20
    bh = th + (pad_y * 2) + 4
    bx = center_x - (bw // 2)
    by = center_y - (bh // 2)

    sh = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    sh_draw = ImageDraw.Draw(sh)
    sh_draw.rounded_rectangle([bx + 2, by + 10, bx + bw + 2, by + bh + 10], radius=bh // 2, fill=(0, 0, 0, 50))
    sh = sh.filter(ImageFilter.GaussianBlur(14))
    canvas = Image.alpha_composite(canvas, sh)

    draw = ImageDraw.Draw(canvas)
    draw.rounded_rectangle(
        [bx, by, bx + bw, by + bh],
        radius=bh // 2,
        fill=(255, 255, 255, 250),
        outline=(218, 225, 233, 255),
        width=2
    )

    r, g, b = accent_rgb
    dot_r = 6
    dot_cy = by + (bh // 2)
    draw.ellipse([bx + 22, dot_cy - dot_r, bx + 22 + (dot_r * 2), dot_cy + dot_r], fill=(r, g, b, 255))
    draw.text((bx + 44, by + pad_y + 1), text, font=font, fill=(15, 23, 42, 255))
    return canvas

def generate_pixel_card(screen_cfg, screen_img, output_path):
    layout = screen_cfg.get("layout", "A")
    accent = screen_cfg["accent"]

    card = create_background(accent, layout=layout)

    # Pixel Pro mockup: exact 940px wide, zero stretch
    phone_layer, phone_w, phone_h = create_pixel_pro_mockup(screen_img, phone_w=940)
    phone_x = (CANVAS_W - phone_w) // 2

    # Placement in 2856 height canvas
    if layout == "A":
        # Top headline, phone resting below
        phone_y = 660
    else:
        # Inverted: phone starts high, headline below
        phone_y = 130

    # Double drop shadow
    shadow = Image.new("RGBA", (CANVAS_W, CANVAS_H), (0, 0, 0, 0))
    sh_draw = ImageDraw.Draw(shadow)
    sh_draw.rounded_rectangle([phone_x + 10, phone_y + 30, phone_x + phone_w - 10, phone_y + phone_h + 30], radius=54, fill=(0, 0, 0, 44))
    shadow = shadow.filter(ImageFilter.GaussianBlur(44))
    card = Image.alpha_composite(card, shadow)

    shadow_dir = Image.new("RGBA", (CANVAS_W, CANVAS_H), (0, 0, 0, 0))
    shd_draw = ImageDraw.Draw(shadow_dir)
    shd_draw.rounded_rectangle([phone_x + 6, phone_y + 16, phone_x + phone_w - 6, phone_y + phone_h + 16], radius=54, fill=(0, 0, 0, 34))
    shadow_dir = shadow_dir.filter(ImageFilter.GaussianBlur(16))
    card = Image.alpha_composite(card, shadow_dir)

    # Paste phone
    card.paste(phone_layer, (phone_x, phone_y), phone_layer)

    # Floating badge chip
    if "badge" in screen_cfg and screen_cfg["badge"]:
        badge_y = phone_y - 28 if layout == "A" else phone_y + phone_h + 24
        card = draw_floating_badge(card, CANVAS_W // 2, badge_y, screen_cfg["badge"], accent)

    draw = ImageDraw.Draw(card)
    font_head = get_font(FONT_HEAVY_PATH, 72)
    font_sub = get_font(FONT_REG_PATH, 34)
    font_pill = get_font(FONT_BOLD_PATH, 26)

    if layout == "A":
        top_pill = screen_cfg["top_tag"]
        pill_bbox = font_pill.getbbox(top_pill.upper())
        pw = (pill_bbox[2] - pill_bbox[0]) + 44
        ph = (pill_bbox[3] - pill_bbox[1]) + 24
        px = (CANVAS_W - pw) // 2
        py = 110
        draw.rounded_rectangle([px, py, px + pw, py + ph], radius=ph // 2, fill=accent)
        draw.text((px + 22, py + 10), top_pill.upper(), font=font_pill, fill=(255, 255, 255, 255))

        cur_y = py + ph + 32
        for line in screen_cfg["headline"].split("\n"):
            hb = font_head.getbbox(line)
            lw = hb[2] - hb[0]
            draw.text(((CANVAS_W - lw) // 2, cur_y), line, font=font_head, fill=(15, 23, 42, 255))
            cur_y += 82

        cur_y += 8
        for line in screen_cfg["subtitle"].split("\n"):
            sb = font_sub.getbbox(line)
            lw = sb[2] - sb[0]
            draw.text(((CANVAS_W - lw) // 2, cur_y), line, font=font_sub, fill=(100, 116, 139, 255))
            cur_y += 46
    else:
        cur_y = phone_y + phone_h + 70
        for line in screen_cfg["headline"].split("\n"):
            hb = font_head.getbbox(line)
            lw = hb[2] - hb[0]
            draw.text(((CANVAS_W - lw) // 2, cur_y), line, font=font_head, fill=(15, 23, 42, 255))
            cur_y += 80

        cur_y += 6
        for line in screen_cfg["subtitle"].split("\n"):
            sb = font_sub.getbbox(line)
            lw = sb[2] - sb[0]
            draw.text(((CANVAS_W - lw) // 2, cur_y), line, font=font_sub, fill=(100, 116, 139, 255))
            cur_y += 44

        cta_text = screen_cfg.get("cta", "Explore Feature")
        cta_bbox = font_pill.getbbox(cta_text)
        cw = (cta_bbox[2] - cta_bbox[0]) + 56
        ch = (cta_bbox[3] - cta_bbox[1]) + 28
        cx = (CANVAS_W - cw) // 2
        cy = cur_y + 16
        draw.rounded_rectangle([cx, cy, cx + cw, cy + ch], radius=ch // 2, fill=accent)
        draw.text((cx + 28, cy + 12), cta_text, font=font_pill, fill=(255, 255, 255, 255))

    # Bottom Category Dock (1280 resolution)
    bot_w = 1060
    bot_h = 92
    bot_x = (CANVAS_W - bot_w) // 2
    bot_y = CANVAS_H - bot_h - 60
    draw.rounded_rectangle([bot_x, bot_y, bot_x + bot_w, bot_y + bot_h], radius=26, fill=(15, 20, 30, 255))

    font_bot_tag = get_font(FONT_BOLD_PATH, 32)
    font_bot_num = get_font(FONT_HEAVY_PATH, 32)
    draw.text((bot_x + 44, bot_y + 26), screen_cfg["bottom_tag"], font=font_bot_tag, fill=(255, 255, 255, 255))
    draw.text((bot_x + bot_w - 90, bot_y + 26), screen_cfg["screen_num"], font=font_bot_num, fill=(148, 163, 184, 255))

    final_card = card.convert("RGB")
    final_card.save(output_path, "PNG")
    print(f"Generated: {output_path}")

CONFIGS = [
    {
        "id": 1,
        "layout": "A",
        "top_tag": "Smart Ledger",
        "headline": "All your wealth,\nin one unified view",
        "subtitle": "Track cash flow, net worth, and liquid assets\nwith mathematical double-entry integrity.",
        "badge": "Day & Night Theme Continuity",
        "bottom_tag": "Dashboard",
        "screen_num": "01",
        "accent": (37, 99, 235)  # Royal Blue
    },
    {
        "id": 2,
        "layout": "A",
        "top_tag": "Analytics & Trends",
        "headline": "Project trends &\nvisualize your runway",
        "subtitle": "Forecast historical net worth growth and project\nfuture financial health with precision charts.",
        "badge": "Real-Time Balance Horizons",
        "bottom_tag": "Analytics",
        "screen_num": "02",
        "accent": (124, 58, 237)  # Violet
    },
    {
        "id": 3,
        "layout": "B",
        "headline": "Every transaction,\ninstantly organized",
        "subtitle": "Filter by account, date, or category with\ninstant search across your entire history.",
        "cta": "Search Records",
        "badge": "Instant Search & Category Filters",
        "bottom_tag": "Transactions",
        "screen_num": "03",
        "accent": (5, 150, 105)  # Emerald
    },
    {
        "id": 4,
        "layout": "A",
        "top_tag": "Automated Bills",
        "headline": "Never miss a bill\nor recurring cadence",
        "subtitle": "Manage planned expenses, utility cadences,\nand subscriptions with smart alerts.",
        "badge": "Zero Late Fees Guaranteed",
        "bottom_tag": "Bills & Subscriptions",
        "screen_num": "04",
        "accent": (217, 119, 6)  # Amber
    },
    {
        "id": 5,
        "layout": "B",
        "headline": "Master your loans\nand EMI payoffs",
        "subtitle": "Track payoff schedules, interest rates, and\nloan amortization with clear visual progress.",
        "cta": "Track Payoffs",
        "badge": "EMI Amortization Progress",
        "bottom_tag": "Loans & Debt",
        "screen_num": "05",
        "accent": (225, 29, 72)  # Rose Red
    },
    {
        "id": 6,
        "layout": "A",
        "top_tag": "Global Accounts",
        "headline": "Multi-currency &\nreal-time exchange",
        "subtitle": "Manage bank accounts, savings, and wallets\nacross USD, EUR, GBP, JPY, and INR.",
        "badge": "160+ Currencies Supported",
        "bottom_tag": "Accounts & Forex",
        "screen_num": "06",
        "accent": (13, 148, 136)  # Teal
    },
    {
        "id": 7,
        "layout": "A",
        "top_tag": "Precise Logging",
        "headline": "Fast logging with\nrich receipt details",
        "subtitle": "Attach receipt photos, tags, places, and notes\nwith an intuitive single-tap entry keypad.",
        "badge": "Receipt Photos & Itemized Tags",
        "bottom_tag": "Expense Details",
        "screen_num": "07",
        "accent": (79, 70, 229)  # Indigo
    },
    {
        "id": 8,
        "layout": "B",
        "headline": "Visualize cash flow\nday by day",
        "subtitle": "Calendar matrix shows daily inflow and outflow\nso you always know your upcoming liquidity.",
        "cta": "View Calendar",
        "badge": "Daily Cash Flow Matrix",
        "bottom_tag": "Cash Calendar",
        "screen_num": "08",
        "accent": (6, 182, 212)  # Cyan
    }
]

def main():
    print("=== Generating Merged Day & Night Continuity Promo Cards (1280x2856) ===")
    for cfg in CONFIGS:
        light_file = os.path.join(RAW_LIGHT_DIR, f"screenshot_phone_{cfg['id']}.png")
        dark_file = os.path.join(RAW_DARK_DIR, f"screenshot_phone_{cfg['id']}.png")
        
        # 1. Merged split screen (Day & Night in same phone with continuity)
        split_img = create_split_screen(light_file, dark_file, 912, 2035)
        merged_out = os.path.join(PROMOS_MERGED_DIR, f"playstore_promo_{cfg['id']}.png")
        generate_pixel_card(cfg, split_img, merged_out)
        
        # Copy to default phone_screenshots for Google Play Store upload
        shutil.copyfile(merged_out, os.path.join(STORE_PROMOS_DIR, f"playstore_promo_{cfg['id']}.png"))

    print("\n=== Generating Pure Dark Theme Cards (1280x2856) ===")
    for cfg in CONFIGS:
        dark_file = os.path.join(RAW_DARK_DIR, f"screenshot_phone_{cfg['id']}.png")
        dark_img = Image.open(dark_file).convert("RGBA")
        dark_out = os.path.join(PROMOS_DARK_DIR, f"playstore_promo_{cfg['id']}.png")
        generate_pixel_card(cfg, dark_img, dark_out)

    print("\n=== Generating Pure Light (White) Theme Cards (1280x2856) ===")
    for cfg in CONFIGS:
        light_file = os.path.join(RAW_LIGHT_DIR, f"screenshot_phone_{cfg['id']}.png")
        light_img = Image.open(light_file).convert("RGBA")
        light_out = os.path.join(PROMOS_LIGHT_DIR, f"playstore_promo_{cfg['id']}.png")
        generate_pixel_card(cfg, light_img, light_out)

    print("\nALL PIXEL PRO PROMO CARDS GENERATED SUCCESSFULLY!")

if __name__ == "__main__":
    main()
