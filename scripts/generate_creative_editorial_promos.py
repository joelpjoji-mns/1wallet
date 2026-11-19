import os
import math
import tempfile
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont, ImageFilter

W, H = 1280, 2856

# Typography
FONT_SERIF = 'store_assets/fonts/PlayfairDisplay-Bold.ttf'
FONT_SERIF_ALT = 'store_assets/fonts/DMSerifDisplay-Regular.ttf'
FONT_SANS_MED = 'store_assets/fonts/PlusJakartaSans-Medium.ttf'
FONT_SANS_BOLD = 'store_assets/fonts/PlusJakartaSans-Bold.ttf'

def get_serif(size):
    return ImageFont.truetype(FONT_SERIF, size)

def get_sans_med(size):
    return ImageFont.truetype(FONT_SANS_MED, size)

def get_sans_bold(size):
    return ImageFont.truetype(FONT_SANS_BOLD, size)

# 8 Creative Themes inspired by Market & Greenhouse
THEMES = [
    {
        "index": 1,
        "mode": "split",  # diagonal split
        "base_bg": (247, 244, 237),  # warm oatmeal
        "patch_bg": (238, 233, 222), # soft organic patch
        "accent": (205, 95, 50),     # rich terracotta
        "text_dark": (28, 25, 23),
        "badge_text": "OFFLINE FIRST",
        "badge_bg": (205, 95, 50),
        "badge_fg": (255, 255, 255),
        "badge_angle": -6,
        "title_1": "All your wealth,",
        "title_2": "gathered here",
        "subtitle": "Small-batch, privacy-first ledger for mindful wealth.",
        "inverted": False,
        "art_doodle": "spiral",
    },
    {
        "index": 2,
        "mode": "light",
        "base_bg": (238, 243, 237),  # pale celadon / greenhouse sage
        "patch_bg": (224, 232, 222),
        "accent": (62, 105, 74),     # forest leaf
        "text_dark": (20, 32, 24),
        "badge_text": "ZERO CLOUD LOCK-IN",
        "badge_bg": (62, 105, 74),
        "badge_fg": (255, 255, 255),
        "badge_angle": 5,
        "title_1": "Every account,",
        "title_2": "photographed clearly",
        "subtitle": "Real balances, true cash velocity, crystal visibility.",
        "inverted": False,
        "art_doodle": "waves_grid",
    },
    {
        "index": 3,
        "mode": "split",
        "base_bg": (250, 246, 242),  # warm peach biscuit
        "patch_bg": (242, 234, 226),
        "accent": (195, 82, 58),     # burnt sienna
        "text_dark": (32, 24, 22),
        "badge_text": "DOUBLE ENTRY",
        "badge_bg": (195, 82, 58),
        "badge_fg": (255, 255, 255),
        "badge_angle": -4,
        "title_1": "Every transaction,",
        "title_2": "balanced honest",
        "subtitle": "Strict mathematical consistency with instant search.",
        "inverted": True,
        "art_doodle": "waves",
    },
    {
        "index": 4,
        "mode": "dark",
        "base_bg": (240, 244, 248),  # cool fog / nordic mist
        "patch_bg": (228, 235, 242),
        "accent": (48, 88, 145),     # nordic slate blue
        "text_dark": (22, 28, 38),
        "badge_text": "DUE REMINDERS",
        "badge_bg": (48, 88, 145),
        "badge_fg": (255, 255, 255),
        "badge_angle": 6,
        "title_1": "Never miss,",
        "title_2": "the next bill",
        "subtitle": "Recurring subscriptions and scheduled transfers.",
        "inverted": False,
        "art_doodle": "grid",
    },
    {
        "index": 5,
        "mode": "split",
        "base_bg": (248, 245, 238),  # warm butter linen
        "patch_bg": (238, 232, 220),
        "accent": (180, 115, 32),    # vintage ochre
        "text_dark": (35, 28, 18),
        "badge_text": "AMORTIZATION",
        "badge_bg": (180, 115, 32),
        "badge_fg": (255, 255, 255),
        "badge_angle": -5,
        "title_1": "Master your,",
        "title_2": "active loans",
        "subtitle": "Payoff schedules and monthly EMI tracking at ease.",
        "inverted": True,
        "art_doodle": "spiral",
    },
    {
        "index": 6,
        "mode": "light",
        "base_bg": (245, 243, 248),  # soft lilac oat
        "patch_bg": (235, 232, 242),
        "accent": (98, 72, 145),     # iris bloom
        "text_dark": (28, 22, 38),
        "badge_text": "MULTI-CURRENCY",
        "badge_bg": (98, 72, 145),
        "badge_fg": (255, 255, 255),
        "badge_angle": 4,
        "title_1": "Any currency,",
        "title_2": "the way you live",
        "subtitle": "USD, EUR, GBP, JPY, INR with integer precision.",
        "inverted": False,
        "art_doodle": "waves",
    },
    {
        "index": 7,
        "mode": "split",
        "base_bg": (246, 245, 242),  # pebble chalk
        "patch_bg": (236, 234, 228),
        "accent": (42, 115, 98),     # eucalyptus
        "text_dark": (24, 30, 28),
        "badge_text": "LOCAL AES-256",
        "badge_bg": (42, 115, 98),
        "badge_fg": (255, 255, 255),
        "badge_angle": -7,
        "title_1": "Your data,",
        "title_2": "owned solely by you",
        "subtitle": "Hardware biometrics and zero telemetry tracking.",
        "inverted": True,
        "art_doodle": "waves_grid",
    },
    {
        "index": 8,
        "mode": "dark",
        "base_bg": (248, 243, 242),  # dusty clay
        "patch_bg": (238, 230, 228),
        "accent": (168, 62, 75),     # rose terracotta
        "text_dark": (35, 20, 24),
        "badge_text": "ON-DEVICE ML",
        "badge_bg": (168, 62, 75),
        "badge_fg": (255, 255, 255),
        "badge_angle": 5,
        "title_1": "Scan receipts,",
        "title_2": "effortless ingress",
        "subtitle": "Fast on-device OCR, SMS alerts, and PDF statement parser.",
        "inverted": False,
        "art_doodle": "spiral",
    },
]

