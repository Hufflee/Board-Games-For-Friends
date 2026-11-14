"""Собирает оригинальный шрифт для названий карт Things in Rings."""
from pathlib import Path
from math import cos, pi, sin
import unicodedata

import cv2
import numpy as np
from fontTools.fontBuilder import FontBuilder
from fontTools.pens.ttGlyphPen import TTGlyphPen

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "games/things_in_rings/art/fonts/TIR-Press.ttf"

# Координаты осевых линий в условной сетке. Кривые заданы точками вручную.
CAPS = {
    "A": "0,0 20,70 29,71 51,0;10,23 42,25",
    "B": "1,0 1,70 26,71 38,67 45,58 45,49 39,41 27,37 2,36;26,37 42,33 49,22 48,12 40,4 25,0 2,0",
    "C": "48,61 39,69 23,71 11,65 3,51 0,34 3,18 13,5 27,-1 42,3 50,12",
    "D": "1,0 1,70 22,70 39,64 48,52 52,35 48,17 38,5 23,0 1,0",
    "E": "44,70 2,69 1,0 46,1;2,36 37,38",
    "F": "1,0 2,69 45,71;2,36 36,38",
    "G": "50,61 42,69 26,71 12,65 3,52 0,34 4,17 14,4 29,-1 45,4 51,14 51,34 32,34",
    "H": "1,0 2,70;50,1 51,71;2,34 50,37",
    "I": "3,69 28,71;16,69 15,1;0,0 29,1",
    "J": "10,69 47,71 46,20 42,8 34,1 20,-1 8,3 1,12",
    "K": "1,0 2,71;48,71 3,28;22,44 52,0",
    "L": "2,71 1,0 43,2",
    "M": "0,0 5,70 13,71 31,37 48,71 57,70 62,0",
    "N": "1,0 2,70 9,70 48,6 50,6 51,71",
    "O": "52,35 48,56 40,67 26,72 12,67 3,55 0,34 4,15 13,4 27,-1 42,4 49,15 52,35",
    "P": "1,0 2,70 27,71 42,65 48,53 47,44 40,35 26,31 2,32",
    "Q": "@O;36,20 55,-4",
    "R": "@P;26,31 51,0",
    "S": "47,62 37,69 23,71 10,66 3,57 4,48 13,41 36,33 46,25 49,16 43,6 31,0 16,0 2,8",
    "T": "0,69 51,71;26,70 24,0",
    "U": "1,71 1,23 6,10 15,2 28,-1 41,3 50,14 52,26 52,71",
    "V": "0,71 20,2 29,0 51,71",
    "W": "0,71 13,0 22,0 36,43 49,0 58,1 72,71",
    "X": "1,71 49,0;49,71 0,0",
    "Y": "0,71 24,38 49,71;24,38 23,0",
    "Z": "1,69 46,71 49,66 2,5 3,0 50,2",
    "Б": "45,70 2,69 1,0 26,0 40,4 48,12 49,23 43,33 31,38 2,37",
    "Г": "1,0 2,69 44,71",
    "Д": "0,-14 0,0 56,1 56,-14;8,0 14,12 19,39 21,70 45,71 47,1",
    "Ж": "31,0 33,71;0,71 32,36 0,0;65,71 32,36 65,0",
    "З": "3,62 13,69 28,71 42,67 48,57 46,47 37,40 24,36 18,36;24,36 39,35 49,27 51,16 45,7 33,1 16,0 1,8",
    "И": "1,70 1,0 8,1 49,69 52,70 51,0",
    "Л": "0,0 9,7 14,24 20,70 47,71 48,0",
    "П": "1,0 2,69 50,71 49,0",
    "У": "0,71 24,28;50,71 27,21 18,7 6,0",
    "Ф": "29,-3 30,73;29,60 14,59 4,51 0,37 4,24 15,17 30,15 46,17 56,26 60,39 56,51 45,59 29,60",
    "Ц": "1,71 1,0 57,1 57,-14;47,71 46,1",
    "Ч": "1,71 1,48 6,38 16,33 31,33 48,41;49,71 48,0",
    "Ш": "1,70 1,0 68,1 69,71;35,70 34,1",
    "Щ": "@Ш;67,1 77,1 77,-14",
    "Ъ": "0,70 19,71 18,0 40,1 53,6 59,16 58,26 51,34 39,37 19,36",
    "Ь": "2,71 1,0 24,1 36,5 44,14 45,25 39,34 25,38 2,36",
    "Ы": "@Ь;62,0 63,71",
    "Э": "1,60 12,68 27,71 40,66 49,54 53,35 49,17 39,4 25,-1 12,2 0,10;20,35 50,37",
    "Ю": "1,0 2,71;1,34 20,35;70,35 66,56 57,68 45,72 32,67 23,54 20,34 24,16 33,4 46,-1 59,4 67,16 70,35",
    "Я": "50,0 51,70 23,71 10,66 3,56 3,46 11,37 23,33 49,34;23,33 0,0",
    "0": "@O;18,20 35,52",
    "1": "3,57 23,71 23,1;3,0 41,1",
    "2": "2,60 12,68 26,71 40,67 47,57 46,48 37,38 12,19 2,6 2,0 49,1",
    "3": "1,63 14,70 30,70 43,65 47,55 43,45 30,38 22,37;30,38 43,33 50,23 48,12 39,4 24,-1 11,1 1,7",
    "4": "35,71 0,25 0,21 53,22;39,70 38,0",
    "5": "45,71 8,69 4,37 18,42 32,41 44,33 48,22 46,12 38,4 24,-1 10,1 0,8",
    "6": "43,64 34,70 20,70 9,63 2,50 0,32 2,16 11,4 24,-1 38,3 46,13 47,25 40,35 28,39 13,36 2,29",
    "7": "1,69 49,71 50,66 34,34 24,0",
    "8": "25,37 12,43 5,51 6,61 14,68 26,71 39,67 46,60 46,50 38,42 25,37 10,31 2,22 2,12 11,3 25,-1 39,2 49,10 50,20 42,30 25,37",
    "9": "4,8 14,1 28,0 40,7 47,20 50,39 47,55 39,67 26,71 13,68 4,58 3,46 10,36 22,32 37,35 48,43",
}

