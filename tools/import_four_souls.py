"""Импорт иллюстраций и сравнение двух русских наборов; Lua не исполняется.
python tools/import_four_souls.py --workshop "папка Mods/Workshop"
Нужны Pillow и пользовательские JSON 2143991933, 2738213595, 2370232448.
"""
import json,re,collections,hashlib,urllib.request,concurrent.futures,time
from pathlib import Path
from PIL import Image
Image.MAX_IMAGE_PIXELS = 200_000_000
import argparse
parser=argparse.ArgumentParser(description='Импорт русских карт Four Souls из пользовательских TTS-модов')
parser.add_argument('--workshop',type=Path,default=Path.home()/'Documents/My Games/Tabletop Simulator/Mods/Workshop')
parser.add_argument('--project',type=Path,default=Path(__file__).resolve().parents[1])
args=parser.parse_args()
src=args.workshop;root=args.project/'games/four_souls';art=root/'art';(art/'sheets').mkdir(parents=True,exist_ok=True);(art/'cards').mkdir(exist_ok=True)
a=json.loads((src/'2738213595.json').read_text(encoding='utf-8-sig'));b=json.loads((src/'2370232448.json').read_text(encoding='utf-8-sig'))
def canonical(s):
 parts=s.split('/');en=max(parts,key=lambda p:len(re.findall('[a-zA-Z]',p))-2*len(re.findall('[А-Яа-яЁё]',p))).lower().strip()
 en=re.sub(r'^(?:[ivx]+|0|o)\.\s*','',en);en=re.sub(r'^the\s+','',en);en=re.sub('[^a-z0-9]','',en)
 return {'magdalene':'maggy','monstostooth':'monstrostooth','moreoption':'moreoptions','guppycollar':'guppyscollar','momspulse':'momspurse','steamsale':'steamysale','gurlings':'gurglings','leeper':'leaper','pokerclip':'pokerchip'}.get(en,en)
def luadata(s):
 return {k:v for k,v in re.findall(r'\b(\w+)\s*=\s*["\']?([A-Za-z_0-9+.-]+)',s)}
third={};categories={'9051ae':'treasure','c451f5':'monster','42143b':'loot','a1bb8c':'event','1b8e80':'room','3e8b51':'bonus'};thirdcats={'80d7ef':'treasure','8e93c4':'monster','5885c4':'loot','c65ba9':'event'}
for o in b['ObjectStates']:
 if o['GUID'] in thirdcats:third[thirdcats[o['GUID']]]=collections.Counter(canonical(c.get('Nickname','')) for c in o['ContainedObjects'])
base_char=set()
def visit(xs):
 for o in xs:
  if o.get('Description')=='character':base_char.add(canonical(o.get('Nickname','')))
  visit(o.get('ContainedObjects',[]))
# В третьем моде есть фанатские мешки: персонажи базы сверяются с его официальным мешком.
for o in b['ObjectStates']:
 if o.get('Nickname')=='Official cards':visit([o])
