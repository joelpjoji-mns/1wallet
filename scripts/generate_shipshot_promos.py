import os
import tempfile
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont, ImageFilter

W, H = 1280, 2856

# Typography
FONT_SERIF = 'store_assets/fonts/Cormorant-Bold.ttf'
FONT_EB = 'store_assets/fonts/PlusJakartaSans-ExtraBold.ttf'
FONT_B = 'store_assets/fonts/PlusJakartaSans-Bold.ttf'
FONT_SB = 'store_assets/fonts/PlusJakartaSans-SemiBold.ttf'
FONT_MED = 'store_assets/fonts/PlusJakartaSans-Medium.ttf'

def get_font(size, weight="bold"):
    if weight == "serif":
        if os.path.exists(FONT_SERIF):
            return ImageFont.truetype(FONT_SERIF, size)
        return ImageFont.truetype(FONT_EB, size)
    elif weight == "extrabold":
        return ImageFont.truetype(FONT_EB, size)
    elif weight == "bold":
        return ImageFont.truetype(FONT_B, size)
    elif weight == "semibold":
        return ImageFont.truetype(FONT_SB, size)
    else:
        return ImageFont.truetype(FONT_MED, size)

SLIDES = [
    {
        "index": 1,
        "mode": "split",  # diagonal split
        "title": "All Your Wealth\nin One Place",
        "subtitle": "Track balances, net worth, and live multi-currency\nexchange rates in real time.",
        "inverted": False,
        "accent": (59, 130, 246),
    },
    {
        "index": 2,
        "mode": "light",  # single phone light mode
        "title": "Instant Multi-Account\nVisibility",
        "subtitle": "Monitor bank accounts, cards, cash, and investments\nin one unified glassmorphic view.",
        "inverted": False,
        "accent": (99, 102, 241),
    },
    {
        "index": 3,
        "mode": "split",  # diagonal split
        "title": "Every Transaction\nAccounted For",
        "subtitle": "Deterministic double-entry ledger with instant\nsearch, filters, and smart categories.",
        "inverted": True,
        "accent": (234, 88, 12),
    },
    {
        "index": 4,
        "mode": "dark",  # single phone dark mode
        "title": "Never Miss\na Due Payment",
        "subtitle": "Track upcoming bills, recurring subscriptions,\nand scheduled transfers automatically.",
        "inverted": False,
        "accent": (16, 185, 129),
    },
    {
        "index": 5,
        "mode": "split",  # diagonal split
        "title": "Master Your Mortgages\n& Active Loans",
        "subtitle": "Complete payoff schedules, monthly EMI tracking,\nand interest amortization at a glance.",
        "inverted": True,
        "accent": (217, 70, 239),
    },
    {
        "index": 6,
        "mode": "light",  # single phone light mode
        "title": "Control Any Currency\nor Card",
        "subtitle": "Support for USD, EUR, GBP, JPY, INR and more\nwith exact integer minor unit precision.",
        "inverted": False,
        "accent": (245, 158, 11),
    },
    {
        "index": 7,
        "mode": "split",  # diagonal split
        "title": "Total Privacy,\nZero Cloud Lock-in",
        "subtitle": "AES-256 local encrypted vaults, biometric locks,\nand end-to-end data ownership.",
        "inverted": True,
        "accent": (14, 165, 233),
    },
    {
        "index": 8,
        "mode": "dark",  # single phone dark mode
        "title": "Smart Ingestion\n& Instant OCR",
        "subtitle": "On-device ML receipt scanning, SMS alert parsing,\nand bank statement imports.",
        "inverted": False,
        "accent": (168, 85, 247),
    },
]

def prepare_screen(img_raw, crop_bottom_px=270):
    w, h = img_raw.size
    # Crop bottom navigation bar
    return img_raw.crop((0, 0, w, h - crop_bottom_px))

def create_split_screen(img_light, img_dark):
    # Both already cropped
    w, h = img_light.size
    split = Image.new("RGBA", (w, h))
    
    # Left: Light mode, Right: Dark mode
    x_top = int(w * 0.28)
    x_bot = int(w * 0.72)
    
    mask = Image.new("L", (w, h), 0)
    draw = ImageDraw.Draw(mask)
    draw.polygon([(0, 0), (x_top, 0), (x_bot, h), (0, h)], fill=255)
    
    split.paste(img_dark, (0, 0))
    split.paste(img_light, (0, 0), mask)
    
    # Luminous separator line with subtle gradient ray
    line_layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    ldraw = ImageDraw.Draw(line_layer)
    ldraw.line([(x_top, 0), (x_bot, h)], fill=(130, 205, 255, 190), width=6)
    ldraw.line([(x_top, 0), (x_bot, h)], fill=(255, 255, 255, 240), width=2)
    split.paste(line_layer, (0, 0), line_layer)
    return split

