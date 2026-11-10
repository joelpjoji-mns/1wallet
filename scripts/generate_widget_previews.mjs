import fs from 'fs';
import path from 'path';
import zlib from 'zlib';

// Fast pure-JS PNG encoder
function encodePNG(width, height, rgbaBuffer) {
  const signature = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]);

  function chunk(type, data) {
    const len = Buffer.alloc(4);
    len.writeUInt32BE(data.length, 0);
    const typeBuf = Buffer.from(type, 'ascii');
    const crcBuf = Buffer.alloc(4);
    let crc = 0xFFFFFFFF;
    const table = new Uint32Array(256);
    for (let i = 0; i < 256; i++) {
      let c = i;
      for (let k = 0; k < 8; k++) c = (c & 1) ? (0xEDB88320 ^ (c >>> 1)) : (c >>> 1);
      table[i] = c;
    }
    for (let i = 0; i < typeBuf.length; i++) crc = table[(crc ^ typeBuf[i]) & 0xFF] ^ (crc >>> 8);
    for (let i = 0; i < data.length; i++) crc = table[(crc ^ data[i]) & 0xFF] ^ (crc >>> 8);
    crc = (crc ^ 0xFFFFFFFF) >>> 0;
    crcBuf.writeUInt32BE(crc, 0);
    return Buffer.concat([len, typeBuf, data, crcBuf]);
  }

  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(width, 0);
  ihdr.writeUInt32BE(height, 4);
  ihdr[8] = 8; // 8-bit depth
  ihdr[9] = 6; // RGBA color type
  ihdr[10] = 0;
  ihdr[11] = 0;
  ihdr[12] = 0;

  const stride = width * 4;
  const filtered = Buffer.alloc((stride + 1) * height);
  for (let y = 0; y < height; y++) {
    filtered[y * (stride + 1)] = 0; // Filter None
    rgbaBuffer.copy(filtered, y * (stride + 1) + 1, y * stride, (y + 1) * stride);
  }

  const compressed = zlib.deflateSync(filtered, { level: 9 });
  return Buffer.concat([
    signature,
    chunk('IHDR', ihdr),
    chunk('IDAT', compressed),
    chunk('IEND', Buffer.alloc(0))
  ]);
}

// 2D Software Drawing Surface
class Surface {
  constructor(width, height) {
    this.width = width;
    this.height = height;
    this.buffer = Buffer.alloc(width * height * 4, 0);
  }

  setPixel(x, y, r, g, b, a = 255) {
    x = Math.round(x);
    y = Math.round(y);
    if (x < 0 || x >= this.width || y < 0 || y >= this.height || a <= 0) return;
    const idx = (y * this.width + x) * 4;
    if (a >= 255) {
      this.buffer[idx] = r;
      this.buffer[idx + 1] = g;
      this.buffer[idx + 2] = b;
      this.buffer[idx + 3] = 255;
    } else {
      const alpha = a / 255;
      const invAlpha = 1 - alpha;
      const curA = this.buffer[idx + 3] / 255;
      const outA = alpha + curA * invAlpha;
      if (outA > 0) {
        this.buffer[idx] = Math.round((r * alpha + this.buffer[idx] * curA * invAlpha) / outA);
        this.buffer[idx + 1] = Math.round((g * alpha + this.buffer[idx + 1] * curA * invAlpha) / outA);
        this.buffer[idx + 2] = Math.round((b * alpha + this.buffer[idx + 2] * curA * invAlpha) / outA);
        this.buffer[idx + 3] = Math.round(outA * 255);
      }
    }
  }

  fillRect(x, y, w, h, r, g, b, a = 255) {
    const x0 = Math.max(0, Math.floor(x));
    const y0 = Math.max(0, Math.floor(y));
    const x1 = Math.min(this.width, Math.ceil(x + w));
    const y1 = Math.min(this.height, Math.ceil(y + h));
    for (let py = y0; py < y1; py++) {
      for (let px = x0; px < x1; px++) {
        this.setPixel(px, py, r, g, b, a);
      }
    }
  }

  fillRoundRect(x, y, w, h, radius, r, g, b, a = 255) {
    const x0 = Math.max(0, Math.floor(x));
    const y0 = Math.max(0, Math.floor(y));
    const x1 = Math.min(this.width, Math.ceil(x + w));
    const y1 = Math.min(this.height, Math.ceil(y + h));
    const rSq = radius * radius;
    for (let py = y0; py < y1; py++) {
      for (let px = x0; px < x1; px++) {
        let inside = true;
        // Top-left
        if (px < x + radius && py < y + radius) {
          const dx = px - (x + radius);
          const dy = py - (y + radius);
          if (dx * dx + dy * dy > rSq) inside = false;
        }
        // Top-right
        else if (px > x + w - radius && py < y + radius) {
          const dx = px - (x + w - radius);
          const dy = py - (y + radius);
          if (dx * dx + dy * dy > rSq) inside = false;
        }
        // Bottom-left
        else if (px < x + radius && py > y + h - radius) {
          const dx = px - (x + radius);
          const dy = py - (y + h - radius);
          if (dx * dx + dy * dy > rSq) inside = false;
        }
        // Bottom-right
        else if (px > x + w - radius && py > y + h - radius) {
          const dx = px - (x + w - radius);
          const dy = py - (y + h - radius);
          if (dx * dx + dy * dy > rSq) inside = false;
        }
        if (inside) {
          this.setPixel(px, py, r, g, b, a);
        }
      }
    }
  }

