"""Автономная HTML-анкета Стиллиона и проверяемое применение решений владельца.

generate --output build/stillion_questions_review.html
apply decisions.json           — только показать план
apply decisions.json --apply   — убрать отмеченные вопросы, сохранив резервную копию
"""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path
import re
import sys
from datetime import datetime

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "games/stillion/logic/st_questions.gd"
PATTERN = re.compile(r'(const TEXT := """\n?)(.*?)(""")', re.S)


def digest(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def parse(source: str) -> list[dict]:
    match = PATTERN.search(source)
    if not match:
        raise ValueError("Не найден банк TEXT")
    category, rows, current = "", [], None
    for line in match[2].splitlines():
        if line.startswith("# "):
            category = line[2:].strip()
        elif line.startswith("? "):
            text = line[2:].strip()
            current = {"id": digest(category + "\n" + text), "category": category,
                       "question": text, "answers": []}
            rows.append(current)
        elif current is not None and re.match(r"^[csue]:", line):
            current["answers"].append(line)
    if not rows or len({r["id"] for r in rows}) != len(rows):
        raise ValueError("Пустой банк или повторяющиеся вопросы")
    return rows


def generate(source: str, output: Path) -> None:
    payload = json.dumps({"source_sha256": digest(source), "questions": parse(source)},
                         ensure_ascii=False).replace("<", "\\u003c")
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(HTML.replace("__PAYLOAD__", payload), encoding="utf-8")


def apply_decisions(source: str, document: dict) -> tuple[str, list[dict]]:
    if not isinstance(document, dict):
        raise ValueError("Ожидается объект JSON с решениями")
    if document.get("schema") != 1 or document.get("source_sha256") != digest(source):
        raise ValueError("Версия анкеты не совпадает с текущим банком: создайте свежую анкету")
    rows = {r["id"]: r for r in parse(source)}
    decisions = document.get("decisions")
    if not isinstance(decisions, list):
        raise ValueError("Не найден список решений")
    seen, dropped = set(), []
    for entry in decisions:
        if not isinstance(entry, dict) or entry.get("id") not in rows or entry["id"] in seen:
            raise ValueError("Неизвестный или повторный id вопроса")
        seen.add(entry["id"])
        row = rows[entry["id"]]
        if entry.get("question") != row["question"] or entry.get("category") != row["category"]:
            raise ValueError("Текст вопроса в решении изменён")
        if entry.get("choice") not in ("keep", "drop", "pending"):
            raise ValueError("Неизвестное решение")
        if not isinstance(entry.get("reason", ""), str) or len(entry.get("reason", "")) > 4000:
            raise ValueError("Некорректное пояснение")
        if entry["choice"] == "drop":
            dropped.append(row)
    if len(dropped) == len(rows):
        raise ValueError("Нельзя удалить весь банк: игра останется без вопросов")
    drop_ids = {r["id"] for r in dropped}
    match = PATTERN.search(source)
    category, omit, kept = "", False, []
    for line in match[2].splitlines(keepends=True):
        if line.startswith("# "):
            category, omit = line[2:].strip(), False
        elif line.startswith("? "):
            omit = digest(category + "\n" + line[2:].strip()) in drop_ids
        if not omit:
            kept.append(line)
    updated = source[:match.start(2)] + "".join(kept) + source[match.end(2):]
    if len(parse(updated)) != len(rows) - len(dropped):
        raise ValueError("Проверка результата удаления не пройдена")
    return updated, dropped


HTML = r'''<!doctype html><html lang="ru"><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Стиллион — проверка вопросов</title>
<style>
:root{color-scheme:dark;font:17px system-ui;background:#191d22;color:#eee7dc}
body{max-width:1100px;margin:auto;padding:24px}header{position:sticky;top:0;background:#191d22ee;backdrop-filter:blur(12px);padding:12px 0;z-index:2}
h1{font-size:30px;margin:0 0 12px}p{color:#b8babd;line-height:1.5;margin:8px 0}
.toolbar,.buttons{display:flex;gap:8px;flex-wrap:wrap;align-items:center}
button,input,select,textarea{font:inherit;color:inherit;background:#2b3038;border:1px solid #555d69;border-radius:8px;padding:10px 12px}
button{cursor:pointer}button:hover{border-color:#debb6b}button[aria-pressed=true]{border-color:#eacb7d;background:#5c4d2d}
button#save{background:#dfbb69;color:#211b13;font-weight:700}input{flex:1;min-width:180px}
article{margin:16px 0;padding:20px;border:1px solid #414953;border-radius:12px;background:#23272e}
article.keep{border-left:5px solid #7fae88}article.drop{border-left:5px solid #cd8e7e}
.category{font-size:14px;color:#cdb57e}h2{font-size:20px;margin:10px 0 16px}
textarea{display:block;box-sizing:border-box;width:100%;min-height:64px;margin-top:12px;font-size:15px;resize:vertical}
details{color:#bfc3c9;font-size:15px;margin-top:12px}summary{cursor:pointer}pre{white-space:pre-wrap;font:inherit;line-height:1.5}
#summary{font-variant-numeric:tabular-nums}#empty{padding:30px;text-align:center}
</style>
<header><h1>Стиллион · Какие вопросы оставляем?</h1>
<p>Выберите «Оставить» или «Убрать» одним нажатием. Пояснение необязательно. Затем сохраните JSON и отправьте его в чат для применения. Сама анкета игру не меняет.</p>
<div class="toolbar"><input id="search" placeholder="Поиск по вопросу"><select id="category"><option value="">Все категории</option></select><select id="state"><option value="">Все решения</option><option value="pending">Не решено</option><option value="keep">Оставить</option><option value="drop">Убрать</option></select><button id="save">Сохранить результат JSON</button></div>
<p id="summary" role="status"></p></header><main id="questions"></main><p id="empty" hidden>Вопросов по этому фильтру нет.</p>
<script id="data" type="application/json">__PAYLOAD__</script><script>
'use strict';
const data=JSON.parse(document.getElementById('data').textContent), key='stillion-review-'+data.source_sha256;
let decisions={};try{const saved=JSON.parse(localStorage.getItem(key)||'{}');if(saved&&typeof saved==='object'&&!Array.isArray(saved))decisions=saved}catch(e){}
const root=document.getElementById('questions'), search=document.getElementById('search'), category=document.getElementById('category'), state=document.getElementById('state');
for(const cat of new Set(data.questions.map(q=>q.category))){const o=document.createElement('option');o.value=cat;o.textContent=cat;category.append(o)}
function choice(id){const c=decisions[id]?.choice;return ['keep','drop'].includes(c)?c:'pending'}
function store(){try{localStorage.setItem(key,JSON.stringify(decisions))}catch(e){}update()}
function update(){const counts={keep:0,drop:0,pending:0};for(const q of data.questions)counts[choice(q.id)]++;document.getElementById('summary').textContent=`Всего ${data.questions.length} · Оставить: ${counts.keep} · Убрать: ${counts.drop} · Не решено: ${counts.pending}`}
function render(){root.replaceChildren();for(const q of data.questions){if(category.value&&q.category!==category.value)continue;if(state.value&&choice(q.id)!==state.value)continue;if(search.value&&!q.question.toLocaleLowerCase('ru').includes(search.value.toLocaleLowerCase('ru')))continue;
 const article=document.createElement('article');article.className=choice(q.id);const cat=document.createElement('div');cat.className='category';cat.textContent=q.category;article.append(cat);
 const title=document.createElement('h2');title.textContent=q.question;article.append(title);const buttons=document.createElement('div');buttons.className='buttons';
 for(const [value,label]of[['keep','Оставить'],['drop','Убрать'],['pending','Пока не решил']]){const b=document.createElement('button');b.textContent=label;b.setAttribute('aria-pressed',choice(q.id)===value);b.onclick=()=>{decisions[q.id]={choice:value,reason:decisions[q.id]?.reason||''};store();render()};buttons.append(b)}article.append(buttons);
 const note=document.createElement('textarea');note.placeholder='Почему? (необязательно)';note.maxLength=4000;note.setAttribute('aria-label','Пояснение: '+q.question);note.value=decisions[q.id]?.reason||'';note.oninput=()=>{decisions[q.id]={choice:choice(q.id),reason:note.value};store()};article.append(note);
 const details=document.createElement('details'),summary=document.createElement('summary'),answers=document.createElement('pre');summary.textContent='Известные ответы';answers.textContent=q.answers.join('\n');details.append(summary,answers);article.append(details);root.append(article)}document.getElementById('empty').hidden=root.childElementCount>0;update()}
for(const input of[search,category,state])input.addEventListener('input',render);
document.getElementById('save').onclick=()=>{const payload={schema:1,source_sha256:data.source_sha256,decisions:data.questions.map(q=>({id:q.id,category:q.category,question:q.question,choice:choice(q.id),reason:decisions[q.id]?.reason||''}))};const url=URL.createObjectURL(new Blob([JSON.stringify(payload,null,2)],{type:'application/json'}));const link=document.createElement('a');link.href=url;link.download='stillion_question_decisions.json';link.click();setTimeout(()=>URL.revokeObjectURL(url),1000)};render();
</script></html>'''


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=["generate", "apply"])
    parser.add_argument("decisions", nargs="?", type=Path)
    parser.add_argument("--source", type=Path, default=SOURCE)
    parser.add_argument("--output", type=Path, default=ROOT / "build/stillion_questions_review.html")
    parser.add_argument("--apply", action="store_true", dest="write")
    args = parser.parse_args()
    source = args.source.read_text(encoding="utf-8")
    if args.command == "generate":
        generate(source, args.output)
        print(f"Анкета: {args.output}; вопросов: {len(parse(source))}")
    else:
        if args.decisions is None:
            parser.error("Укажите файл JSON с решениями")
        document = json.loads(args.decisions.read_text(encoding="utf-8"))
        updated, dropped = apply_decisions(source, document)
        print(f"Будет удалено: {len(dropped)}; останется: {len(parse(updated))}")
        for row in dropped:
            print(f"- {row['question']}")
        if args.write and dropped:
            backup = ROOT / "backups" / ("st_question_review_" + datetime.now().strftime("%Y%m%d_%H%M%S"))
            backup.mkdir(parents=True, exist_ok=False)
            (backup / ".gdignore").touch()
            (backup / args.source.name).write_text(source, encoding="utf-8")
            args.source.write_text(updated, encoding="utf-8")
            print(f"Применено. Копия: {backup}")
        else:
            print("Файлы игры не изменены; для применения добавьте --apply")


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")
    main()
