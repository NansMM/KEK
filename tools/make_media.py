#!/usr/bin/env python3
"""Génère toutes les textures de KEK (TGA 32 bits, origine en haut à gauche).

Aucune dépendance : formes vectorielles rastérisées avec suréchantillonnage 4x4.
Usage : python tools/make_media.py
"""
import math
import os
import struct

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "KEK", "Media")
SS = 4


# ---------------------------------------------------------------- écriture TGA
def write_tga(name, w, h, rgba):
    path = os.path.join(OUT, name + ".tga")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, w, h, 32, 0x28)
    data = bytearray()
    for (r, g, b, a) in rgba:
        data += bytes((b, g, r, a))
    with open(path, "wb") as f:
        f.write(header + bytes(data))


def clamp(x, a=0.0, b=1.0):
    return a if x < a else b if x > b else x


def coverage(w, h, inside):
    out = []
    inv = 1.0 / (SS * SS)
    for y in range(h):
        for x in range(w):
            c = 0
            for sy in range(SS):
                v = (y + (sy + 0.5) / SS) / h
                for sx in range(SS):
                    u = (x + (sx + 0.5) / SS) / w
                    if inside(u, v):
                        c += 1
            out.append(c * inv)
    return out


def white(cov):
    return [(255, 255, 255, int(round(c * 255))) for c in cov]


# ---------------------------------------------------------------- primitives
def circle(cx, cy, r):
    r2 = r * r
    return lambda u, v: (u - cx) ** 2 + (v - cy) ** 2 <= r2


def ring(cx, cy, r, t):
    lo, hi = (r - t) ** 2, r * r
    return lambda u, v: lo <= (u - cx) ** 2 + (v - cy) ** 2 <= hi


def rect(x0, y0, x1, y1):
    return lambda u, v: x0 <= u <= x1 and y0 <= v <= y1


def rrect(x0, y0, x1, y1, r):
    def f(u, v):
        if not (x0 <= u <= x1 and y0 <= v <= y1):
            return False
        cx = min(max(u, x0 + r), x1 - r)
        cy = min(max(v, y0 + r), y1 - r)
        return (u - cx) ** 2 + (v - cy) ** 2 <= r * r
    return f


def seg(x0, y0, x1, y1, w):
    dx, dy = x1 - x0, y1 - y0
    L = dx * dx + dy * dy
    rr = (w / 2) ** 2

    def f(u, v):
        t = 0 if L == 0 else clamp(((u - x0) * dx + (v - y0) * dy) / L)
        px, py = x0 + t * dx, y0 + t * dy
        return (u - px) ** 2 + (v - py) ** 2 <= rr
    return f


def poly(pts):
    n = len(pts)

    def f(u, v):
        inside = False
        j = n - 1
        for i in range(n):
            xi, yi = pts[i]
            xj, yj = pts[j]
            if (yi > v) != (yj > v) and u < (xj - xi) * (v - yi) / (yj - yi) + xi:
                inside = not inside
            j = i
        return inside
    return f


def union(*fs):
    return lambda u, v: any(f(u, v) for f in fs)


def sub(a, *bs):
    return lambda u, v: a(u, v) and not any(b(u, v) for b in bs)


def inter(a, b):
    return lambda u, v: a(u, v) and b(u, v)


def star_pts(cx, cy, R, r, n):
    pts = []
    for i in range(n * 2):
        ang = -math.pi / 2 + i * math.pi / n
        rad = R if i % 2 == 0 else r
        pts.append((cx + math.cos(ang) * rad, cy + math.sin(ang) * rad))
    return pts


def bezier(p0, p1, p2, steps=24):
    pts = []
    for i in range(steps + 1):
        t = i / steps
        a, b, c = (1 - t) ** 2, 2 * (1 - t) * t, t * t
        pts.append((a * p0[0] + b * p1[0] + c * p2[0], a * p0[1] + b * p1[1] + c * p2[1]))
    return pts


