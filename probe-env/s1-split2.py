import re,math,sys
f=sys.argv[1]; ws={}; recv={}; paints=[]
for l in open(f,encoding='utf-8'):
    m=re.search(r'wsrecv id=(\w+) createdAt=(\d+) wsEpoch=(\d+)',l)
    if m: ws[m[1]]=dict(created=int(m[2]),ws=int(m[3]))
    m=re.search(r'recv id=(\w+) seq=(\d+) relayCreatedAt=(\d+) recvEpoch=(\d+) decryptedEpoch=(\d+) newestEmit=(\S+) innerCount=(\d+)',l)
    if m: recv[int(m[3])]=dict(id=m[1],bytes=int(m[2]),created=int(m[4]),recv=int(m[5]),dec=int(m[6]),inner=int(m[8]))
    m=re.search(r'paint .*epoch=(\d+) n=(\d+) newestSeq=(\d+) .*emitEpoch=(\d+) latencyMs=(-?\d+)',l)
    if m: paints.append(dict(paint=int(m[1]),seq=int(m[3]),emit=int(m[4]),lat=int(m[5])))
seen=set(); rows=[]
for p in paints:
    if p['seq'] in seen: continue
    seen.add(p['seq']); r=recv.get(p['seq'])
    if not r: continue
    w=ws.get(r['id'])
    rows.append(dict(seq=p['seq'], emit_to_ws=(w['ws']-p['emit']) if w else None, queue_wait=(r['recv']-w['ws']) if w else None, decrypt=r['dec']-r['recv'], render=p['paint']-r['dec'], total=p['lat']))
pct=lambda v,q: sorted(v)[math.ceil(q*len(v))-1]
print(f'{f}: ws frames={len(ws)} recv={len(recv)} paint batches={len(seen)} paired={len(rows)}')
for k in ('emit_to_ws','queue_wait','decrypt','render','total'):
    v=[r[k] for r in rows if r[k] is not None]
    if v: print(f'  {k:11s} p50={sorted(v)[len(v)//2]:6.0f} p95={pct(v,0.95):6.0f} max={max(v):6.0f}')
