#!/usr/bin/env python3
"""Leadership slide: Android graphics stack, two workstreams by layer."""

from PIL import Image, ImageDraw, ImageFont

W, H = 1800, 1080
FONT = "/usr/share/fonts/truetype/wqy/wqy-microhei.ttc"

NAVY = (22, 42, 90)
BLUE = (47, 111, 212)
BLUE_BG = (232, 242, 255)
BLUE_BD = (160, 196, 245)
ORANGE = (201, 108, 22)
ORANGE_BG = (255, 243, 224)
ORANGE_BD = (245, 196, 130)
GRAY = (90, 98, 114)
WHITE = (255, 255, 255)
LINE = (210, 216, 228)
TEXT = (28, 34, 48)


def font(size):
    return ImageFont.truetype(FONT, size)


def round_rect(draw, xy, r, fill, outline=None, width=2):
    draw.rounded_rectangle(xy, radius=r, fill=fill, outline=outline, width=width)


def center_text(draw, xy, text, f, fill):
    x0, y0, x1, y1 = xy
    bbox = draw.textbbox((0, 0), text, font=f)
    tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
    draw.text(((x0 + x1 - tw) / 2, (y0 + y1 - th) / 2 - bbox[1]), text, font=f, fill=fill)


def wrap_center(draw, cx, y, text, f, fill, max_w):
    """Draw wrapped centered text starting at y; return bottom y."""
    words = text
    # Chinese: wrap by width
    lines, cur = [], ""
    for ch in words:
        trial = cur + ch
        if draw.textbbox((0, 0), trial, font=f)[2] <= max_w:
            cur = trial
        else:
            lines.append(cur)
            cur = ch
    if cur:
        lines.append(cur)
    for line in lines:
        bbox = draw.textbbox((0, 0), line, font=f)
        tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
        draw.text((cx - tw / 2, y), line, font=f, fill=fill)
        y += th + 8
    return y