# ---------------------------------------------------------------- glyphes (64x64, blancs)
def g_users():
    p1 = union(circle(0.40, 0.33, 0.15), inter(circle(0.40, 0.90, 0.28), rect(0, 0, 1, 0.84)))
    p2 = union(circle(0.69, 0.38, 0.12), inter(circle(0.71, 0.88, 0.23), rect(0, 0, 1, 0.84)))
    gap = union(circle(0.40, 0.33, 0.20), inter(circle(0.40, 0.90, 0.33), rect(0, 0, 1, 0.9)))
    return union(p1, sub(p2, gap))


def g_feed():
    shapes = []
    for y in (0.27, 0.5, 0.73):
        shapes.append(circle(0.21, y, 0.07))
        shapes.append(seg(0.38, y, 0.83, y, 0.11))
    return union(*shapes)


def g_skull():
    head = union(circle(0.5, 0.42, 0.32), rrect(0.31, 0.50, 0.69, 0.86, 0.07))
    eyes = union(circle(0.38, 0.46, 0.09), circle(0.62, 0.46, 0.09))
    nose = poly([(0.5, 0.57), (0.455, 0.66), (0.545, 0.66)])
    teeth = union(seg(0.435, 0.75, 0.435, 0.90, 0.04), seg(0.565, 0.75, 0.565, 0.90, 0.04))
    return sub(head, eyes, nose, teeth)


def g_moon():
    m = sub(circle(0.46, 0.54, 0.33), circle(0.63, 0.40, 0.28))
    return union(m, poly(star_pts(0.75, 0.25, 0.11, 0.04, 4)))


def g_flag():
    pole = seg(0.24, 0.13, 0.24, 0.88, 0.08)
    banner = poly([(0.28, 0.15), (0.84, 0.15), (0.70, 0.36), (0.84, 0.57), (0.28, 0.57)])
    return union(pole, banner)


def g_hammer():
    handle = seg(0.25, 0.81, 0.57, 0.47, 0.10)
    ang = math.atan2(0.47 - 0.81, 0.57 - 0.25)
    perp = ang + math.pi / 2
    cx, cy, L, W = 0.63, 0.41, 0.48, 0.19
    dx, dy = math.cos(perp) * L / 2, math.sin(perp) * L / 2
    ex, ey = math.cos(ang) * W / 2, math.sin(ang) * W / 2
    head = poly([(cx - dx - ex, cy - dy - ey), (cx + dx - ex, cy + dy - ey),
                 (cx + dx + ex, cy + dy + ey), (cx - dx + ex, cy - dy + ey)])
    return union(handle, head)


def g_gear():
    def f(u, v):
        dx, dy = u - 0.5, v - 0.5
        d = math.hypot(dx, dy)
        a = math.atan2(dy, dx)
        tooth = clamp(math.cos(a * 8) * 2.4, -1, 1)
        return 0.13 <= d <= 0.305 + 0.065 * tooth
    return f


def g_search():
    return union(ring(0.43, 0.43, 0.25, 0.09), seg(0.62, 0.62, 0.81, 0.81, 0.12))


def g_close():
    return union(seg(0.28, 0.28, 0.72, 0.72, 0.10), seg(0.72, 0.28, 0.28, 0.72, 0.10))


def g_plus():
    return union(seg(0.5, 0.24, 0.5, 0.76, 0.11), seg(0.24, 0.5, 0.76, 0.5, 0.11))


def g_minus():
    return seg(0.24, 0.5, 0.76, 0.5, 0.11)


def g_check():
    return union(seg(0.23, 0.53, 0.42, 0.72, 0.12), seg(0.42, 0.72, 0.79, 0.31, 0.12))


def g_pin():
    return sub(union(circle(0.5, 0.40, 0.25), poly([(0.29, 0.53), (0.71, 0.53), (0.5, 0.89)])),
               circle(0.5, 0.40, 0.09))


def g_clock():
    return union(ring(0.5, 0.5, 0.35, 0.085), seg(0.5, 0.5, 0.5, 0.29, 0.085), seg(0.5, 0.5, 0.66, 0.59, 0.085))