  strokeRoundRect(x, y, w, h, radius, lineWidth, r, g, b, a = 255) {
    // Fill outer and clear/mask inner
    const x0 = Math.max(0, Math.floor(x));
    const y0 = Math.max(0, Math.floor(y));
    const x1 = Math.min(this.width, Math.ceil(x + w));
    const y1 = Math.min(this.height, Math.ceil(y + h));
    const innerX = x + lineWidth;
    const innerY = y + lineWidth;
    const innerW = w - lineWidth * 2;
    const innerH = h - lineWidth * 2;
    const innerR = Math.max(0, radius - lineWidth);

    const rSq = radius * radius;
    const innerRSq = innerR * innerR;

    for (let py = y0; py < y1; py++) {
      for (let px = x0; px < x1; px++) {
        // Check outer
        let insideOuter = true;
        if (px < x + radius && py < y + radius) {
          const dx = px - (x + radius), dy = py - (y + radius);
          if (dx * dx + dy * dy > rSq) insideOuter = false;
        } else if (px > x + w - radius && py < y + radius) {
          const dx = px - (x + w - radius), dy = py - (y + radius);
          if (dx * dx + dy * dy > rSq) insideOuter = false;
        } else if (px < x + radius && py > y + h - radius) {
          const dx = px - (x + radius), dy = py - (y + h - radius);
          if (dx * dx + dy * dy > rSq) insideOuter = false;
        } else if (px > x + w - radius && py > y + h - radius) {
          const dx = px - (x + w - radius), dy = py - (y + h - radius);
          if (dx * dx + dy * dy > rSq) insideOuter = false;
        }

        if (!insideOuter) continue;

        // Check inner
        let insideInner = true;
        if (px < innerX || px >= innerX + innerW || py < innerY || py >= innerY + innerH) {
          insideInner = false;
        } else if (px < innerX + innerR && py < innerY + innerR) {
          const dx = px - (innerX + innerR), dy = py - (innerY + innerR);
          if (dx * dx + dy * dy > innerRSq) insideInner = false;
        } else if (px > innerX + innerW - innerR && py < innerY + innerR) {
          const dx = px - (innerX + innerW - innerR), dy = py - (innerY + innerR);
          if (dx * dx + dy * dy > innerRSq) insideInner = false;
        } else if (px < innerX + innerR && py > innerY + innerH - innerR) {
          const dx = px - (innerX + innerR), dy = py - (innerY + innerH - innerR);
          if (dx * dx + dy * dy > innerRSq) insideInner = false;
        } else if (px > innerX + innerW - innerR && py > innerY + innerH - innerR) {
          const dx = px - (innerX + innerW - innerR), dy = py - (innerY + innerH - innerR);
          if (dx * dx + dy * dy > innerRSq) insideInner = false;
        }

        if (!insideInner) {
          this.setPixel(px, py, r, g, b, a);
        }
      }
    }
  }

  fillCircle(cx, cy, radius, r, g, b, a = 255) {
    const x0 = Math.max(0, Math.floor(cx - radius));
    const y0 = Math.max(0, Math.floor(cy - radius));
    const x1 = Math.min(this.width, Math.ceil(cx + radius));
    const y1 = Math.min(this.height, Math.ceil(cy + radius));
    const rSq = radius * radius;
    for (let py = y0; py < y1; py++) {
      for (let px = x0; px < x1; px++) {
        const dx = px - cx;
        const dy = py - cy;
        if (dx * dx + dy * dy <= rSq) {
          this.setPixel(px, py, r, g, b, a);
        }
      }
    }
  }

  drawLine(x0, y0, x1, y1, width, r, g, b, a = 255) {
    const dx = x1 - x0;
    const dy = y1 - y0;
    const dist = Math.sqrt(dx * dx + dy * dy);
    if (dist === 0) return;
    const steps = Math.ceil(dist * 2);
    for (let s = 0; s <= steps; s++) {
      const t = s / steps;
      const px = x0 + dx * t;
      const py = y0 + dy * t;
      this.fillCircle(px, py, width / 2, r, g, b, a);
    }
  }
}

