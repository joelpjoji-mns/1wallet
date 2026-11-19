import os
from PIL import Image, ImageDraw, ImageFont, ImageFilter

W, H = 1280, 2856

# Typography with authentic static Plus Jakarta Sans weights
FONT_EB = 'store_assets/fonts/PlusJakartaSans-ExtraBold.ttf'
FONT_B = 'store_assets/fonts/PlusJakartaSans-Bold.ttf'
FONT_SB = 'store_assets/fonts/PlusJakartaSans-SemiBold.ttf'
FONT_MED = 'store_assets/fonts/PlusJakartaSans-Medium.ttf'

def get_font(size, weight="bold"):
    if weight == "extrabold":
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
        "tag": "Overview",
        "tag_num": "01",
        "pill": "Smart Finance",
        "title": "All Your Wealth\nin One Place",
        "subtitle": "Track balances, net worth, and live multi-currency\nexchange rates in real time.",
        "cta": None,
        "inverted": False,
    },
    {
        "index": 2,
        "tag": "Portfolios",
        "tag_num": "02",
        "pill": "Live Balances",
        "title": "Instant Multi-Account\nVisibility",
        "subtitle": "Monitor bank accounts, cards, cash, and investments\nin one unified glassmorphic view.",
        "cta": None,
        "inverted": False,
    },
    {
        "index": 3,
        "tag": "Ledger",
        "tag_num": "03",
        "pill": None,
        "title": "Every Transaction\nAccounted For",
        "subtitle": "Deterministic double-entry ledger with instant\nsearch, filters, and smart categories.",
        "cta": "Search Records",
        "inverted": True,
    },
    {
        "index": 4,
        "tag": "Recurring",
        "tag_num": "04",
        "pill": "Bill Reminders",
        "title": "Never Miss\na Due Payment",
        "subtitle": "Track upcoming bills, recurring subscriptions,\nand scheduled transfers automatically.",
        "cta": None,
        "inverted": False,
    },
    {
        "index": 5,
        "tag": "Debt & Loans",
        "tag_num": "05",
        "pill": None,
        "title": "Master Your Mortgages\n& Active Loans",
        "subtitle": "Complete payoff schedules, monthly EMI tracking,\nand interest amortization at a glance.",
        "cta": "Track EMIs",
        "inverted": True,
    },
    {
        "index": 6,
        "tag": "Accounts",
        "tag_num": "06",
        "pill": "Multi-Currency",
        "title": "Control Any Currency\nor Card",
        "subtitle": "Support for USD, EUR, GBP, JPY, INR and more\nwith exact integer minor unit precision.",
        "cta": None,
        "inverted": False,
    },
    {
        "index": 7,
        "tag": "Quick Entry",
        "tag_num": "07",
        "pill": None,
        "title": "Log Expenses\nwith Receipt Photos",
        "subtitle": "Snap photos of bills, auto-categorize expenses,\nand split transfers seamlessly in seconds.",
        "cta": "Attach Receipt",
        "inverted": True,
    },
    {
        "index": 8,
        "tag": "Calendar",
        "tag_num": "08",
        "pill": "Cash Flow Heatmap",
        "title": "Visualize Daily\nCash Velocity",
        "subtitle": "Full calendar heatmap showing daily spending spikes,\nincomes, and net monthly balance.",
        "cta": None,
        "inverted": False,
    },
]

def create_split_screen(img_light, img_dark):
    w, h = img_light.size
    split = Image.new("RGBA", (w, h))
    
    # Left: Light mode, Right: Dark mode
    # Diagonal line from (0.28 * w, 0) to (0.72 * w, h)
    x_top = w * 0.28
    x_bot = w * 0.72
    
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

