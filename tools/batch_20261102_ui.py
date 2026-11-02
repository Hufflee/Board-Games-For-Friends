"""Однократная правка ограниченных фрагментов UI пакета 02.11."""
from pathlib import Path

def edit(path, old, new):
    p = Path(path)
    text = p.read_text(encoding='utf-8-sig')
    assert old in text, path
    p.write_text(text.replace(old, new, 1), encoding='utf-8')

p = Path('games/word_slam/ui/ws_table.gd')
s = p.read_text(encoding='utf-8-sig')
s = s.replace('\t\t\t\t_show_roll(int(v["roll"]))', '\t\t\t\t_rolling = false')
start = s.index('\tvar card: Dictionary = _v["card"]', s.index('func _update_word_panel'))
end = s.index('\tvar col := HCStyle.vbox(0)', start)
s = s[:start] + s[end:]
start = s.index('\tvar words := HCStyle.vbox(0)', s.index('func _update_word_panel'))
end = s.index('\tif phase == "word":', start)
s = s[:start] + '\tcol.size_flags_horizontal = Control.SIZE_EXPAND_FILL\n' + s[end:]
p.write_text(s, encoding='utf-8')

p = Path('games/word_slam/ui/ws_lobby.gd')
s = p.read_text(encoding='utf-8-sig')
start = s.index('\t\tvar names := CheckBox.new()')
end = s.index('\t\t_body.add_child(r2)', start)
s = s[:start] + s[end:]
s = s.replace('"%s · %d карт · %s%s"', '"%s · %d карт · %s"').replace(', " · с именами" if s.get("ws_names", true) else ""', '')
p.write_text(s, encoding='utf-8')

edit('games/word_slam/ui/ws_app.gd',
     '[b]Слово.[/b] Рассказчики видят карту из 6 слов, кубик выбирает одно (6 — «имя»: фильм, книга, человек). Один из рассказчиков (по очереди) может перебросить, если слово незнакомое.',
     '[b]Слово.[/b] Рассказчики получают одно случайное слово из общего словаря 1000 слов без имён собственных. Один из рассказчиков (по очереди) может заменить его другим случайным словом, если оно незнакомое.')

p = Path('games/phantom_ink/ui/pi_table.gd')
s = p.read_text(encoding='utf-8-sig')
start = s.index('\tif int(_v.object_card) >= 0:')
end = s.index('\tif phase == "game_over":', start)
s = s[:start] + '''\tvar object_words: Array = _v.get("object_words", [])
\tif not object_words.is_empty():
\t\t_note(col, "СЛОВА ДУХОВ")
\t\tfor i in object_words.size():
\t\t\tvar marks := PackedStringArray()
\t\t\tvar votes: Array = _v.get("votes", [])
\t\t\tfor t in votes.size():
\t\t\t\tif int(votes[t]) == i:
\t\t\t\t\tmarks.append("☀" if t == 0 else "☾")
\t\t\tvar label := "%d. %s  %s" % [i + 1, str(object_words[i]), " ".join(marks)]
\t\t\tif phase == "object":
\t\t\t\tvar choice := _button(col, label, "object", i)
\t\t\t\tif votes.size() == 2 and int(votes[int(int(_v.role) / 2)]) == i:
\t\t\t\t\tchoice.theme_type_variation = "PrimaryButton"
\t\t\telif i == int(_v.object_slot):
\t\t\t\t_note(col, "Тайное слово: " + str(object_words[i]))
''' + s[end:]
start = s.index('\t\t\tvar row := PIStyle.hbox(4)', s.index('\t\t"object":'))
end = s.index('\t\t"eye":', start)
s = s[:start] + s[end:]
p.write_text(s, encoding='utf-8')

edit('games/phantom_ink/ui/pi_app.gd', 'Духи видят одну карту предметов и согласуют номер слова.', 'Духи видят шесть случайных слов из общего словаря и выбирают одно; голоса обоих духов видны только им.')
