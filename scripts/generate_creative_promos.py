import os
import math
import shutil
from PIL import Image, ImageDraw, ImageFont, ImageFilter

CANVAS_W = 1080
CANVAS_H = 2160

FONTS_DIR = "C:/Windows/Fonts"
FONT_HEAVY_PATH = os.path.join(FONTS_DIR, "bahnschrift.ttf")
FONT_BOLD_PATH = os.path.join(FONTS_DIR, "segoeuib.ttf")
FONT_REG_PATH = os.path.join(FONTS_DIR, "segoeui.ttf")

def get_font(path, size):
    try:
        return ImageFont.truetype(path, size)
    except Exception:
        return ImageFont.load_default()

def create_background(accent_rgb, layout="A"):
    """
    Creates an ultra-clean, luxury background:
    - Soft, pristine white-to-light-cool-gray gradient
    - Gentle, flowing organic pastel curves (low opacity, never muddy or overwhelming)
    - High contrast guaranteed for all text areas.
    """
    scale = 2
    w, h = CANVAS_W * scale, CANVAS_H * scale
    bg = Image.new("RGBA", (w, h), (249, 250, 253, 255))
    draw = ImageDraw.Draw(bg)

    r, g, b = accent_rgb

    # Base subtle vertical gradient (very soft and clean)
    for y in range(0, h, 8):
        factor = y / h
        # Pristine off-white top to gentle soft-slate bottom
        cr = int(252 - factor * 8)
        cg = int(253 - factor * 7)
        cb = int(255 - factor * 5)
        draw.rectangle([0, y, w, y + 8], fill=(cr, cg, cb, 255))

    # Gentle ambient waves (rendered behind the phone)
    step = 40
    wave1_pts = [(0, 0)]
    for x in range(0, w + step, step):
        t = x / w
        if layout == "A":
            # Flowing wave across lower mid section
            y = int(h * 0.46 + math.sin(t * math.pi * 1.5) * (h * 0.12) + math.cos(t * math.pi * 0.8) * 90)
        else:
            # Flowing wave across upper mid section
            y = int(h * 0.35 + math.cos(t * math.pi * 1.4) * (h * 0.10) + math.sin(t * math.pi * 0.7) * 80)
        wave1_pts.append((x, y))
    wave1_pts.extend([(w, h), (0, h)])
    # Low opacity tint (14%)
    draw.polygon(wave1_pts, fill=(r, g, b, 24))

    wave2_pts = [(0, 0)]
    for x in range(0, w + step, step):
        t = x / w
        if layout == "A":
            y = int(h * 0.54 + math.sin((t + 0.3) * math.pi * 1.3) * (h * 0.14))
        else:
            y = int(h * 0.42 + math.sin((t + 0.2) * math.pi * 1.2) * (h * 0.12))
        wave2_pts.append((x, y))
    wave2_pts.extend([(w, h), (0, h)])
    # Slightly richer accent curve (18%)
    draw.polygon(wave2_pts, fill=(r, g, b, 30))

    # Soft glowing ambient orb centered behind phone body
    orb = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    orb_draw = ImageDraw.Draw(orb)
    orb_center_y = int(h * 0.60) if layout == "A" else int(h * 0.36)
    orb_draw.ellipse(
        [int(w * 0.12), orb_center_y - int(h * 0.20), int(w * 0.88), orb_center_y + int(h * 0.20)],
        fill=(r, g, b, 28)
    )
    orb = orb.filter(ImageFilter.GaussianBlur(180))
    bg = Image.alpha_composite(bg, orb)

    return bg.resize((CANVAS_W, CANVAS_H), Image.Resampling.LANCZOS)

