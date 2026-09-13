# AC-19: dump each control store and grep for message bodies and filesystem paths.
# usage: python s2-privacy.py <store.sqlite>... ; prints per-file hit counts (expect 0 everywhere).
import sqlite3, sys, re
pats = {
    'steer/prompt/message words': re.compile(r'steer|prompt|message', re.I),
    'windows path': re.compile(r'[A-Za-z]:\\\\'),
    'unix home path': re.compile(r'/home/|/Users/'),
    'busywork prompt text': re.compile(r'non-deterministic|NFA|busywork|numbers from 1 to 300', re.I),
}
for f in sys.argv[1:]:
    c = sqlite3.connect(f)
    dump = '\n'.join(c.iterdump())
    print(f, 'dump bytes', len(dump))
    for name, p in pats.items():
        hits = [m.group(0) for m in p.finditer(dump)]
        print(f'  {name}: {len(hits)}', (sorted(set(hits))[:5] if hits else ''))
    for m in re.finditer(r'.{0,60}(steer|prompt)[^\n]{0,60}', dump, re.I):
        print('   ctx:', m.group(0)[:130])