def g_crown():
    body = poly([(0.15, 0.74), (0.15, 0.33), (0.34, 0.52), (0.5, 0.24), (0.66, 0.52), (0.85, 0.33), (0.85, 0.74)])
    return union(body, rrect(0.15, 0.78, 0.85, 0.86, 0.025),
                 circle(0.15, 0.30, 0.05), circle(0.5, 0.21, 0.05), circle(0.85, 0.30, 0.05))


def g_arrowup():
    return union(seg(0.5, 0.82, 0.5, 0.28, 0.13), seg(0.5, 0.21, 0.26, 0.45, 0.13), seg(0.5, 0.21, 0.74, 0.45, 0.13))


def g_chevdown():
    return union(seg(0.28, 0.39, 0.5, 0.61, 0.11), seg(0.5, 0.61, 0.72, 0.39, 0.11))


def g_chevright():
    return union(seg(0.39, 0.28, 0.61, 0.5, 0.11), seg(0.61, 0.5, 0.39, 0.72, 0.11))


def g_chat():
    return union(rrect(0.14, 0.18, 0.86, 0.66, 0.14), poly([(0.27, 0.60), (0.49, 0.60), (0.25, 0.86)]))


def g_trash():
    body = sub(poly([(0.28, 0.35), (0.72, 0.35), (0.67, 0.87), (0.33, 0.87)]),
               seg(0.43, 0.46, 0.43, 0.77, 0.055), seg(0.57, 0.46, 0.57, 0.77, 0.055))
    return union(seg(0.20, 0.27, 0.80, 0.27, 0.085), rrect(0.39, 0.14, 0.61, 0.27, 0.035), body)


def g_trophy():
    cup = union(inter(circle(0.5, 0.25, 0.29), rect(0, 0.25, 1, 1)), rect(0.21, 0.13, 0.79, 0.25))
    handles = sub(union(ring(0.22, 0.33, 0.12, 0.055), ring(0.78, 0.33, 0.12, 0.055)), rect(0.24, 0, 0.76, 1))
    return union(cup, handles, rect(0.455, 0.52, 0.545, 0.71), rrect(0.29, 0.71, 0.71, 0.82, 0.03))


def g_heart():
    return union(circle(0.35, 0.40, 0.18), circle(0.65, 0.40, 0.18), poly([(0.185, 0.47), (0.815, 0.47), (0.5, 0.86)]))


def g_sword():
    return union(seg(0.34, 0.66, 0.80, 0.20, 0.12), seg(0.21, 0.56, 0.44, 0.79, 0.09),
                 seg(0.31, 0.69, 0.17, 0.83, 0.09), circle(0.14, 0.86, 0.06))


def g_hourglass():
    return union(poly([(0.27, 0.17), (0.73, 0.17), (0.5, 0.5)]), poly([(0.5, 0.5), (0.73, 0.83), (0.27, 0.83)]),
                 rrect(0.20, 0.10, 0.80, 0.19, 0.03), rrect(0.20, 0.81, 0.80, 0.90, 0.03))


def g_star():
    return poly(star_pts(0.5, 0.54, 0.40, 0.17, 5))


def g_bag():
    body = rrect(0.19, 0.36, 0.81, 0.87, 0.14)
    neck = rrect(0.37, 0.18, 0.63, 0.40, 0.05)
    return sub(union(body, neck), seg(0.30, 0.40, 0.70, 0.40, 0.04))


def g_book():
    left = poly([(0.12, 0.22), (0.47, 0.29), (0.47, 0.85), (0.12, 0.78)])
    right = poly([(0.53, 0.29), (0.88, 0.22), (0.88, 0.78), (0.53, 0.85)])
    return union(left, right)