def create_phone_mockup(raw_screenshot_path, phone_w=840, phone_h=1400):
    """
    Creates a flagship smartphone mockup:
    - Crops out Android OS status bar (y=0..80) and nav bar (y=1850..1920)
    - Renders titanium dark chassis frame
    - Pristine 9:41 status bar with Dynamic Island and crisp battery/signal
    - Bottom home indicator
    """
    bezel = 14
    screen_w = phone_w - (bezel * 2)
    screen_h = phone_h - (bezel * 2)
    radius_outer = 54
    radius_screen = 42

    phone_layer = Image.new("RGBA", (phone_w, phone_h), (0, 0, 0, 0))
    phone_draw = ImageDraw.Draw(phone_layer)

    # Outer titanium phone chassis
    phone_draw.rounded_rectangle(
        [0, 0, phone_w, phone_h],
        radius=radius_outer,
        fill=(14, 17, 23, 255),
        outline=(55, 65, 81, 255),
        width=3
    )

    # Screen viewport canvas (dark obsidian background matching app)
    screen_canvas = Image.new("RGBA", (screen_w, screen_h), (14, 14, 16, 255))

    if os.path.exists(raw_screenshot_path):
        raw_img = Image.open(raw_screenshot_path).convert("RGBA")
        # Crop: strip ugly top status bar (y=0..80) and bottom nav bar (y=1850..1920)
        cropped = raw_img.crop((0, 80, 1080, 1850))
        status_bar_h = 58
        app_content_h = screen_h - status_bar_h - 18
        app_resized = cropped.resize((screen_w, app_content_h), Image.Resampling.LANCZOS)
        screen_canvas.paste(app_resized, (0, status_bar_h))

    # Pristine Marketing Status Bar
    sb_draw = ImageDraw.Draw(screen_canvas)

    # Time 9:41
    font_time = get_font(FONT_HEAVY_PATH, 22)
    sb_draw.text((36, 17), "9:41", font=font_time, fill=(255, 255, 255, 245))

    # Dynamic Island
    island_w = 114
    island_h = 28
    island_x = (screen_w - island_w) // 2
    island_y = 15
    sb_draw.rounded_rectangle(
        [island_x, island_y, island_x + island_w, island_y + island_h],
        radius=island_h // 2,
        fill=(0, 0, 0, 255),
        outline=(32, 34, 38, 255),
        width=1
    )
    # Camera dot inside island
    sb_draw.ellipse([island_x + island_w - 24, island_y + 8, island_x + island_w - 12, island_y + 20], fill=(20, 26, 40, 255))

    # Cellular signal bars (4 bars)
    sig_x = screen_w - 110
    sig_y = 22
    for b_idx in range(4):
        bh = 4 + (b_idx * 3)
        sb_draw.rounded_rectangle(
            [sig_x + (b_idx * 6), sig_y + 12 - bh, sig_x + (b_idx * 6) + 4, sig_y + 12],
            radius=1,
            fill=(255, 255, 255, 240)
        )

    # Battery icon
    bat_x = screen_w - 68
    bat_y = 20
    sb_draw.rounded_rectangle([bat_x, bat_y, bat_x + 28, bat_y + 14], radius=4, outline=(255, 255, 255, 230), width=2)
    sb_draw.rectangle([bat_x + 29, bat_y + 4, bat_x + 31, bat_y + 10], fill=(255, 255, 255, 200))
    sb_draw.rounded_rectangle([bat_x + 3, bat_y + 3, bat_x + 22, bat_y + 11], radius=2, fill=(255, 255, 255, 240))

    # Home indicator bar at bottom
    home_w = 140
    home_h = 5
    home_x = (screen_w - home_w) // 2
    home_y = screen_h - 14
    sb_draw.rounded_rectangle([home_x, home_y, home_x + home_w, home_y + home_h], radius=2, fill=(255, 255, 255, 120))

    # Rounded corner mask for screen viewport
    screen_mask = Image.new("L", (screen_w, screen_h), 0)
    mask_draw = ImageDraw.Draw(screen_mask)
    mask_draw.rounded_rectangle([0, 0, screen_w, screen_h], radius=radius_screen, fill=255)

    phone_layer.paste(screen_canvas, (bezel, bezel), screen_mask)
    return phone_layer

