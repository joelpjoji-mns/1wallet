import os
import math
import tempfile
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont, ImageFilter

W, H = 1280, 2856

# Typography
FONT_SERIF = 'store_assets/fonts/PlayfairDisplay-Bold.ttf'
FONT_SANS_MED = 'store_assets/fonts/PlusJakartaSans-Medium.ttf'
FONT_SANS_BOLD = 'store_assets/fonts/PlusJakartaSans-Bold.ttf'

def get_serif(size):
    return ImageFont.truetype(FONT_SERIF, size)

def get_sans_med(size):
    return ImageFont.truetype(FONT_SANS_MED, size)

def get_sans_bold(size):
    return ImageFont.truetype(FONT_SANS_BOLD, size)

THEMES = [
    {
        "index": 1,
        "mode": "split",
        "base_bg": (247, 244, 237),
        "patch_bg": (238, 233, 222),
        "accent": (205, 95, 50),
        "text_dark": (28, 25, 23),
        "badge_text": "OFFLINE FIRST",
        "badge_bg": (205, 95, 50),
        "badge_fg": (255, 255, 255),
        "badge_angle": 0,
        "title_1": "All your wealth,",
        "title_2": "gathered here",
        "subtitle": "Small-batch, privacy-first ledger for mindful wealth.",
        "inverted": False,
        "art_doodle": "spiral",
    },
    {
        "index": 2,
        "mode": "light",
        "base_bg": (238, 243, 237),
        "patch_bg": (224, 232, 222),
        "accent": (62, 105, 74),
        "text_dark": (20, 32, 24),
        "badge_text": "ZERO CLOUD LOCK-IN",
        "badge_bg": (62, 105, 74),
        "badge_fg": (255, 255, 255),
        "badge_angle": 0,
        "title_1": "Every account,",
        "title_2": "photographed clearly",
        "subtitle": "Real balances, true cash velocity, crystal visibility.",
        "inverted": False,
        "art_doodle": "waves_grid",
    },
    {
        "index": 3,
        "mode": "split",
        "base_bg": (250, 246, 242),
        "patch_bg": (242, 234, 226),
        "accent": (195, 82, 58),
        "text_dark": (32, 24, 22),
        "badge_text": "DOUBLE ENTRY",
        "badge_bg": (195, 82, 58),
        "badge_fg": (255, 255, 255),
        "badge_angle": 0,
        "title_1": "Every transaction,",
        "title_2": "balanced honest",
        "subtitle": "Strict mathematical consistency with instant search.",
        "inverted": False,
        "art_doodle": "waves",
    },
    {
        "index": 4,
        "mode": "dark",
        "base_bg": (240, 244, 248),
        "patch_bg": (228, 235, 242),
        "accent": (48, 88, 145),
        "text_dark": (22, 28, 38),
        "badge_text": "DUE REMINDERS",
        "badge_bg": (48, 88, 145),
        "badge_fg": (255, 255, 255),
        "badge_angle": 0,
        "title_1": "Never miss,",
        "title_2": "the next bill",
        "subtitle": "Recurring subscriptions and scheduled transfers.",
        "inverted": False,
        "art_doodle": "grid",
    },
    {
        "index": 5,
        "mode": "split",
        "base_bg": (248, 245, 238),
        "patch_bg": (238, 232, 220),
        "accent": (180, 115, 32),
        "text_dark": (35, 28, 18),
        "badge_text": "AMORTIZATION",
        "badge_bg": (180, 115, 32),
        "badge_fg": (255, 255, 255),
        "badge_angle": 0,
        "title_1": "Master your",
        "title_2": "active loans",
        "subtitle": "Payoff schedules and monthly EMI tracking at ease.",
        "inverted": False,
        "art_doodle": "spiral",
    },
    {
        "index": 6,
        "mode": "light",
        "base_bg": (245, 243, 248),
        "patch_bg": (235, 232, 242),
        "accent": (98, 72, 145),
        "text_dark": (28, 22, 38),
        "badge_text": "MULTI-CURRENCY",
        "badge_bg": (98, 72, 145),
        "badge_fg": (255, 255, 255),
        "badge_angle": 0,
        "title_1": "Any currency,",
        "title_2": "the way you live",
        "subtitle": "USD, EUR, GBP, JPY, INR with integer precision.",
        "inverted": False,
        "art_doodle": "waves",
    },
    {
        "index": 7,
        "mode": "split",
        "base_bg": (246, 245, 242),
        "patch_bg": (236, 234, 228),
        "accent": (42, 115, 98),
        "text_dark": (24, 30, 28),
        "badge_text": "LOCAL AES-256",
        "badge_bg": (42, 115, 98),
        "badge_fg": (255, 255, 255),
        "badge_angle": 0,
        "title_1": "Your data,",
        "title_2": "owned solely by you",
        "subtitle": "Hardware biometrics and zero telemetry tracking.",
        "inverted": False,
        "art_doodle": "waves_grid",
    },
    {
        "index": 8,
        "mode": "dark",
        "base_bg": (248, 243, 242),
        "patch_bg": (238, 230, 228),
        "accent": (168, 62, 75),
        "text_dark": (35, 20, 24),
        "badge_text": "ON-DEVICE ML",
        "badge_bg": (168, 62, 75),
        "badge_fg": (255, 255, 255),
        "badge_angle": 0,
        "title_1": "Scan receipts,",
        "title_2": "effortless ingress",
        "subtitle": "Fast on-device OCR, SMS alerts, and PDF statement parser.",
        "inverted": False,
        "art_doodle": "spiral",
    },
]

