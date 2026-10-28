"""Локальный QA-пак: точный индекс export-pack + только тестовая сцена/настройки."""
import hashlib,json,struct,sys
from pathlib import Path

src,dst=map(Path,sys.argv[1:3])
root=Path(__file__).resolve().parents[2]
settings=src.parent/"qa-project.binary"
assert settings.read_bytes()[:4]==b"ECFG"
extra={
 "project.binary":settings.read_bytes(),
 "tests/fixtures/ws_release_qa28.gd":(root/"tests/fixtures/ws_release_qa28.gd").read_bytes(),
 "tests/fixtures/ws_release_qa28.tscn":(root/"tests/fixtures/ws_release_qa28.tscn").read_bytes()
}
with src.open("rb") as inp,dst.open("wb") as out:
 h=inp.read(104)
 magic,version,major,minor,patch,flags,base,index=struct.unpack("<6I2Q",h[:40])
 assert magic==0x43504447 and version==4 and flags==2
 inp.seek(index)
 n=struct.unpack("<I",inp.read(4))[0]; entries=[]
 for _ in range(n):
  length=struct.unpack("<I",inp.read(4))[0];name=inp.read(length).rstrip(b"\0").decode()
  offset,size=struct.unpack("<2Q",inp.read(16));md5=inp.read(16);entryflags=struct.unpack("<I",inp.read(4))[0]
  assert entryflags==0
  assert not name.startswith(("build/","backups/"))
  entries.append((name,offset,size,md5))
 assert "games/word_slam/ui/ws_table.gdc" in [x[0] for x in entries]
 out.write(struct.pack("<6I2Q",magic,version,major,minor,patch,2,128,0)+bytes(64))
 out.write(bytes(128-out.tell()))
 records=[]
 for name,offset,size,md5 in entries+[(k,0,len(v),hashlib.md5(v).digest()) for k,v in extra.items() if k!="project.binary"]:
  start=out.tell()
  if name in extra:
   data=extra[name];out.write(data);size=len(data);md5=hashlib.md5(data).digest()
  else:
   inp.seek(base+offset)
   remaining=size
   while remaining:
    block=inp.read(min(1048576,remaining));assert block
    out.write(block);remaining-=len(block)
  records.append((name,start-128,size,md5))
  out.write(bytes((-out.tell())%32))
 idx=out.tell()
 out.write(struct.pack("<I",len(records)))
 for name,offset,size,md5 in records:
  text=name.encode();text+=bytes((-len(text))%4)
  out.write(struct.pack("<I",len(text))+text+struct.pack("<2Q",offset,size)+md5+struct.pack("<I",0))
 out.seek(32);out.write(struct.pack("<Q",idx))
names=[r[0] for r in records]
dst.with_suffix(".manifest.json").write_text(json.dumps(names,ensure_ascii=False,indent=2),encoding="utf-8")
print("QA VALID: GDPC4/ECFG; files",len(records),"build/backups=0; production WS bytecode from exported pack")