# Строчные формы и капитель для заголовочного набора.
LOWER = {
    "a":"2,42 12,49 28,50 40,44 44,36 43,0;43,29 26,30 11,27 3,21 0,12 6,3 18,-1 32,3 43,13",
    "b":"1,71 0,1;1,36 11,46 23,50 37,46 46,34 48,21 43,9 34,2 23,-1 10,4 1,14",
    "d":"47,71 46,0;46,37 35,47 22,50 10,45 3,36 0,23 4,10 13,2 25,-1 36,4 46,15",
    "e":"1,25 47,28 45,36 39,45 27,50 15,47 5,38 0,25 3,13 12,4 24,-1 38,1 47,7",
    "f":"31,67 21,70 12,65 8,54 8,0;0,47 29,48",
    "g":"46,50 45,-9 40,-18 29,-23 15,-22 4,-17;45,39 35,48 22,50 10,46 3,36 0,24 4,12 13,5 24,3 36,7 45,16",
    "h":"1,71 0,0;1,36 13,46 25,50 37,47 44,38 44,0",
    "i":"1,48 0,0;1,66 1,66",
    "j":"18,48 17,-10 12,-20 0,-23;18,66 18,66",
    "k":"1,71 0,0;42,49 1,19;22,34 45,0",
    "l":"0,71 0,12 4,3 12,0",
    "m":"1,49 0,0;1,34 12,46 22,49 32,45 36,36 36,0;36,35 47,46 57,49 66,45 71,35 71,0",
    "n":"1,49 0,0;1,34 12,46 25,49 37,45 43,35 43,0",
    "p":"1,49 0,-23;1,35 12,46 25,50 38,45 46,34 47,22 43,10 34,2 22,-1 10,4 1,13",
    "q":"46,49 46,-23;46,37 35,47 22,50 10,45 3,36 0,23 4,10 13,2 25,-1 36,4 46,15",
    "r":"1,49 0,0;1,32 12,45 24,50 33,46",
    "t":"11,63 10,14 14,4 23,0 33,4;0,47 32,48",
    "y":"0,49 20,7;43,49 17,-12 11,-21 1,-23",
    "б":"43,70 18,67 8,59 3,48 0,25 4,11 13,2 28,0 40,5 47,16 47,28 41,39 28,44 15,41 2,33",
    "д":"0,-13 0,0 51,1 51,-13;8,0 14,14 19,49 39,50 41,1",
    "ф":"28,70 28,-23;28,43 15,48 6,44 0,32 2,16 10,7 22,6 28,11 36,6 47,8 56,18 57,32 52,44 42,48 28,43",
    "ц":"0,50 0,0 47,1 47,-13;40,50 39,1",
    "щ":"0,50 0,0 69,1 69,-13;30,49 30,1;59,50 59,1",
}
PUNCT = {
    ".":"1,1 1,1", ",":"6,3 2,-9", ":":"1,8 1,8;1,40 1,40",
    ";":"6,8 2,-4;6,40 6,40", "!":"1,71 0,21;0,1 0,1",
    "?":"0,60 10,69 25,71 39,65 44,55 40,46 25,36 22,22;22,1 22,1",
    "-":"1,31 25,31", "–":"1,31 43,31", "—":"1,31 64,31",
    "'":"4,71 1,59", "’":"4,71 1,59", "‘":"1,59 4,71", "ʼ":"4,71 1,59",
    '"':"1,71 1,60;16,71 16,60", "«":"20,49 1,30 20,11;39,49 20,30 39,11",
    "»":"1,49 20,30 1,11;20,49 39,30 20,11",
    "(":"21,72 9,58 2,38 3,18 11,-1 21,-12", ")":"0,72 12,58 19,38 18,18 10,-1 0,-12",
    "/":"0,-4 42,75", "&":"48,1 10,45 5,56 10,66 21,70 32,67 38,59 33,49 13,35 3,26 0,15 6,5 18,0 33,3 44,14 49,28",
    "+":"1,32 43,32;22,53 22,11", "−":"1,31 43,31", "=":"1,21 43,21;1,41 43,41",
    "%":"0,0 57,70;15,62 10,69 4,66 1,59 1,49 7,42 14,46 17,55 15,62;56,19 51,26 45,23 42,16 42,6 48,-1 55,3 58,12 56,19",
    "№":"1,0 2,70 7,69 34,14 37,14 38,71;51,31 70,31;71,58 67,69 58,71 51,65 50,52 55,44 64,45 70,52 71,58",
    "#":"9,0 20,70;30,0 41,70;1,24 48,24;3,48 50,48",
    "…":"1,1 1,1;19,1 19,1;37,1 37,1",
}
ALIASES = dict(zip("АВЕКМНОРСТХ", "ABEKMHOPCTX", strict=True))
SMALL = dict(zip("аеорсху", "aeopcxy", strict=True))
MARKS = {
    "\u0300": "-10,12 5,0", "\u0301": "-5,0 10,12",
    "\u0302": "-12,0 0,10 12,0", "\u0303": "-13,2 -7,8 1,8 7,3 14,7",
    "\u0304": "-13,4 13,4", "\u0306": "-12,9 -8,2 0,0 8,2 12,9",
    "\u0307": "0,4 0,4", "\u0308": "-10,4 -10,4;10,4 10,4",
    "\u030a": "0,12 7,8 7,1 0,-2 -7,1 -7,8 0,12",
    "\u030b": "-12,0 -2,12;4,0 14,12", "\u030c": "-12,10 0,0 12,10",
    "\u0327": "0,3 8,-4 4,-10 -6,-12", "\u0328": "4,3 -3,-5 -2,-11 7,-13",
}

