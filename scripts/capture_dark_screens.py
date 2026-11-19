import subprocess, time, os

def adb(cmd):
    return subprocess.run(f"adb {cmd}", shell=True, capture_output=True, text=True).stdout.strip()

def tap(x, y, d=0.8):
    adb(f"shell input tap {x} {y}")
    time.sleep(d)

def swipe(x1, y1, x2, y2, dur=300, d=0.8):
    adb(f"shell input swipe {x1} {y1} {x2} {y2} {dur}")
    time.sleep(d)

def screencap(dst):
    adb("shell screencap -p /sdcard/temp_screen.png")
    adb(f"pull /sdcard/temp_screen.png \"{dst}\"")
    time.sleep(0.3)
    print(f"Captured: {dst}")

def bring_to_front():
    adb("shell am start -n com.joelpjoji.one.wallet/.MainActivity")
    time.sleep(0.6)

def go_to_home_tab():
    adb("shell input keyevent 4")
    adb("shell input keyevent 4")
    bring_to_front()
    tap(160, 2650, 0.6)
    swipe(640, 600, 640, 2400, 300, 0.6)
    swipe(640, 600, 640, 2400, 300, 0.6)

out_dir = r"C:\Users\Joel\Documents\Github\1wallet\store_assets\raw_screenshots_dark"
os.makedirs(out_dir, exist_ok=True)

print("Starting dark capture...")
# 1. Dashboard
go_to_home_tab()
screencap(os.path.join(out_dir, "screenshot_phone_1.png"))

# 2. Balance Trend
swipe(50, 1800, 50, 800, 350, 1.0)
screencap(os.path.join(out_dir, "screenshot_phone_2.png"))

# 3. Transactions History
bring_to_front()
tap(400, 2650, 1.0)
screencap(os.path.join(out_dir, "screenshot_phone_3.png"))

# 4. Planned payments
go_to_home_tab()
tap(74, 216, 0.8)
tap(300, 1350, 1.0)
screencap(os.path.join(out_dir, "screenshot_phone_4.png"))
tap(74, 216, 0.8)

# 5. Loans
go_to_home_tab()
tap(74, 216, 0.8)
tap(300, 1680, 1.0)
screencap(os.path.join(out_dir, "screenshot_phone_5.png"))
tap(74, 216, 0.8)

# 6. Accounts
bring_to_front()
tap(1000, 2650, 1.0)
screencap(os.path.join(out_dir, "screenshot_phone_6.png"))

# 7. Add Record Details
go_to_home_tab()
tap(1100, 2440, 1.0)
tap(730, 520, 0.8)
tap(200, 360, 0.8)
screencap(os.path.join(out_dir, "screenshot_phone_7.png"))
tap(74, 216, 0.8)

# 8. Calendar
bring_to_front()
tap(650, 2650, 1.0)
screencap(os.path.join(out_dir, "screenshot_phone_8.png"))
go_to_home_tab()
print("All 8 Dark Theme raw screenshots captured successfully!")
