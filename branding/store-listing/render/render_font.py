"""Names a font where the app's text names none (the overlay in
hud_painter.dart, chip labels in app_theme.dart): on a phone that is the
system font, in flutter test it draws boxes. For renders only; take it out
again. Keeps the files' line endings.

    python render_font.py on|off [family]
"""
import pathlib
import re
import sys

MARK = '/*RENDERFONT*/'
CR = chr(13)
LF = chr(10)
FILES = {
    'lib/services/video/hud_painter.dart': [
        'TextStyle(fontSize: 0.42 * u, color: _dimWhite, shadows: _soft(u))',
        'TextStyle(' + LF + '      fontSize: size,' + LF + '      fontWeight: FontWeight.w600,',
        'TextStyle(' + LF + '      fontSize: size,' + LF + '      fontWeight: FontWeight.w700,',
    ],
    'lib/theme/app_theme.dart': [
        'labelStyle: TextStyle(' + LF + '        color: WidgetStateColor.resolveWith(',
    ],
}
for name, anchors in FILES.items():
    path = pathlib.Path(name)
    raw = path.read_bytes().decode('utf-8')
    crlf = (CR + LF) in raw
    text = raw.replace(CR + LF, LF)
    if sys.argv[1] == 'on':
        family = sys.argv[2] if len(sys.argv) > 2 else 'Roboto'
        assert MARK not in text, 'already patched'
        for a in anchors:
            assert text.count(a) == 1, a
            text = text.replace(a, a.replace('TextStyle(', f"TextStyle({MARK}fontFamily: '{family}', ", 1))
    else:
        text, n = re.subn(re.escape(MARK) + r"fontFamily: '[^']*', ", '', text)
        assert n == len(anchors), (name, n)
    path.write_bytes((text.replace(LF, CR + LF) if crlf else text).encode('utf-8'))
print(sys.argv[1], 'ok')