def paths(spec):
    result = []
    for stroke in spec.split(";"):
        if stroke.startswith("@"):
            result.extend(paths(CAPS[stroke[1:]]))
        else:
            result.append([tuple(map(float, point.split(","))) for point in stroke.split()])
    return result


def design(ch):
    if ch in SMALL:
        return design(SMALL[ch])
    if ch in LOWER:
        return paths(LOWER[ch]), False
    if ch in PUNCT:
        return paths(PUNCT[ch]), True
    if ch in CAPS or ch in ALIASES:
        return paths(CAPS[ALIASES.get(ch, ch)]), True
    if ch.upper() in CAPS or ch.upper() in ALIASES:
        base, _ = design(ch.upper())
        return [[(x*.86, y*.74) for x,y in stroke] for stroke in base], False
    decomposition = unicodedata.normalize("NFD", ch)
    if len(decomposition) > 1 and all(mark in MARKS for mark in decomposition[1:]):
        strokes, cap = design(decomposition[0])
        width = max(x for stroke in strokes for x,_ in stroke)
        top = max(y for stroke in strokes for _,y in stroke)
        for mark in decomposition[1:]:
            anchor = -13 if unicodedata.combining(mark) in {202, 220} else top + 24
            strokes.extend([[(x+width/2, y+anchor) for x,y in stroke] for stroke in paths(MARKS[mark])])
        return strokes, cap
    special = {
        "І":"@I", "Ј":"@J", "Ѕ":"@S", "Ґ":"@Г;43,70 44,82",
        "Є":"@C;2,34 31,36", "Љ":"@Л;47,35 62,37 75,33 82,24 81,12 72,3 59,0 48,0",
        "Њ":"@H;50,36 65,37 77,32 83,23 82,12 74,3 61,0 50,0",
        "Џ":"@U;27,1 27,-13",
    }
    if ch.upper() in special:
        base = paths(special[ch.upper()])
        return (base, True) if ch.isupper() else ([[(x*.86,y*.74) for x,y in p] for p in base], False)
    raise KeyError(ch)


