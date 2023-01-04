#!/usr/bin/python3

from PIL import Image
import argparse, os


class BitWriter:
    def __init__(self):
        self.bytes   = bytearray()
        self.bit_pos = 0
    def __call__(self, value, nbits):
        assert value >= 0
        assert value < (1 << nbits)
        while nbits > 0:
            b = min(8 - self.bit_pos, nbits)
            nbits -= b
            v = (value & (((1 << b) - 1) << nbits)) >> nbits
            if self.bit_pos == 0: self.bytes.append(0)
            self.bytes[-1] |= v << self.bit_pos
            self.bit_pos += b
            self.bit_pos %= 8

class BitReader:
    def __init__(self, bytes):
        self.bytes    = bytes
        self.bit_pos  = 0
        self.byte_pos = 0
    def __call__(self, nbits):
        value = 0
        while nbits > 0:
            if self.byte_pos == len(self.bytes): return -1
            b = min(8 - self.bit_pos, nbits)
            nbits -= b
            value <<= b
            value |= (self.bytes[self.byte_pos] >> self.bit_pos) & ((1 << b) - 1)
            self.bit_pos  += b
            self.byte_pos += self.bit_pos == 8
            self.bit_pos  %= 8
        return value

BITS_D  = 9
BITS_L1 = 5
BITS_L2 = 12
MIN_L   = 2
MAX_L   = MIN_L + (1 << BITS_L2) - 1

def encode(write, data, bits_per_color):
    def max_len(i, d):
        l = 0
        while i + l < len(data) and data[i - d + l % d] == data[i + l]: l += 1
        return l
    i = 0
    while i < len(data):
        l = d = 0
        for dd in range(1, min(i + 1, 1 << BITS_D)):
            ll = max_len(i, dd)
            if ll > l:
                d = dd
                l = ll
                if l >= MAX_L: break
        if l < MIN_L:
            write(0, BITS_D)
            write(data[i], bits_per_color)
            i += 1
        else:
            write(d, BITS_D)
            l = min(l, MAX_L)
            if l < (1 << BITS_L1):
                write(0, 1)
                write(l - MIN_L, BITS_L1)
            else:
                write(1, 1)
                write(l - MIN_L, BITS_L2)
            i += l


def decode(code, bits_per_color):
    read = BitReader(code)
    data = bytearray()
    while 1:
        d = read(BITS_D)
        if d == -1: break
        if d == 0: data.append(read(bits_per_color))
        else:
            l = read(BITS_L2 if read(1) else BITS_L1)
            for _ in range(l + MIN_L): data.append(data[-d])
    return data


def main():
    parser = argparse.ArgumentParser(description="encode png")
    parser.add_argument("png_file")
    parser.add_argument("bin_file", nargs='?')
    args = parser.parse_args()


    img = Image.open(args.png_file).convert("RGBA")
    colors = [(0, 0, 0, 0)]
    color_table = { (0, 0, 0, 0) : 0 }
    for i, (_, c) in enumerate(img.getcolors()):
        if c[3] == 0:
            color_table[c] = 0
        else:
            color_table[c] = len(colors)
            colors.append(c)
    bits_per_color = len(colors).bit_length()
    W, H = img.size
    data = bytearray(color_table[img.getpixel((x, y))] for y in range(H) for x in range(W))

    write = BitWriter()
    write(W, 16)
    write(H, 16)
    write(len(colors), 8)
    for c in colors:
        for i in range(4): write(c[i], 8)
    encode(write, data, bits_per_color)
    assert data == decode(write.bytes[5 + len(colors) * 4:], bits_per_color)

    bin_file = args.bin_file or os.path.splitext(args.png_file)[0] + ".bin"
    with open(bin_file, "wb") as f:
        f.write(write.bytes)


if __name__ == "__main__": main()