# ─── Art & Decorative Line Primitives ────────────────────────────────────────

def draw_wavy_lines(draw, x_start, y_start, width, amplitude=12, wavelength=90, count=3, spacing=18, color=(0,0,0,50), stroke=3):
    for i in range(count):
        pts = []
        y_offset = y_start + i * spacing
        for x in range(0, width, 4):
            y = y_offset + amplitude * math.sin((x / wavelength) * 2 * math.pi)
            pts.append((x_start + x, y))
        draw.line(pts, fill=color, width=stroke)

def draw_spiral_doodle(draw, cx, cy, max_r=55, turns=2.6, color=(0,0,0,45), stroke=3):
    pts = []
    steps = int(turns * 70)
    for s in range(steps):
        theta = s * (2 * math.pi / 70)
        r = (s / steps) * max_r
        x = cx + r * math.cos(theta)
        y = cy + r * math.sin(theta)
        pts.append((x, y))
    draw.line(pts, fill=color, width=stroke)

def draw_fine_grid(draw, x, y, w, h, spacing=52, color=(0,0,0,25), stroke=1):
    for gx in range(x, x + w, spacing):
        draw.line([(gx, y), (gx, y + h)], fill=color, width=stroke)
    for gy in range(y, y + h, spacing):
        draw.line([(x, gy), (x + w, gy)], fill=color, width=stroke)

