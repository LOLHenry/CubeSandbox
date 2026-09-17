#!/usr/bin/env python3
"""Leadership slide: map RenderThread / SurfaceFlinger / SwiftShader onto AOSP pipeline."""

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
BQ = (47, 150, 176)
BQ_BG = (232, 247, 250)


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


def arrow(draw, x0, y, x1, fill):
    draw.line((x0, y, x1 - 10, y), fill=fill, width=4)
    draw.polygon([(x1, y), (x1 - 14, y - 8), (x1 - 14, y + 8)], fill=fill)


def chip(draw, x, y, w, h, text, f):
    round_rect(draw, (x, y, x + w, y + h), 8, ORANGE_BG, ORANGE, 2)
    center_text(draw, (x, y, x + w, y + h), text, f, ORANGE)


def main():
    img = Image.new("RGB", (W, H), WHITE)
    d = ImageDraw.Draw(img)

    title = "官方管线怎么落这三块：RenderThread / SurfaceFlinger / SwiftShader"
    bbox = d.textbbox((0, 0), title, font=font(36))
    d.text(((W - (bbox[2] - bbox[0])) / 2, 24), title, font=font(36), fill=NAVY)

    sub = "对齐 AOSP Graphics Figure 2。三者不是三层上下叠：前两个是进程里的模块，SwiftShader 是它们共同调用的 GLES。"
    bbox = d.textbbox((0, 0), sub, font=font(20))
    d.text(((W - (bbox[2] - bbox[0])) / 2, 78), sub, font=font(20), fill=GRAY)

    # --- producers ---
    px0, px1 = 56, 500
    round_rect(d, (px0, 130, px1, 620), 18, BLUE_BG, BLUE, 3)
    d.text((px0 + 24, 146), "生产者（官方图左侧）", font=font(24), fill=BLUE)

    round_rect(d, (px0 + 20, 190, px1 - 20, 390), 14, WHITE, BLUE_BD, 2)
    d.text((px0 + 40, 206), "App 进程 · View 主路径", font=font(22), fill=NAVY)
    d.text((px0 + 40, 244), "UI thread：记下怎么画", font=font(20), fill=TEXT)
    d.text((px0 + 40, 278), "RenderThread：HWUI 发 GLES", font=font(22), fill=BLUE)
    chip(d, px0 + 40, 324, 380, 46, "调 SwiftShader 填像素", font(20))

    round_rect(d, (px0 + 20, 414, px1 - 20, 590), 14, WHITE, BLUE_BD, 2)
    d.text((px0 + 40, 430), "自行送帧（不经 Choreographer）", font=font(22), fill=NAVY)
    d.text((px0 + 40, 470), "游戏 / 视频 / WebView 自己 swap", font=font(20), fill=TEXT)
    chip(d, px0 + 40, 518, 380, 46, "同样调 SwiftShader 填像素", font(20))

    # --- bufferqueue ---
    bx0, bx1 = 540, 760
    round_rect(d, (bx0, 250, bx1, 500), 16, BQ_BG, BQ, 3)
    center_text(d, (bx0, 270, bx1, 360), "BufferQueue", font(26), BQ)
    center_text(d, (bx0, 360, bx1, 470), "交缓冲\n官方 Figure 3", font(20), MUTED)
    arrow(d, px1 + 6, 290, bx0 - 4, BLUE)
    arrow(d, px1 + 6, 500, bx0 - 4, BLUE)

    # --- surfaceflinger ---
    sx0, sx1 = 800, 1220
    round_rect(d, (sx0, 160, sx1, 590), 18, BLUE_BG, BLUE, 3)
    d.text((sx0 + 24, 176), "SurfaceFlinger", font=font(28), fill=BLUE)
    d.text((sx0 + 24, 220), "独立进程 · 官方图中间", font=font(20), fill=MUTED)
    d.text((sx0 + 24, 268), "收各路缓冲，叠成一整屏", font=font(22), fill=TEXT)
    d.text((sx0 + 24, 308), "真机优先交给 HWC；搞不定", font=font(20), fill=TEXT)
    d.text((sx0 + 24, 344), "就自己发 GLES 做合成。", font=font(20), fill=TEXT)
    chip(d, sx0 + 24, 400, 372, 52, "GLES 合成也走 SwiftShader", font(20))
    d.text((sx0 + 24, 470), "本沙箱 HWC 弱，合成常打满 CPU", font=font(20), fill=ORANGE)
    arrow(d, bx1 + 6, 375, sx0 - 4, BQ)

    # --- display ---
    dx0, dx1 = 1260, 1488
    round_rect(d, (dx0, 280, dx1, 470), 16, (246, 248, 252), LINE, 2)
    center_text(d, (dx0, 280, dx1, 470), "显示 /\n截图给 Agent", font(24), NAVY)
    arrow(d, sx1 + 6, 375, dx0 - 4, BLUE)

    # --- swiftshader bar ---
    round_rect(d, (56, 648, 1488, 760), 16, ORANGE_BG, ORANGE, 3)
    d.text((80, 666), "SwiftShader（本沙箱的 GLES 实现）", font=font(28), fill=ORANGE)
    d.text((80, 710), "官方 Figure 2 里每条 producer 旁边的 GPU，以及 SurfaceFlinger 里的 GPU。真机是 GPU 驱动；这里用 CPU 冒充。", font=font(20), fill=TEXT)

    # --- two tracks ---
    round_rect(d, (1520, 130, 1744, 430), 16, BLUE_BG, BLUE, 3)
    d.text((1540, 148), "按需", font=font(28), fill=BLUE)
    d.text((1540, 196), "少让 RenderThread", font=font(20), fill=TEXT)
    d.text((1540, 228), "和自行送帧下单", font=font(20), fill=TEXT)
    d.text((1540, 268), "少让 SF 叠", font=font(20), fill=TEXT)
    d.text((1540, 316), "切生产者 + 合成", font=font(20), fill=BLUE)

    round_rect(d, (1520, 454, 1744, 760), 16, ORANGE_BG, ORANGE, 3)
    d.text((1540, 472), "快速", font=font(28), fill=ORANGE)
    d.text((1540, 520), "不改 RenderThread", font=font(20), fill=TEXT)
    d.text((1540, 552), "不改 SurfaceFlinger", font=font(20), fill=TEXT)
    d.text((1540, 600), "把 SwiftShader", font=font(20), fill=TEXT)
    d.text((1540, 632), "填像素加快", font=font(20), fill=TEXT)
    d.text((1540, 680), "切 GLES 实现", font=font(20), fill=ORANGE)

    foot = "官方图：source.android.com/docs/core/graphics  Figure 1 / 2 / 3。没有 RenderThread、也没有 SwiftShader 这两个名字。"
    bbox = d.textbbox((0, 0), foot, font=font(18))
    d.text(((W - (bbox[2] - bbox[0])) / 2, 800), foot, font=font(18), fill=GRAY)

    note1 = "RenderThread = App 里 HWUI 的线程，不是系统服务。SurfaceFlinger = 合成进程。SwiftShader = 库，谁发 GLES 谁调它。"
    bbox = d.textbbox((0, 0), note1, font=font(18))
    d.text(((W - (bbox[2] - bbox[0])) / 2, 840), note1, font=font(18), fill=MUTED)

    note2 = "systrace 文档只把 RenderThread 画成时间轴上的一段（UI thread → RenderThread → queueBuffer → SurfaceFlinger），不是软件分层图。"
    bbox = d.textbbox((0, 0), note2, font=font(18))
    d.text(((W - (bbox[2] - bbox[0])) / 2, 876), note2, font=font(18), fill=MUTED)

    out = "/workspace/docs/assets/android-cpu-render-stack.png"
    img.save(out, "PNG", optimize=True)
    print("wrote", out, img.size)


if __name__ == "__main__":
    main()
