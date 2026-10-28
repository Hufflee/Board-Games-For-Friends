"""Только собственная ENet-пара WS; свежие профили и проверка PCK перед release-запуском."""
import argparse,os,subprocess,time,json,struct,hashlib
from pathlib import Path
p=argparse.ArgumentParser()
p.add_argument("--release",action="store_true")
p.add_argument("--graphics",action="store_true")
args=p.parse_args()
root=Path.cwd()
label=("release" if args.release else "debug")+("-gl" if args.graphics else "-headless")+"-enet"
folder=root/"build/batch28_word_slam"/label
original_folder=folder
suffix=1
while folder.exists():
 suffix+=1
 folder=original_folder.with_name(original_folder.name+"-"+str(suffix))
folder.mkdir(parents=True,exist_ok=False)
exe=root/"build/batch28_word_slam/release-fixed/WSQAClean.exe" if args.release else Path("C:/Users/rabin/Desktop/ШТУКИ/godot/Godot_v4.7.2-stable_win64_console.exe")
if args.release:
 pack=exe.with_suffix(".pck")
 assert exe.is_file() and pack.is_file()
 original=Path("C:/Users/rabin/AppData/Roaming/Godot/export_templates/4.7.2.stable/windows_release_x86_64.exe")
 assert hashlib.sha256(exe.read_bytes()).digest()==hashlib.sha256(original.read_bytes()).digest()
 with pack.open("rb") as f:
  h=f.read(104);magic,version,major,minor,patch,flags,base,index=struct.unpack("<6I2Q",h[:40])
  assert magic==0x43504447 and version==4 and flags==2
  f.seek(index);n=struct.unpack("<I",f.read(4))[0];valid_settings=False
  for _ in range(n):
   k=struct.unpack("<I",f.read(4))[0];name=f.read(k).rstrip(b"\0").decode()
   offset,size=struct.unpack("<2Q",f.read(16));f.read(20);where=f.tell()
   assert not name.startswith(("build/","backups/"))
   if name=="project.binary":
    f.seek(base+offset);valid_settings=f.read(4)==b"ECFG";f.seek(where)
  assert valid_settings
processes=[]
try:
 for role in ["server","client"]:
  env=os.environ.copy()
  env["APPDATA"]=str(folder/(role+"-profile"))
  env["WS_QA_ROLE"]=role;env["WS_QA_DIR"]=str(folder);env["WS_QA_PORT"]="28186"
  env["TEMP"]=str(root/"build/batch28_word_slam/qa-temp");env["TMP"]=env["TEMP"]
  command=[str(exe),"--audio-driver","Dummy"]
  if args.graphics: command+=["--rendering-method","gl_compatibility","--rendering-driver","opengl3","--position","-32000,-32000","--max-fps","60"]
  else: command+=["--headless"]
  if not args.release: command+=["--path",str(root),"--script","res://tests/test_ws_guess_reentrancy28.gd"]
  out=(folder/(role+".log")).open("w",encoding="utf-8");err=(folder/(role+".stderr.log")).open("w",encoding="utf-8")
  startup=subprocess.STARTUPINFO();startup.dwFlags|=subprocess.STARTF_USESHOWWINDOW;startup.wShowWindow=0
  proc=subprocess.Popen(command,cwd=str(root),env=env,stdout=out,stderr=err,startupinfo=startup,creationflags=subprocess.CREATE_NO_WINDOW)
  processes.append((role,proc,out,err))
  (folder/(role+".pid")).write_text(str(proc.pid))
  if role=="server":
   end=time.monotonic()+20
   while not (folder/"listening").exists() and time.monotonic()<end and proc.poll() is None: time.sleep(.05)
   assert (folder/"listening").exists(),"Хост не начал слушать"
 end=time.monotonic()+55
 while any(proc.poll() is None for _,proc,_,_ in processes) and time.monotonic()<end: time.sleep(.1)
 result={}
 for role,proc,out,err in processes:
  timed_out=proc.poll() is None
  if timed_out: proc.terminate()
  code=proc.wait(timeout=5);out.close();err.close()
  text=(folder/(role+".log")).read_text(encoding="utf-8",errors="replace")
  errors=(folder/(role+".stderr.log")).read_text(encoding="utf-8",errors="replace")
  result[role]={"pid":proc.pid,"exit":code,"timeout":timed_out,"summary":next((x for x in text.splitlines() if x.startswith("WS REENTRANCY:")),""),"script_error":"SCRIPT ERROR" in text+errors}
 (folder/"result.json").write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding="utf-8")
 print(json.dumps(result,ensure_ascii=False))
 raise SystemExit(0 if all(v["exit"]==0 and v["summary"] and not v["script_error"] for v in result.values()) else 1)
finally:
 for role,proc,out,err in processes:
  if proc.poll() is None: proc.terminate();proc.wait(timeout=5)
  out.close();err.close()
