extends "res://scripts/mvp/loot_drop.gd"
class_name FishingPickup
## 旧钓鱼拾取入口（combat_arena 每帧驱动版），现在只是 LootDrop 的薄壳：
## 视觉、数量与防重复逻辑都在 LootDrop，这里关掉自动拾取，保持原有
## setup / player_inside / set_amount 调用方式不变，避免两套实现各写一半。
##
## 新系统请直接用 LootDrop.spawn(...) 或 loot.grant(...)，不要再用本类。


func setup(loot_item: String, loot_amount: int) -> void:
	auto_collect = false
	super.setup(loot_item, loot_amount)