// Minimal 5x7 bitmap font for crisp legible text in thumbnails
const FONT = {
  ' ': [0,0,0,0,0],
  'A': [0x7C, 0x12, 0x11, 0x12, 0x7C],
  'B': [0x7F, 0x49, 0x49, 0x49, 0x36],
  'C': [0x3E, 0x41, 0x41, 0x41, 0x22],
  'D': [0x7F, 0x41, 0x41, 0x22, 0x1C],
  'E': [0x7F, 0x49, 0x49, 0x49, 0x41],
  'F': [0x7F, 0x09, 0x09, 0x09, 0x01],
  'G': [0x3E, 0x41, 0x49, 0x49, 0x7A],
  'H': [0x7F, 0x08, 0x08, 0x08, 0x7F],
  'I': [0x00, 0x41, 0x7F, 0x41, 0x00],
  'J': [0x20, 0x40, 0x41, 0x3F, 0x01],
  'K': [0x7F, 0x08, 0x14, 0x22, 0x41],
  'L': [0x7F, 0x40, 0x40, 0x40, 0x40],
  'M': [0x7F, 0x02, 0x04, 0x02, 0x7F],
  'N': [0x7F, 0x04, 0x08, 0x10, 0x7F],
  'O': [0x3E, 0x41, 0x41, 0x41, 0x3E],
  'P': [0x7F, 0x09, 0x09, 0x09, 0x06],
  'Q': [0x3E, 0x41, 0x51, 0x21, 0x5E],
  'R': [0x7F, 0x09, 0x19, 0x29, 0x46],
  'S': [0x46, 0x49, 0x49, 0x49, 0x31],
  'T': [0x01, 0x01, 0x7F, 0x01, 0x01],
  'U': [0x3F, 0x40, 0x40, 0x40, 0x3F],
  'V': [0x1F, 0x20, 0x40, 0x20, 0x1F],
  'W': [0x7F, 0x20, 0x18, 0x20, 0x7F],
  'X': [0x63, 0x14, 0x08, 0x14, 0x63],
  'Y': [0x07, 0x08, 0x70, 0x08, 0x07],
  'Z': [0x61, 0x51, 0x49, 0x45, 0x43],
  '0': [0x3E, 0x51, 0x49, 0x45, 0x3E],
  '1': [0x00, 0x42, 0x7F, 0x40, 0x00],
  '2': [0x42, 0x61, 0x51, 0x49, 0x46],
  '3': [0x21, 0x41, 0x45, 0x4B, 0x31],
  '4': [0x18, 0x14, 0x12, 0x7F, 0x10],
  '5': [0x27, 0x45, 0x45, 0x45, 0x39],
  '6': [0x3C, 0x4A, 0x49, 0x49, 0x30],
  '7': [0x01, 0x71, 0x09, 0x05, 0x03],
  '8': [0x36, 0x49, 0x49, 0x49, 0x36],
  '9': [0x06, 0x49, 0x49, 0x29, 0x1E],
  '$': [0x12, 0x2A, 0x7F, 0x2A, 0x24],
  '+': [0x08, 0x08, 0x3E, 0x08, 0x08],
  '-': [0x08, 0x08, 0x08, 0x08, 0x08],
  '.': [0x00, 0x60, 0x60, 0x00, 0x00],
  ',': [0x00, 0x80, 0x60, 0x00, 0x00],
  ':': [0x00, 0x36, 0x36, 0x00, 0x00],
  '/': [0x20, 0x10, 0x08, 0x04, 0x02],
  '%': [0x23, 0x13, 0x08, 0x64, 0x62],
  '#': [0x14, 0x7F, 0x14, 0x7F, 0x14],
};

function drawText(surface, text, x, y, scale = 2, r = 255, g = 255, b = 255, a = 255) {
  text = text.toUpperCase();
  let curX = x;
  for (let i = 0; i < text.length; i++) {
    const ch = text[i];
    const glyph = FONT[ch] || FONT[' '];
    for (let col = 0; col < 5; col++) {
      const bits = glyph[col];
      for (let row = 0; row < 7; row++) {
        if ((bits & (1 << row)) !== 0) {
          surface.fillRect(curX + col * scale, y + row * scale, scale, scale, r, g, b, a);
        }
      }
    }
    curX += 6 * scale;
  }
}

// Draw premium 1Wallet Card Shell
function createCard(width = 800, height = 440, accentColor = [124, 77, 255]) {
  const s = new Surface(width, height);
  const pad = 24;
  const radius = 32;

  // Background subtle gradient
  for (let y = pad; y < height - pad; y++) {
    const t = (y - pad) / (height - pad * 2);
    const bgR = Math.round(18 + t * 6);
    const bgG = Math.round(19 + t * 6);
    const bgB = Math.round(28 + t * 8);
    s.fillRoundRect(pad, pad, width - pad * 2, height - pad * 2, radius, bgR, bgG, bgB, 255);
  }

  // Glass Border with subtle glow
  s.strokeRoundRect(pad, pad, width - pad * 2, height - pad * 2, radius, 3, 255, 255, 255, 38);

  return { surface: s, pad, radius, accent: accentColor };
}

