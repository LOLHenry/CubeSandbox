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
MUTED = (72, 82, 98)


def font(size):
    return ImageFont.truetype(FONT, size)


def round_rect(draw, xy, r, fill, outline=None, width=2):
    draw.rounded_rectangle(xy, radius=r, fill=fill, outline=outline, width=width)


def center_text(draw, xy, text, f, fill):
    x0, y0, x1, y1 = xy
    lines = text.split("\n")
    sizes = []
    for line in lines:
        bbox = draw.textbbox((0, 0), line, font=f)
        sizes.append((bbox[2] - bbox[0], bbox[3] - bbox[1], bbox[1]))
    gap = 2
    total_h = sum(h for _, h, _ in sizes) + gap * (len(lines) - 1)
    y = y0 + (y1 - y0 - total_h) / 2
    for i, line in enumerate(lines):
        tw, th, b1 = sizes[i]
        draw.text(((x0 + x1 - tw) / 2, y - b1), line, font=f, fill=fill)
        y += th + gap


def draw_lines(draw, x, y, lines, f, fill, gap=10):
    for line in lines:
        if line == "":
            y += gap
            continue
        draw.text((x, y), line, font=f, fill=fill)
        bbox = draw.textbbox((0, 0), line if line else " ", font=f)
        y += (bbox[3] - bbox[1]) + gap
    return y


def draw_h_flow(draw, x0, y0, x1, steps, pill_h, f, fill, bd, accent):
    n = len(steps)
    gap_arrow = 28
    inner = x1 - x0
    pill_w = (inner - gap_arrow * (n - 1)) / n
    y1 = y0 + pill_h
    for i, label in enumerate(steps):
        px0 = x0 + i * (pill_w + gap_arrow)
        px1 = px0 + pill_w
        round_rect(draw, (px0, y0, px1, y1), 10, WHITE, bd, 2)
        center_text(draw, (px0, y0, px1, y1), label, f, accent)
        if i < n - 1:
            ax0 = px1 + 5
            ax1 = px0 + pill_w + gap_arrow - 5
            midy = (y0 + y1) / 2
            draw.line((ax0, midy, ax1 - 8, midy), fill=accent, width=3)
            draw.polygon(
                [(ax1, midy), (ax1 - 10, midy - 6), (ax1 - 10, midy + 6)],
                fill=accent,
            )


