# Split a s2-controls.mjs combined log into the per-control evidence files the
# Slice 2 runbook (SLICE-2-VERIFICATION.md section 5) expects: one integer latency
# (ack ms - sent ms) per line, with a header line stating the measurement mode.
# usage: python s2-split-evidence.py <combined.log> <harness> <outdir>
import re, sys, collections, os
src, harness, outdir = sys.argv[1:4]
sent = {}; lat = collections.defaultdict(list)
for l in open(src, encoding='utf-8'):
    m = re.search(r'\[agent-controls\] sent kind=(\w+) id=(\S+).* ms=(\d+)', l)
    if m: sent[m[2]] = (m[1], int(m[3]))
    m = re.search(r'\[agent-controls\] ack id=(\S+) status=(\S+) branch=(\S+) ms=(\d+)', l)
    if m and m[1] in sent:
        k, t = sent[m[1]]; lat[k].append((int(m[4]) - t, m[2], m[3]))
for k, v in lat.items():
    p = os.path.join(outdir, f'slice2-{harness}-{k}-gate-prod-nodebug.log')
    with open(p, 'w', encoding='utf-8', newline='\n') as f:
        f.write(f'# production page build, no debugger attached; harness={harness} control={k} n={len(v)}; '
                f'latency = desktop ack epoch ms - desktop send epoch ms; status/branch per sample in trailing comment\n')
        for ms, st, br in v: f.write(f'{ms}\n')
        f.write('# statuses: ' + ', '.join(f'{ms}:{st}/{br}' for ms, st, br in v) + '\n')
    print(p, 'n=', len(v))
