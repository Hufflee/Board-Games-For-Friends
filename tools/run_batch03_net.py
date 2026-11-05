"""Настоящий ENet двух тихих процессов с отдельными профилями."""
from pathlib import Path
import subprocess, os, uuid
root=Path(__file__).resolve().parents[1]
out=root/'build/batch03_net'
out.mkdir(parents=True,exist_ok=True)
(out/'received').unlink(missing_ok=True)
godot=r'C:\Users\rabin\Desktop\ШТУКИ\godot\Godot_v4.7.2-stable_win64_console.exe'
tasks=[]
for role in ['host','client']:
    profile=out/('profile_'+uuid.uuid4().hex)
    profile.mkdir()
    log=(out/(role+'.log')).open('w',encoding='utf-8')
    process=subprocess.Popen([godot,'--headless','--audio-driver','Dummy','--path',str(root),'--script','res://tests/test_batch03_net.gd'],cwd=root,env={**os.environ,'APPDATA':str(profile),'B03_ROLE':role},stdout=log,stderr=subprocess.STDOUT,creationflags=subprocess.CREATE_NO_WINDOW)
    tasks.append((role,process,log))
failed=False
for role,process,log in tasks:
    try: code=process.wait(timeout=35)
    except subprocess.TimeoutExpired: process.kill();process.wait();code=99
    log.close()
    text=(out/(role+'.log')).read_text(encoding='utf-8')
    bad=code!=0 or 'SCRIPT ERROR' in text or '\nERROR:' in text
    failed|=bad
    print(role,code,'ОШИБКИ' if bad else 'чистый лог')
    print('\n'.join(line for line in text.splitlines() if 'BATCH03 NET' in line))
raise SystemExit(1 if failed else 0)
