"""Fail when package version, embedded load order or documented local links drift."""
from pathlib import Path
import json
import re
import xml.etree.ElementTree as ET
root = Path(__file__).resolve().parents[1]
meta = json.loads((root / 'package.json').read_text())
assert meta['license'] == 'Apache-2.0'
assert 'Apache License' in (root / 'LICENSE').read_text()
assert 'Version 2.0, January 2004' in (root / 'LICENSE').read_text()
version = re.search(r'VERSION = "([^"]+)"', (root / 'src/Core.lua').read_text()).group(1)
assert version == meta['version'], 'runtime/package version drift'
load_order = [node.attrib['file'].replace('\\', '/') for node in ET.parse(root / 'Embed.xml').getroot()]
assert load_order == meta['snd']['loadOrder'], 'XML/package load order drift'
for path in load_order:
    assert (root / path).is_file(), path
for path in root.glob('*.md'):
    text = path.read_text()
    assert text.count('```') % 2 == 0, path
    for link in re.findall(r'\]\(([^)]+)\)', text):
        if not link.startswith(('http:', 'https:', '#', 'mailto:')):
            assert (root / link.split('#')[0]).exists(), (path.name, link)
print('PASS metadata, version, embed order and local documentation links')
