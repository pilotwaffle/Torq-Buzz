import re,math,sys
f=sys.argv[1]; recv={}; paints=[]
for l in open(f,encoding='utf-8'):
    m=re.search(r'\[live-activity\] recv seq=(\d+) relayCreatedAt=(\d+) recvEpoch=(\d+) decryptedEpoch=(\d+) newestEmit=(\S+) innerCount=(\d+)',l)
    if m: recv[int(m[1])]=dict(created=int(m[2]),recv=int(m[3]),dec=int(m[4]),inner=int(m[6]))
    m=re.search(r'\[live-activity\] paint .*epoch=(\d+) n=(\d+) newestSeq=(\d+) .*emitEpoch=(\d+) latencyMs=(-?\d+)',l)
    if m: paints.append(dict(paint=int(m[1]),seq=int(m[3]),emit=int(m[4]),lat=int(m[5])))
seen=set(); rows=[]
for p in paints:
    if p['seq'] in seen: continue
    seen.add(p['seq']); r=recv.get(p['seq'])
    if r: rows.append(dict(seq=p['seq'],emit_to_relay=(r['created']*1000-p['emit']),emit_to_recv=r['recv']-p['emit'],decrypt=r['dec']-r['recv'],render=p['paint']-r['dec'],total=p['lat'],inner=r['inner']))
def pct(v,q): v=sorted(v); return v[math.ceil(q*len(v))-1]
print(f'{f}: recv frames={len(recv)} paint batches={len(seen)} paired={len(rows)}')
for k in ('emit_to_recv','decrypt','render','total'):
    v=[r[k] for r in rows]; print(f'  {k:12s} p50={sorted(v)[len(v)//2]:6.0f} p95={pct(v,0.95):6.0f} max={max(v):6.0f}')
print('  inner events per frame p50',sorted(r['inner'] for r in rows)[len(rows)//2],'max',max(r['inner'] for r in rows))
t0=rows[0]['seq']
print('  first 5 rows:',[(r['seq'],r['emit_to_recv'],r['decrypt'],r['render']) for r in rows[:5]])
print('  last 5 rows:',[(r['seq'],r['emit_to_recv'],r['decrypt'],r['render']) for r in rows[-5:]])
