#!/usr/bin/env python3
"""Wireframe PPTX of the Android graphics stack photo, plus SwiftShader placement."""

from lxml import etree
from pptx import Presentation
from pptx.dml.color import RGBColor
from pptx.enum.shapes import MSO_CONNECTOR, MSO_SHAPE
from pptx.enum.text import MSO_ANCHOR, PP_ALIGN
from pptx.oxml.ns import qn
from pptx.util import Emu, Inches, Pt

OUT = "/workspace/docs/assets/android-graphics-stack-wireframe.pptx"

# 16:9
SW, SH = Inches(16), Inches(9)

NAVY = RGBColor(0x16, 0x2A, 0x5A)
BLACK = RGBColor(0x22, 0x22, 0x22)
GRAY = RGBColor(0x66, 0x66, 0x66)
WHITE = RGBColor(0xFF, 0xFF, 0xFF)
LAYER = RGBColor(0xF4, 0xF5, 0xF7)
LAYER_LINE = RGBColor(0x33, 0x33, 0x33)
BOX_FILL = RGBColor(0xFF, 0xFF, 0xFF)
RED = RGBColor(0xD0, 0x32, 0x32)
BLUE = RGBColor(0x2F, 0x6F, 0xD4)
YELLOW = RGBColor(0xD4, 0xA0, 0x12)
ORANGE = RGBColor(0xC9, 0x6C, 0x16)
ORANGE_BG = RGBColor(0xFF, 0xF3, 0xE0)
MUTED = RGBColor(0xF7, 0xF7, 0xF7)


def inch(x):
    return Inches(x)


def set_fill(shape, color):
    shape.fill.solid()
    shape.fill.fore_color.rgb = color


def set_line(shape, color, pt=1.0):
    shape.line.color.rgb = color
    shape.line.width = Pt(pt)


def set_run(run, size, bold=False, color=BLACK, name="微软雅黑"):
    run.font.size = Pt(size)
    run.font.bold = bold
    run.font.color.rgb = color
    run.font.name = name
    rPr = run._r.get_or_add_rPr()
    ea = rPr.find(qn("a:ea"))
    if ea is None:
        ea = etree.SubElement(rPr, qn("a:ea"))
    ea.set("typeface", name)


def add_text_box(slide, x, y, w, h, text, size=11, bold=False, color=BLACK, align=PP_ALIGN.LEFT, anchor=MSO_ANCHOR.MIDDLE):
    box = slide.shapes.add_textbox(inch(x), inch(y), inch(w), inch(h))
    tf = box.text_frame
    tf.word_wrap = True
    tf.auto_size = None
    tf.paragraphs[0].alignment = align
    box.text_frame._txBody.bodyPr.set("anchor", {MSO_ANCHOR.TOP: "t", MSO_ANCHOR.MIDDLE: "ctr", MSO_ANCHOR.BOTTOM: "b"}[anchor])
    p = tf.paragraphs[0]
    p.alignment = align
    run = p.add_run()
    run.text = text
    set_run(run, size, bold, color)
    return box


def add_rect(slide, x, y, w, h, fill, line, text="", size=11, bold=False, tcolor=BLACK, lw=1.0):
    sh = slide.shapes.add_shape(MSO_SHAPE.ROUNDED_RECTANGLE, inch(x), inch(y), inch(w), inch(h))
    sh.adjustments[0] = 0.08
    set_fill(sh, fill)
    set_line(sh, line, lw)
    tf = sh.text_frame
    tf.word_wrap = True
    tf.auto_size = None
    tf.paragraphs[0].alignment = PP_ALIGN.CENTER
    sh.text_frame._txBody.bodyPr.set("anchor", "ctr")
    p = tf.paragraphs[0]
    p.alignment = PP_ALIGN.CENTER
    run = p.add_run()
    run.text = text
    set_run(run, size, bold, tcolor)
    return sh


