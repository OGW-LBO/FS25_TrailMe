"""Build FS25_TrailMe.

Zeichnet das Mod-Icon (512x512 DXT1 ohne Mipmaps, ModHub-/TestRunner-konform),
prueft modDesc.xml und packt die ZIP. Es werden nur .xml/.lua/.dds gepackt.

Die ZIP bleibt bewusst in diesem Ordner und wird NICHT in den Mods-Ordner
kopiert - das macht der Nutzer selbst.
"""

import math
import os
import struct
import xml.dom.minidom
import zipfile

from PIL import Image, ImageDraw

os.chdir(os.path.dirname(os.path.abspath(__file__)))

MOD_NAME = "FS25_TrailMe"
ICON = "icon_TrailMe.dds"
DATEIEN = [
    "modDesc.xml",
    "FolgeMirMain.lua",
    "FolgeMirVehicle.lua",
    "FolgeMirEvent.lua",
    ICON,
]

# --- Icon zeichnen (kein Text, keine Logos - ModHub-Guideline) ---------------
W = H = 512
img = Image.new("RGB", (W, H), (18, 32, 52))
d = ImageDraw.Draw(img)

# Himmel oben heller, Boden unten dunkler
for y in range(H):
    t = y / (H - 1)
    r = int(46 + (16 - 46) * t)
    g = int(78 + (38 - 78) * t)
    b = int(112 + (30 - 112) * t)
    d.line([(0, y), (W, y)], fill=(r, g, b))


def trecker(cx, cy, s, haube, kabine):
    """Trecker in Seitenansicht, Blickrichtung rechts. (cx, cy) ist der
    Aufstandspunkt der Raeder, s skaliert das ganze Fahrzeug."""

    def kasten(x0, y0, x1, y1, rad, farbe):
        d.rounded_rectangle([cx + x0 * s, cy + y0 * s, cx + x1 * s, cy + y1 * s],
                            radius=max(3, int(rad * s)), fill=farbe)

    def rund(x0, y0, x1, y1, farbe):
        d.ellipse([cx + x0 * s, cy + y0 * s, cx + x1 * s, cy + y1 * s], fill=farbe)

    kasten(-34, -202, -14, -150, 6, (58, 58, 64))     # Auspuff
    kasten(-96, -106, 78, -30, 15, haube)             # Haube
    kasten(-44, -170, 34, -94, 13, kabine)            # Kabine
    kasten(-34, -160, 24, -114, 8, (170, 210, 232))   # Scheibe
    rund(-130, -100, -16, 14, kabine)                 # Kotfluegel, das Rad
    rund(-124, -72, -22, 30, (30, 30, 34))            # deckt ihn bis auf den Bogen ab
    rund(-110, -58, -36, 16, (98, 98, 104))
    rund(-98, -46, -48, 4, (52, 52, 58))
    rund(14, -48, 84, 22, (30, 30, 34))               # Vorderrad
    rund(25, -37, 73, 11, (98, 98, 104))


def pfeil(x0, y0, x1, y1, dicke, farbe):
    """Gerader Pfeil von (x0, y0) nach (x1, y1)."""
    dx, dy = x1 - x0, y1 - y0
    laenge = math.hypot(dx, dy)
    ex, ey = dx / laenge, dy / laenge      # Richtung
    nx, ny = -ey, ex                       # Senkrechte dazu
    spitze = dicke * 2.2
    sx, sy = x1 - ex * spitze, y1 - ey * spitze
    h = dicke * 0.5

    d.polygon([(x0 + nx * h, y0 + ny * h), (sx + nx * h, sy + ny * h),
               (sx - nx * h, sy - ny * h), (x0 - nx * h, y0 - ny * h)],
              fill=farbe)
    d.polygon([(x1, y1),
               (sx + nx * spitze * 0.55, sy + ny * spitze * 0.55),
               (sx - nx * spitze * 0.55, sy - ny * spitze * 0.55)], fill=farbe)


# Links unten der Folger, rechts oben das Fahrzeug, dem er folgt
trecker(165, 455, 0.80, (198, 70, 50), (228, 104, 76))
trecker(380, 215, 0.72, (74, 118, 64), (106, 154, 90))

# Der Pfeil dazwischen zeigt vom Folger auf das vordere Fahrzeug
pfeil(240, 340, 320, 260, 30, (240, 200, 74))

img.save("_icon_vorschau.png")   # zum Ansehen, wird nicht gepackt
img.save(ICON, pixel_format="DXT1")

# --- DDS-Header auf die TestRunner-Vorgabe bringen ---------------------------
# 512x512 DXT1 ohne Mipmaps = 128 Byte Header + 131072 Byte Daten = 131200 Byte
with open(ICON, "rb") as f:
    daten = bytearray(f.read())

daten = daten[: 128 + 131072]
struct.pack_into("<I", daten, 8, 0xA1007)    # dwFlags
struct.pack_into("<I", daten, 28, 1)         # dwMipMapCount
struct.pack_into("<I", daten, 108, 0x1000)   # dwCaps
struct.pack_into("<I", daten, 112, 0)        # dwCaps2

with open(ICON, "wb") as f:
    f.write(daten)

groesse = os.path.getsize(ICON)
assert groesse == 131200, "Icon hat %d Bytes, erwartet 131200" % groesse
print("Icon:", ICON, groesse, "Bytes (512x512 DXT1, ohne Mipmaps)")

# --- modDesc pruefen ---------------------------------------------------------
dom = xml.dom.minidom.parse("modDesc.xml")
desc_version = dom.documentElement.getAttribute("descVersion")
assert desc_version == "116", "descVersion ist %s, erwartet 116" % desc_version

quellen = [k.getAttribute("filename")
           for k in dom.getElementsByTagName("sourceFile")]
quellen += [k.getAttribute("filename")
            for k in dom.getElementsByTagName("specialization")]

for q in quellen:
    assert os.path.exists(q), "in modDesc genannt, fehlt aber: %s" % q

print("modDesc.xml: wohlgeformt, descVersion", desc_version,
      "- alle", len(quellen), "Skriptdateien vorhanden")

# --- ZIP bauen (modDesc.xml im Root, nur xml/lua/dds) ------------------------
zip_name = MOD_NAME + ".zip"

if os.path.exists(zip_name):
    os.remove(zip_name)

with zipfile.ZipFile(zip_name, "w", zipfile.ZIP_DEFLATED) as z:
    for fn in DATEIEN:
        assert os.path.splitext(fn)[1] in (".xml", ".lua", ".dds"), fn
        z.write(fn, fn)

print("ZIP:", zip_name, os.path.getsize(zip_name), "Bytes")

with zipfile.ZipFile(zip_name) as z:
    for i in z.namelist():
        print("  ", i)
