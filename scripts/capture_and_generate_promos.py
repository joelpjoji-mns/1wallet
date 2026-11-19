import os
import sys
import time
import subprocess
from PIL import Image, ImageDraw, ImageFont, ImageFilter
import math
import shutil

# Directories
WORKSPACE = r"C:\Users\Joel\Documents\Github\1wallet"
RAW_DARK_DIR = os.path.join(WORKSPACE, "store_assets", "raw_screenshots_dark")
RAW_LIGHT_DIR = os.path.join(WORKSPACE, "store_assets", "raw_screenshots_light")
PROMOS_DARK_DIR = os.path.join(WORKSPACE, "store_assets", "promos_dark")
PROMOS_LIGHT_DIR = os.path.join(WORKSPACE, "store_assets", "promos_light")
STORE_PROMOS_DIR = os.path.join(WORKSPACE, "store_assets", "phone_screenshots")
FASTLANE_DIR = os.path.join(WORKSPACE, "android", "fastlane", "metadata", "android", "en-US", "images", "promo_cards")

for d in [RAW_DARK_DIR, RAW_LIGHT_DIR, PROMOS_DARK_DIR, PROMOS_LIGHT_DIR, STORE_PROMOS_DIR, FASTLANE_DIR]:
    os.makedirs(d, exist_ok=True)

def adb(cmd):
    full_cmd = f"adb {cmd}"
    res = subprocess.run(full_cmd, shell=True, capture_output=True, text=True)
    return res.stdout.strip()

def tap(x, y, delay=0.8):
    adb(f"shell input tap {x} {y}")
    time.sleep(delay)

def swipe(x1, y1, x2, y2, duration=300, delay=0.8):
    adb(f"shell input swipe {x1} {y1} {x2} {y2} {duration}")
    time.sleep(delay)

def screencap(save_path):
    remote = "/sdcard/temp_screen.png"
    adb(f"shell screencap -p {remote}")
    adb(f"pull {remote} \"{save_path}\"")
    time.sleep(0.3)
    print(f"Captured uncropped: {save_path}")

def bring_to_front():
    adb("shell am start -n com.joelpjoji.one.wallet/.MainActivity")
    time.sleep(0.6)

def go_to_home_tab():
    bring_to_front()
    tap(160, 2650, delay=0.6) # Home tab
    # Scroll to top of Home
    swipe(640, 600, 640, 2400, 300, delay=0.6)
    swipe(640, 600, 640, 2400, 300, delay=0.6)

def set_app_theme(theme="dark"):
    """Navigate to Settings -> Theme mode -> select Light or Dark"""
    go_to_home_tab()
    tap(74, 216, delay=0.8) # drawer
    swipe(400, 2200, 400, 600, 300, delay=0.8) # swipe up in drawer
    tap(300, 2300, delay=1.0) # settings
    tap(400, 1660, delay=1.0) # theme mode
    if theme == "light":
        tap(400, 1330, delay=1.2) # select light theme
        print("Switched app theme to: LIGHT")
    else:
        tap(400, 1500, delay=1.2) # select dark (AMOLED)
        print("Switched app theme to: DARK")
    # In-app back navigation
    tap(74, 216, delay=0.8)
    tap(74, 216, delay=0.8)
    go_to_home_tab()