def add_layer(slide, x, y, w, h, title):
    sh = slide.shapes.add_shape(MSO_SHAPE.RECTANGLE, inch(x), inch(y), inch(w), inch(h))
    set_fill(sh, LAYER)
    set_line(sh, LAYER_LINE, 1.25)
    add_text_box(slide, x + 0.08, y + 0.02, 2.4, 0.28, title, 12, True, NAVY)
    return sh


def add_arrow(slide, x1, y1, x2, y2, color, pt=1.75):
    conn = slide.shapes.add_connector(
        MSO_CONNECTOR.STRAIGHT, inch(x1), inch(y1), inch(x2), inch(y2)
    )
    conn.line.color.rgb = color
    conn.line.width = Pt(pt)
    ln = conn._element.spPr.find(qn("a:ln"))
    if ln is None:
        ln = etree.SubElement(conn._element.spPr, qn("a:ln"))
    for tag in ("a:headEnd", "a:tailEnd"):
        old = ln.find(qn(tag))
        if old is not None:
            ln.remove(old)
    tail = etree.SubElement(ln, qn("a:tailEnd"))
    tail.set("type", "triangle")
    tail.set("w", "med")
    tail.set("len", "med")
    return conn


def add_elbow(slide, points, color, pt=1.75):
    """points: list of (x,y) inch tuples, draw polyline with arrow on last segment."""
    for i in range(len(points) - 1):
        x1, y1 = points[i]
        x2, y2 = points[i + 1]
        last = i == len(points) - 2
        if last:
            add_arrow(slide, x1, y1, x2, y2, color, pt)
        else:
            conn = slide.shapes.add_connector(
                MSO_CONNECTOR.STRAIGHT, inch(x1), inch(y1), inch(x2), inch(y2)
            )
            conn.line.color.rgb = color
            conn.line.width = Pt(pt)


class B:
    def __init__(self, x, y, w, h):
        self.x, self.y, self.w, self.h = x, y, w, h

    @property
    def cx(self):
        return self.x + self.w / 2

    @property
    def cy(self):
        return self.y + self.h / 2

    @property
    def l(self):
        return self.x

    @property
    def r(self):
        return self.x + self.w

    @property
    def t(self):
        return self.y

    @property
    def b(self):
        return self.y + self.h


def layout():
    """Coordinates matching the uploaded stack photo."""
    Lx, Lw = 1.55, 14.15
    app = B(Lx, 0.18, Lw, 0.38)
    fw = B(Lx, 0.56, Lw, 1.12)
    nat = B(Lx, 1.72, Lw, 3.42)
    hal = B(Lx, 5.18, Lw, 0.98)
    ker = B(Lx, 6.20, Lw, 2.42)

    gfx = B(2.05, 0.78, 1.45, 0.62)
    ogl = B(4.55, 0.72, 1.55, 0.62)
    wm = B(8.55, 0.72, 1.95, 0.62)

    runtime = B(2.55, 1.95, 7.55, 0.42)
    hwui = B(2.85, 2.55, 1.35, 0.48)
    librs = B(4.40, 2.55, 1.25, 0.48)
    vulkan = B(5.85, 2.55, 1.25, 0.48)
    libgui = B(8.00, 2.55, 1.45, 0.48)
    codec = B(12.35, 2.42, 2.05, 0.62)
    skia = B(1.85, 3.22, 1.25, 0.48)
    gles = B(3.55, 3.85, 2.15, 0.62)
    sf = B(8.15, 3.18, 2.35, 0.52)
    alloc = B(7.55, 4.05, 1.95, 0.55)
    hwcs = B(9.85, 4.05, 2.15, 0.55)

    gralloc = B(7.75, 5.38, 1.55, 0.55)
    hwc = B(10.05, 5.38, 1.45, 0.55)
    overlay = B(12.05, 5.38, 1.45, 0.55)

    jpeg = B(1.85, 6.55, 1.45, 0.95)
    png = B(3.45, 6.55, 1.45, 0.95)
    gpu = B(5.25, 6.55, 1.45, 0.95)
    ion = B(7.15, 6.55, 1.35, 0.95)
    overlay_acc = B(8.75, 6.55, 1.55, 0.95)
    fb = B(10.50, 6.55, 1.45, 0.95)
    video = B(12.15, 6.55, 1.55, 0.95)
    return locals()


