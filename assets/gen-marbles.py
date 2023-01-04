#!/usr/bin/python3

from PIL import Image

colors = [
    (50, 50, 50),
    (140, 20, 20),
    (60, 50, 150),
    (120, 120, 0),
    (10, 120, 50),
]

img = Image.open("marble.png").convert("RGBA")
W, H = img.size
R, G, B, A = img.split()


#dst = Image.new("RGBA", (W * len(colors), H))
dst = Image.open("stuff.png").convert("RGBA")
for i, (r, g, b) in enumerate(colors):

    r /= 255
    g /= 255
    b /= 255

    m = Image.merge("RGBA", (Image.eval(R, lambda x: int(x * r)),
                             Image.eval(G, lambda x: int(x * g)),
                             Image.eval(B, lambda x: int(x * b)),
                             A))
    dst.paste(m, (W * i, 0))

dst.save("marbles.png")