def outline(strokes, cap):
    # Анизотропное перо: вертикали плотнее, горизонтали легче.
    mask = np.zeros((430, 410), np.uint8)
    for stroke in strokes:
        for i,(x,y) in enumerate(stroke):
            next_x,next_y = stroke[min(i+1,len(stroke)-1)]
            steps = max(1, round(max(abs(next_x-x),abs(next_y-y))*2))
            for k in range(steps+1):
                t = k/steps
                px,py = x+(next_x-x)*t, y+(next_y-y)*t
                px += .095*py
                radius_x = (8.9 if cap else 7.9)+.32*cos(py*pi/71)
                radius_y = (6.6 if cap else 6.0)+.22*sin(px*pi/43)
                cv2.ellipse(mask,(round(45+px*3),round(344-py*3)),
                            (round(radius_x*3),round(radius_y*3)),0,0,360,255,-1)
    edges,_ = cv2.findContours(mask,cv2.RETR_TREE,cv2.CHAIN_APPROX_SIMPLE)
    left = min(int(p[0][0]) for edge in edges for p in edge)
    right = max(int(p[0][0]) for edge in edges for p in edge)
    pen = TTGlyphPen(None)
    factor = 2.7
    for edge in edges:
        if cv2.contourArea(edge)<12:
            continue
        approx = cv2.approxPolyDP(edge,1.25,True)
        points = [(round((int(x)-left)*factor+30),round((344-int(y))*factor)) for [[x,y]] in approx]
        def midpoint(p,q):
            return tuple(round((a+b)/2) for a,b in zip(p,q))
        pen.moveTo(midpoint(points[-1],points[0]))
        for i,pt in enumerate(points):
            pen.qCurveTo(pt,midpoint(pt,points[(i+1)%len(points)]))
        pen.closePath()
    return pen.glyph(), (round((right-left)*factor)+60,30)


def build():
    blocks = [range(32,127), range(0x00C0,0x0180), range(0x0400,0x0460)]
    characters = {chr(i) for block in blocks for i in block} | set(PUNCT)
    characters |= {"\u00a0","\u202f","ß","Æ","æ","Ø","ø","Œ","œ","Ł","ł"}
    extra = {
        "Æ":"0,0 30,71 44,71 44,0 83,1;44,70 82,71;44,36 76,38;12,24 42,25",
        "Ø":"@O;1,-4 53,75",
        "Œ":"@O;47,4 90,0;53,36 82,37;45,67 88,71",
        "Ł":"@L;-9,26 24,47",
        "ß":"0,0 0,53 6,66 17,71 30,69 38,60 35,50 24,42 35,34 41,24 39,12 30,3 17,0",
    }
    for k,v in extra.items():
        CAPS[k] = v
    empty=TTGlyphPen(None).glyph()
    glyphs={".notdef":outline(paths("0,0 0,71 48,71 48,0 0,0;12,15 35,57"),True)[0]}
    metrics={".notdef":(525,30)}
    cmap={}
    for c in sorted(characters):
        name=f"uni{ord(c):04X}"
        if c.isspace():
            glyph,metric=empty,(250,0)
        else:
            try:
                variant,cap=design(c)
            except KeyError:
                continue
            glyph,metric=outline(variant,cap)
        cmap[ord(c)]=name
        glyphs[name]=glyph
        metrics[name]=metric
    font=FontBuilder(1000,isTTF=True)
    font.setupGlyphOrder(list(glyphs))
    font.setupCharacterMap(cmap)
    font.setupGlyf(glyphs)
    font.setupHorizontalMetrics(metrics)
    font.setupHorizontalHeader(ascent=875,descent=-250)
    font.setupNameTable({"familyName":"TIR Press","styleName":"Bold","uniqueFontIdentifier":"TIR Press Bold 1.000",
                         "fullName":"TIR Press Bold","psName":"TIRPress-Bold","version":"Version 1.000"})
    font.setupOS2(sTypoAscender=875,sTypoDescender=-250,usWinAscent=875,usWinDescent=250,usWeightClass=700,fsSelection=32)
    font.font["head"].macStyle=1
    font.setupPost()
    OUTPUT.parent.mkdir(parents=True,exist_ok=True)
    font.save(OUTPUT)

if __name__ == "__main__":
    build()