def draw_stack(slide, boxes, highlight_ss=False):
    L = boxes
    add_layer(slide, L["app"].x, L["app"].y, L["app"].w, L["app"].h, "APP")
    add_layer(slide, L["fw"].x, L["fw"].y, L["fw"].w, L["fw"].h, "Framework")
    add_layer(slide, L["nat"].x, L["nat"].y, L["nat"].w, L["nat"].h, "Native")
    add_layer(slide, L["hal"].x, L["hal"].y, L["hal"].w, L["hal"].h, "HAL")
    add_layer(slide, L["ker"].x, L["ker"].y, L["ker"].w, L["ker"].h, "Kernel")

    def box(b, text, size=11, bold=False, fill=BOX_FILL, line=BLACK, tcolor=BLACK, lw=1.0):
        add_rect(slide, b.x, b.y, b.w, b.h, fill, line, text, size, bold, tcolor, lw)

    box(L["gfx"], "Graphics\n控件", 10)
    box(L["ogl"], "Open GL", 12, True)
    box(L["wm"], "windowManger", 11)

    box(L["runtime"], "libandroid_runtime", 12, True)
    box(L["hwui"], "HWUI", 12, True)
    box(L["librs"], "libRS", 12, True)
    box(L["vulkan"], "Vulkan", 12, True)
    box(L["libgui"], "libgui", 12, True)
    box(L["codec"], "MediaCodec", 12, True)
    box(L["skia"], "Skia", 12, True)

    gles_fill = ORANGE_BG if highlight_ss else BOX_FILL
    gles_line = ORANGE if highlight_ss else BLACK
    gles_lw = 2.25 if highlight_ss else 1.0
    box(L["gles"], "Open GL ES", 13, True, gles_fill, gles_line, ORANGE if highlight_ss else BLACK, gles_lw)

    box(L["sf"], "SurfaceFlinger", 12, True)
    box(L["alloc"], "allocator\nservice", 10)
    box(L["hwcs"], "HWComposer\nservice", 10)

    box(L["gralloc"], "Gralloc", 12, True)
    box(L["hwc"], "HWC", 12, True)
    box(L["overlay"], "overlay", 12, True)

    box(L["jpeg"], "JPEG\n硬解加速\n（可选）", 10)
    box(L["png"], "PNG\n硬解加速\n（可选）", 10)
    gpu_fill = RGBColor(0xEE, 0xEE, 0xEE) if highlight_ss else BOX_FILL
    gpu_line = GRAY if highlight_ss else BLACK
    box(L["gpu"], "GPU\n图形通用绘制", 10, True, gpu_fill, gpu_line, GRAY if highlight_ss else BLACK)
    box(L["ion"], "ION\n内存提供", 10)
    box(L["overlay_acc"], "叠加加速器\n（可选）", 10)
    box(L["fb"], "FB\n图形图层", 10)
    box(L["video"], "视频通路\n（可选）", 10)

    add_text_box(slide, L["jpeg"].x, L["ker"].b - 0.32, 3.2, 0.28, "图形加速解码器类", 9, False, GRAY, PP_ALIGN.CENTER)
    add_text_box(slide, L["gpu"].x, L["ker"].b - 0.32, 1.45, 0.28, "图形通用绘制", 9, False, GRAY, PP_ALIGN.CENTER)
    add_text_box(slide, L["ion"].x, L["ker"].b - 0.32, 1.35, 0.28, "内存提供", 9, False, GRAY, PP_ALIGN.CENTER)
    add_text_box(slide, L["overlay_acc"].x, L["ker"].b - 0.32, 1.55, 0.28, "叠加加速", 9, False, GRAY, PP_ALIGN.CENTER)
    add_text_box(slide, L["fb"].x, L["ker"].b - 0.32, 3.2, 0.28, "显示层", 9, False, GRAY, PP_ALIGN.CENTER)

    # 绘制通路 red
    add_arrow(slide, L["gfx"].cx, L["gfx"].b, L["gfx"].cx, L["runtime"].t, RED)
    add_arrow(slide, L["ogl"].cx, L["ogl"].b, L["ogl"].cx, L["runtime"].t, RED)
    add_arrow(slide, L["runtime"].cx - 2.4, L["runtime"].b, L["hwui"].cx, L["hwui"].t, RED)
    add_arrow(slide, L["runtime"].cx - 0.8, L["runtime"].b, L["librs"].cx, L["librs"].t, RED)
    add_arrow(slide, L["runtime"].cx + 0.6, L["runtime"].b, L["vulkan"].cx, L["vulkan"].t, RED)
    add_arrow(slide, L["hwui"].l, L["hwui"].cy, L["skia"].r, L["skia"].cy, RED)
    add_arrow(slide, L["hwui"].cx, L["hwui"].b, L["gles"].cx, L["gles"].t, RED)
    add_arrow(slide, L["librs"].cx, L["librs"].b, L["gles"].cx + 0.35, L["gles"].t, RED)
    add_arrow(slide, L["skia"].cx, L["skia"].b, L["jpeg"].cx, L["jpeg"].t, RED)
    add_arrow(slide, L["skia"].r + 0.15, L["skia"].b, L["png"].cx, L["png"].t, RED)
    add_elbow(slide, [(L["vulkan"].cx, L["vulkan"].b), (L["vulkan"].cx, L["gles"].cy), (L["gpu"].cx, L["gles"].cy), (L["gpu"].cx, L["gpu"].t)], RED)
    add_arrow(slide, L["gles"].cx, L["gles"].b, L["gpu"].cx, L["gpu"].t, RED)

    # window / gui / codec / sf  黑
    add_arrow(slide, L["wm"].cx, L["wm"].b, L["wm"].cx, L["runtime"].t, BLACK, 1.4)
    add_arrow(slide, L["runtime"].r - 1.2, L["runtime"].b, L["libgui"].cx, L["libgui"].t, BLACK, 1.4)
    add_arrow(slide, L["libgui"].r, L["libgui"].cy, L["codec"].l, L["codec"].cy, BLACK, 1.4)
    add_arrow(slide, L["libgui"].cx, L["libgui"].b, L["sf"].cx, L["sf"].t, BLACK, 1.4)
    add_arrow(slide, L["sf"].cx - 0.4, L["sf"].b, L["alloc"].cx, L["alloc"].t, BLACK, 1.4)
    add_arrow(slide, L["sf"].cx + 0.5, L["sf"].b, L["hwcs"].cx, L["hwcs"].t, BLACK, 1.4)
    add_arrow(slide, L["alloc"].cx, L["alloc"].b, L["gralloc"].cx, L["gralloc"].t, BLACK, 1.4)
    add_arrow(slide, L["gralloc"].cx, L["gralloc"].b, L["ion"].cx, L["ion"].t, BLACK, 1.4)
    add_arrow(slide, L["gles"].r, L["gles"].cy, L["alloc"].l, L["gles"].cy, BLACK, 1.4)
    add_text_box(slide, L["gles"].r + 0.05, L["gles"].t - 0.28, 1.1, 0.26, "GPU叠加", 9, False, GRAY)

    # 叠加蓝
    add_arrow(slide, L["sf"].r, L["sf"].cy, L["hwcs"].cx, L["sf"].cy, BLUE)
    add_arrow(slide, L["hwcs"].cx, L["hwcs"].b, L["hwc"].cx, L["hwc"].t, BLUE)
    add_arrow(slide, L["hwc"].l, L["hwc"].cy, L["overlay_acc"].cx, L["hwc"].cy, BLUE)
    add_text_box(slide, L["hwc"].l - 1.35, L["hwc"].t - 0.28, 1.4, 0.26, "叠加 Compose", 9, False, BLUE)
    add_arrow(slide, L["hwc"].cx, L["hwc"].b, L["fb"].cx, L["fb"].t, BLUE)
    add_text_box(slide, L["hwc"].r - 0.2, L["hwc"].b, 0.9, 0.24, "刷新", 9, False, BLUE)

    # 送显黄
    add_arrow(slide, L["hwc"].r, L["hwc"].cy, L["overlay"].l, L["overlay"].cy, YELLOW)
    add_arrow(slide, L["overlay"].cx, L["overlay"].b, L["video"].cx, L["video"].t, YELLOW)
    add_text_box(slide, L["overlay"].r - 0.15, L["overlay"].b, 1.1, 0.24, "独立送显", 9, False, YELLOW)

    # legend
    add_text_box(slide, 0.12, 0.18, 1.35, 0.28, "图例", 11, True, NAVY)
    add_arrow(slide, 0.18, 0.58, 0.95, 0.58, RED)
    add_text_box(slide, 0.12, 0.62, 1.35, 0.28, "绘制通路", 10, False, RED)
    add_arrow(slide, 0.18, 1.02, 0.95, 1.02, BLUE)
    add_text_box(slide, 0.12, 1.06, 1.35, 0.28, "叠加通路", 10, False, BLUE)
    add_arrow(slide, 0.18, 1.46, 0.95, 1.46, YELLOW)
    add_text_box(slide, 0.12, 1.50, 1.35, 0.28, "送显通路", 10, False, YELLOW)

    add_text_box(
        slide,
        0.10,
        5.25,
        1.40,
        0.85,
        "HAL：封装底层驱动对接",
        9,
        False,
        GRAY,
    )
    add_text_box(
        slide,
        0.10,
        6.35,
        1.40,
        1.6,
        "Kernel：芯片能力。JPEG/叠加/视频通路可选，需硬件支持。",
        9,
        False,
        GRAY,
    )


