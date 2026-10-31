extends RefCounted
## 试玩地图清单与场景切换的公共数据（CodeBuddyPro，2026-10-28）。
##
## 只读 data/scene_menu.json，不持有节点；地图选择界面、切换组件、地图内返回钩子共用这一份。
## 用 preload 调用静态方法（不加 class_name，避免全局类缓存没刷新时取不到）：
##   const DATA = preload("res://scripts/ui/scene_menu_data.gd")
##   DATA.maps() / DATA.find_map("combat_mvp") / DATA.menu_scene_path()

const CONFIG_PATH: String = "res://data/scene_menu.json"
const DEFAULT_MENU_SCENE: String = "res://scenes/ui/map_select.tscn"
## 默认返回键用字母 B（Back），不要用 F1–F12：用户键盘没有功能键。
const DEFAULT_RETURN_KEY: String = "B"
## 地图内返回钩子的节点名（挂在 root 下，切场景不会跟着释放）。
const RETURN_HOOK_NAME: String = "SceneReturnHook"

static var _config: Dictionary = {}
static var _loaded: bool = false


static func config() -> Dictionary:
	if _loaded:
		return _config
	_loaded = true
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
	if parsed is Dictionary:
		_config = parsed as Dictionary
	else:
		push_error("试玩地图清单读取失败：%s" % CONFIG_PATH)
		_config = {}
	return _config


## 地图清单，每项含 id / name / kind / kind_label / status / description / scene。
static func maps() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry: Variant in config().get("maps", []):
		if entry is Dictionary:
			result.append(entry as Dictionary)
	return result


static func find_map(map_id: String) -> Dictionary:
	for entry: Dictionary in maps():
		if str(entry.get("id", "")) == map_id:
			return entry
	return {}


static func menu_scene_path() -> String:
	return str(config().get("menu_scene", DEFAULT_MENU_SCENE))


static func session_notice() -> String:
	return str(config().get("session_notice", ""))


static func return_key_name() -> String:
	return str(config().get("return_key", DEFAULT_RETURN_KEY))


## 只支持单个字母（A–Z）与 Backspace：本项目不再用 F1–F12（用户键盘没有功能键），
## Tab / Esc 留给各图自己的背包与暂停。默认 B，避开 WASD / 数字键 / R / E / V 等已用键位。
static func return_keycode() -> int:
	var label: String = return_key_name().strip_edges().to_upper()
	if label == "BACKSPACE":
		return KEY_BACKSPACE
	if label.length() == 1:
		var letter: int = label.unicode_at(0)
		if letter >= 65 and letter <= 90:
			return KEY_A + (letter - 65)
	return KEY_B


## 加载地图场景；失败返回 null，原因用 failure_reason() 取。
static func load_scene(scene_path: String) -> PackedScene:
	if scene_path.is_empty():
		return null
	if not ResourceLoader.exists(scene_path):
		return null
	var resource: Resource = ResourceLoader.load(scene_path, "PackedScene", ResourceLoader.CACHE_MODE_REUSE)
	return resource as PackedScene


static func failure_reason(scene_path: String) -> String:
	if scene_path.is_empty():
		return "这张地图没有配置场景路径"
	if not ResourceLoader.exists(scene_path):
		return "找不到场景文件：%s" % scene_path
	if not scene_path.ends_with(".tscn") and not scene_path.ends_with(".scn"):
		return "配置的不是场景文件：%s" % scene_path
	return "场景加载失败：%s" % scene_path