# ─── Perfectly Centered Sticker Pill Badge ───────────────────────────────────

def draw_sticker_pill(canvas, text, cx, cy, bg_color, fg_color, font, angle=0):
    bbox = font.getbbox(text)
    tl, tt, tr, tb = bbox
    tw = tr - tl
    th = tb - tt
    
    pad_x = 34
    pad_y = 16
    pw = tw + pad_x * 2
    ph = th + pad_y * 2
    
    pill_img = Image.new("RGBA", (pw, ph), (0, 0, 0, 0))
    pdraw = ImageDraw.Draw(pill_img)
    
    pdraw.rounded_rectangle((0, 0, pw - 1, ph - 1), radius=ph // 2, fill=(*bg_color, 255))
    
    # Mathematical exact centering using middle-middle text anchor
    pdraw.text((pw / 2, ph / 2), text, font=font, fill=(*fg_color, 255), anchor="mm")
    
    if angle != 0:
        pill_img = pill_img.rotate(angle, resample=Image.Resampling.BICUBIC, expand=True)
        
    pw_rot, ph_rot = pill_img.size
    canvas.paste(pill_img, (cx - pw_rot // 2, cy - ph_rot // 2), pill_img)

# ─── Line Art ─────────────────────────────────────────────────────────────────

def draw_wavy_lines(draw, x_start, y_start, width, amplitude=10, wavelength=75, count=3, spacing=16, color=(0,0,0,50), stroke=3):
    for i in range(count):
        pts = []
        y_offset = y_start + i * spacing
        for x in range(0, width, 4):
            y = y_offset + amplitude * math.sin((x / wavelength) * 2 * math.pi)
            pts.append((x_start + x, y))
        draw.line(pts, fill=color, width=stroke)

def draw_spiral_doodle(draw, cx, cy, max_r=50, turns=2.6, color=(0,0,0,45), stroke=3):
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

# ─── Full-Resolution Uncropped Phone Mockup (1280:2856) ─────────────────────

def create_split_screen(img_light, img_dark):
    # Pure uncropped 1280x2856 images
    w, h = img_light.size
    split = Image.new("RGBA", (w, h))
    
    x_top = int(w * 0.28)
    x_bot = int(w * 0.72)
    
    mask = Image.new("L", (w, h), 0)
    draw = ImageDraw.Draw(mask)
    draw.polygon([(0, 0), (x_top, 0), (x_bot, h), (0, h)], fill=255)
    
    split.paste(img_dark, (0, 0))
    split.paste(img_light, (0, 0), mask)
    
    # Crisp separator line
    line_layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    ldraw = ImageDraw.Draw(line_layer)
    ldraw.line([(x_top, 0), (x_bot, h)], fill=(255, 255, 255, 220), width=6)
    ldraw.line([(x_top, 0), (x_bot, h)], fill=(255, 255, 255, 255), width=2)
    split.paste(line_layer, (0, 0), line_layer)
    return split

def build_phone_frame(screen_img, dark_theme=False, scale_w=820):
    # Preserves the EXACT 1280 : 2856 aspect ratio without any crop
    disp_w = scale_w
    disp_h = int(disp_w * 2856 / 1280)  # exact ratio: 820 -> 1829px
    
    screen_resized = screen_img.resize((disp_w, disp_h), Image.Resampling.LANCZOS)
    
    disp_radius = 52
    screen_mask = Image.new("L", (disp_w, disp_h), 0)
    sdraw = ImageDraw.Draw(screen_mask)
    sdraw.rounded_rectangle((0, 0, disp_w - 1, disp_h - 1), radius=disp_radius, fill=255)
    
    # Camera cutout
    cam_x = disp_w // 2
    cam_y = 36
    cam_r = 13
    sdraw.ellipse((cam_x - cam_r, cam_y - cam_r, cam_x + cam_r, cam_y + cam_r), fill=0)
    
    border_x = 20
    border_top = 20
    border_bot = 20
    
    chassis_w = disp_w + border_x * 2
    chassis_h = disp_h + border_top + border_bot
    chassis_radius = 68
    
    phone = Image.new("RGBA", (chassis_w + 24, chassis_h + 20), (0, 0, 0, 0))
    pdraw = ImageDraw.Draw(phone)
    
    chassis_fill = (22, 24, 30, 255) if dark_theme else (255, 255, 255, 255)
    chassis_outline = (55, 60, 75, 255) if dark_theme else (218, 222, 230, 255)
    body_box = (12, 10, chassis_w + 12, chassis_h + 10)
    pdraw.rounded_rectangle(body_box, radius=chassis_radius, fill=chassis_fill, outline=chassis_outline, width=3)
    
    # Side buttons
    btn_color = (65, 70, 82, 255) if dark_theme else (210, 215, 224, 255)
    pdraw.rounded_rectangle((4, 400, 10, 500), radius=3, fill=btn_color)
    pdraw.rounded_rectangle((4, 530, 10, 630), radius=3, fill=btn_color)
    pdraw.rounded_rectangle((chassis_w + 12, 460, chassis_w + 18, 580), radius=3, fill=btn_color)
    
    # Paste display
    screen_pos = (12 + border_x, 10 + border_top)
    phone.paste(screen_resized, screen_pos, screen_mask)
    
    # Camera lens
    pdraw.ellipse((screen_pos[0] + cam_x - cam_r,
                   screen_pos[1] + cam_y - cam_r,
                   screen_pos[0] + cam_x + cam_r,
                   screen_pos[1] + cam_y + cam_r), fill=(15, 18, 24, 255))

    # Soft ambient drop shadow
    shadow_margin = 90
    sw_c = phone.width + shadow_margin * 2
    sh_c = phone.height + shadow_margin * 2
    shadow_layer = Image.new("RGBA", (sw_c, sh_c), (0, 0, 0, 0))
    s_draw = ImageDraw.Draw(shadow_layer)
    
    s_color = (15, 20, 30, 48) if not dark_theme else (0, 0, 0, 135)
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
    img_light = Image.open(raw_light_path).convert("RGBA")
    img_dark = Image.open(raw_dark_path).convert("RGBA")
    
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

    canvas = Image.new("RGBA", (W, H), (*theme["base_bg"], 255))
    draw = ImageDraw.Draw(canvas)

    # Crisp organic patch
    patch_layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    pdraw = ImageDraw.Draw(patch_layer)
    pdraw.ellipse((W - 680, -100, W + 450, 1300), fill=(*theme["patch_bg"], 255))
    patch_layer = patch_layer.filter(ImageFilter.GaussianBlur(6))
    canvas.paste(patch_layer, (0, 0), patch_layer)

    # Decorative line art
    accent_rgb = theme["accent"]
    line_color = (*accent_rgb, 65)
    
    doodle = theme.get("art_doodle", "waves")
    if "waves" in doodle:
        draw_wavy_lines(draw, x_start=80, y_start=110, width=280, amplitude=10, wavelength=70, count=3, spacing=16, color=line_color, stroke=3)
    if "grid" in doodle:
        draw_fine_grid(draw, x=W - 380, y=90, w=300, h=300, spacing=48, color=(*accent_rgb, 35), stroke=1)
    if "spiral" in doodle:
        draw_spiral_doodle(draw, cx=160, cy=680, max_r=50, turns=2.6, color=line_color, stroke=3)

    f_title1 = get_serif(108)
    f_title2 = get_serif(118)
    f_sub = get_sans_med(36)
    f_badge = get_sans_bold(26)

    t1 = theme["title_1"]
    t2 = theme["title_2"]
    sub = theme["subtitle"]

    inverted = theme["inverted"]
    # Phone size preserved at pure 1280:2856 ratio, scale_w=820
    phone_comp, margin = build_phone_frame(screen_img, dark_theme=is_dark_phone, scale_w=820)
    phone_w, phone_h = phone_comp.size
    phone_x = (W - phone_w) // 2

    if not inverted:
        # Layout A: Text Top, Phone Bottom
        cursor_y = 180
        
        # Line 1: Dark
        bbox1 = f_title1.getbbox(t1)
        w1 = bbox1[2] - bbox1[0]
        h1 = bbox1[3] - bbox1[1]
        draw.text(((W - w1) // 2, cursor_y), t1, font=f_title1, fill=(*theme["text_dark"], 255))
        cursor_y += h1 + 16
        
        # Line 2: Big Accent
        bbox2 = f_title2.getbbox(t2)
        w2 = bbox2[2] - bbox2[0]
        h2 = bbox2[3] - bbox2[1]
        draw.text(((W - w2) // 2, cursor_y), t2, font=f_title2, fill=(*theme["accent"], 255))
        cursor_y += h2 + 24
        
        # Subtitle
        bbox_sub = f_sub.getbbox(sub)
        w_sub = bbox_sub[2] - bbox_sub[0]
        draw.text(((W - w_sub) // 2, cursor_y), sub, font=f_sub, fill=(108, 102, 98, 255))
        cursor_y += 75
        
        # Perfectly Centered Sticker Pill Badge
        badge_y = cursor_y + 16
        draw_sticker_pill(canvas, theme["badge_text"], cx=W // 2, cy=badge_y,
                          bg_color=theme["badge_bg"], fg_color=theme["badge_fg"],
                          font=f_badge, angle=theme["badge_angle"])

        phone_y = 740 - margin
        canvas.paste(phone_comp, (phone_x, phone_y), phone_comp)
        
    else:
        # Layout B: Phone Top, Text Bottom
        phone_y = 90 - margin
        canvas.paste(phone_comp, (phone_x, phone_y), phone_comp)
        
        cursor_y = 1990
        
        # Line 1: Dark
        bbox1 = f_title1.getbbox(t1)
        w1 = bbox1[2] - bbox1[0]
        h1 = bbox1[3] - bbox1[1]
        draw.text(((W - w1) // 2, cursor_y), t1, font=f_title1, fill=(*theme["text_dark"], 255))
        cursor_y += h1 + 16
        
        # Line 2: Big Accent
        bbox2 = f_title2.getbbox(t2)
        w2 = bbox2[2] - bbox2[0]
        h2 = bbox2[3] - bbox2[1]
        draw.text(((W - w2) // 2, cursor_y), t2, font=f_title2, fill=(*theme["accent"], 255))
        cursor_y += h2 + 24
        
        # Subtitle
        bbox_sub = f_sub.getbbox(sub)
        w_sub = bbox_sub[2] - bbox_sub[0]
        draw.text(((W - w_sub) // 2, cursor_y), sub, font=f_sub, fill=(108, 102, 98, 255))
        cursor_y += 70
        
        # Perfectly Centered Sticker Pill Badge
        badge_y = cursor_y + 16
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
    
    print("=== Re-rendering Cards with Exact Raw Aspect Ratio & Centered Badges ===")
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
        
    print("\nDone! All 8 cards updated with exact phone screenshot resolution.")

if __name__ == "__main__":
    main()