def add_legend_note(slide, text):
    add_text_box(slide, 1.55, 8.62, 14.15, 0.32, text, 11, False, NAVY, PP_ALIGN.LEFT)


def main():
    prs = Presentation()
    prs.slide_width = SW
    prs.slide_height = SH
    blank = prs.slide_layouts[6]
    L = layout()

    # slide 1 original photo
    s0 = prs.slides.add_slide(blank)
    add_text_box(s0, 0.4, 0.15, 15.2, 0.4, "原图（线框所依）", 20, True, NAVY)
    photo = "/home/ubuntu/.cursor/projects/workspace/assets/6601cb88-8692-4f53-9abf-f3f1b7745a68.png"
    s0.shapes.add_picture(photo, inch(1.6), inch(0.6), inch(12.8), inch(8.1))

    # slide 2 wireframe
    s1 = prs.slides.add_slide(blank)
    draw_stack(s1, L, highlight_ss=False)
    add_legend_note(s1, "线框复刻。红=绘制，蓝=叠加，黄=送显。模块名按原图（含 windowManger 拼写）。")

    # slide 3 swiftshader
    s2 = prs.slides.add_slide(blank)
    draw_stack(s2, L, highlight_ss=True)

    add_rect(
        s2,
        0.10,
        1.95,
        1.40,
        3.05,
        ORANGE_BG,
        ORANGE,
        "SwiftShader\n落点\n\nNative 层\nOpen GL ES\n的实现\n\n截断到 GPU\n的绘制红线\n\nHWUI / SF\n只是下单方",
        11,
        True,
        ORANGE,
        2.0,
    )
    add_rect(
        s2,
        L["gpu"].x - 0.04,
        L["gpu"].y - 0.04,
        L["gpu"].w + 0.08,
        L["gpu"].h + 0.08,
        RGBColor(0xF0, 0xF0, 0xF0),
        GRAY,
        "GPU\n真机才走\n本沙箱旁路",
        10,
        True,
        GRAY,
        1.5,
    )
    add_legend_note(
        s2,
        "SwiftShader = Native 层 OpenGL ES 的用户态实现，不是 Kernel GPU，也不是 SurfaceFlinger / HWC。SF 的 GPU 叠加同样打进这个 GLES 盒。",
    )

    # slide 4 analysis
    s3 = prs.slides.add_slide(blank)
    add_text_box(s3, 0.5, 0.25, 15, 0.45, "从这张栈图看，SwiftShader 应该在哪", 22, True, NAVY)

    rows = [
        ("在哪", "Native 层，Open GL ES 这一格的实现。对应原图红线：HWUI / Skia / libRS → Open GL ES → GPU。本沙箱在 Open GL ES 处截住，不再进 Kernel 的 GPU。"),
        ("为什么不在 Framework", "上面的 Open GL、Graphics 控件只是 API / 控件。它们下单，不填像素。"),
        ("为什么不在 HWUI / Skia", "HWUI、Skia 把显示列表变成 GLES 调用。SwiftShader 是被调用的后端，不是它们自己。"),
        ("为什么不在 SurfaceFlinger", "SF 是叠加通路的中枢。它做 GPU 叠加时自己也是 GLES 客户端，同样打进 Open GL ES → SwiftShader。"),
        ("为什么不在 HWC / overlay / FB", "那是蓝/黄的叠加与送显。guest 模式 HWC 弱，合成往往退回 GLES，于是又回到 SwiftShader，但 SwiftShader 不是 HWC。"),
        ("Vulkan 那条红线", "原图 Vulkan → GPU。SwiftShader 也能实现 Vulkan；本沙箱 guest 主路径仍是 GLES。不要把 Vulkan 盒改名叫 SwiftShader。"),
        ("Gralloc / ION", "缓冲分配还在。SwiftShader 画出的像素仍要进 GraphicBuffer，再交给 SurfaceFlinger。"),
    ]
    y = 0.85
    for title, body in rows:
        add_rect(s3, 0.5, y, 2.3, 0.85, ORANGE_BG, ORANGE, title, 13, True, ORANGE, 1.25)
        add_rect(s3, 2.95, y, 12.4, 0.85, MUTED, RGBColor(0xDD, 0xDD, 0xDD), body, 13, False, BLACK, 1.0)
        y += 0.95

    add_text_box(
        s3,
        0.5,
        8.45,
        15,
        0.4,
        "一句话：画在 Native 的 Open GL ES 上，替掉到 GPU 的绘制红线；不要画成一层新 HAL，也不要画进 Kernel。",
        16,
        True,
        ORANGE,
    )

    prs.save(OUT)
    print("wrote", OUT)
    preview_pngs(L)