def g_bell():
    dome = union(inter(circle(0.5, 0.43, 0.26), rect(0, 0, 1, 0.43)),
                 poly([(0.24, 0.43), (0.76, 0.43), (0.81, 0.70), (0.19, 0.70)]))
    return union(dome, rrect(0.13, 0.68, 0.87, 0.77, 0.04), circle(0.5, 0.84, 0.075), circle(0.5, 0.16, 0.055))


def g_sliders():
    return union(seg(0.17, 0.29, 0.83, 0.29, 0.065), circle(0.36, 0.29, 0.10),
                 seg(0.17, 0.50, 0.83, 0.50, 0.065), circle(0.65, 0.50, 0.10),
                 seg(0.17, 0.71, 0.83, 0.71, 0.065), circle(0.44, 0.71, 0.10))


def g_grip():
    return union(seg(0.88, 0.40, 0.40, 0.88, 0.07), seg(0.88, 0.60, 0.60, 0.88, 0.07), seg(0.88, 0.80, 0.80, 0.88, 0.07))


def g_link():
    return union(seg(0.30, 0.70, 0.70, 0.30, 0.10),
                 sub(ring(0.30, 0.70, 0.17, 0.08), rect(0.40, 0.40, 1, 0.60)),
                 sub(ring(0.70, 0.30, 0.17, 0.08), rect(0, 0.40, 0.60, 0.60)))


def g_flame():
    left = bezier((0.29, 0.62), (0.26, 0.34), (0.55, 0.10))
    right = bezier((0.55, 0.10), (0.78, 0.38), (0.71, 0.62))
    return union(poly(left + right), circle(0.5, 0.64, 0.215))


def g_dot():
    return circle(0.5, 0.5, 0.5)


GLYPHS = {
    "users": g_users, "feed": g_feed, "skull": g_skull, "moon": g_moon, "flag": g_flag,
    "hammer": g_hammer, "gear": g_gear, "search": g_search, "close": g_close, "plus": g_plus,
    "minus": g_minus, "check": g_check, "pin": g_pin, "clock": g_clock, "crown": g_crown,
    "arrowup": g_arrowup, "chevdown": g_chevdown, "chevright": g_chevright, "chat": g_chat,
    "trash": g_trash, "trophy": g_trophy, "heart": g_heart, "sword": g_sword,
    "hourglass": g_hourglass, "star": g_star, "bag": g_bag, "book": g_book, "bell": g_bell,
    "sliders": g_sliders, "grip": g_grip, "link": g_link, "flame": g_flame, "dot": g_dot,
}


# ---------------------------------------------------------------- textures de base
def make_corner():
    # quart de cercle (coin haut-gauche), rayon = taille de la texture
    write_tga("corner", 32, 32, white(coverage(32, 32, circle(1.0, 1.0, 1.0))))


def make_circle():
    write_tga("circle", 64, 64, white(coverage(64, 64, circle(0.5, 0.5, 0.5))))


def make_ring():
    write_tga("ring", 64, 64, white(coverage(64, 64, ring(0.5, 0.5, 0.5, 0.075))))


def make_roundsq():
    write_tga("roundsq", 64, 64, white(coverage(64, 64, rrect(0, 0, 1, 1, 0.22))))


def make_shadow():
    # ombre portée douce, découpée en 9 par le code (bords de 24 px sur 64)
    w = h = 64
    lo, hi = 24.0, 40.0
    px = []
    for y in range(h):
        for x in range(w):
            cx, cy = x + 0.5, y + 0.5
            dx = max(lo - cx, 0, cx - hi)
            dy = max(lo - cy, 0, cy - hi)
            d = math.hypot(dx, dy) / 24.0
            a = (1 - clamp(d)) ** 2.2
            px.append((0, 0, 0, int(round(a * 255))))
    write_tga("shadow", w, h, px)


def make_gradients():
    w, h = 128, 8
    write_tga("grad-h", w, h, [(255, 255, 255, int(round(255 * (1 - (x + 0.5) / w)))) for y in range(h) for x in range(w)])
    w, h = 8, 128
    write_tga("grad-v", w, h, [(255, 255, 255, int(round(255 * (1 - (y + 0.5) / h)))) for y in range(h) for x in range(w)])