def draw_floating_badge(canvas, center_x, center_y, text, accent_rgb):
    """Draw a luxury frosted floating feature chip over the mockup."""
    font = get_font(FONT_BOLD_PATH, 24)
    bbox = font.getbbox(text)
    tw = bbox[2] - bbox[0]
    th = bbox[3] - bbox[1]

    pad_x = 24
    pad_y = 12
    bw = tw + (pad_x * 2) + 16
    bh = th + (pad_y * 2) + 4
    bx = center_x - (bw // 2)
    by = center_y - (bh // 2)

    # Soft ambient drop shadow for badge
    sh = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    sh_draw = ImageDraw.Draw(sh)
    sh_draw.rounded_rectangle([bx + 2, by + 8, bx + bw + 2, by + bh + 8], radius=bh // 2, fill=(0, 0, 0, 50))
    sh = sh.filter(ImageFilter.GaussianBlur(12))
    canvas = Image.alpha_composite(canvas, sh)

    draw = ImageDraw.Draw(canvas)
    # White glass capsule body
    draw.rounded_rectangle(
        [bx, by, bx + bw, by + bh],
        radius=bh // 2,
        fill=(255, 255, 255, 250),
        outline=(218, 225, 233, 255),
        width=2
    )

    # Accent dot indicator
    r, g, b = accent_rgb
    dot_r = 5
    dot_cy = by + (bh // 2)
    draw.ellipse([bx + 18, dot_cy - dot_r, bx + 18 + (dot_r * 2), dot_cy + dot_r], fill=(r, g, b, 255))

    # Text
    draw.text((bx + 38, by + pad_y + 1), text, font=font, fill=(15, 23, 42, 255))
    return canvas

def generate_card(screen_cfg, output_path):
    layout = screen_cfg.get("layout", "A") # "A" = top headline, "B" = inverted (phone top)
    accent = screen_cfg["accent"]

    # 1. Clean background
    card = create_background(accent, layout=layout)

    # 2. Mockup dimensions
    phone_w = 840
    phone_h = 1420
    phone_x = (CANVAS_W - phone_w) // 2

    if layout == "A":
        # Layout A: Top headline, phone below
        phone_y = 560
    else:
        # Layout B: Inverted, phone at top, headline below
        phone_y = 110

    # 3. Double realistic drop shadow for phone
    shadow = Image.new("RGBA", (CANVAS_W, CANVAS_H), (0, 0, 0, 0))
    sh_draw = ImageDraw.Draw(shadow)
    # Diffuse ambient
    sh_draw.rounded_rectangle(
        [phone_x + 8, phone_y + 26, phone_x + phone_w - 8, phone_y + phone_h + 26],
        radius=54,
        fill=(0, 0, 0, 42)
    )
    shadow = shadow.filter(ImageFilter.GaussianBlur(38))
    card = Image.alpha_composite(card, shadow)

    # Directional shadow
    shadow_dir = Image.new("RGBA", (CANVAS_W, CANVAS_H), (0, 0, 0, 0))
    shd_draw = ImageDraw.Draw(shadow_dir)
    shd_draw.rounded_rectangle(
        [phone_x + 4, phone_y + 14, phone_x + phone_w - 4, phone_y + phone_h + 14],
        radius=54,
        fill=(0, 0, 0, 32)
    )
    shadow_dir = shadow_dir.filter(ImageFilter.GaussianBlur(14))
    card = Image.alpha_composite(card, shadow_dir)

    # 4. Paste phone mockup
    phone = create_phone_mockup(screen_cfg["screenshot"], phone_w, phone_h)
    card.paste(phone, (phone_x, phone_y), phone)

    # 5. Floating feature badge
    if "badge" in screen_cfg and screen_cfg["badge"]:
        if layout == "A":
            # Float right above the phone bezel as a clean connector
            badge_y = phone_y - 22
            badge_x = CANVAS_W // 2
        else:
            # Inverted layout: Float between phone and bottom headline
            badge_y = phone_y + phone_h + 20
            badge_x = CANVAS_W // 2
        card = draw_floating_badge(card, badge_x, badge_y, screen_cfg["badge"], accent)

    draw = ImageDraw.Draw(card)

    # 6. Typography rendering
    font_head = get_font(FONT_HEAVY_PATH, 58)
    font_sub = get_font(FONT_REG_PATH, 28)
    font_pill = get_font(FONT_BOLD_PATH, 22)

    if layout == "A":
        # Top pill badge (e.g. "SMART LEDGER")
        top_pill = screen_cfg["top_tag"]
        pill_bbox = font_pill.getbbox(top_pill.upper())
        pw = (pill_bbox[2] - pill_bbox[0]) + 36
        ph = (pill_bbox[3] - pill_bbox[1]) + 20
        px = (CANVAS_W - pw) // 2
        py = 90
        draw.rounded_rectangle([px, py, px + pw, py + ph], radius=ph // 2, fill=accent)
        draw.text((px + 18, py + 8), top_pill.upper(), font=font_pill, fill=(255, 255, 255, 255))

        # Headline
        cur_y = py + ph + 26
        for line in screen_cfg["headline"].split("\n"):
            hb = font_head.getbbox(line)
            lw = hb[2] - hb[0]
            draw.text(((CANVAS_W - lw) // 2, cur_y), line, font=font_head, fill=(15, 23, 42, 255))
            cur_y += 66

        # Subtitle
        cur_y += 6
        for line in screen_cfg["subtitle"].split("\n"):
            sb = font_sub.getbbox(line)
            lw = sb[2] - sb[0]
            draw.text(((CANVAS_W - lw) // 2, cur_y), line, font=font_sub, fill=(100, 116, 139, 255))
            cur_y += 38

    else:
        # Inverted layout: Text below phone
        cur_y = phone_y + phone_h + 58
        # Headline
        for line in screen_cfg["headline"].split("\n"):
            hb = font_head.getbbox(line)
            lw = hb[2] - hb[0]
            draw.text(((CANVAS_W - lw) // 2, cur_y), line, font=font_head, fill=(15, 23, 42, 255))
            cur_y += 64

        # Subtitle
        cur_y += 4
        for line in screen_cfg["subtitle"].split("\n"):
            sb = font_sub.getbbox(line)
            lw = sb[2] - sb[0]
            draw.text(((CANVAS_W - lw) // 2, cur_y), line, font=font_sub, fill=(100, 116, 139, 255))
            cur_y += 36

        # Call to action capsule button
        cta_text = screen_cfg.get("cta", "Explore Feature")
        cta_bbox = font_pill.getbbox(cta_text)
        cw = (cta_bbox[2] - cta_bbox[0]) + 48
        ch = (cta_bbox[3] - cta_bbox[1]) + 24
        cx = (CANVAS_W - cw) // 2
        cy = cur_y + 12
        draw.rounded_rectangle([cx, cy, cx + cw, cy + ch], radius=ch // 2, fill=accent)
        draw.text((cx + 24, cy + 9), cta_text, font=font_pill, fill=(255, 255, 255, 255))

    # 7. Sleek Bottom Category Dock (Shipshot signature element)
    bot_w = 920
    bot_h = 76
    bot_x = (CANVAS_W - bot_w) // 2
    bot_y = CANVAS_H - bot_h - 48

    draw.rounded_rectangle([bot_x, bot_y, bot_x + bot_w, bot_y + bot_h], radius=22, fill=(15, 20, 30, 255))

    font_bot_tag = get_font(FONT_BOLD_PATH, 26)
    font_bot_num = get_font(FONT_HEAVY_PATH, 26)

    draw.text((bot_x + 36, bot_y + 22), screen_cfg["bottom_tag"], font=font_bot_tag, fill=(255, 255, 255, 255))
    draw.text((bot_x + bot_w - 74, bot_y + 22), screen_cfg["screen_num"], font=font_bot_num, fill=(148, 163, 184, 255))

    # 8. Convert to pure 24-bit RGB (strict Google Play specification)
    final_card = card.convert("RGB")
    final_card.save(output_path, "PNG")
    print(f"Generated: {output_path}")

PROMO_SCREENS = [
    {
        "id": 1,
        "layout": "A",
        "screenshot": "android/fastlane/metadata/android/en-US/images/screenshot_phone_1.png",
        "top_tag": "Smart Ledger",
        "headline": "All your wealth,\nin one unified view",
        "subtitle": "Track cash flow, net worth, and liquid assets\nwith mathematical double-entry integrity.",
        "badge": "Total Wealth & Liquid Balances",
        "bottom_tag": "Dashboard",
        "screen_num": "01",
        "accent": (37, 99, 235)  # Royal Blue
    },
    {
        "id": 2,
        "layout": "A",
        "screenshot": "android/fastlane/metadata/android/en-US/images/screenshot_phone_2.png",
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
        "layout": "B",  # INVERTED LAYOUT (Phone top, text below)
        "screenshot": "android/fastlane/metadata/android/en-US/images/screenshot_phone_3.png",
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
        "screenshot": "android/fastlane/metadata/android/en-US/images/screenshot_phone_4.png",
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
        "layout": "B",  # INVERTED LAYOUT
        "screenshot": "android/fastlane/metadata/android/en-US/images/screenshot_phone_5.png",
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
        "screenshot": "android/fastlane/metadata/android/en-US/images/screenshot_phone_6.png",
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
        "screenshot": "android/fastlane/metadata/android/en-US/images/screenshot_phone_7.png",
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
        "layout": "B",  # INVERTED LAYOUT
        "screenshot": "android/fastlane/metadata/android/en-US/images/screenshot_phone_8.png",
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
    main_dir = os.path.abspath("store_assets/phone_screenshots")
    copy_dir = os.path.abspath("android/fastlane/metadata/android/en-US/images/promo_cards")
    os.makedirs(main_dir, exist_ok=True)
    os.makedirs(copy_dir, exist_ok=True)

    for cfg in PROMO_SCREENS:
        out_file = os.path.join(main_dir, f"playstore_promo_{cfg['id']}.png")
        generate_card(cfg, out_file)
        copy_file = os.path.join(copy_dir, f"playstore_promo_{cfg['id']}.png")
        shutil.copyfile(out_file, copy_file)

if __name__ == "__main__":
    main()