def preview_pngs(L):
    """Raster preview for visual QA; PPTX is the deliverable."""
    from PIL import Image, ImageDraw, ImageFont

    dpi = 120
    font_path = "/usr/share/fonts/truetype/wqy/wqy-microhei.ttc"

    def fnt(n):
        return ImageFont.truetype(font_path, n)

    def px(inches):
        return int(inches * dpi)

    def draw_slide(highlight):
        img = Image.new("RGB", (px(16), px(9)), (255, 255, 255))
        d = ImageDraw.Draw(img)

        def rect(b, fill, outline, width=2):
            d.rounded_rectangle(
                (px(b.x), px(b.y), px(b.r), px(b.b)),
                radius=8,
                fill=fill,
                outline=outline,
                width=width,
            )

        def text(x, y, s, size, fill=(20, 20, 20)):
            d.text((px(x), px(y)), s, font=fnt(size), fill=fill)

        def box(b, lines, fill=(255, 255, 255), outline=(30, 30, 30), tw=2, tfill=(20, 20, 20), size=14):
            rect(b, fill, outline, tw)
            joined = "\n".join(lines)
            bbox = d.multiline_textbbox((0, 0), joined, font=fnt(size), spacing=2)
            twd, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
            d.multiline_text(
                (px(b.cx) - twd / 2, px(b.cy) - th / 2),
                joined,
                font=fnt(size),
                fill=tfill,
                align="center",
                spacing=2,
            )

        def line(x1, y1, x2, y2, color, w=3):
            d.line((px(x1), px(y1), px(x2), px(y2)), fill=color, width=w)

        for key, title in (("app", "APP"), ("fw", "Framework"), ("nat", "Native"), ("hal", "HAL"), ("ker", "Kernel")):
            b = L[key]
            d.rectangle((px(b.x), px(b.y), px(b.r), px(b.b)), fill=(244, 245, 247), outline=(50, 50, 50), width=2)
            text(b.x + 0.08, b.y + 0.04, title, 16, (22, 42, 90))

        box(L["gfx"], ["Graphics", "控件"])
        box(L["ogl"], ["Open GL"])
        box(L["wm"], ["windowManger"])
        box(L["runtime"], ["libandroid_runtime"])
        box(L["hwui"], ["HWUI"])
        box(L["librs"], ["libRS"])
        box(L["vulkan"], ["Vulkan"])
        box(L["libgui"], ["libgui"])
        box(L["codec"], ["MediaCodec"])
        box(L["skia"], ["Skia"])
        gfill = (255, 243, 224) if highlight else (255, 255, 255)
        gout = (201, 108, 22) if highlight else (30, 30, 30)
        gt = (201, 108, 22) if highlight else (20, 20, 20)
        box(L["gles"], ["Open GL ES"], gfill, gout, 4 if highlight else 2, gt, 18)
        box(L["sf"], ["SurfaceFlinger"])
        box(L["alloc"], ["allocator", "service"])
        box(L["hwcs"], ["HWComposer", "service"])
        box(L["gralloc"], ["Gralloc"])
        box(L["hwc"], ["HWC"])
        box(L["overlay"], ["overlay"])
        box(L["jpeg"], ["JPEG 硬解", "（可选）"])
        box(L["png"], ["PNG 硬解", "（可选）"])
        if highlight:
            box(L["gpu"], ["GPU", "真机才走", "本沙箱旁路"], (240, 240, 240), (102, 102, 102), 2, (102, 102, 102), 13)
        else:
            box(L["gpu"], ["GPU"])
        box(L["ion"], ["ION"])
        box(L["overlay_acc"], ["叠加加速器", "（可选）"])
        box(L["fb"], ["FB"])
        box(L["video"], ["视频通路", "（可选）"])

        R, BL, Y = (208, 50, 50), (47, 111, 212), (212, 160, 18)
        K = (40, 40, 40)
        line(L["gfx"].cx, L["gfx"].b, L["gfx"].cx, L["runtime"].t, R)
        line(L["ogl"].cx, L["ogl"].b, L["ogl"].cx, L["runtime"].t, R)
        line(L["hwui"].cx, L["hwui"].b, L["gles"].cx, L["gles"].t, R)
        line(L["gles"].cx, L["gles"].b, L["gpu"].cx, L["gpu"].t, R)
        line(L["vulkan"].cx, L["vulkan"].b, L["vulkan"].cx, L["gles"].cy, R)
        line(L["vulkan"].cx, L["gles"].cy, L["gpu"].cx, L["gles"].cy, R)
        line(L["gpu"].cx, L["gles"].cy, L["gpu"].cx, L["gpu"].t, R)
        line(L["libgui"].cx, L["libgui"].b, L["sf"].cx, L["sf"].t, K)
        line(L["sf"].cx, L["sf"].b, L["alloc"].cx, L["alloc"].t, K)
        line(L["hwcs"].cx, L["hwcs"].b, L["hwc"].cx, L["hwc"].t, BL)
        line(L["hwc"].r, L["hwc"].cy, L["overlay"].l, L["overlay"].cy, Y)

        text(0.12, 0.18, "绘制红 / 叠加蓝 / 送显黄", 13, (90, 90, 90))
        if highlight:
            d.rounded_rectangle((px(0.10), px(1.95), px(1.50), px(5.00)), 10, fill=(255, 243, 224), outline=(201, 108, 22), width=3)
            d.multiline_text((px(0.18), px(2.10)), "SwiftShader\n落点\nNative\nOpen GL ES", font=fnt(15), fill=(201, 108, 22), spacing=4)
        return img

    p1 = "/opt/cursor/artifacts/android_stack_wireframe_preview.png"
    p2 = "/opt/cursor/artifacts/android_stack_swiftshader_placement.png"
    draw_slide(False).save(p1, "PNG", optimize=True)
    draw_slide(True).save(p2, "PNG", optimize=True)
    print("preview", p1, p2)


if __name__ == "__main__":
    main()