def make_shine():
    w, h = 64, 64
    px = []
    for y in range(h):
        for x in range(w):
            d = (x + 0.5 - 32) / 11.0
            a = math.exp(-d * d) * 0.85
            px.append((255, 255, 255, int(round(a * 255))))
    write_tga("shine", w, h, px)


def make_noise_free_glow():
    # halo radial doux (toasts spéciaux, survols)
    w = h = 128
    px = []
    for y in range(h):
        for x in range(w):
            d = math.hypot((x + 0.5) / w - 0.5, (y + 0.5) / h - 0.5) / 0.5
            a = (1 - clamp(d)) ** 2
            px.append((255, 255, 255, int(round(a * 255))))
    write_tga("glow", w, h, px)


# ---------------------------------------------------------------- logo (feu de camp)
def lerp(a, b, t):
    return a + (b - a) * t


def mix(c1, c2, t):
    return tuple(lerp(c1[i], c2[i], t) for i in range(3))


def make_logo():
    S = 128
    log_shape = union(seg(0.20, 0.86, 0.80, 0.72, 0.115), seg(0.20, 0.72, 0.80, 0.86, 0.115))
    log_end = union(circle(0.20, 0.86, 0.045), circle(0.80, 0.72, 0.045), circle(0.20, 0.72, 0.045), circle(0.80, 0.86, 0.045))

    outer_l = bezier((0.27, 0.66), (0.22, 0.36), (0.53, 0.06))
    outer_r = bezier((0.53, 0.06), (0.80, 0.36), (0.73, 0.66))
    outer = union(poly(outer_l + outer_r), circle(0.5, 0.66, 0.235))
    tongue = poly(bezier((0.24, 0.62), (0.16, 0.42), (0.30, 0.28)) + bezier((0.30, 0.28), (0.30, 0.46), (0.40, 0.60)))
    outer = union(outer, tongue)

    inner_l = bezier((0.37, 0.72), (0.35, 0.50), (0.52, 0.34))
    inner_r = bezier((0.52, 0.34), (0.67, 0.52), (0.63, 0.72))
    inner = union(poly(inner_l + inner_r), circle(0.5, 0.71, 0.13))

    cov_log = coverage(S, S, log_shape)
    cov_end = coverage(S, S, log_end)
    cov_out = coverage(S, S, outer)
    cov_in = coverage(S, S, inner)

    px = []
    for i in range(S * S):
        y = (i // S + 0.5) / S
        # couleurs
        log_c = (0.42, 0.25, 0.13)
        end_c = (0.78, 0.55, 0.32)
        t = clamp((y - 0.06) / 0.66)
        out_c = mix((1.00, 0.74, 0.25), (0.98, 0.33, 0.12), t)
        in_c = mix((1.00, 0.96, 0.72), (1.00, 0.80, 0.32), clamp((y - 0.34) / 0.45))
        # composition « over »
        r = g = b = 0.0
        a = 0.0
        for cov, col in ((cov_log[i], log_c), (cov_end[i], end_c), (cov_out[i], out_c), (cov_in[i], in_c)):
            if cov <= 0:
                continue
            na = cov + a * (1 - cov)
            r = (col[0] * cov + r * a * (1 - cov)) / na
            g = (col[1] * cov + g * a * (1 - cov)) / na
            b = (col[2] * cov + b * a * (1 - cov)) / na
            a = na
        px.append((int(round(r * 255)), int(round(g * 255)), int(round(b * 255)), int(round(a * 255))))
    write_tga("logo", S, S, px)


def main():
    make_corner()
    make_circle()
    make_ring()
    make_roundsq()
    make_shadow()
    make_gradients()
    make_shine()
    make_noise_free_glow()
    make_logo()
    for name, fn in GLYPHS.items():
        write_tga(os.path.join("Icons", name), 64, 64, white(coverage(64, 64, fn())))
    print("Textures générées dans", OUT)


if __name__ == "__main__":
    main()
