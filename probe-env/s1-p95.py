import re,math,sys
f=sys.argv[1]; rows=[]
for l in open(f,encoding='utf-8'):
    m=re.search(r'epoch=(\d+) n=(\d+) newestSeq=(\d+) newestEmit=(\S+) emitEpoch=(\d+) latencyMs=(-?\d+)',l)
    if m: rows.append((int(m[1]),int(m[3]),int(m[6])))
samples=[]; last=None
for ep,seq,lat in rows:
    if seq!=last: samples.append((ep,seq,lat)); last=seq
lats=sorted(s[2] for s in samples); n=len(lats)
p=lambda q: lats[math.ceil(q*n)-1]
p50=(lats[n//2-1]+lats[n//2])/2 if n%2==0 else lats[n//2]
print(f'{f}: batch samples={n} p50={p50} p90={p(0.9)} p95={p(0.95)} p99={p(0.99)} max={max(lats)} min={min(lats)} span={(samples[-1][0]-samples[0][0])/1000:.0f}s seq {samples[0][1]}->{samples[-1][1]}')
t0=samples[0][0]
for k in range(4):
    w=sorted(s[2] for s in samples if k*60<=(s[0]-t0)/1000<(k+1)*60)
    if w: print(f'  min {k+1}: n={len(w)} p50={w[len(w)//2]} p95={w[math.ceil(0.95*len(w))-1]} max={w[-1]}')