def main():
    img = Image.new("RGB", (W, H), WHITE)
    d = ImageDraw.Draw(img)

    title_f = font(44)
    sub_f = font(22)
    layer_title_f = font(30)
    layer_body_f = font(22)
    badge_f = font(22)
    call_title_f = font(28)
    call_body_f = font(22)
    foot_f = font(20)

    title = "Android 图形栈：两条手段切在不同层"
    bbox = d.textbbox((0, 0), title, font=title_f)
    d.text(((W - (bbox[2] - bbox[0])) / 2, 36), title, font=title_f, fill=NAVY)

    sub = "上到下是系统分层。按需改上面三层（少画）；快速改最底层（画快）。"
    bbox = d.textbbox((0, 0), sub, font=sub_f)
    d.text(((W - (bbox[2] - bbox[0])) / 2, 96), sub, font=sub_f, fill=GRAY)

    # Left stack
    sx0, sx1 = 80, 980
    layers = [
        {
            "title": "应用层",
            "body": "各 App 的界面、动画、WebView",
            "note": "给人看的画面从这里开始",
            "fill": BLUE_BG,
            "bd": BLUE_BD,
            "accent": BLUE,
        },
        {
            "title": "框架层",
            "body": "系统刷新心跳（vsync），决定何时再画一帧",
            "note": "决策期没人看屏，心跳仍在叫刷新",
            "fill": BLUE_BG,
            "bd": BLUE_BD,
            "accent": BLUE,
        },
        {
            "title": "合成层",
            "body": "SurfaceFlinger：把多个窗口叠成一整屏",
            "note": "不截图时仍在合成",
            "fill": BLUE_BG,
            "bd": BLUE_BD,
            "accent": BLUE,
        },
        {
            "title": "图形驱动层",
            "body": "真机：GPU 画图　　本沙箱：CPU 软渲染（SwiftShader）",
            "note": "本该 GPU 干的活，现在全压在 CPU 上",
            "fill": ORANGE_BG,
            "bd": ORANGE_BD,
            "accent": ORANGE,
        },
    ]

    y = 160
    gap = 18
    h_top = 118
    h_bot = 150
    boxes = []
    for i, layer in enumerate(layers):
        h = h_bot if i == 3 else h_top
        box = (sx0, y, sx1, y + h)
        boxes.append(box)
        round_rect(d, box, 16, layer["fill"], layer["bd"], 3)
        # left accent bar
        d.rounded_rectangle((sx0, y, sx0 + 12, y + h), radius=6, fill=layer["accent"])
        d.text((sx0 + 36, y + 16), f"{i + 1}  {layer['title']}", font=layer_title_f, fill=NAVY)
        d.text((sx0 + 36, y + 58), layer["body"], font=layer_body_f, fill=TEXT)
        if i == 3:
            d.text((sx0 + 36, y + 96), layer["note"], font=layer_body_f, fill=ORANGE)
        y = y + h + gap

    # arrows between layers
    for i in range(3):
        x = (sx0 + sx1) / 2
        y1 = boxes[i][3]
        y2 = boxes[i + 1][1]
        mid = (y1 + y2) / 2
        d.line((x, y1 + 2, x, y2 - 2), fill=LINE, width=3)

    # screenshot footer
    fy0 = boxes[-1][3] + 28
    round_rect(d, (sx0 + 180, fy0, sx1 - 180, fy0 + 56), 12, (246, 248, 252), LINE, 2)
    center_text(d, (sx0 + 180, fy0, sx1 - 180, fy0 + 56), "截图  →  交给 Agent 决策", font(24), NAVY)

    # Right callouts
    cx0, cx1 = 1040, 1720

    # brace-like callout 1 covering first 3 layers
    y_on0 = boxes[0][1]
    y_on1 = boxes[2][3]
    round_rect(d, (cx0, y_on0, cx1, y_on1), 18, BLUE_BG, BLUE, 3)
    d.text((cx0 + 36, y_on0 + 28), "按需渲染", font=call_title_f, fill=BLUE)
    d.text((cx0 + 36, y_on0 + 72), "切上面三层", font=badge_f, fill=BLUE)

    lines = [
        "业务逻辑问题：不该画的时候还在画。",
        "",
        "Agent 在推理时不看屏幕，",
        "应用动画、系统心跳、窗口合成",
        "仍按「给人看」的方式空转。",
        "",
        "手段：非截图阶段少刷、少合成。",
        "目的：把每台从 4 核压回接近 2 核。",
    ]
    ty = y_on0 + 118
    for line in lines:
        d.text((cx0 + 36, ty), line, font=call_body_f, fill=TEXT)
        ty += 34

    # callout 2 for driver layer — tall enough to hold all copy
    y_f0 = boxes[3][1]
    y_f1 = fy0 + 56
    lines2 = [
        "基础库问题：画一帧太贵。",
        "",
        "手机上这一层是 GPU；",
        "沙箱里换成了 CPU 软渲染。",
        "",
        "手段：把这一层的 CPU 画图加快。",
        "不改 App，改最底层的软渲染库。",
    ]
    need = 110 + 32 * len(lines2) + 24
    if y_f0 + need > y_f1:
        y_f1 = y_f0 + need
    round_rect(d, (cx0, y_f0, cx1, y_f1), 18, ORANGE_BG, ORANGE, 3)
    d.text((cx0 + 36, y_f0 + 24), "快速渲染", font=call_title_f, fill=ORANGE)
    d.text((cx0 + 36, y_f0 + 68), "切最底层（图形驱动）", font=badge_f, fill=ORANGE)
    ty = y_f0 + 110
    for line in lines2:
        d.text((cx0 + 36, ty), line, font=call_body_f, fill=TEXT)
        ty += 32

    # connectors from stack to callouts
    d.line((sx1, (boxes[0][1] + boxes[2][3]) / 2, cx0, (y_on0 + y_on1) / 2), fill=BLUE_BD, width=3)
    d.line((sx1, (boxes[3][1] + boxes[3][3]) / 2, cx0, y_f0 + 80), fill=ORANGE_BD, width=3)

    out = "/workspace/docs/assets/android-cpu-render-stack.png"
    img.save(out, "PNG", optimize=True)
    print("wrote", out, img.size)


if __name__ == "__main__":
    main()
