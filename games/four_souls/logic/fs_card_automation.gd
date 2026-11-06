extends RefCounted
const Tarot := preload("res://games/four_souls/logic/fs_tarot_cards.gd")
const Runes := preload("res://games/four_souls/logic/fs_rune_cards.gd")
const Consumables := preload("res://games/four_souls/logic/fs_consumable_cards.gd")
const Trinkets := preload("res://games/four_souls/logic/fs_trinket_cards.gd")
const Treasures := preload("res://games/four_souls/logic/fs_treasure_cards.gd")
const Active := preload("res://games/four_souls/logic/fs_active_cards.gd")
const Monster20 := preload("res://games/four_souls/logic/fs_monster20_cards.gd")
const Packet21 := preload("res://games/four_souls/logic/fs_packet21_cards.gd")
const Packet22 := preload("res://games/four_souls/logic/fs_packet22_cards.gd")
const Packet24 := preload("res://games/four_souls/logic/fs_packet24_cards.gd")
const Packet25 := preload("res://games/four_souls/logic/fs_packet25_cards.gd")
const Packet26 := preload("res://games/four_souls/logic/fs_packet26_cards.gd")
const Packet27 := preload("res://games/four_souls/logic/fs_packet27_cards.gd")
const Packet28 := preload("res://games/four_souls/logic/fs_packet28_cards.gd")
const Treasure20 := preload("res://games/four_souls/logic/fs_treasure20_cards.gd")
const Wildcard20 := preload("res://games/four_souls/logic/fs_wildcard20_cards.gd")
const Monster19 := preload("res://games/four_souls/logic/fs_monster19_cards.gd")
const Monster18 := preload("res://games/four_souls/logic/fs_monster18_cards.gd")
const Monster17 := preload("res://games/four_souls/logic/fs_monster17_cards.gd")
const Monster16 := preload("res://games/four_souls/logic/fs_monster16_cards.gd")
const Packet15 := preload("res://games/four_souls/logic/fs_packet15_cards.gd")
const Treasure14 := preload("res://games/four_souls/logic/fs_treasure14_cards.gd")
const Treasure13 := preload("res://games/four_souls/logic/fs_treasure13_cards.gd")
const Treasure12 := preload("res://games/four_souls/logic/fs_treasure12_cards.gd")
const Encounters := preload("res://games/four_souls/logic/fs_encounter_cards.gd")
const Secondary := preload("res://games/four_souls/logic/fs_secondary_cards.gd")
## РџРѕСЃР»РµРґРѕРІР°С‚РµР»СЊРЅРѕСЃС‚Рё СЌС„С„РµРєС‚РѕРІ РїРѕ РїСЂРѕРІРµСЂРµРЅРЅС‹Рј С‚РµРєСЃС‚Р°Рј card_texts.json.
## Р’С‹Р±РѕСЂ СЃРѕРґРµСЂР¶РёС‚ С‚РёРї РґРѕРїСѓСЃС‚РёРјС‹С… С†РµР»РµР№; С‡РёСЃР»Р° Рё РѕРїРµСЂР°С†РёРё РїСЂРёС…РѕРґСЏС‚ С‚РѕР»СЊРєРѕ РёР· СЌС‚РѕРіРѕ СЂРµРµСЃС‚СЂР°.
const BATCH_01 := [40, 120, 199, 476, 506, 544, 700, 703, 719, 727, 730, 716, 395, 414, 417, 424, 369, 822, 828, 834]
const BATCH_03 := [497, 498, 499, 541, 512, 507, 508, 509, 510, 511, 515, 516, 517, 524, 525, 554, 531, 532, 542, 501]
const BATCH_04 := [567, 572, 573, 574, 643, 644, 645, 646, 655, 656, 657, 658, 659, 660, 661, 663, 664, 665, 650, 662]
const REROLL_LOOT := [515, 516, 517, 574, 663, 664, 665]
const CANCEL_LOOT := [509, 510, 511, 573, 659, 660, 661]

