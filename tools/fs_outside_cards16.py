"""Собственные текстовые лица дополнительной двусторонней карты Догмы, без заимствованной иллюстрации."""
from pathlib import Path
from PIL import Image,ImageDraw,ImageFont
import json
root=Path(__file__).resolve().parents[1]
font_path=str(root/'hub/art/fonts/Exo2-Variable.ttf')
rows={913:('ВСАДНИКИ','4 здоровья · защита 4+ · атака 1','Активный игрок обязан атаковать эту карту раз за ход, если может.\n\nВместо смерти: добавьте жетон, полностью восстановите здоровье. Активный игрок получает сокровище и отменяет атаку.\n\nПосле четвёртого жетона переверните на сторону «Зверь!».\n\nНЕУКРОТИМЫЙ — занимает новый слот и не может быть накрыт.'),914:('ЗВЕРЬ!','6 здоровья · защита 4+ · атака 2','При перевороте на эту сторону или объявлении атаки каждый живой игрок бросает кубик.\n\nВсе игроки с наименьшим результатом умирают.\n\nНЕУКРОТИМЫЙ — занимает новый слот и не может быть накрыт.\n\nНАГРАДА: 1 сокровище, 6 добычи и 2 души.')}
for cid,(title,stats,body) in rows.items():
 im=Image.new('RGB',(650,900),'#27221f');d=ImageDraw.Draw(im)
 d.rounded_rectangle((12,12,638,888),radius=24,outline='#9a8059',width=5)
 d.text((36,38),title,font=ImageFont.truetype(font_path,45),fill='#e3d8c4')
 d.text((36,108),stats,font=ImageFont.truetype(font_path,23),fill='#bea784')
 font=ImageFont.truetype(font_path,28); y=172
 for para in body.split('\n'):
  if not para:y+=19;continue
  line=''
  for word in para.split():
   if d.textlength(line+' '+word,font=font)>570:
    d.text((38,y),line,font=font,fill='#d7ccba');y+=38;line=word
   else:line=(line+' '+word).strip()
  d.text((38,y),line,font=font,fill='#d7ccba');y+=38
 d.text((38,850),'Дополнительная карта Догмы',font=ImageFont.truetype(font_path,21),fill='#a18f77')
 im.save(root/f'games/four_souls/art/cards/{cid}.webp')
p=root/'games/four_souls/art/card_texts.json';data=json.loads(p.read_text(encoding='utf-8'))
for cid,(title,stats,body) in rows.items():
 data[str(cid)]=dict(name_ru=title,type='outside',text=body,stats={},reward='',verified='2026-11-05',verified_image=False,note='Перевод официальных правил https://foursouls.com/cards/r-the_harbingers/; собственное текстовое лицо.')
p.write_text(json.dumps(data,ensure_ascii=False,indent=1)+'\n',encoding='utf-8')