if not base_char:base_char={'isaac','maggy','cain','judas','bluebaby','eve','samson','lazarus','lilith','eden','forgotten','azazel','lost','keeper','apollyon','guppy','bumbo','whoreofbabylon','darkjudas','tapeworm'}
cards=[];urls={};missing=[];used=collections.defaultdict(collections.Counter);characters=[]
def add(o,cat,defs,base=False,pair=''):
 defs={**defs,**o.get('CustomDeck',{})};cid=int(o.get('CardID',0));spec=defs.get(str(cid//100))
 if not spec:raise ValueError((o.get('Nickname'),cid))
 nick=o.get('Nickname','');name=canonical(nick);lua=luadata(o.get('LuaScript',''))
 if cat in third:
  base=used[cat][name]<third[cat][name];used[cat][name]+=1
 id=len(cards);url=spec['FaceURL'];key=hashlib.sha1(url.encode()).hexdigest()[:16];urls[key]=url
 back=spec.get('BackURL','');bk=hashlib.sha1(back.encode()).hexdigest()[:16] if back else ''
 if back:urls[bk]=back
 entry={'id':id,'name':nick,'key':name,'kind':cat,'base':base,'sheet':key,'index':cid%100,'cols':spec['NumWidth'],'rows':spec['NumHeight'],'back':bk,'lua':lua,'pair':pair}
 cards.append(entry);return id
for o in a['ObjectStates']:
 if o['GUID'] in categories:
  for c in o.get('ContainedObjects',[]):add(c,categories[o['GUID']],o.get('CustomDeck',{}))
for o in a['ObjectStates']:
 chars=[c for c in o.get('ContainedObjects',[]) if c.get('Description')=='character'];items=[c for c in o.get('ContainedObjects',[]) if c.get('Description')=='character-item']
 if not chars:continue
 c=chars[0];key=canonical(c['Nickname']);isbase=key in base_char
 ci=add(c,'character',o.get('CustomDeck',{}),isbase)
 ii=add(items[0],'eternal',o.get('CustomDeck',{}),isbase,key) if items else -1
 characters.append({'card':ci,'item':ii,'base':isbase,'key':key})
for cat,counter in third.items():
 deficit=counter-used[cat]
 if deficit:missing.append([cat,dict(deficit)])
seen=set();unique=[]
for char in characters:
 if char['key'] in seen:
  cards[char['card']]['base']=False
  if char['item']>=0:cards[char['item']]['base']=False
  continue
 seen.add(char['key']);unique.append(char)
characters=unique
for card in cards:
 if card['kind']=='bonus':card['base']=card['key'] in ['soulofgreed','soulofguppy','soulofgluttony']
(art/'sheets'/'.gdignore').touch()
manifest={'cards':cards,'characters':characters,'sources':{'layout':'2143991933.json','assets':'2738213595.json','baseline':'2370232448.json'},'base_counts':{k:sum(v.values()) for k,v in third.items()},'unmatched_baseline':missing,'source_urls':urls}
(art/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8');print('CARDS',len(cards),'CHARACTERS',len(characters),'SHEETS',len(urls),'UNMATCHED',missing,flush=True)
# Качаем только исходники второго мода. Не исполняем Lua, читаем лишь свойства карт.
def fetch(kv):
 key,url=kv;dest=art/'sheets'/(key+'.jpg')
 if dest.exists():return key,True,''
 url=re.sub(r'https?://cloud-[0-9]+\.steamusercontent.com', 'https://steamusercontent-a.akamaihd.net',url)
 for attempt in range(3):
  try:
   req=urllib.request.Request(url,headers={'User-Agent':'Mozilla/5.0'})
   data=urllib.request.urlopen(req,timeout=45).read()
   import io
   im=Image.open(io.BytesIO(data)).convert('RGB');im.save(dest,quality=96);return key,True,''
  except Exception as e:
   if attempt==2:return key,False,str(e)
 return key,False,'unknown'
errors=[]
with concurrent.futures.ThreadPoolExecutor(max_workers=6) as pool:
 for i,(key,ok,error) in enumerate(pool.map(fetch,urls.items())):
  if not ok:errors.append([key,error]);print('FAIL',key,error,flush=True)
  if i%20==0:print('DOWNLOADED',i+1,'/',len(urls),flush=True)
groups=collections.defaultdict(list)
for c in cards:groups[c['sheet']].append(c)
for sheet,group in groups.items():
 path=art/'sheets'/(sheet+'.jpg')
 if not path.exists():continue
 im=Image.open(path);im.load()
 for c in group:
  w=im.width/c['cols'];h=im.height/c['rows'];x=c['index']%c['cols'];y=c['index']//c['cols']
  crop=im.crop((round(x*w),round(y*h),round((x+1)*w),round((y+1)*h)))
  if crop.height>900:crop.thumbnail((650,900))
  crop.save(art/'cards'/(str(c['id'])+'.webp'),quality=94)
 im.close()
 print('CROPPED',sheet,len(group),flush=True)
(art/'download_errors.json').write_text(json.dumps(errors,indent=2),encoding='utf-8');print('DONE errors',len(errors),flush=True)