static func handles(effect: Dictionary) -> bool:
	var id: int = int(effect.get("card", -1))
	if id in Packet28.IDS:
		return (effect.get("kind", "") == "event" and id in Packet28.EVENTS) or (effect.get("kind", "") == "item" and effect.has("automation_context"))
	if id in Packet26.ITEMS or id in Packet27.ITEMS or id in [848, 882]:
		return effect.get("kind", "") == "item"
	if id in Packet25.ROOMS or id in Packet25.ITEMS:
		return effect.get("kind", "") == "item" and (id in Packet25.ITEMS or effect.has("automation_context"))
	if id in Packet24.BONUSES or id in Packet24.EVENTS or id in Packet24.ROOMS:
		return effect.get("kind", "") == "event" or (effect.get("kind", "") == "item" and effect.has("automation_context"))
	if id in Packet22.IDS:
		return effect.get("kind", "") == "loot" or (effect.get("kind", "") == "item" and effect.has("automation_context"))
	if id in Packet21.IDS:
		return effect.get("kind", "") == "loot" or effect.get("kind", "") == "item"
	if id in Wildcard20.IDS:
		return effect.get("kind", "") == "loot" or (effect.get("kind", "") == "item" and effect.has("automation_context"))
	if id in Treasure20.IDS:
		return effect.get("kind", "") == "item" and (effect.has("automation_context") or id in Treasure20.ACTIVATED)
	if id in Monster20.IDS:
		return effect.get("kind", "") == "item" and effect.has("automation_context")
	if id in Monster19.IDS:
		return effect.get("kind", "") == "item" and effect.has("automation_context")
	if id in Monster18.IDS:
		return effect.get("kind", "") == "item" and effect.has("automation_context")
	if id in Monster17.IDS:
		return effect.get("kind", "") == "item" and effect.has("automation_context")
	if id in Monster16.IDS or id in [913, 914]:
		return effect.get("kind", "") == "item" and effect.has("automation_context")
	if id in Packet15.IDS:
		return effect.get("kind", "") == "item" and (effect.has("automation_context") or id in Packet15.ACTIVATED)
	if id in Treasure14.IDS:
		return effect.get("kind", "") == "item" and (effect.has("automation_context") or id in Treasure14.ACTIVATED)
	if id in Treasure13.IDS:
		return effect.get("kind", "") == "item" and (effect.has("automation_context") or id in Treasure13.ACTIVATED)
	if id in Treasure12.IDS:
		return effect.get("kind", "") == "item" and (effect.has("automation_context") or id in Treasure12.ACTIVATED)
	if id in Encounters.IDS:
		return effect.get("kind", "") == "event" or (effect.get("kind", "") == "item" and effect.has("automation_context"))
	if id in Secondary.IDS:
		return effect.get("kind", "") == "item" and (effect.has("automation_context") or id in Secondary.ACTIVATED)
	if id in Active.IDS:
		return effect.get("kind", "") == "item" and (effect.has("automation_context") or id in Active.ACTIVATED)
	if id in Treasures.IDS:
		return effect.get("kind", "") == "item" and (effect.has("automation_context") or id in [38, 69, 77])
	if id in Trinkets.IDS and effect.has("automation_context"):
		return effect.get("kind", "") == "item"
	if id in BATCH_03 or id in BATCH_04 or id in Tarot.IDS or id in Runes.IDS or id in Consumables.IDS:
		return effect.get("kind", "") == "loot"
	if id not in BATCH_01:
		return false
	return str(effect.get("kind", "")) == ("reward" if id in [395, 414, 417, 424, 369] else "event" if id in [700, 703, 719, 727, 730, 716] else "loot" if id in [476, 506, 544] else "item") and not bool(effect.get("conditional", false))

static func op(name: String, amount: int = 1) -> Dictionary:
	return {"op": name, "amount": amount}

static func choose(name: String, targets: String, amount: int = 1, optional: bool = false) -> Dictionary:
	return {"op": name, "targets": targets, "amount": amount, "optional": optional}