def build_phone_frame(screen_img, dark_theme=False):
    # Screen scaled with exact 1280:2856 aspect ratio (no distortion)
    disp_w = 740
    disp_h = int(disp_w * 2856 / 1280)  # 1651px exactly
    
    screen_resized = screen_img.resize((disp_w, disp_h), Image.Resampling.LANCZOS)
    
    # Screen rounded corners
    disp_radius = 46
    screen_mask = Image.new("L", (disp_w, disp_h), 0)
    sdraw = ImageDraw.Draw(screen_mask)
    sdraw.rounded_rectangle((0, 0, disp_w, disp_h), radius=disp_radius, fill=255)
    
    # Pixel Pro camera hole
    cam_x = disp_w // 2
    cam_y = 34
    cam_r = 12
    sdraw.ellipse((cam_x - cam_r, cam_y - cam_r, cam_x + cam_r, cam_y + cam_r), fill=0)
    
    # Bezel borders
    border_x = 20
    border_top = 20
    border_bot = 20
    
    chassis_w = disp_w + border_x * 2  # 780px
    chassis_h = disp_h + border_top + border_bot  # 1691px
    chassis_radius = 62
    
    phone = Image.new("RGBA", (chassis_w + 24, chassis_h + 20), (0, 0, 0, 0))
    pdraw = ImageDraw.Draw(phone)
    
    # Physical side buttons
    btn_color = (65, 70, 82, 255) if dark_theme else (90, 95, 108, 255)
    # Left: Volume buttons
    pdraw.rounded_rectangle((4, 360, 10, 460), radius=3, fill=btn_color)
    pdraw.rounded_rectangle((4, 490, 10, 590), radius=3, fill=btn_color)
    # Right: Power button
    pdraw.rounded_rectangle((chassis_w + 12, 420, chassis_w + 18, 540), radius=3, fill=btn_color)
    
    # Phone chassis
    body_box = (12, 10, chassis_w + 12, chassis_h + 10)
    chassis_fill = (14, 16, 20, 255) if dark_theme else (22, 24, 30, 255)
    chassis_outline = (55, 60, 75, 255) if dark_theme else (75, 80, 95, 255)
    
    pdraw.rounded_rectangle(body_box, radius=chassis_radius, fill=chassis_fill, outline=chassis_outline, width=3)
    
    # Inner subtle rim
    inner_box = (12 + 2, 10 + 2, chassis_w + 12 - 2, chassis_h + 10 - 2)
    pdraw.rounded_rectangle(inner_box, radius=chassis_radius - 2, outline=(35, 38, 48, 255), width=1)
    
    # Speaker slit at top
    spk_w = 110
    spk_h = 5
    spk_x = 12 + (chassis_w - spk_w) // 2
    spk_y = 10 + 8
    pdraw.rounded_rectangle((spk_x, spk_y, spk_x + spk_w, spk_y + spk_h), radius=2, fill=(45, 48, 56, 255))
    
    # Paste display
    screen_paste_pos = (12 + border_x, 10 + border_top)
    phone.paste(screen_resized, screen_paste_pos, screen_mask)
    
    # Physical camera lens
    pdraw.ellipse((screen_paste_pos[0] + cam_x - cam_r,
                   screen_paste_pos[1] + cam_y - cam_r,
                   screen_paste_pos[0] + cam_x + cam_r,
                   screen_paste_pos[1] + cam_y + cam_r), fill=(10, 12, 16, 255))
    pdraw.ellipse((screen_paste_pos[0] + cam_x - cam_r + 2,
                   screen_paste_pos[1] + cam_y - cam_r + 2,
                   screen_paste_pos[0] + cam_x + cam_r - 2,
                   screen_paste_pos[1] + cam_y + cam_r - 2), outline=(40, 50, 70, 200), width=1)
    pdraw.ellipse((screen_paste_pos[0] + cam_x - 3,
                   screen_paste_pos[1] + cam_y - 4,
                   screen_paste_pos[0] + cam_x - 1,
                   screen_paste_pos[1] + cam_y - 2), fill=(190, 220, 255, 180))

    # Multi-tier realistic soft drop shadow
    shadow_margin = 100
    sw = phone.width + shadow_margin * 2
    sh = phone.height + shadow_margin * 2
    shadow_layer = Image.new("RGBA", (sw, sh), (0, 0, 0, 0))
    s_draw = ImageDraw.Draw(shadow_layer)
    
    # Ambient soft shadow
    s_color = (0, 12, 35, 70) if not dark_theme else (0, 0, 0, 160)
    s_draw.rounded_rectangle((shadow_margin + 12, shadow_margin + 36,
                              shadow_margin + 12 + chassis_w, shadow_margin + 36 + chassis_h),
                             radius=chassis_radius + 6, fill=s_color)
    shadow_layer = shadow_layer.filter(ImageFilter.GaussianBlur(45))
    
    # Contact shadow
    contact_layer = Image.new("RGBA", (sw, sh), (0, 0, 0, 0))
    c_draw = ImageDraw.Draw(contact_layer)
    c_color = (0, 15, 40, 90) if not dark_theme else (0, 0, 0, 220)
    c_draw.rounded_rectangle((shadow_margin + 12, shadow_margin + 18,
                              shadow_margin + 12 + chassis_w, shadow_margin + 18 + chassis_h),
                             radius=chassis_radius, fill=c_color)
    contact_layer = contact_layer.filter(ImageFilter.GaussianBlur(16))
    
    composite = Image.new("RGBA", (sw, sh), (0, 0, 0, 0))
    composite.paste(shadow_layer, (0, 0), shadow_layer)
    composite.paste(contact_layer, (0, 0), contact_layer)
    composite.paste(phone, (shadow_margin, shadow_margin), phone)
    
    return composite, shadow_margin

