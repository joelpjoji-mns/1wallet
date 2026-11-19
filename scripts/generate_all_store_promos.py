import os
from PIL import Image, ImageDraw, ImageFont, ImageFilter

CANVAS_W = 1080
CANVAS_H = 2160

FONTS_DIR = "C:/Windows/Fonts"
FONT_BOLD_PATH = os.path.join(FONTS_DIR, "segoeuib.ttf")
FONT_REG_PATH = os.path.join(FONTS_DIR, "segoeui.ttf")
FONT_HEAVY_PATH = os.path.join(FONTS_DIR, "bahnschrift.ttf")

def get_font(path, size):
    try:
        return ImageFont.truetype(path, size)
    except Exception:
        return ImageFont.load_default()

def generate_promo_card(screenshot_path, top_tag, headline, subtitle, bottom_tag, screen_num, accent_color, output_path):
    # 1. Base Canvas - Luxury clean light studio finish
    card = Image.new("RGBA", (CANVAS_W, CANVAS_H), (247, 249, 252, 255))
    
    # 2. Organic ambient decorative curves (soft tinted shapes)
    overlay = Image.new("RGBA", (CANVAS_W, CANVAS_H), (0, 0, 0, 0))
    ol_draw = ImageDraw.Draw(overlay)
    
    ar, ag, ab = accent_color[:3]
    ol_draw.ellipse([-240, -120, 760, 640], fill=(ar, ag, ab, 22))
    ol_draw.ellipse([540, 160, 1340, 960], fill=(ar, ag, ab, 18))
    ol_draw.ellipse([-180, 1150, 520, 1850], fill=(ar, ag, ab, 15))
    ol_draw.ellipse([640, 1250, 1300, 1980], fill=(ar, ag, ab, 20))
    
    card = Image.alpha_composite(card, overlay)
    draw = ImageDraw.Draw(card)

    # 3. Top Tag Pill (e.g. "SMART MONEY")
    font_tag = get_font(FONT_BOLD_PATH, 24)
    tag_pad_x = 28
    tag_pad_y = 9
    
    tag_bbox = font_tag.getbbox(top_tag.upper())
    tag_text_w = tag_bbox[2] - tag_bbox[0]
    tag_text_h = tag_bbox[3] - tag_bbox[1]
    
    tag_w = tag_text_w + (tag_pad_x * 2)
    tag_h = tag_text_h + (tag_pad_y * 2) + 4
    tag_x = (CANVAS_W - tag_w) // 2
    tag_y = 100

    draw.rounded_rectangle(
        [tag_x, tag_y, tag_x + tag_w, tag_y + tag_h],
        radius=tag_h // 2,
        fill=accent_color
    )
    draw.text(
        (tag_x + tag_pad_x, tag_y + tag_pad_y),
        top_tag.upper(),
        font=font_tag,
        fill=(255, 255, 255, 255)
    )

    # 4. Headline (Premium bold headline)
    font_headline = get_font(FONT_HEAVY_PATH, 56)
    head_lines = headline.split("\n")
    cur_y = tag_y + tag_h + 36
    for line in head_lines:
        h_bbox = font_headline.getbbox(line)
        line_w = h_bbox[2] - h_bbox[0]
        draw.text(((CANVAS_W - line_w) // 2, cur_y), line, font=font_headline, fill=(15, 23, 42, 255))
        cur_y += 70

    # 5. Subtitle (Clean balanced description)
    font_sub = get_font(FONT_REG_PATH, 28)
    sub_lines = subtitle.split("\n")
    cur_y += 6
    for line in sub_lines:
        s_bbox = font_sub.getbbox(line)
        line_w = s_bbox[2] - s_bbox[0]
        draw.text(((CANVAS_W - line_w) // 2, cur_y), line, font=font_sub, fill=(100, 116, 139, 255))
        cur_y += 42

    # 6. Flagship Smartphone Mockup
    phone_w = 780
    phone_h = 1380
    phone_x = (CANVAS_W - phone_w) // 2
    phone_y = cur_y + 36

    # Ambient drop shadow
    shadow = Image.new("RGBA", (CANVAS_W, CANVAS_H), (0, 0, 0, 0))
    sh_draw = ImageDraw.Draw(shadow)
    sh_draw.rounded_rectangle(
        [phone_x + 12, phone_y + 18, phone_x + phone_w - 12, phone_y + phone_h + 24],
        radius=56,
        fill=(0, 0, 0, 50)
    )
    shadow = shadow.filter(ImageFilter.GaussianBlur(38))
    card = Image.alpha_composite(card, shadow)
    draw = ImageDraw.Draw(card)

    # Phone Outer Bezel (Titanium Dark chassis)
    bezel = 14
    draw.rounded_rectangle(
        [phone_x, phone_y, phone_x + phone_w, phone_y + phone_h],
        radius=56,
        fill=(15, 20, 28, 255),
        outline=(52, 64, 80, 255),
        width=3
    )

    # Screen viewport
    screen_x = phone_x + bezel
    screen_y = phone_y + bezel
    screen_w = phone_w - (bezel * 2)
    screen_h = phone_h - (bezel * 2)
    screen_radius = 44

    # Load and render app screenshot inside viewport
    if os.path.exists(screenshot_path):
        screen_img = Image.open(screenshot_path).convert("RGBA")
        screen_resized = screen_img.resize((screen_w, screen_h), Image.Resampling.LANCZOS)
        
        mask = Image.new("L", (screen_w, screen_h), 0)
        mask_draw = ImageDraw.Draw(mask)
        mask_draw.rounded_rectangle([0, 0, screen_w, screen_h], radius=screen_radius, fill=255)
        
        card.paste(screen_resized, (screen_x, screen_y), mask)

    # Dynamic Island / Camera pill at top of screen
    island_w = 110
    island_h = 30
    island_x = phone_x + (phone_w - island_w) // 2
    island_y = screen_y + 14
    draw.rounded_rectangle(
        [island_x, island_y, island_x + island_w, island_y + island_h],
        radius=island_h // 2,
        fill=(0, 0, 0, 255)
    )

    # 7. Bottom Category Bar (Matching reference)
    bot_w = 900
    bot_h = 80
    bot_x = (CANVAS_W - bot_w) // 2
    bot_y = CANVAS_H - bot_h - 56

    draw.rounded_rectangle(
        [bot_x, bot_y, bot_x + bot_w, bot_y + bot_h],
        radius=24,
        fill=(17, 24, 39, 255)
    )

    font_bot = get_font(FONT_BOLD_PATH, 28)
    draw.text((bot_x + 36, bot_y + 24), bottom_tag.upper(), font=font_bot, fill=(255, 255, 255, 255))
    draw.text((bot_x + bot_w - 74, bot_y + 24), screen_num, font=font_bot, fill=(148, 163, 184, 255))

    # Convert to pure 24-bit RGB (strict Google Play specification)
    final_card = card.convert("RGB")
    final_card.save(output_path, "PNG", quality=95)
    print(f"Generated: {output_path}")

SCREENS = [
    {
        "id": 1,
        "screenshot": "android/fastlane/metadata/android/en-US/images/screenshot_phone_1.png",
        "top_tag": "Smart Ledger",
        "headline": "All your wealth,\nin one unified view",
        "subtitle": "Track cash flow, net worth, and liquid assets\nwith mathematical double-entry integrity.",
        "bottom_tag": "Dashboard",
        "screen_num": "01",
        "accent": (37, 99, 235)  # Royal Blue
    },
    {
        "id": 2,
        "screenshot": "android/fastlane/metadata/android/en-US/images/screenshot_phone_2.png",
        "top_tag": "Analytics & Trends",
        "headline": "Track trends &\nproject your wealth",
        "subtitle": "Analyze historical balances and forecast future\nfinancial runway with interactive charts.",
        "bottom_tag": "Analytics",
        "screen_num": "02",
        "accent": (124, 58, 237)  # Violet
    },
    {
        "id": 3,
        "screenshot": "android/fastlane/metadata/android/en-US/images/screenshot_phone_3.png",
        "top_tag": "Global Forex",
        "headline": "Multi-currency &\ninstant forex tracking",
        "subtitle": "Hold, spend, and convert foreign currencies\nwith live, real-time exchange rates.",
        "bottom_tag": "Forex",
        "screen_num": "03",
        "accent": (5, 150, 105)  # Emerald
    },
    {
        "id": 4,
        "screenshot": "android/fastlane/metadata/android/en-US/images/screenshot_phone_4.png",
        "top_tag": "Automated Bills",
        "headline": "Never miss a bill\nor recurring payment",
        "subtitle": "Manage planned expenses, utility cadences,\nand subscriptions with smart alerts.",
        "bottom_tag": "Bills & Planning",
        "screen_num": "04",
        "accent": (217, 119, 6)  # Amber Gold
    },
    {
        "id": 5,
        "screenshot": "android/fastlane/metadata/android/en-US/images/screenshot_phone_5.png",
        "top_tag": "Debt Control",
        "headline": "Master your loans\nand debt payoff",
        "subtitle": "Track mortgages, auto loans, and EMIs with\nvisual progress bars and payoff schedules.",
        "bottom_tag": "Loans & EMI",
        "screen_num": "05",
        "accent": (225, 29, 72)  # Rose Red
    },
    {
        "id": 6,
        "screenshot": "android/fastlane/metadata/android/en-US/images/screenshot_phone_6.png",
        "top_tag": "Unified Portfolio",
        "headline": "Every account,\norganized in one place",
        "subtitle": "Bank accounts, credit cards, cash, savings,\nand digital wallets in seamless harmony.",
        "bottom_tag": "Accounts",
        "screen_num": "06",
        "accent": (13, 148, 136)  # Teal
    },
    {
        "id": 7,
        "screenshot": "android/fastlane/metadata/android/en-US/images/screenshot_phone_7.png",
        "top_tag": "Instant Capture",
        "headline": "Scan paper receipts\nwith on-device AI",
        "subtitle": "Extract amounts, merchants, places, and dates\ninstantly using privacy-first local OCR.",
        "bottom_tag": "AI OCR Scanner",
        "screen_num": "07",
        "accent": (79, 70, 229)  # Indigo
    },
    {
        "id": 8,
        "screenshot": "android/fastlane/metadata/android/en-US/images/screenshot_phone_8.png",
        "top_tag": "Cash Flow View",
        "headline": "Visualize cash flow\nday by day",
        "subtitle": "Calendar grid shows daily inflow and outflow\nso you always know what is coming next.",
        "bottom_tag": "Calendar Planner",
        "screen_num": "08",
        "accent": (6, 182, 212)  # Cyan
    }
]

def main():
    out_dir = "android/fastlane/metadata/android/en-US/images/promo_cards"
    os.makedirs(out_dir, exist_ok=True)
    
    for s in SCREENS:
        out_file = os.path.join(out_dir, f"playstore_promo_{s['id']}.png")
        generate_promo_card(
            screenshot_path=s["screenshot"],
            top_tag=s["top_tag"],
            headline=s["headline"],
            subtitle=s["subtitle"],
            bottom_tag=s["bottom_tag"],
            screen_num=s["screen_num"],
            accent_color=s["accent"],
            output_path=out_file
        )

if __name__ == "__main__":
    main()