def capture_all_8(output_dir):
    print(f"=== Starting capture sequence for: {output_dir} ===")
    
    # 1. Screen 1: Home Dashboard (Top - Net Worth & All Accounts)
    go_to_home_tab()
    screencap(os.path.join(output_dir, "screenshot_phone_1.png"))
    
    # 2. Screen 2: Home Scrolled (Balance Trend Chart & Currency Calculator)
    # Swipe up from gap between cards
    swipe(50, 1800, 50, 800, 350, delay=1.0)
    screencap(os.path.join(output_dir, "screenshot_phone_2.png"))
    
    # 3. Screen 3: Transactions History
    bring_to_front()
    tap(400, 2650, delay=1.0) # History tab
    screencap(os.path.join(output_dir, "screenshot_phone_3.png"))
    
    # 4. Screen 4: Planned Payments
    go_to_home_tab()
    tap(74, 216, delay=0.8) # Drawer
    tap(300, 1350, delay=1.0) # Planned payments
    screencap(os.path.join(output_dir, "screenshot_phone_4.png"))
    tap(74, 216, delay=0.8) # in-app back
    
    # 5. Screen 5: Loans & Debt Control
    go_to_home_tab()
    tap(74, 216, delay=0.8) # Drawer
    tap(300, 1680, delay=1.0) # Loans
    screencap(os.path.join(output_dir, "screenshot_phone_5.png"))
    tap(74, 216, delay=0.8) # in-app back
    
    # 6. Screen 6: Accounts Tab
    bring_to_front()
    tap(1000, 2650, delay=1.0) # Accounts tab
    screencap(os.path.join(output_dir, "screenshot_phone_6.png"))
    
    # 7. Screen 7: Add/Edit Record Details
    go_to_home_tab()
    tap(1100, 2440, delay=1.0) # + FAB
    tap(730, 520, delay=0.8) # Details tab
    tap(200, 360, delay=0.8) # Expense tab
    screencap(os.path.join(output_dir, "screenshot_phone_7.png"))
    tap(74, 216, delay=0.8) # in-app back
    
    # 8. Screen 8: Cash Calendar
    bring_to_front()
    tap(650, 2650, delay=1.0) # Calendar tab
    screencap(os.path.join(output_dir, "screenshot_phone_8.png"))
    
    go_to_home_tab()
    print(f"=== Completed capture sequence for: {output_dir} ===")

# ================= PROMO GENERATION LOGIC =================
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

def create_background(accent_rgb, layout="A", is_light_theme=False):
    scale = 2
    w, h = CANVAS_W * scale, CANVAS_H * scale
    
    base_color = (250, 251, 254, 255)
    bg = Image.new("RGBA", (w, h), base_color)
    draw = ImageDraw.Draw(bg)

    r, g, b = accent_rgb

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
            y = int(h * 0.46 + math.sin(t * math.pi * 1.5) * (h * 0.12) + math.cos(t * math.pi * 0.8) * 90)
        else:
            y = int(h * 0.35 + math.cos(t * math.pi * 1.4) * (h * 0.10) + math.sin(t * math.pi * 0.7) * 80)
        wave1_pts.append((x, y))
    wave1_pts.extend([(w, h), (0, h)])
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
    draw.polygon(wave2_pts, fill=(r, g, b, 30))

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

def create_phone_mockup(raw_screenshot_path, phone_w=840, phone_h=1420, is_light_theme=False):
    bezel = 14
    screen_w = phone_w - (bezel * 2)
    screen_h = phone_h - (bezel * 2)
    radius_outer = 54
    radius_screen = 42

    phone_layer = Image.new("RGBA", (phone_w, phone_h), (0, 0, 0, 0))
    phone_draw = ImageDraw.Draw(phone_layer)

    # Frame chassis
    frame_fill = (14, 17, 23, 255) if not is_light_theme else (24, 28, 36, 255)
    frame_outline = (55, 65, 81, 255) if not is_light_theme else (90, 100, 115, 255)

    phone_draw.rounded_rectangle(
        [0, 0, phone_w, phone_h],
        radius=radius_outer,
        fill=frame_fill,
        outline=frame_outline,
        width=3
    )

    bg_screen = (14, 14, 16, 255) if not is_light_theme else (255, 255, 255, 255)
    screen_canvas = Image.new("RGBA", (screen_w, screen_h), bg_screen)

    if os.path.exists(raw_screenshot_path):
        raw_img = Image.open(raw_screenshot_path).convert("RGBA")
        app_resized = raw_img.resize((screen_w, screen_h), Image.Resampling.LANCZOS)
        screen_canvas.paste(app_resized, (0, 0))

    # Mask screen viewport with clean rounded corners
    screen_mask = Image.new("L", (screen_w, screen_h), 0)
    mask_draw = ImageDraw.Draw(screen_mask)
    mask_draw.rounded_rectangle([0, 0, screen_w, screen_h], radius=radius_screen, fill=255)

    phone_layer.paste(screen_canvas, (bezel, bezel), screen_mask)
    return phone_layer