function drawHeader(card, title, subtitle, iconChar = 'W') {
  const { surface: s, pad, accent } = card;
  const iconSize = 52;
  const iconX = pad + 24;
  const iconY = pad + 24;

  // Icon container pill
  s.fillRoundRect(iconX, iconY, iconSize, iconSize, 16, accent[0], accent[1], accent[2], 45);
  s.strokeRoundRect(iconX, iconY, iconSize, iconSize, 16, 2, accent[0], accent[1], accent[2], 120);

  // Icon symbol
  drawText(s, iconChar, iconX + 16, iconY + 12, 4, accent[0], accent[1], accent[2], 255);

  // Title
  drawText(s, title, iconX + iconSize + 18, iconY + 6, 3, 240, 240, 248, 255);

  // Subtitle
  if (subtitle) {
    drawText(s, subtitle, iconX + iconSize + 18, iconY + 30, 2, 140, 145, 170, 255);
  }

  // Pill badge on right
  const pillW = 120;
  const pillH = 34;
  const pillX = 800 - pad - 24 - pillW;
  const pillY = iconY + 8;
  s.fillRoundRect(pillX, pillY, pillW, pillH, 17, 255, 255, 255, 18);
  s.strokeRoundRect(pillX, pillY, pillW, pillH, 17, 1.5, 255, 255, 255, 35);
  drawText(s, '1WALLET', pillX + 22, pillY + 10, 2, 200, 205, 225, 220);
}

