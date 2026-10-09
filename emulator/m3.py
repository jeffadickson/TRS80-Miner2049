"""Minimal TRS-80 Model III harness for testing the Miner 2049er port.

Models only what the game uses:
  * 64K memory; $3C00-$3FFF video RAM (64 x 16), $3800-$3BFF keyboard matrix (read-only)
  * port $E0: read = interrupt status, inverted (bit 2 = 0: real-time clock ticked), write = mask
  * port $EC: read clears the RTC interrupt; write = mode (ignored)
  * port $FF: write bits 0-1 = cassette output (logged for audio)
CPU clock 2.02752 MHz; one RTC tick every 67,584 T-states.
"""
import os as _os, sys as _sys
REPO = _os.path.abspath(_os.path.join(_os.path.dirname(__file__), '..'))
for _d in ('tools', 'tests', 'emulator', '../BigFive-Miner2049/tools', '../BigFive-Miner2049/emulator'):
    if _os.path.join(REPO, _d) not in _sys.path: _sys.path.insert(0, _os.path.join(REPO, _d))

import z80, struct

CLOCK = 2027520
TICK = CLOCK // 30

KEYS = {   # name -> (row address offset bit, bit)
    'ENTER': (0x40, 0), 'CLEAR': (0x40, 1), 'BREAK': (0x40, 2), 'UP': (0x40, 3), 'DOWN': (0x40, 4),
    'LEFT': (0x40, 5), 'RIGHT': (0x40, 6), 'SPACE': (0x40, 7), 'SHIFT': (0x80, 0),
}
for i, ch in enumerate('@ABCDEFGHIJKLMNOPQRSTUVWXYZ'):
    KEYS[ch] = (1 << (i // 8), i % 8)
for i in range(10):
    KEYS[str(i)] = (0x10 if i < 8 else 0x20, i % 8)

class M3:
    def __init__(self):
        self.m = z80.Z80Machine()
        self.mem = self.m.memory
        self.keys = set()
        self.rtc = 0
        self.t = 0
        self.next_tick = TICK
        self.audio = []          # (tstate, level)
        self.frames = 0
        self.m.set_input_callback(self._in)
        self.m.set_output_callback(self._out)
        self.m.mark_addrs(0x3800, 0x400, self.m.READ_MARK)
        self.m.set_read_callback(self._read)

    def _kbd(self, addr):
        rows = addr & 0xFF
        v = 0
        for k in self.keys:
            r, b = KEYS[k]
            if rows & r: v |= 1 << b
        return v

    def _read(self, addr):
        if 0x3800 <= addr < 0x3C00:
            return self._kbd(addr)
        return self.mem[addr]

    def _in(self, port):
        p = port & 0xFF
        if p == 0xE0: return 0xFB if self.rtc else 0xFF   # active low, as on the real machine
        if p == 0xEC: self.rtc = 0; return 0xFF
        if p == 0xFF: return 0x00
        return 0xFF

    def _out(self, port, value):
        p = port & 0xFF
        if p == 0xFF and self.audio is not None: self.audio.append((self.t + TICK - self.m.ticks_to_stop, value & 3))

    def load_cmd(self, path):
        d = open(path, 'rb').read(); i = 0; entry = None
        while i < len(d):
            typ, ln = d[i], d[i + 1]; i += 2
            if ln == 0 and typ == 1: ln = 256
            if typ == 1:
                n = ln if ln > 2 else ln + 256
                addr = d[i] | d[i + 1] << 8
                data = d[i + 2:i + n]
                self.mem[addr:addr + len(data)] = data
                i += n
            elif typ == 2:
                entry = d[i] | d[i + 1] << 8; i += ln; break
            else:
                i += ln
        self.m.pc = entry
        self.m.sp = 0xFFF0
        return entry

    def run_frame(self, hook=None):
        """run one 1/30 s period"""
        self.m.ticks_to_stop = TICK
        n = 0
        while self.m.ticks_to_stop > 0 and n < 1000:   # run() can return early (e.g. on a read callback)
            self.m.run(); n += 1
        self.t += TICK
        self.rtc = 1
        self.frames += 1

    def screen(self, scale=3, fg=(220, 235, 255), debug=False):
        from PIL import Image                      # (only screenshots need PIL and numpy)
        import numpy as np
        vr = bytes(self.mem[0x3C00:0x4000])
        bg = bytes(self.mem[0x9C00:0xA000])
        img = np.zeros((48 * 2 * scale, 128 * scale, 3), np.uint8)
        ch_img = None
        for r in range(16):
            for c in range(64):
                v = vr[r * 64 + c]
                if 128 <= v < 192:
                    b0 = bg[r * 64 + c]
                    for k in range(6):
                        if v & (1 << k):
                            x = c * 2 + (k & 1); y = r * 3 + (k >> 1)
                            col = fg
                            if debug and not (128 <= b0 < 192 and b0 & (1 << k)): col = (255, 170, 80)
                            img[y * 2 * scale:(y + 1) * 2 * scale - 1, x * scale:(x + 1) * scale - 1] = col
                elif 32 < v < 128:
                    img[(r * 3) * 2 * scale:(r * 3 + 3) * 2 * scale] = self._char(v, r, c, img, scale, fg)
        return Image.fromarray(img)

    FONT = None
    def _char(self, v, r, c, img, scale, fg):
        # crude text: use a 5x7 bitmap font from PIL's default, drawn into the cell
        from PIL import Image, ImageDraw, ImageFont
        import numpy as np
        sl = img[(r * 3) * 2 * scale:(r * 3 + 3) * 2 * scale].copy()
        cell = Image.new('L', (2 * scale * 1 * 2, 6 * scale), 0)
        d = ImageDraw.Draw(cell)
        f = ImageFont.load_default()
        d.text((0, 0), chr(v), fill=255, font=f)
        a = np.array(cell.resize((2 * scale, 6 * scale)))
        x0 = c * 2 * scale
        h = min(a.shape[0], sl.shape[0])
        sub = sl[:h, x0:x0 + 2 * scale]
        sub[a[:h, :sub.shape[1]] > 100] = fg
        return sl