def draw_floating_badge(canvas, center_x, center_y, text, accent_rgb):
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

    sh = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    sh_draw = ImageDraw.Draw(sh)
    sh_draw.rounded_rectangle([bx + 2, by + 8, bx + bw + 2, by + bh + 8], radius=bh // 2, fill=(0, 0, 0, 50))
    sh = sh.filter(ImageFilter.GaussianBlur(12))
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
    dot_r = 5
    dot_cy = by + (bh // 2)
    draw.ellipse([bx + 18, dot_cy - dot_r, bx + 18 + (dot_r * 2), dot_cy + dot_r], fill=(r, g, b, 255))
    draw.text((bx + 38, by + pad_y + 1), text, font=font, fill=(15, 23, 42, 255))
    return canvas

def generate_promo_card(screen_cfg, raw_screenshot_path, output_path, is_light_theme=False):
    layout = screen_cfg.get("layout", "A")
    accent = screen_cfg["accent"]

    card = create_background(accent, layout=layout, is_light_theme=is_light_theme)

    phone_w = 840
    phone_h = 1420
    phone_x = (CANVAS_W - phone_w) // 2
    phone_y = 560 if layout == "A" else 110

    # Double soft drop shadow
    shadow = Image.new("RGBA", (CANVAS_W, CANVAS_H), (0, 0, 0, 0))
    sh_draw = ImageDraw.Draw(shadow)
    sh_draw.rounded_rectangle([phone_x + 8, phone_y + 26, phone_x + phone_w - 8, phone_y + phone_h + 26], radius=54, fill=(0, 0, 0, 42))
    shadow = shadow.filter(ImageFilter.GaussianBlur(38))
    card = Image.alpha_composite(card, shadow)

    shadow_dir = Image.new("RGBA", (CANVAS_W, CANVAS_H), (0, 0, 0, 0))
    shd_draw = ImageDraw.Draw(shadow_dir)
    shd_draw.rounded_rectangle([phone_x + 4, phone_y + 14, phone_x + phone_w - 4, phone_y + phone_h + 14], radius=54, fill=(0, 0, 0, 32))
    shadow_dir = shadow_dir.filter(ImageFilter.GaussianBlur(14))
    card = Image.alpha_composite(card, shadow_dir)

    phone = create_phone_mockup(raw_screenshot_path, phone_w, phone_h, is_light_theme=is_light_theme)
    card.paste(phone, (phone_x, phone_y), phone)

    if "badge" in screen_cfg and screen_cfg["badge"]:
        badge_y = phone_y - 22 if layout == "A" else phone_y + phone_h + 20
        card = draw_floating_badge(card, CANVAS_W // 2, badge_y, screen_cfg["badge"], accent)

    draw = ImageDraw.Draw(card)
    font_head = get_font(FONT_HEAVY_PATH, 58)
    font_sub = get_font(FONT_REG_PATH, 28)
    font_pill = get_font(FONT_BOLD_PATH, 22)

    if layout == "A":
        top_pill = screen_cfg["top_tag"]
        pill_bbox = font_pill.getbbox(top_pill.upper())
        pw = (pill_bbox[2] - pill_bbox[0]) + 36
        ph = (pill_bbox[3] - pill_bbox[1]) + 20
        px = (CANVAS_W - pw) // 2
        py = 90
        draw.rounded_rectangle([px, py, px + pw, py + ph], radius=ph // 2, fill=accent)
        draw.text((px + 18, py + 8), top_pill.upper(), font=font_pill, fill=(255, 255, 255, 255))

        cur_y = py + ph + 26
        for line in screen_cfg["headline"].split("\n"):
            hb = font_head.getbbox(line)
            lw = hb[2] - hb[0]
            draw.text(((CANVAS_W - lw) // 2, cur_y), line, font=font_head, fill=(15, 23, 42, 255))
            cur_y += 66

        cur_y += 6
        for line in screen_cfg["subtitle"].split("\n"):
            sb = font_sub.getbbox(line)
            lw = sb[2] - sb[0]
            draw.text(((CANVAS_W - lw) // 2, cur_y), line, font=font_sub, fill=(100, 116, 139, 255))
            cur_y += 38
    else:
        cur_y = phone_y + phone_h + 58
        for line in screen_cfg["headline"].split("\n"):
            hb = font_head.getbbox(line)
            lw = hb[2] - hb[0]
            draw.text(((CANVAS_W - lw) // 2, cur_y), line, font=font_head, fill=(15, 23, 42, 255))
            cur_y += 64

        cur_y += 4
        for line in screen_cfg["subtitle"].split("\n"):
            sb = font_sub.getbbox(line)
            lw = sb[2] - sb[0]
            draw.text(((CANVAS_W - lw) // 2, cur_y), line, font=font_sub, fill=(100, 116, 139, 255))
            cur_y += 36

        cta_text = screen_cfg.get("cta", "Explore Feature")
        cta_bbox = font_pill.getbbox(cta_text)
        cw = (cta_bbox[2] - cta_bbox[0]) + 48
        ch = (cta_bbox[3] - cta_bbox[1]) + 24
        cx = (CANVAS_W - cw) // 2
        cy = cur_y + 12
        draw.rounded_rectangle([cx, cy, cx + cw, cy + ch], radius=ch // 2, fill=accent)
        draw.text((cx + 24, cy + 9), cta_text, font=font_pill, fill=(255, 255, 255, 255))

    # Bottom Category Dock
    bot_w = 920
    bot_h = 76
    bot_x = (CANVAS_W - bot_w) // 2
    bot_y = CANVAS_H - bot_h - 48
    draw.rounded_rectangle([bot_x, bot_y, bot_x + bot_w, bot_y + bot_h], radius=22, fill=(15, 20, 30, 255))

    font_bot_tag = get_font(FONT_BOLD_PATH, 26)
    font_bot_num = get_font(FONT_HEAVY_PATH, 26)
    draw.text((bot_x + 36, bot_y + 22), screen_cfg["bottom_tag"], font=font_bot_tag, fill=(255, 255, 255, 255))
    draw.text((bot_x + bot_w - 74, bot_y + 22), screen_cfg["screen_num"], font=font_bot_num, fill=(148, 163, 184, 255))

    final_card = card.convert("RGB")
    final_card.save(output_path, "PNG")
    print(f"Generated Promo Card: {output_path}")

CONFIGS = [
    {
        "id": 1,
        "layout": "A",
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

def generate_all_promos():
    print("Generating Dark Theme Promos...")
    for cfg in CONFIGS:
        raw_file = os.path.join(RAW_DARK_DIR, f"screenshot_phone_{cfg['id']}.png")
        out_file = os.path.join(PROMOS_DARK_DIR, f"playstore_promo_{cfg['id']}.png")
        generate_promo_card(cfg, raw_file, out_file, is_light_theme=False)
        dest_main = os.path.join(STORE_PROMOS_DIR, f"playstore_promo_{cfg['id']}.png")
        shutil.copyfile(out_file, dest_main)

    print("Generating Light (White) Theme Promos...")
    for cfg in CONFIGS:
        raw_file = os.path.join(RAW_LIGHT_DIR, f"screenshot_phone_{cfg['id']}.png")
        out_file = os.path.join(PROMOS_LIGHT_DIR, f"playstore_promo_{cfg['id']}.png")
        generate_promo_card(cfg, raw_file, out_file, is_light_theme=True)

def main():
    # Screenshots are already captured! Generate all promos:
    print("=== Generating All Promo Cards (Dark & Light) ===")
    generate_all_promos()
    print("\nALL PROMOS GENERATED SUCCESSFULLY!")

if __name__ == "__main__":
    main()