def main():
    img = Image.new("RGB", (W, H), WHITE)
    d = ImageDraw.Draw(img)

    title_f = font(42)
    sub_f = font(22)
    layer_title_f = font(28)
    layer_body_f = font(22)
    call_title_f = font(30)
    call_sub_f = font(22)
    call_body_f = font(22)

    title = "Android 图形栈：两条手段切在不同层"
    bbox = d.textbbox((0, 0), title, font=title_f)
    d.text(((W - (bbox[2] - bbox[0])) / 2, 28), title, font=title_f, fill=NAVY)

    sub = "上到下是系统分层。蓝 = 按需（少画），橙 = 快速（画快）。分团队，各切各的层。"
    bbox = d.textbbox((0, 0), sub, font=sub_f)
    d.text(((W - (bbox[2] - bbox[0])) / 2, 86), sub, font=sub_f, fill=GRAY)

    sx0, sx1 = 72, 980
    layers = [
        {
            "title": "1  应用层",
            "body": "View 走下面排帧；游戏 / 视频 / WebView 可自己送帧",
            "note": "只停 Choreographer，停不掉自行送帧",
            "fill": BLUE_BG,
            "bd": BLUE_BD,
            "accent": BLUE,
            "note_fill": BLUE,
            "h": 148,
        },
        {
            "title": "2  框架层",
            "body": "",
            "note": "View 主路径，不截图时仍在转",
            "flow": [
                "Choreographer\n排帧",
                "ViewRootImpl\n重绘",
                "HWUI\n发画令",
                "SurfaceFlinger\n合成",
            ],
            "fill": BLUE_BG,
            "bd": BLUE_BD,
            "accent": BLUE,
            "note_fill": BLUE,
            "h": 226,
        },
        {
            "title": "3  图形驱动层",
            "body": "接 GLES：HWUI 或应用自己发。真机 GPU，本沙箱 SwiftShader",
            "note": "SwiftShader 用 CPU 冒充 GPU，像素在这里填",
            "fill": ORANGE_BG,
            "bd": ORANGE_BD,
            "accent": ORANGE,
            "note_fill": ORANGE,
            "h": 200,
        },
    ]

    y = 160
    gap = 16
    boxes = []
    for layer in layers:
        h = layer["h"]
        box = (sx0, y, sx1, y + h)
        boxes.append(box)
        round_rect(d, box, 16, layer["fill"], layer["bd"], 3)
        d.rounded_rectangle((sx0, y, sx0 + 12, y + h), radius=6, fill=layer["accent"])
        d.text((sx0 + 36, y + 16), layer["title"], font=layer_title_f, fill=NAVY)
        if layer.get("flow"):
            d.text((sx0 + 220, y + 20), layer["note"], font=layer_body_f, fill=layer["note_fill"])
            draw_h_flow(
                d,
                sx0 + 36,
                y + 64,
                sx1 - 24,
                layer["flow"],
                72,
                font(18),
                WHITE,
                layer["bd"],
                layer["accent"],
            )
            d.text(
                (sx0 + 36, y + 152),
                "这是 View 主路径，不是全部渲染。HWUI 只发画令，不填像素。",
                font=font(20),
                fill=MUTED,
            )
            d.text(
                (sx0 + 36, y + 184),
                "像素：真机 GPU；本沙箱 SwiftShader 用 CPU 画。",
                font=font(20),
                fill=MUTED,
            )
        else:
            d.text((sx0 + 36, y + 64), layer["body"], font=layer_body_f, fill=TEXT)
            d.text((sx0 + 36, y + 100), layer["note"], font=layer_body_f, fill=layer["note_fill"])
        y = y + h + gap

    xmid = (sx0 + sx1) / 2
    for i in range(len(boxes) - 1):
        d.line((xmid, boxes[i][3] + 2, xmid, boxes[i + 1][1] - 2), fill=LINE, width=3)

    fy0 = boxes[-1][3] + 22
    round_rect(d, (sx0 + 160, fy0, sx1 - 160, fy0 + 52), 12, (246, 248, 252), LINE, 2)
    center_text(
        d,
        (sx0 + 160, fy0, sx1 - 160, fy0 + 52),
        "截图  →  交给 Agent 决策",
        font(24),
        NAVY,
    )

    cx0, cx1 = 1048, 1728
    y_on0 = boxes[0][1]
    y_on1 = boxes[1][3]
    round_rect(d, (cx0, y_on0, cx1, y_on1), 18, BLUE_BG, BLUE, 3)
    d.text((cx0 + 32, y_on0 + 22), "按需渲染", font=call_title_f, fill=BLUE)
    d.text((cx0 + 32, y_on0 + 64), "切上面两层：应用 / 框架", font=call_sub_f, fill=BLUE)
    draw_lines(
        d,
        cx0 + 32,
        y_on0 + 110,
        [
            "问题：不该画的时候还在画。",
            "",
            "View 在排帧；游戏 / 视频 / WebView",
            "还可自己往 Surface 送帧。",
            "",
            "手段：应用少送帧，框架少排、少合成。",
            "目的：抠掉决策期无效占用。",
        ],
        call_body_f,
        TEXT,
        gap=8,
    )

    y_f0 = boxes[2][1]
    y_f1 = boxes[2][3]
    round_rect(d, (cx0, y_f0, cx1, y_f1), 18, ORANGE_BG, ORANGE, 3)
    d.text((cx0 + 32, y_f0 + 18), "快速渲染", font=call_title_f, fill=ORANGE)
    d.text((cx0 + 32, y_f0 + 58), "切最底层：图形驱动", font=call_sub_f, fill=ORANGE)
    draw_lines(
        d,
        cx0 + 32,
        y_f0 + 98,
        [
            "问题：画一帧太贵。",
            "手机上这一层是 GPU；沙箱换成 CPU 软渲染。",
            "",
            "手段：把这一层的 CPU 画图加快。",
            "目的：缩短等稳定截图的时间。",
        ],
        call_body_f,
        TEXT,
        gap=8,
    )

    d.line((sx1, (boxes[0][1] + boxes[1][3]) / 2, cx0, (y_on0 + y_on1) / 2), fill=BLUE_BD, width=3)
    d.line((sx1, (boxes[2][1] + boxes[2][3]) / 2, cx0, (y_f0 + y_f1) / 2), fill=ORANGE_BD, width=3)

    out = "/workspace/docs/assets/android-cpu-render-stack.png"
    img.save(out, "PNG", optimize=True)
    print("wrote", out, img.size)


if __name__ == "__main__":
    main()
