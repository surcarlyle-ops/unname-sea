extends Node
## 测试用 HUD 替身：只记录 push_message，证明「背包已满」提示不阻塞、不吞信息。

var messages: Array[String] = []


func push_message(message: String) -> void:
	messages.append(message)