static func plan(id: int, context: String = "") -> Array:
	if id in Packet28.IDS:
		return Packet28.plan(id, context)
	if id in Packet27.ITEMS and not context.begins_with("loot_cost26/"):
		return Packet27.plan(id, context)
	if id in Packet26.ITEMS or id in Packet27.ITEMS or id in [848, 882]:
		return Packet26.plan(id, context)
	if id in Packet25.ROOMS or id in Packet25.ITEMS:
		return Packet25.plan(id, context)
	if id in Packet24.BONUSES or id in Packet24.EVENTS or id in Packet24.ROOMS:
		return Packet24.plan(id, context)
	if id in Packet22.IDS:
		return Packet22.plan(id, context)
	if id in Packet21.IDS:
		return Packet21.plan(id, context)
	if id in Wildcard20.IDS:
		return Wildcard20.plan(id, context)
	if id in Treasure20.IDS:
		return Treasure20.plan(id, context)
	if id in Monster20.IDS:
		return Monster20.plan(id, context)
	if id in Monster19.IDS:
		return Monster19.plan(id, context)
	if id in Monster18.IDS:
		return Monster18.plan(id, context)
	if id in Monster17.IDS:
		return Monster17.plan(id, context)
	if id in Monster16.IDS or id in [913, 914]:
		return Monster16.plan(id, context)
	if id in Packet15.IDS:
		return Packet15.plan(id, context)
	if id in Treasure14.IDS:
		return Treasure14.plan(id, context)
	if id in Treasure13.IDS:
		return Treasure13.plan(id, context)
	if id in Treasure12.IDS:
		return Treasure12.plan(id, context)
	if id in Encounters.IDS:
		return Encounters.plan(id, context)
	if id in Secondary.IDS:
		return Secondary.plan(id, context)
	if id in Active.IDS:
		return Active.plan(id, context)
	if id in Treasures.IDS:
		return Treasures.plan(id, context)
	if id in Trinkets.IDS:
		return Trinkets.plan(id, context)
	if id in Consumables.IDS:
		return Consumables.plan(id)
	if id in Runes.IDS:
		return Runes.plan(id)
	if id in Tarot.IDS:
		return Tarot.plan(id)
	if id == 40 and context == "turn_end":
		return [choose("recharge", "items", 1, true)]
	match id:
		497, 498, 499, 541, 567, 643, 644, 645, 646: return [choose("damage", "damage_targets")]
		512: return [choose("damage", "damage_targets", 2)]
		650: return [choose("damage", "damage_targets", 3)]
		507, 508, 572, 655, 656, 657, 658: return [choose("recharge", "items")]
		662: return [choose("recharge_all", "players")]
		509, 510, 511, 573, 659, 660, 661: return [choose("cancel_selected", "cancelable_cards")]
		515, 516, 517, 574, 663, 664, 665: return [choose("reroll", "rolls")]
		524, 525, 554: return [choose("prevent_damage", "players")]
		531, 532: return [choose("black_heart", "players")]
		542: return [choose("double_coins", "players")]
		501: return [choose("spades_loot", "other_players")]
		40: return [op("ready_character")]
		120: return [op("auto_roll"), op("fruit_result")]
		199: return [op("destroy_self"), choose("steal_soul", "other_souls")]
		476: return [op("coins"), op("auto_roll")]
		506: return [op("auto_roll"), op("sticky_result")]
		544: return [op("coins"), choose("recharge", "items")]
		700, 703, 719, 727, 730: return [op("auto_roll"), op("event_result")]
		716: return [choose("lose_all_coins", "richest")]
		395: return [op("skip_turn")]
		414: return [op("discard_slayer_hand")]
		417: return [choose("peek_hand", "players", 1, true), op("read_peek")]
		424: return [op("expand_monsters")]
		369: return [op("damage_all")]
		822: return [choose("reroll", "rolls")]
		828: return [choose("roll", "roll_modifiers")]
		834: return [choose("temporary_attack", "combatants")]
	return []