def build_phone_frame(screen_img, dark_theme=False, scale_w=840):
    sw, sh = screen_img.size
    disp_w = scale_w
    disp_h = int(disp_w * sh / sw)
    
    screen_resized = screen_img.resize((disp_w, disp_h), Image.Resampling.LANCZOS)
    
    # Screen rounded corners
    disp_radius = 52
    screen_mask = Image.new("L", (disp_w, disp_h), 0)
    sdraw = ImageDraw.Draw(screen_mask)
    sdraw.rounded_rectangle((0, 0, disp_w, disp_h), radius=disp_radius, fill=255)
    
    # Pixel Pro camera hole
    cam_x = disp_w // 2
    cam_y = 36
    cam_r = 13
    sdraw.ellipse((cam_x - cam_r, cam_y - cam_r, cam_x + cam_r, cam_y + cam_r), fill=0)
    
    # Bezel borders
    border_x = 22
    border_top = 22
    border_bot = 22
    
    chassis_w = disp_w + border_x * 2
    chassis_h = disp_h + border_top + border_bot
    chassis_radius = 68
    
    phone = Image.new("RGBA", (chassis_w + 24, chassis_h + 20), (0, 0, 0, 0))
    pdraw = ImageDraw.Draw(phone)
    
    btn_color = (65, 70, 82, 255) if dark_theme else (90, 95, 108, 255)
    # Left buttons
    pdraw.rounded_rectangle((4, 380, 10, 480), radius=3, fill=btn_color)
    pdraw.rounded_rectangle((4, 510, 10, 610), radius=3, fill=btn_color)
    # Right button
    pdraw.rounded_rectangle((chassis_w + 12, 440, chassis_w + 18, 560), radius=3, fill=btn_color)
    
    # Phone chassis
    body_box = (12, 10, chassis_w + 12, chassis_h + 10)
    chassis_fill = (15, 17, 23, 255) if dark_theme else (24, 26, 32, 255)
    chassis_outline = (60, 65, 80, 255) if dark_theme else (85, 90, 105, 255)
    
    pdraw.rounded_rectangle(body_box, radius=chassis_radius, fill=chassis_fill, outline=chassis_outline, width=4)
    
    # Inner rim
    inner_box = (12 + 2, 10 + 2, chassis_w + 12 - 2, chassis_h + 10 - 2)
    pdraw.rounded_rectangle(inner_box, radius=chassis_radius - 2, outline=(35, 38, 48, 255), width=1)
    
    # Speaker slit at top
    spk_w = 120
    spk_h = 6
    spk_x = 12 + (chassis_w - spk_w) // 2
    spk_y = 10 + 8
    pdraw.rounded_rectangle((spk_x, spk_y, spk_x + spk_w, spk_y + spk_h), radius=2, fill=(45, 48, 56, 255))
    
    # Paste display
    screen_paste_pos = (12 + border_x, 10 + border_top)
    phone.paste(screen_resized, screen_paste_pos, screen_mask)
    
    # Camera lens overlay
    pdraw.ellipse((screen_paste_pos[0] + cam_x - cam_r,
                   screen_paste_pos[1] + cam_y - cam_r,
                   screen_paste_pos[0] + cam_x + cam_r,
                   screen_paste_pos[1] + cam_y + cam_r), fill=(10, 12, 16, 255))
    pdraw.ellipse((screen_paste_pos[0] + cam_x - cam_r + 2,
                   screen_paste_pos[1] + cam_y - cam_r + 2,
                   screen_paste_pos[0] + cam_x + cam_r - 2,
                   screen_paste_pos[1] + cam_y + cam_r - 2), outline=(40, 50, 70, 200), width=1)

    # Multi-tier realistic soft drop shadow
    shadow_margin = 110
    sw = phone.width + shadow_margin * 2
    sh = phone.height + shadow_margin * 2
    shadow_layer = Image.new("RGBA", (sw, sh), (0, 0, 0, 0))
    s_draw = ImageDraw.Draw(shadow_layer)
    
    s_color = (0, 12, 35, 75) if not dark_theme else (0, 0, 0, 175)
    s_draw.rounded_rectangle((shadow_margin + 12, shadow_margin + 36,
                              shadow_margin + 12 + chassis_w, shadow_margin + 36 + chassis_h),
                             radius=chassis_radius + 6, fill=s_color)
    shadow_layer = shadow_layer.filter(ImageFilter.GaussianBlur(48))
    
    contact_layer = Image.new("RGBA", (sw, sh), (0, 0, 0, 0))
    c_draw = ImageDraw.Draw(contact_layer)
    c_color = (0, 15, 40, 95) if not dark_theme else (0, 0, 0, 230)
    c_draw.rounded_rectangle((shadow_margin + 12, shadow_margin + 18,
                              shadow_margin + 12 + chassis_w, shadow_margin + 18 + chassis_h),
                             radius=chassis_radius, fill=c_color)
    contact_layer = contact_layer.filter(ImageFilter.GaussianBlur(18))
    
    composite = Image.new("RGBA", (sw, sh), (0, 0, 0, 0))
    composite.paste(shadow_layer, (0, 0), shadow_layer)
    composite.paste(contact_layer, (0, 0), contact_layer)
    composite.paste(phone, (shadow_margin, shadow_margin), phone)
    
    return composite, shadow_margin

