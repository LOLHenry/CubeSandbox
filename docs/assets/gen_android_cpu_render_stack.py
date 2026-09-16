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
    bbox = draw.textbbox((0, 0), text, font=f)
    tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
    draw.text(((x0 + x1 - tw) / 2, (y0 + y1 - th) / 2 - bbox[1]), text, font=f, fill=fill)


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
    gap_arrow = 36
    inner = x1 - x0
    pill_w = (inner - gap_arrow * (n - 1)) / n
    y1 = y0 + pill_h
    for i, label in enumerate(steps):
        px0 = x0 + i * (pill_w + gap_arrow)
        px1 = px0 + pill_w
        round_rect(draw, (px0, y0, px1, y1), 10, WHITE, bd, 2)
        center_text(draw, (px0, y0, px1, y1), label, f, accent)
        if i < n - 1:
            ax0 = px1 + 6
            ax1 = px0 + pill_w + gap_arrow - 6
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
            "body": "各 App 的界面、动画、WebView",
            "note": "决策期没人看，动画还在动",
            "fill": BLUE_BG,
            "bd": BLUE_BD,
            "accent": BLUE,
            "note_fill": BLUE,
        },
        {
            "title": "2  框架层",
            "body": "",
            "note": "不截图时这条链路仍在转",
            "flow": ["vsync 心跳", "调度下一帧", "窗口重绘", "送去合成"],
            "fill": BLUE_BG,
            "bd": BLUE_BD,
            "accent": BLUE,
            "note_fill": BLUE,
        },
        {
            "title": "3  合成层",
            "body": "SurfaceFlinger：把多个窗口叠成一整屏",
            "note": "决策期无截图也在叠",
            "fill": BLUE_BG,
            "bd": BLUE_BD,
            "accent": BLUE,
            "note_fill": BLUE,
        },
        {
            "title": "4  图形驱动层",
            "body": "真机是 GPU；本沙箱是 CPU 软渲染（SwiftShader）",
            "note": "本该 GPU 干的活，现在全压在 CPU 上",
            "fill": ORANGE_BG,
            "bd": ORANGE_BD,
            "accent": ORANGE,
            "note_fill": ORANGE,
        },
    ]

    y = 140
    gap = 14
    boxes = []
    for layer in layers:
        h = 176 if layer.get("flow") else 118
        box = (sx0, y, sx1, y + h)
        boxes.append(box)
        round_rect(d, box, 16, layer["fill"], layer["bd"], 3)
        d.rounded_rectangle((sx0, y, sx0 + 12, y + h), radius=6, fill=layer["accent"])
        d.text((sx0 + 36, y + 12), layer["title"], font=layer_title_f, fill=NAVY)
        if layer.get("flow"):
            d.text((sx0 + 220, y + 16), layer["note"], font=layer_body_f, fill=layer["note_fill"])
            draw_h_flow(
                d,
                sx0 + 36,
                y + 58,
                sx1 - 24,
                layer["flow"],
                48,
                font(20),
                WHITE,
                layer["bd"],
                layer["accent"],
            )
            d.text((sx0 + 36, y + 122), "决定何时再画一帧（Choreographer / vsync）", font=font(20), fill=MUTED)
        else:
            d.text((sx0 + 36, y + 50), layer["body"], font=layer_body_f, fill=TEXT)
            d.text((sx0 + 36, y + 82), layer["note"], font=layer_body_f, fill=layer["note_fill"])
        y = y + h + gap

    xmid = (sx0 + sx1) / 2
    for i in range(3):
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
    y_on1 = boxes[2][3]
    round_rect(d, (cx0, y_on0, cx1, y_on1), 18, BLUE_BG, BLUE, 3)
    d.text((cx0 + 32, y_on0 + 22), "按需渲染", font=call_title_f, fill=BLUE)
    d.text((cx0 + 32, y_on0 + 64), "切上面三层：应用 / 框架 / 合成", font=call_sub_f, fill=BLUE)
    draw_lines(
        d,
        cx0 + 32,
        y_on0 + 110,
        [
            "问题：不该画的时候还在画。",
            "",
            "Agent 在推理，屏幕无人看，",
            "动画、心跳、合成仍按给人看的方式刷。",
            "",
            "手段：非截图阶段少刷、少合成。",
            "目的：抠掉决策期无效占用。",
        ],
        call_body_f,
        TEXT,
        gap=8,
    )

    y_f0 = boxes[3][1]
    y_f1 = y_f0 + 236
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

    d.line((sx1, (boxes[0][1] + boxes[2][3]) / 2, cx0, (y_on0 + y_on1) / 2), fill=BLUE_BD, width=3)
    d.line((sx1, (boxes[3][1] + boxes[3][3]) / 2, cx0, (y_f0 + y_f1) / 2), fill=ORANGE_BD, width=3)

    out = "/workspace/docs/assets/android-cpu-render-stack.png"
    img.save(out, "PNG", optimize=True)
    print("wrote", out, img.size)


if __name__ == "__main__":
    main()
