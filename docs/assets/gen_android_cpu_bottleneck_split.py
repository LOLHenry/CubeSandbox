#!/usr/bin/env python3
"""Leadership slide: split CPU soft-render bottleneck into business vs libraries."""

from PIL import Image, ImageDraw, ImageFont

W, H = 1800, 1080
FONT = "/usr/share/fonts/truetype/wqy/wqy-microhei.ttc"

NAVY = (22, 42, 90)
BLUE = (47, 111, 212)
BLUE_BG = (232, 242, 255)
ORANGE = (201, 108, 22)
ORANGE_BG = (255, 243, 224)
GRAY = (90, 98, 114)
WHITE = (255, 255, 255)
TEXT = (28, 34, 48)
MUTED = (72, 82, 98)


def font(size):
    return ImageFont.truetype(FONT, size)


def round_rect(draw, xy, r, fill, outline, width=3):
    draw.rounded_rectangle(xy, radius=r, fill=fill, outline=outline, width=width)


def main():
    img = Image.new("RGB", (W, H), WHITE)
    d = ImageDraw.Draw(img)

    title = "CPU 软渲染：瓶颈要拆开，不能只写 SwiftShader 慢"
    bbox = d.textbbox((0, 0), title, font=font(38))
    d.text(((W - (bbox[2] - bbox[0])) / 2, 28), title, font=font(38), fill=NAVY)
    sub = "画像：软渲染热点 >50%，复杂界面 <10fps。先分清是不该送工，还是送进去一次太贵。"
    bbox = d.textbbox((0, 0), sub, font=font(22))
    d.text(((W - (bbox[2] - bbox[0])) / 2, 86), sub, font=font(22), fill=GRAY)

    # left business
    round_rect(d, (56, 140, 872, 900), 18, BLUE_BG, BLUE)
    d.text((88, 164), "业务逻辑问题", font=font(32), fill=BLUE)
    d.text((88, 212), "不该送给 SwiftShader 的活还在送  →  按需", font=font(22), fill=BLUE)

    left = [
        ("决策期仍按 60fps 刷", "Agent 只要截图那一张，刷新策略还是给人看。"),
        ("同一屏打两次", "窗口 GLES + SurfaceFlinger GLES 合成，guest 下 HWC 弱，两次都进 SwiftShader。"),
        ("自行送帧停不掉", "游戏 / 视频 / WebView 不走 Choreographer。"),
        ("1080×1920 @ 480dpi", "catalog 规格。每帧像素多，放大后面每一次填像素。"),
    ]
    y = 280
    for t, b in left:
        round_rect(d, (88, y, 840, y + 130), 12, WHITE, BLUE, 2)
        d.text((112, y + 16), t, font=font(24), fill=NAVY)
        d.text((112, y + 58), b, font=font(20), fill=TEXT)
        y += 148

    # right libraries
    round_rect(d, (928, 140, 1744, 900), 18, ORANGE_BG, ORANGE)
    d.text((960, 164), "基础库性能瓶颈", font=font(32), fill=ORANGE)
    d.text((960, 212), "送进去的活，一次太贵  →  快速（切 SwiftShader）", font=font(22), fill=ORANGE)

    right = [
        ("PixelProcessor / QuadRasterizer", "逐像素着色、混合、深度。2D 界面填像素，最重的一类。"),
        ("SamplerCore", "纹理采样。图标、文字、WebView 贴图都走这里。"),
        ("Reactor + LLVM / Subzero JIT", "按绘制状态动态生成例程。状态乱跳会编译；命中缓存后主要是光栅。"),
        ("多线程 + SIMD（本机 4 核 ARM）", "官方两条优化。鲲鹏 4 核上软光栅和 Android 抢核。"),
    ]
    y = 280
    for t, b in right:
        round_rect(d, (960, y, 1712, y + 130), 12, WHITE, ORANGE, 2)
        d.text((984, y + 16), t, font=font(24), fill=NAVY)
        d.text((984, y + 58), b, font=font(20), fill=TEXT)
        y += 148

    foot = "模块名来自 SwiftShader 官方 docs/Index.md。>50% 只标到「软渲染」这一层，没有各库占比；快速第一件事是把这一刀切开。"
    bbox = d.textbbox((0, 0), foot, font=font(20))
    d.text(((W - (bbox[2] - bbox[0])) / 2, 940), foot, font=font(20), fill=MUTED)
    foot2 = "HWUI / Skia 是下单方，不是填像素的库。Vertex/SetupProcessor 对 2D UI 通常轻于像素阶段，表上不单列。"
    bbox = d.textbbox((0, 0), foot2, font=font(20))
    d.text(((W - (bbox[2] - bbox[0])) / 2, 978), foot2, font=font(20), fill=MUTED)

    out = "/workspace/docs/assets/android-cpu-bottleneck-split.png"
    img.save(out, "PNG", optimize=True)
    print("wrote", out, img.size)


if __name__ == "__main__":
    main()