const WIDGETS = [
  {
    name: 'widget_preview_balance',
    title: 'TOTAL BALANCE',
    subtitle: 'NET WORTH $18,420.00',
    icon: '$',
    accent: [124, 77, 255],
    draw(card) {
      const { surface: s, pad } = card;
      // Big number
      drawText(s, '$12,480.00', pad + 28, pad + 110, 6, 255, 255, 255, 255);

      // Currency chips
      const chips = ['USD 12,480', 'EUR 11,550', 'GBP 9,750'];
      let cx = pad + 28;
      for (const chip of chips) {
        s.fillRoundRect(cx, pad + 180, 140, 32, 16, 255, 255, 255, 20);
        s.strokeRoundRect(cx, pad + 180, 140, 32, 16, 1, 255, 255, 255, 40);
        drawText(s, chip, cx + 14, pad + 190, 2, 180, 185, 210, 255);
        cx += 152;
      }

      // Flow boxes (Income / Expense)
      const boxW = 340;
      const boxH = 90;
      const by = pad + 240;

      // Income panel (Green)
      s.fillRoundRect(pad + 28, by, boxW, boxH, 18, 0, 230, 118, 25);
      s.strokeRoundRect(pad + 28, by, boxW, boxH, 18, 1.5, 0, 230, 118, 60);
      drawText(s, 'INCOME', pad + 48, by + 18, 2, 0, 230, 118, 240);
      drawText(s, '+$4,250.00', pad + 48, by + 44, 4, 0, 230, 118, 255);

      // Expense panel (Red)
      s.fillRoundRect(pad + 390, by, boxW, boxH, 18, 255, 82, 82, 25);
      s.strokeRoundRect(pad + 390, by, boxW, boxH, 18, 1.5, 255, 82, 82, 60);
      drawText(s, 'EXPENSE', pad + 410, by + 18, 2, 255, 82, 82, 240);
      drawText(s, '-$1,820.40', pad + 410, by + 44, 4, 255, 82, 82, 255);
    }
  },
  {
    name: 'widget_preview_accounts',
    title: 'ACCOUNTS OVERVIEW',
    subtitle: '5 ACTIVE ACCOUNTS',
    icon: 'A',
    accent: [0, 229, 255],
    draw(card) {
      const { surface: s, pad } = card;
      const accs = [
        { name: 'CHECKING', bal: '$5,420.00', color: [0, 229, 255] },
        { name: 'SAVINGS', bal: '$6,500.00', color: [0, 230, 118] },
        { name: 'CASH', bal: '$560.00', color: [255, 171, 0] },
        { name: 'CREDIT CARD', bal: '-$340.00', color: [255, 82, 82] },
        { name: 'INVESTMENT', bal: '$8,200.00', color: [124, 77, 255] },
        { name: 'EMERGENCY', bal: '$2,000.00', color: [255, 64, 129] },
      ];

      for (let i = 0; i < accs.length; i++) {
        const col = i % 3;
        const row = Math.floor(i / 3);
        const ax = pad + 28 + col * 236;
        const ay = pad + 115 + row * 125;
        const aw = 220;
        const ah = 105;

        s.fillRoundRect(ax, ay, aw, ah, 16, 255, 255, 255, 14);
        s.strokeRoundRect(ax, ay, aw, ah, 16, 1.5, 255, 255, 255, 30);
        s.fillCircle(ax + 24, ay + 26, 8, accs[i].color[0], accs[i].color[1], accs[i].color[2], 255);
        drawText(s, accs[i].name, ax + 40, ay + 18, 2, 170, 175, 195, 255);
        drawText(s, accs[i].bal, ax + 20, ay + 56, 3, 255, 255, 255, 255);
      }
    }
  },
  {
    name: 'widget_preview_recent',
    title: 'RECENT TRANSACTIONS',
    subtitle: 'LATEST SPENDING & INCOME',
    icon: 'R',
    accent: [255, 171, 0],
    draw(card) {
      const { surface: s, pad } = card;
      const txs = [
        { title: 'SUPERMARKET GROCERIES', cat: 'FOOD & DINING', amt: '-$64.50', pos: false },
        { title: 'MONTHLY TECH SALARY', cat: 'INCOME', amt: '+$3,250.00', pos: true },
        { title: 'STREAMING SUBSCRIPTION', cat: 'ENTERTAINMENT', amt: '-$14.99', pos: false },
      ];

      for (let i = 0; i < txs.length; i++) {
        const ty = pad + 110 + i * 86;
        s.fillRoundRect(pad + 28, ty, 700, 72, 16, 255, 255, 255, 14);
        s.strokeRoundRect(pad + 28, ty, 700, 72, 16, 1.5, 255, 255, 255, 28);

        const iconColor = txs[i].pos ? [0, 230, 118] : [255, 82, 82];
        s.fillCircle(pad + 58, ty + 36, 18, iconColor[0], iconColor[1], iconColor[2], 40);
        drawText(s, txs[i].pos ? '+' : '-', pad + 52, ty + 26, 3, iconColor[0], iconColor[1], iconColor[2], 255);

        drawText(s, txs[i].title, pad + 96, ty + 18, 2, 240, 240, 250, 255);
        drawText(s, txs[i].cat, pad + 96, ty + 42, 2, 130, 135, 160, 255);

        drawText(s, txs[i].amt, pad + 510, ty + 26, 3, iconColor[0], iconColor[1], iconColor[2], 255);
      }
    }
  },
  {
    name: 'widget_preview_balance_trend',
    title: 'BALANCE TREND',
    subtitle: '30 DAYS · +14.8% GROWTH',
    icon: 'T',
    accent: [0, 230, 118],
    draw(card) {
      const { surface: s, pad } = card;
      drawText(s, '$18,920.00', pad + 28, pad + 105, 5, 255, 255, 255, 255);
      drawText(s, '+$2,410.00 THIS MONTH', pad + 28, pad + 160, 2, 0, 230, 118, 255);

      // Sparkline points
      const points = [
        [pad + 30, pad + 320],
        [pad + 120, pad + 300],
        [pad + 210, pad + 310],
        [pad + 300, pad + 260],
        [pad + 390, pad + 275],
        [pad + 480, pad + 230],
        [pad + 570, pad + 210],
        [pad + 660, pad + 240],
        [pad + 710, pad + 190],
      ];

      for (let i = 0; i < points.length - 1; i++) {
        s.drawLine(points[i][0], points[i][1], points[i+1][0], points[i+1][1], 5, 0, 230, 118, 255);
      }
      for (const p of points) {
        s.fillCircle(p[0], p[1], 7, 0, 230, 118, 255);
      }
    }
  },
  {
    name: 'widget_preview_top_categories',
    title: 'TOP CATEGORIES',
    subtitle: 'SPENDING BREAKDOWN',
    icon: 'C',
    accent: [255, 64, 129],
    draw(card) {
      const { surface: s, pad } = card;
      const cats = [
        { name: 'GROCERIES & FOOD', pct: 44, amt: '$720.00', color: [255, 64, 129] },
        { name: 'HOUSING & UTILITIES', pct: 32, amt: '$520.00', color: [124, 77, 255] },
        { name: 'SHOPPING & GEAR', pct: 16, amt: '$260.00', color: [0, 229, 255] },
        { name: 'ENTERTAINMENT', pct: 8, amt: '$130.00', color: [255, 171, 0] },
      ];

      for (let i = 0; i < cats.length; i++) {
        const cy = pad + 110 + i * 66;
        drawText(s, cats[i].name, pad + 28, cy, 2, 220, 225, 240, 255);
        drawText(s, cats[i].amt, pad + 590, cy, 2, 255, 255, 255, 255);

        // Progress bar background
        s.fillRoundRect(pad + 28, cy + 22, 670, 14, 7, 255, 255, 255, 20);
        // Progress fill
        const barW = Math.round(670 * (cats[i].pct / 100));
        s.fillRoundRect(pad + 28, cy + 22, barW, 14, 7, cats[i].color[0], cats[i].color[1], cats[i].color[2], 255);
      }
    }
  },
  {
    name: 'widget_preview_safe_spend',
    title: 'SAFE TO SPEND',
    subtitle: 'DAILY BUDGET PACING',
    icon: 'S',
    accent: [0, 230, 118],
    draw(card) {
      const { surface: s, pad } = card;
      drawText(s, '$48.50', pad + 28, pad + 110, 6, 0, 230, 118, 255);
      drawText(s, 'AVAILABLE PER DAY UNTIL MONTH END', pad + 28, pad + 175, 2, 170, 175, 195, 255);

      s.fillRoundRect(pad + 28, pad + 220, 700, 24, 12, 255, 255, 255, 25);
      s.fillRoundRect(pad + 28, pad + 220, 480, 24, 12, 0, 230, 118, 255);

      drawText(s, 'SPENT $980.00 OF $1,500.00 BUDGET (65%)', pad + 28, pad + 265, 2, 200, 205, 225, 255);
      drawText(s, '12 DAYS REMAINING IN PERIOD', pad + 28, pad + 295, 2, 140, 145, 170, 255);
    }
  },
  {
    name: 'widget_preview_upcoming',
    title: 'UPCOMING BILLS',
    subtitle: 'SCHEDULED PAYMENTS DUE',
    icon: 'U',
    accent: [255, 82, 82],
    draw(card) {
      const { surface: s, pad } = card;
      const bills = [
        { name: 'APARTMENT RENT', due: 'IN 2 DAYS', amt: '$1,200.00', urgent: true },
        { name: 'ELECTRICITY BILL', due: 'IN 5 DAYS', amt: '$84.50', urgent: false },
        { name: 'INTERNET FIBER', due: 'IN 8 DAYS', amt: '$60.00', urgent: false },
      ];

      for (let i = 0; i < bills.length; i++) {
        const by = pad + 110 + i * 85;
        s.fillRoundRect(pad + 28, by, 700, 72, 16, 255, 255, 255, 14);
        s.strokeRoundRect(pad + 28, by, 700, 72, 16, 1.5, 255, 255, 255, 30);

        drawText(s, bills[i].name, pad + 48, by + 18, 2, 240, 240, 250, 255);
        const dueColor = bills[i].urgent ? [255, 82, 82] : [255, 171, 0];
        drawText(s, bills[i].due, pad + 48, by + 44, 2, dueColor[0], dueColor[1], dueColor[2], 255);

        drawText(s, bills[i].amt, pad + 520, by + 26, 3, 255, 255, 255, 255);
      }
    }
  },
  {
    name: 'widget_preview_calendar',
    title: 'CALENDAR PACE',
    subtitle: 'NOVEMBER 2026',
    icon: 'M',
    accent: [124, 77, 255],
    draw(card) {
      const { surface: s, pad } = card;
      drawText(s, 'SPENT TODAY: $32.40', pad + 28, pad + 115, 3, 255, 255, 255, 255);
      drawText(s, 'THIS MONTH: $1,420.00', pad + 28, pad + 155, 3, 124, 77, 255, 255);

      // Mini 7-day row
      const days = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
      const spent = ['$12', '$45', '$0', '$28', '$84', '$110', '$32'];
      for (let i = 0; i < 7; i++) {
        const dx = pad + 28 + i * 102;
        const dy = pad + 220;
        s.fillRoundRect(dx, dy, 90, 80, 14, 255, 255, 255, 14);
        s.strokeRoundRect(dx, dy, 90, 80, 14, 1, 255, 255, 255, 28);
        drawText(s, days[i], dx + 24, dy + 16, 2, 140, 145, 170, 255);
        drawText(s, spent[i], dx + 20, dy + 45, 2, 240, 240, 255, 255);
      }
    }
  },
  {
    name: 'widget_preview_quick_actions',
    title: 'QUICK ACTIONS',
    subtitle: 'INSTANT SHORTCUTS',
    icon: '+',
    accent: [0, 229, 255],
    draw(card) {
      const { surface: s, pad } = card;
      const actions = [
        { label: 'ADD EXPENSE', icon: '-', color: [255, 82, 82] },
        { label: 'ADD INCOME', icon: '+', color: [0, 230, 118] },
        { label: 'SCAN RECEIPT', icon: 'S', color: [0, 229, 255] },
      ];

      for (let i = 0; i < actions.length; i++) {
        const ax = pad + 28 + i * 238;
        const ay = pad + 130;
        const aw = 224;
        const ah = 150;

        s.fillRoundRect(ax, ay, aw, ah, 22, actions[i].color[0], actions[i].color[1], actions[i].color[2], 25);
        s.strokeRoundRect(ax, ay, aw, ah, 22, 2, actions[i].color[0], actions[i].color[1], actions[i].color[2], 80);

        s.fillCircle(ax + aw / 2, ay + 50, 26, actions[i].color[0], actions[i].color[1], actions[i].color[2], 200);
        drawText(s, actions[i].icon, ax + aw / 2 - 10, ay + 36, 4, 18, 19, 28, 255);

        drawText(s, actions[i].label, ax + 24, ay + 104, 2, 240, 240, 250, 255);
      }
    }
  },
  {
    name: 'widget_preview_currency_values',
    title: 'EXCHANGE RATES',
    subtitle: 'BASE: USD · LIVE CONVERSION',
    icon: 'E',
    accent: [255, 171, 0],
    draw(card) {
      const { surface: s, pad } = card;
      const rates = [
        { pair: 'EUR / USD', rate: '0.9240', change: '+0.15%' },
        { pair: 'GBP / USD', rate: '0.7810', change: '-0.08%' },
        { pair: 'JPY / USD', rate: '154.20', change: '+0.42%' },
        { pair: 'INR / USD', rate: '84.35', change: '+0.05%' },
      ];

      for (let i = 0; i < rates.length; i++) {
        const col = i % 2;
        const row = Math.floor(i / 2);
        const rx = pad + 28 + col * 356;
        const ry = pad + 120 + row * 105;

        s.fillRoundRect(rx, ry, 340, 90, 16, 255, 255, 255, 14);
        s.strokeRoundRect(rx, ry, 340, 90, 16, 1.5, 255, 255, 255, 30);

        drawText(s, rates[i].pair, rx + 24, ry + 20, 2, 160, 165, 190, 255);
        drawText(s, rates[i].rate, rx + 24, ry + 48, 3, 255, 255, 255, 255);
        drawText(s, rates[i].change, rx + 210, ry + 50, 2, 0, 230, 118, 255);
      }
    }
  },
  {
    name: 'widget_preview_account_groups',
    title: 'ACCOUNT GROUPS',
    subtitle: 'ASSETS & LIABILITIES SPLIT',
    icon: 'G',
    accent: [124, 77, 255],
    draw(card) {
      const { surface: s, pad } = card;
      const groups = [
        { name: 'BANK ACCOUNTS', bal: '$11,920.00', count: '3 ACCOUNTS' },
        { name: 'CASH HOLDINGS', bal: '$560.00', count: '2 WALLETS' },
        { name: 'CREDIT CARDS', bal: '-$340.00', count: '1 CARD' },
        { name: 'INVESTMENTS', bal: '$8,200.00', count: '2 PORTFOLIOS' },
      ];

      for (let i = 0; i < groups.length; i++) {
        const col = i % 2;
        const row = Math.floor(i / 2);
        const gx = pad + 28 + col * 356;
        const gy = pad + 120 + row * 105;

        s.fillRoundRect(gx, gy, 340, 90, 16, 255, 255, 255, 14);
        s.strokeRoundRect(gx, gy, 340, 90, 16, 1.5, 255, 255, 255, 30);

        drawText(s, groups[i].name, gx + 24, gy + 18, 2, 170, 175, 200, 255);
        drawText(s, groups[i].bal, gx + 24, gy + 48, 3, 255, 255, 255, 255);
      }
    }
  },
  {
    name: 'widget_preview_credit_utilization',
    title: 'CREDIT UTILIZATION',
    subtitle: '18% OF TOTAL LIMIT',
    icon: 'D',
    accent: [0, 230, 118],
    draw(card) {
      const { surface: s, pad } = card;
      drawText(s, '18%', pad + 28, pad + 105, 6, 0, 230, 118, 255);
      drawText(s, 'TOTAL BALANCE: $720.00 / LIMIT: $4,000.00', pad + 28, pad + 175, 2, 170, 175, 195, 255);

      s.fillRoundRect(pad + 28, pad + 215, 700, 24, 12, 255, 255, 255, 25);
      s.fillRoundRect(pad + 28, pad + 215, 126, 24, 12, 0, 230, 118, 255);

      drawText(s, 'HEALTHY RATIO (<30%) · $3,280.00 AVAILABLE', pad + 28, pad + 260, 2, 0, 230, 118, 240);
    }
  },
  {
    name: 'widget_preview_savings_rate',
    title: 'SAVINGS RATE',
    subtitle: 'MONTHLY SAVINGS TARGET',
    icon: '%',
    accent: [0, 230, 118],
    draw(card) {
      const { surface: s, pad } = card;
      drawText(s, '42%', pad + 28, pad + 105, 6, 0, 230, 118, 255);
      drawText(s, 'SAVED $1,800.00 OF $4,250.00 INCOME', pad + 28, pad + 175, 2, 220, 225, 240, 255);

      s.fillRoundRect(pad + 28, pad + 215, 700, 24, 12, 255, 255, 255, 25);
      s.fillRoundRect(pad + 28, pad + 215, 294, 24, 12, 0, 230, 118, 255);

      drawText(s, 'ON TRACK FOR ANNUAL TARGET (GOAL: 35%)', pad + 28, pad + 260, 2, 0, 230, 118, 240);
    }
  },
  {
    name: 'widget_preview_tag_cloud',
    title: 'TAG CLOUD',
    subtitle: 'TOP SPENDING TAGS',
    icon: '#',
    accent: [255, 171, 0],
    draw(card) {
      const { surface: s, pad } = card;
      const tags = [
        { name: '#GROCERIES', amt: '$420' },
        { name: '#DINING', amt: '$180' },
        { name: '#COFFEE', amt: '$64' },
        { name: '#SUBSCRIPTIONS', amt: '$52' },
        { name: '#TECH', amt: '$310' },
        { name: '#TRAVEL', amt: '$190' },
      ];

      for (let i = 0; i < tags.length; i++) {
        const col = i % 3;
        const row = Math.floor(i / 3);
        const tx = pad + 28 + col * 236;
        const ty = pad + 120 + row * 95;

        s.fillRoundRect(tx, ty, 220, 75, 16, 255, 171, 0, 25);
        s.strokeRoundRect(tx, ty, 220, 75, 16, 1.5, 255, 171, 0, 70);

        drawText(s, tags[i].name, tx + 18, ty + 16, 2, 255, 210, 80, 255);
        drawText(s, tags[i].amt, tx + 18, ty + 42, 3, 255, 255, 255, 255);
      }
    }
  },
  {
    name: 'widget_preview_cash_burn_runway',
    title: 'CASH RUNWAY',
    subtitle: 'FINANCIAL RUNWAY & BURN',
    icon: 'F',
    accent: [255, 171, 0],
    draw(card) {
      const { surface: s, pad } = card;
      drawText(s, '14.2 MO', pad + 28, pad + 105, 6, 255, 171, 0, 255);
      drawText(s, 'MONTHLY BURN RATE: $2,100.00 / MO', pad + 28, pad + 175, 2, 200, 205, 225, 255);

      s.fillRoundRect(pad + 28, pad + 220, 700, 75, 18, 255, 255, 255, 14);
      s.strokeRoundRect(pad + 28, pad + 220, 700, 75, 18, 1.5, 255, 255, 255, 30);
      drawText(s, 'LIQUID CASH RESERVES: $29,820.00', pad + 48, pad + 248, 2, 0, 230, 118, 255);
    }
  },
  {
    name: 'widget_preview_no_spend_streak',
    title: 'NO-SPEND STREAK',
    subtitle: 'DISCRETIONARY EXPENSE FREEZE',
    icon: 'N',
    accent: [255, 82, 82],
    draw(card) {
      const { surface: s, pad } = card;
      drawText(s, '5 DAYS', pad + 28, pad + 105, 6, 255, 82, 82, 255);
      drawText(s, 'CURRENT STREAK ACTIVE · BEST: 14 DAYS', pad + 28, pad + 175, 2, 220, 225, 240, 255);

      s.fillRoundRect(pad + 28, pad + 220, 700, 75, 18, 255, 82, 82, 25);
      s.strokeRoundRect(pad + 28, pad + 220, 700, 75, 18, 1.5, 255, 82, 82, 70);
      drawText(s, 'LAST ZERO-SPEND DAY: YESTERDAY', pad + 48, pad + 248, 2, 255, 255, 255, 255);
    }
  },
  {
    name: 'widget_preview_weekend_weekday',
    title: 'WEEKEND VS WEEKDAY',
    subtitle: 'SPENDING VELOCITY RATIO',
    icon: 'V',
    accent: [0, 229, 255],
    draw(card) {
      const { surface: s, pad } = card;
      drawText(s, '2.1X', pad + 28, pad + 105, 6, 0, 229, 255, 255);
      drawText(s, 'WEEKEND SPENDING SPEED RELATIVE TO WEEKDAYS', pad + 28, pad + 175, 2, 170, 175, 195, 255);

      const colW = 340;
      s.fillRoundRect(pad + 28, pad + 220, colW, 80, 16, 255, 255, 255, 14);
      drawText(s, 'WEEKDAY AVG', pad + 48, pad + 235, 2, 140, 145, 170, 255);
      drawText(s, '$42.50 / DAY', pad + 48, pad + 260, 3, 255, 255, 255, 255);

      s.fillRoundRect(pad + 390, pad + 220, colW, 80, 16, 0, 229, 255, 25);
      drawText(s, 'WEEKEND AVG', pad + 410, pad + 235, 2, 0, 229, 255, 255);
      drawText(s, '$89.20 / DAY', pad + 410, pad + 260, 3, 0, 229, 255, 255);
    }
  },
  {
    name: 'widget_preview_pending_review',
    title: 'PENDING REVIEW',
    subtitle: 'INBOX & AUTO-CAPTURE',
    icon: 'I',
    accent: [255, 171, 0],
    draw(card) {
      const { surface: s, pad } = card;
      drawText(s, '3 ITEMS', pad + 28, pad + 105, 6, 255, 171, 0, 255);
      drawText(s, '2 SMS TRANSACTIONS · 1 RECEIPT OCR', pad + 28, pad + 175, 2, 220, 225, 240, 255);

      s.fillRoundRect(pad + 28, pad + 220, 700, 75, 18, 255, 171, 0, 25);
      s.strokeRoundRect(pad + 28, pad + 220, 700, 75, 18, 1.5, 255, 171, 0, 70);
      drawText(s, 'TAP TO REVIEW & CONFIRM TO LEDGER', pad + 48, pad + 248, 2, 255, 255, 255, 255);
    }
  },
];

const outDir = path.resolve('android/app/src/main/res/drawable');

for (const w of WIDGETS) {
  const card = createCard(800, 440, w.accent);
  drawHeader(card, w.title, w.subtitle, w.icon);
  w.draw(card);
  const pngBuf = encodePNG(800, 440, card.surface.buffer);
  const outPath = path.join(outDir, `${w.name}.png`);
  fs.writeFileSync(outPath, pngBuf);
  console.log(`Generated ${w.name}.png (${pngBuf.length} bytes)`);
}

// Also update widget_preview_default.png with widget_preview_balance.png content
const defaultPreviewBuf = fs.readFileSync(path.join(outDir, 'widget_preview_balance.png'));
fs.writeFileSync(path.join(outDir, 'widget_preview_default.png'), defaultPreviewBuf);
console.log('Updated widget_preview_default.png');
