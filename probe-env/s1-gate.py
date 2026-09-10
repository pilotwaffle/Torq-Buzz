import re,math,sys
f=sys.argv[1]; ws={}; recv={}; paints=[]
for l in open(f,encoding='utf-8'):
    m=re.search(r'wsrecv id=(\w+) createdAt=(\d+) wsEpoch=(\d+)',l)
    if m: ws[m[1]]=int(m[3])
    m=re.search(r'recv id=(\w+) bytes=(\d+) seq=(\d+) relayCreatedAt=(\d+) recvEpoch=(\d+) decryptedEpoch=(\d+)',l)
    if m: recv[int(m[3])]=dict(id=m[1],bytes=int(m[2]),recv=int(m[5]),dec=int(m[6]))
    m=re.search(r'paint .*epoch=(\d+) n=\d+ newestSeq=(\d+) .*emitEpoch=(\d+) latencyMs=(-?\d+)',l)
    if m: paints.append((int(m[1]),int(m[2]),int(m[3]),int(m[4])))
seen=set(); rows=[]
for paint,seq,emit,lat in paints:
    if seq in seen or seq not in recv: continue
    seen.add(seq); r=recv[seq]; w=ws.get(r['id'])
    if w is None: continue
    rows.append(dict(emit_to_ws=w-emit,queue=r['recv']-w,decrypt=r['dec']-r['recv'],render=paint-r['dec'],ws_to_paint=paint-w,total=lat))
pct=lambda v,q: sorted(v)[math.ceil(q*len(v))-1]
print(f'{f}: samples={len(rows)}')
for k in ('emit_to_ws','queue','decrypt','render','ws_to_paint','total'):
    v=[r[k] for r in rows]; print(f'  {k:11s} p50={sorted(v)[len(v)//2]:6.0f} p95={pct(v,.95):6.0f} max={max(v):6.0f}')