def render_card(slide, raw_light_path, raw_dark_path, mode="merged"):
    is_dark = (mode == "dark")
    
    img_light = Image.open(raw_light_path).convert("RGBA")
    img_dark = Image.open(raw_dark_path).convert("RGBA")
    
    if mode == "merged":
        screen_img = create_split_screen(img_light, img_dark)
    elif mode == "dark":
        screen_img = img_dark
    else:
        screen_img = img_light

    # Canvas
    canvas = Image.new("RGBA", (W, H), (13, 15, 21, 255) if is_dark else (244, 246, 251, 255))
    
    # Seamless background fluid shapes (matching Shipshot reference)
    bg_shapes = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    bdraw = ImageDraw.Draw(bg_shapes)
    
    if is_dark:
        # Deep sapphire & slate glow
        bdraw.ellipse((W - 650, H - 1500, W + 500, H - 200), fill=(22, 40, 85, 140))
        bdraw.ellipse((-350, 250, 650, 1350), fill=(16, 28, 65, 120))
        bg_shapes = bg_shapes.filter(ImageFilter.GaussianBlur(110))
    else:
        # Soft periwinkle & ice curves
        bdraw.ellipse((W - 600, H - 1400, W + 550, H - 200), fill=(218, 230, 248, 255))
        bdraw.ellipse((-400, 200, 550, 1200), fill=(232, 240, 252, 255))
        bg_shapes = bg_shapes.filter(ImageFilter.GaussianBlur(80))
        
    canvas.paste(bg_shapes, (0, 0), bg_shapes)

    # Phone mockup
    phone_comp, margin = build_phone_frame(screen_img, dark_theme=is_dark)
    phone_w, phone_h = phone_comp.size
    
    inverted = slide["inverted"]
    phone_x = (W - phone_w) // 2
    
    if not inverted:
        # Layout A: Text Top, Phone Bottom
        # Phone begins at y = 660, ends at y = 660 + 1691 = 2351. Dock at 2656.
        phone_y = 660 - margin
        canvas.paste(phone_comp, (phone_x, phone_y), phone_comp)
        
        draw = ImageDraw.Draw(canvas)
        cursor_y = 100
        
        # Pill badge
        if slide["pill"]:
            f_pill = get_font(28, weight="bold")
            pill_text = slide["pill"]
            bbox = f_pill.getbbox(pill_text)
            tw = bbox[2] - bbox[0]
            th = bbox[3] - bbox[1]
            pw = tw + 42
            ph = 52
            px = (W - pw) // 2
            pill_color = (37, 99, 235, 255)  # Royal electric blue
            draw.rounded_rectangle((px, cursor_y, px + pw, cursor_y + ph), radius=ph // 2, fill=pill_color)
            draw.text(((W - tw) // 2, cursor_y + (ph - th) // 2 - 2), pill_text, fill=(255, 255, 255, 255), font=f_pill)
            cursor_y += ph + 28
            
        # Title (ExtraBold, high-impact)
        f_title = get_font(72, weight="extrabold")
        title_lines = slide["title"].split("\n")
        title_color = (255, 255, 255, 255) if is_dark else (15, 23, 42, 255)
        for line in title_lines:
            bbox = f_title.getbbox(line)
            tw = bbox[2] - bbox[0]
            draw.text(((W - tw) // 2, cursor_y), line, fill=title_color, font=f_title)
            cursor_y += (bbox[3] - bbox[1]) + 18
            
        # Subtitle (Medium weight)
        cursor_y += 12
        f_sub = get_font(32, weight="medium")
        sub_lines = slide["subtitle"].split("\n")
        sub_color = (148, 163, 184, 255) if is_dark else (100, 116, 139, 255)
        for line in sub_lines:
            bbox = f_sub.getbbox(line)
            tw = bbox[2] - bbox[0]
            draw.text(((W - tw) // 2, cursor_y), line, fill=sub_color, font=f_sub)
            cursor_y += (bbox[3] - bbox[1]) + 14
            
    else:
        # Layout B: Phone Top, Text Bottom
        # Phone begins at y = 110, ends at y = 110 + 1691 = 1801.
        phone_y = 110 - margin
        canvas.paste(phone_comp, (phone_x, phone_y), phone_comp)
        
        draw = ImageDraw.Draw(canvas)
        cursor_y = 1880
        
        # Title (ExtraBold)
        f_title = get_font(72, weight="extrabold")
        title_lines = slide["title"].split("\n")
        title_color = (255, 255, 255, 255) if is_dark else (15, 23, 42, 255)
        for line in title_lines:
            bbox = f_title.getbbox(line)
            tw = bbox[2] - bbox[0]
            draw.text(((W - tw) // 2, cursor_y), line, fill=title_color, font=f_title)
            cursor_y += (bbox[3] - bbox[1]) + 18
            
        # Subtitle
        cursor_y += 12
        f_sub = get_font(32, weight="medium")
        sub_lines = slide["subtitle"].split("\n")
        sub_color = (148, 163, 184, 255) if is_dark else (100, 116, 139, 255)
        for line in sub_lines:
            bbox = f_sub.getbbox(line)
            tw = bbox[2] - bbox[0]
            draw.text(((W - tw) // 2, cursor_y), line, fill=sub_color, font=f_sub)
            cursor_y += (bbox[3] - bbox[1]) + 14
            
        # CTA Pill Button
        if slide["cta"]:
            cursor_y += 30
            f_cta = get_font(30, weight="bold")
            cta_text = slide["cta"]
            bbox = f_cta.getbbox(cta_text)
            tw = bbox[2] - bbox[0]
            th = bbox[3] - bbox[1]
            pw = tw + 52
            ph = 60
            px = (W - pw) // 2
            cta_color = (37, 99, 235, 255)  # Royal electric blue
            draw.rounded_rectangle((px, cursor_y, px + pw, cursor_y + ph), radius=ph // 2, fill=cta_color)
            draw.text(((W - tw) // 2, cursor_y + (ph - th) // 2 - 2), cta_text, fill=(255, 255, 255, 255), font=f_cta)

    # Docked Bottom Bar (Shipshot signature footer)
    dock_h = 200
    dock_y = H - dock_h
    dock = Image.new("RGBA", (W, dock_h), (0, 0, 0, 0))
    ddraw = ImageDraw.Draw(dock)
    dock_color = (21, 23, 31, 255) if not is_dark else (18, 20, 27, 255)
    ddraw.rounded_rectangle((0, 0, W, dock_h + 50), radius=48, fill=dock_color)
    
    # Left Category text
    f_cat = get_font(48, weight="bold")
    cat_text = slide["tag"]
    c_bbox = f_cat.getbbox(cat_text)
    c_h = c_bbox[3] - c_bbox[1]
    ddraw.text((72, (dock_h - c_h) // 2 - 6), cat_text, fill=(255, 255, 255, 255), font=f_cat)
    
    # Right Numeric text
    f_num = get_font(46, weight="medium")
    num_text = slide["tag_num"]
    n_bbox = f_num.getbbox(num_text)
    n_w = n_bbox[2] - n_bbox[0]
    n_h = n_bbox[3] - n_bbox[1]
    ddraw.text((W - 72 - n_w, (dock_h - n_h) // 2 - 6), num_text, fill=(148, 163, 184, 255), font=f_num)
    
    canvas.paste(dock, (0, dock_y), dock)
    
    return canvas.convert("RGB")

from pathlib import Path
import io

import tempfile

def save_image_safely(img, target_path):
    with tempfile.NamedTemporaryFile(suffix=".png", delete=False) as tf:
        temp_path = tf.name
    img.save(temp_path, format="PNG")
    os.replace(temp_path, target_path)

def main():
    modes = ["merged", "light", "dark"]
    base_dir = Path("store_assets").resolve()
    for mode in modes:
        out_dir = base_dir / f"shipshot_{mode}"
        out_dir.mkdir(parents=True, exist_ok=True)
        print(f"=== Rendering {mode.upper()} Edition ===")
        for s in SLIDES:
            idx = s["index"]
            raw_l = str(base_dir / "raw_screenshots_light" / f"screenshot_phone_{idx}.png")
            raw_d = str(base_dir / "raw_screenshots_dark" / f"screenshot_phone_{idx}.png")
            out_file = out_dir / f"playstore_promo_{idx}.png"
            print(f"Rendering slide {idx} ({s['tag']}) -> {out_file.name}...")
            img = render_card(s, raw_l, raw_d, mode=mode)
            save_image_safely(img, out_file)
            
    # Copy merged edition as default store listing
    target_dir = base_dir / "phone_screenshots"
    target_dir.mkdir(parents=True, exist_ok=True)
    fastlane_dir = Path("android/fastlane/metadata/android/en-US/images/promo_cards").resolve()
    fastlane_dir.mkdir(parents=True, exist_ok=True)
    for idx in range(1, 9):
        src = base_dir / "shipshot_merged" / f"playstore_promo_{idx}.png"
        dst = target_dir / f"playstore_promo_{idx}.png"
        fl_dst = fastlane_dir / f"playstore_promo_{idx}.png"
        with tempfile.NamedTemporaryFile(suffix=".png", delete=False) as tf:
            temp_path = tf.name
        Path(temp_path).write_bytes(src.read_bytes())
        os.replace(temp_path, dst)
        Path(fl_dst).write_bytes(src.read_bytes())
    print("Done! All 3 editions rendered and active screenshots updated.")

if __name__ == "__main__":
    main()