def draw_sticker_pill(canvas, text, cx, cy, bg_color, fg_color, font, angle=0):
    dummy = ImageDraw.Draw(Image.new("RGBA", (10, 10)))
    bbox = font.getbbox(text)
    tw = bbox[2] - bbox[0]
    th = bbox[3] - bbox[1]
    
    pad_x = 36
    pad_y = 18
    pw = tw + pad_x * 2
    ph = th + pad_y * 2
    
    pill_img = Image.new("RGBA", (pw + 10, ph + 10), (0, 0, 0, 0))
    pdraw = ImageDraw.Draw(pill_img)
    
    # Pill with crisp outline
    pdraw.rounded_rectangle((4, 4, pw + 4, ph + 4), radius=ph // 2, fill=(*bg_color, 255))
    pdraw.text(((pw - tw) // 2 + 4, (ph - th) // 2 + 2), text, font=font, fill=(*fg_color, 255))
    
    if angle != 0:
        pill_img = pill_img.rotate(angle, resample=Image.Resampling.BICUBIC, expand=True)
        
    pw_rot, ph_rot = pill_img.size
    canvas.paste(pill_img, (cx - pw_rot // 2, cy - ph_rot // 2), pill_img)

# ─── Phone & Display Processing ───────────────────────────────────────────────

def prepare_screen(img_raw, crop_bottom_px=270):
    w, h = img_raw.size
    return img_raw.crop((0, 0, w, h - crop_bottom_px))

def create_split_screen(img_light, img_dark):
    w, h = img_light.size
    split = Image.new("RGBA", (w, h))
    
    x_top = int(w * 0.28)
    x_bot = int(w * 0.72)
    
    mask = Image.new("L", (w, h), 0)
    draw = ImageDraw.Draw(mask)
    draw.polygon([(0, 0), (x_top, 0), (x_bot, h), (0, h)], fill=255)
    
    split.paste(img_dark, (0, 0))
    split.paste(img_light, (0, 0), mask)
    
    # Crisp luminous separator
    line_layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    ldraw = ImageDraw.Draw(line_layer)
    ldraw.line([(x_top, 0), (x_bot, h)], fill=(255, 255, 255, 200), width=5)
    ldraw.line([(x_top, 0), (x_bot, h)], fill=(255, 255, 255, 255), width=2)
    split.paste(line_layer, (0, 0), line_layer)
    return split

def build_phone_frame(screen_img, dark_theme=False, scale_w=840):
    sw, sh = screen_img.size
    disp_w = scale_w
    disp_h = int(disp_w * sh / sw)
    
    screen_resized = screen_img.resize((disp_w, disp_h), Image.Resampling.LANCZOS)
    
    disp_radius = 50
    screen_mask = Image.new("L", (disp_w, disp_h), 0)
    sdraw = ImageDraw.Draw(screen_mask)
    sdraw.rounded_rectangle((0, 0, disp_w, disp_h), radius=disp_radius, fill=255)
    
    # Front camera hole
    cam_x = disp_w // 2
    cam_y = 36
    cam_r = 13
    sdraw.ellipse((cam_x - cam_r, cam_y - cam_r, cam_x + cam_r, cam_y + cam_r), fill=0)
    
    border_x = 20
    border_top = 20
    border_bot = 20
    
    chassis_w = disp_w + border_x * 2
    chassis_h = disp_h + border_top + border_bot
    chassis_radius = 66
    
    phone = Image.new("RGBA", (chassis_w + 24, chassis_h + 20), (0, 0, 0, 0))
    pdraw = ImageDraw.Draw(phone)
    
    # White ceramic frame or Obsidian frame
    chassis_fill = (22, 24, 30, 255) if dark_theme else (255, 255, 255, 255)
    chassis_outline = (55, 60, 75, 255) if dark_theme else (218, 222, 230, 255)
    body_box = (12, 10, chassis_w + 12, chassis_h + 10)
    pdraw.rounded_rectangle(body_box, radius=chassis_radius, fill=chassis_fill, outline=chassis_outline, width=3)
    
    # Subtle buttons
    btn_color = (65, 70, 82, 255) if dark_theme else (210, 215, 224, 255)
    pdraw.rounded_rectangle((4, 380, 10, 480), radius=3, fill=btn_color)
    pdraw.rounded_rectangle((4, 510, 10, 610), radius=3, fill=btn_color)
    pdraw.rounded_rectangle((chassis_w + 12, 440, chassis_w + 18, 560), radius=3, fill=btn_color)
    
    # Paste display
    screen_pos = (12 + border_x, 10 + border_top)
    phone.paste(screen_resized, screen_pos, screen_mask)
    
    # Camera lens detail
    pdraw.ellipse((screen_pos[0] + cam_x - cam_r,
                   screen_pos[1] + cam_y - cam_r,
                   screen_pos[0] + cam_x + cam_r,
                   screen_pos[1] + cam_y + cam_r), fill=(15, 18, 24, 255))

    # Crisp soft shadow (subtle, editorial quality)
    shadow_margin = 90
    sw_c = phone.width + shadow_margin * 2
    sh_c = phone.height + shadow_margin * 2
    shadow_layer = Image.new("RGBA", (sw_c, sh_c), (0, 0, 0, 0))
    s_draw = ImageDraw.Draw(shadow_layer)
    
    s_color = (15, 20, 30, 45) if not dark_theme else (0, 0, 0, 130)
    s_draw.rounded_rectangle((shadow_margin + 12, shadow_margin + 28,
                              shadow_margin + 12 + chassis_w, shadow_margin + 28 + chassis_h),
                             radius=chassis_radius + 4, fill=s_color)
    shadow_layer = shadow_layer.filter(ImageFilter.GaussianBlur(32))
    
    composite = Image.new("RGBA", (sw_c, sh_c), (0, 0, 0, 0))
    composite.paste(shadow_layer, (0, 0), shadow_layer)
    composite.paste(phone, (shadow_margin, shadow_margin), phone)
    
    return composite, shadow_margin

# ─── Render Card ─────────────────────────────────────────────────────────────

def render_editorial_card(theme, raw_light_path, raw_dark_path):
    img_light = prepare_screen(Image.open(raw_light_path).convert("RGBA"))
    img_dark = prepare_screen(Image.open(raw_dark_path).convert("RGBA"))
    
    mode = theme["mode"]
    if mode == "split":
        screen_img = create_split_screen(img_light, img_dark)
        is_dark_phone = True
    elif mode == "dark":
        screen_img = img_dark
        is_dark_phone = True
    else:
        screen_img = img_light
        is_dark_phone = False

    # 1. Base Canvas
    canvas = Image.new("RGBA", (W, H), (*theme["base_bg"], 255))
    draw = ImageDraw.Draw(canvas)

    # 2. Organic Background Patch with Crisp / Tiny Blur (Only 4px blur, clean editorial look)
    patch_layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    pdraw = ImageDraw.Draw(patch_layer)
    # Organic soft curved polygon
    pdraw.ellipse((W - 680, -100, W + 450, 1300), fill=(*theme["patch_bg"], 255))
    patch_layer = patch_layer.filter(ImageFilter.GaussianBlur(6))
    canvas.paste(patch_layer, (0, 0), patch_layer)

    # 3. Fine Art Doodles & Lines (Crisp line art)
    accent_rgb = theme["accent"]
    line_color = (*accent_rgb, 65)
    
    doodle = theme.get("art_doodle", "waves")
    if "waves" in doodle:
        # Waves in top corner
        draw_wavy_lines(draw, x_start=80, y_start=110, width=280, amplitude=10, wavelength=70, count=3, spacing=16, color=line_color, stroke=3)
    if "grid" in doodle:
        # Fine architectural grid
        draw_fine_grid(draw, x=W - 380, y=90, w=300, h=300, spacing=48, color=(*accent_rgb, 35), stroke=1)
    if "spiral" in doodle:
        # Charming hand-drawn spiral coil
        draw_spiral_doodle(draw, cx=160, cy=680, max_r=50, turns=2.6, color=line_color, stroke=3)

    # 4. Typography Layout
    f_title1 = get_serif(108)
    f_title2 = get_serif(118)
    f_sub = get_sans_med(36)
    f_badge = get_sans_bold(26)

    t1 = theme["title_1"]
    t2 = theme["title_2"]
    sub = theme["subtitle"]

    inverted = theme["inverted"]
    phone_comp, margin = build_phone_frame(screen_img, dark_theme=is_dark_phone, scale_w=840)
    phone_w, phone_h = phone_comp.size
    phone_x = (W - phone_w) // 2

    if not inverted:
        # Layout A: Text Top, Phone Bottom
        cursor_y = 190
        
        # Line 1: Dark
        bbox1 = f_title1.getbbox(t1)
        w1 = bbox1[2] - bbox1[0]
        h1 = bbox1[3] - bbox1[1]
        draw.text(((W - w1) // 2, cursor_y), t1, font=f_title1, fill=(*theme["text_dark"], 255))
        cursor_y += h1 + 18
        
        # Line 2: Big Accent Color
        bbox2 = f_title2.getbbox(t2)
        w2 = bbox2[2] - bbox2[0]
        h2 = bbox2[3] - bbox2[1]
        draw.text(((W - w2) // 2, cursor_y), t2, font=f_title2, fill=(*theme["accent"], 255))
        cursor_y += h2 + 28
        
        # Subtitle: Clean & minimal
        bbox_sub = f_sub.getbbox(sub)
        w_sub = bbox_sub[2] - bbox_sub[0]
        draw.text(((W - w_sub) // 2, cursor_y), sub, font=f_sub, fill=(108, 102, 98, 255))
        cursor_y += 75
        
        # Sticker Pill Badge (centered or playfully offset)
        badge_y = cursor_y + 20
        draw_sticker_pill(canvas, theme["badge_text"], cx=W // 2, cy=badge_y,
                          bg_color=theme["badge_bg"], fg_color=theme["badge_fg"],
                          font=f_badge, angle=theme["badge_angle"])

        # Phone docked cleanly in bottom half
        phone_y = 750 - margin
        canvas.paste(phone_comp, (phone_x, phone_y), phone_comp)
        
    else:
        # Layout B: Phone Top, Text Bottom
        phone_y = 100 - margin
        canvas.paste(phone_comp, (phone_x, phone_y), phone_comp)
        
        cursor_y = 1980
        
        # Line 1: Dark
        bbox1 = f_title1.getbbox(t1)
        w1 = bbox1[2] - bbox1[0]
        h1 = bbox1[3] - bbox1[1]
        draw.text(((W - w1) // 2, cursor_y), t1, font=f_title1, fill=(*theme["text_dark"], 255))
        cursor_y += h1 + 18
        
        # Line 2: Big Accent Color
        bbox2 = f_title2.getbbox(t2)
        w2 = bbox2[2] - bbox2[0]
        h2 = bbox2[3] - bbox2[1]
        draw.text(((W - w2) // 2, cursor_y), t2, font=f_title2, fill=(*theme["accent"], 255))
        cursor_y += h2 + 28
        
        # Subtitle: Clean & minimal
        bbox_sub = f_sub.getbbox(sub)
        w_sub = bbox_sub[2] - bbox_sub[0]
        draw.text(((W - w_sub) // 2, cursor_y), sub, font=f_sub, fill=(108, 102, 98, 255))
        cursor_y += 70
        
        # Sticker Pill Badge
        badge_y = cursor_y + 20
        draw_sticker_pill(canvas, theme["badge_text"], cx=W // 2, cy=badge_y,
                          bg_color=theme["badge_bg"], fg_color=theme["badge_fg"],
                          font=f_badge, angle=theme["badge_angle"])

    return canvas.convert("RGB")

def save_image_safely(img, target_path):
    with tempfile.NamedTemporaryFile(suffix=".png", delete=False) as tf:
        temp_path = tf.name
    img.save(temp_path, format="PNG")
    os.replace(temp_path, target_path)

def main():
    base_dir = Path("store_assets").resolve()
    target_dir = base_dir / "phone_screenshots"
    target_dir.mkdir(parents=True, exist_ok=True)
    fastlane_dir = Path("android/fastlane/metadata/android/en-US/images/promo_cards").resolve()
    fastlane_dir.mkdir(parents=True, exist_ok=True)
    
    print("=== Generating Editorial Artisanal Promo Cards (Shipshot Creative) ===")
    for t in THEMES:
        idx = t["index"]
        raw_l = str(base_dir / "raw_screenshots_light" / f"screenshot_phone_{idx}.png")
        raw_d = str(base_dir / "raw_screenshots_dark" / f"screenshot_phone_{idx}.png")
        out_file = target_dir / f"playstore_promo_{idx}.png"
        fl_file = fastlane_dir / f"playstore_promo_{idx}.png"
        
        print(f"Rendering slide {idx} [{t['mode']}] -> {out_file.name}...")
        img = render_editorial_card(t, raw_l, raw_d)
        save_image_safely(img, out_file)
        save_image_safely(img, fl_file)
        
    print("\nDone! All 8 creative editorial cards rendered.")

if __name__ == "__main__":
    main()
