#!/usr/bin/env python3
"""Print "x y" for the first UI node whose text or content-desc contains a needle.

usage: ui_tap_point.py <dump.xml> <needle>

Stdlib only: the capture script must run on a machine with adb and python3 and
nothing else.
"""
import html
import re
import sys

xml = open(sys.argv[1], encoding='utf-8').read()
needle = sys.argv[2].lower()

for m in re.finditer(r'<node[^>]*>', xml):
    node = m.group(0)
    label = ''
    for attr in ('text', 'content-desc'):
        v = re.search(r'\b%s="([^"]*)"' % attr, node)
        if v and v.group(1).strip():
            label = v.group(1)
            break
    if needle not in html.unescape(label).lower():
        continue
    b = re.search(r'bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"', node)
    if not b:
        continue
    x1, y1, x2, y2 = map(int, b.groups())
    if x2 - x1 <= 0 or y2 - y1 <= 0:
        continue
    print((x1 + x2) // 2, (y1 + y2) // 2)
    sys.exit(0)

sys.exit(1)