def render_card(slide, raw_light_path, raw_dark_path):
    img_light_raw = Image.open(raw_light_path).convert("RGBA")
    img_dark_raw = Image.open(raw_dark_path).convert("RGBA")
    
    img_light = prepare_screen(img_light_raw)
    img_dark = prepare_screen(img_dark_raw)
    
    mode = slide.get("mode", "split")
    if mode == "split":
        screen_img = create_split_screen(img_light, img_dark)
        is_dark_phone = True
    elif mode == "dark":
        screen_img = img_dark
        is_dark_phone = True
    else:
        screen_img = img_light
        is_dark_phone = False

    # Canvas with soft elegant background
    # Subtle organic mesh tints
    accent = slide.get("accent", (59, 130, 246))
    canvas = Image.new("RGBA", (W, H), (247, 248, 252, 255))
    
    bg_shapes = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    bdraw = ImageDraw.Draw(bg_shapes)
    
    # Soft ambient glow matching slide accent
    glow_color = (accent[0], accent[1], accent[2], 38)
    bdraw.ellipse((W - 650, H - 1600, W + 550, H - 150), fill=glow_color)
    bdraw.ellipse((-400, 150, 600, 1250), fill=(225, 235, 250, 180))
    bg_shapes = bg_shapes.filter(ImageFilter.GaussianBlur(95))
    canvas.paste(bg_shapes, (0, 0), bg_shapes)

    # Phone mockup (scaled nicely)
    phone_comp, margin = build_phone_frame(screen_img, dark_theme=is_dark_phone, scale_w=830)
    phone_w, phone_h = phone_comp.size
    
    inverted = slide["inverted"]
    phone_x = (W - phone_w) // 2
    
    draw = ImageDraw.Draw(canvas)
    
    if not inverted:
        # Layout A: Text Top, Phone Bottom (Phone extends to bottom of screen naturally)
        cursor_y = 150
        
        # Title (ExtraBold, high-impact)
        f_title = get_font(84, weight="extrabold")
        title_lines = slide["title"].split("\n")
        title_color = (15, 23, 42, 255)
        for line in title_lines:
            bbox = f_title.getbbox(line)
            tw = bbox[2] - bbox[0]
            draw.text(((W - tw) // 2, cursor_y), line, fill=title_color, font=f_title)
            cursor_y += (bbox[3] - bbox[1]) + 20
            
        # Subtitle (Medium weight)
        cursor_y += 10
        f_sub = get_font(36, weight="medium")
        sub_lines = slide["subtitle"].split("\n")
        sub_color = (100, 116, 139, 255)
        for line in sub_lines:
            bbox = f_sub.getbbox(line)
            tw = bbox[2] - bbox[0]
            draw.text(((W - tw) // 2, cursor_y), line, fill=sub_color, font=f_sub)
            cursor_y += (bbox[3] - bbox[1]) + 16
            
        # Place Phone cleanly in bottom area
        phone_y = 660 - margin
        canvas.paste(phone_comp, (phone_x, phone_y), phone_comp)
        
    else:
        # Layout B: Phone Top, Text Bottom
        # Phone starts near top
        phone_y = 100 - margin
        canvas.paste(phone_comp, (phone_x, phone_y), phone_comp)
        
        cursor_y = 1960
        
        # Title (ExtraBold)
        f_title = get_font(84, weight="extrabold")
        title_lines = slide["title"].split("\n")
        title_color = (15, 23, 42, 255)
        for line in title_lines:
            bbox = f_title.getbbox(line)
            tw = bbox[2] - bbox[0]
            draw.text(((W - tw) // 2, cursor_y), line, fill=title_color, font=f_title)
            cursor_y += (bbox[3] - bbox[1]) + 20
            
        # Subtitle
        cursor_y += 10
        f_sub = get_font(36, weight="medium")
        sub_lines = slide["subtitle"].split("\n")
        sub_color = (100, 116, 139, 255)
        for line in sub_lines:
            bbox = f_sub.getbbox(line)
            tw = bbox[2] - bbox[0]
            draw.text(((W - tw) // 2, cursor_y), line, fill=sub_color, font=f_sub)
            cursor_y += (bbox[3] - bbox[1]) + 16

    # Return RGB canvas (NO docked bottom bar!)
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
    
    print("=== Rendering Creative Shipshot Promo Cards (No Bottom Bar, Varied Layouts) ===")
    for s in SLIDES:
        idx = s["index"]
        raw_l = str(base_dir / "raw_screenshots_light" / f"screenshot_phone_{idx}.png")
        raw_d = str(base_dir / "raw_screenshots_dark" / f"screenshot_phone_{idx}.png")
        out_file = target_dir / f"playstore_promo_{idx}.png"
        fl_file = fastlane_dir / f"playstore_promo_{idx}.png"
        
        print(f"Rendering slide {idx} [{s['mode']}] -> {out_file.name}...")
        img = render_card(s, raw_l, raw_d)
        save_image_safely(img, out_file)
        save_image_safely(img, fl_file)
        
    print("\nDone! All 8 promo cards updated in both store_assets and fastlane directory.")

if __name__ == "__main__":
    main()
