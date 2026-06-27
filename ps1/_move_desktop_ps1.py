import os, shutil
from pathlib import Path
src_root = Path(r'C:\Users\Light\Desktop')
dst_root = Path(r'D:\code\ps1\desktop')
dst_root.mkdir(parents=True, exist_ok=True)
ps1s=[]
for root, dirs, files in os.walk(src_root):
    for f in files:
        if f.lower().endswith('.ps1'):
            ps1s.append(Path(root)/f)
print('FOUND', len(ps1s))
moved=[]; errors=[]
for p in ps1s:
    rel=p.relative_to(src_root)
    q=dst_root/rel
    q.parent.mkdir(parents=True, exist_ok=True)
    if q.exists():
        stem=q.with_suffix('')
        suf=q.suffix
        i=1
        nq=Path(str(stem)+f'__dup{i}'+suf)
        while nq.exists():
            i+=1
            nq=Path(str(stem)+f'__dup{i}'+suf)
        q=nq
    try:
        shutil.move(str(p), str(q))
        moved.append((str(p), str(q)))
    except Exception as e:
        errors.append((str(p), repr(e)))
print('MOVED', len(moved))
for a,b in moved:
    print(a+' => '+b)
print('ERRORS', len(errors))
for a,e in errors:
    print(a+' :: '+e)
