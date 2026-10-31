#class_name ignore
extends SceneTree

const Guard := preload("res://addons/gd-guard/guard.gd")


func _init() -> void:
	var failures := _run()
	if failures.is_empty():
		print("gd-guard tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("gd-guard tests failed: %d" % failures.size())
	quit(1)


func _run() -> PackedStringArray:
	var failures: PackedStringArray = []
	_expect_messages(failures)
	_expect_format(failures)
	_check(failures, "same-script private state", _fixture("""
		class_name Class1
		var _amount: int = 0
		var amount: int:
			get:
				return _amount
	"""), [])
	_check(failures, "public and same-script access", _fixture("""
		class_name Foo
		extends Node
		var _amount := 0
		func _ready() -> void:
			_amount = 1
			self._amount = 2
			print(_amount)
			print(self._amount)
			print(class_1.amount)
			super._ready()
			super._init()
	"""), [])
	_check(failures, "cross-script private var and func", _fixture("""
		class_name Class2
		extends Node
		@export var class_1: Class1
		func _ready() -> void:
			print(class_1._amount)
			class_1._amount = 10
			print(class_1.amount)
			class_1._do_thing()
	"""), [
		{"line": 5, "message": Guard.MESSAGE_PRIVATE},
		{"line": 6, "message": Guard.MESSAGE_PRIVATE},
		{"line": 8, "message": Guard.MESSAGE_PRIVATE},
	])
	_check(failures, "indirect receivers", _fixture("""
		class_name Foo
		extends Node
		func _ready() -> void:
			print(node.get_child(0)._amount)
			print(%MySprite._amount)
			print(Class1._amount)
			print(self.foo._bar)
	"""), [
		{"line": 4, "message": Guard.MESSAGE_PRIVATE},
		{"line": 5, "message": Guard.MESSAGE_PRIVATE},
		{"line": 6, "message": Guard.MESSAGE_PRIVATE},
		{"line": 7, "message": Guard.MESSAGE_PRIVATE},
	])
	_check(failures, "strings and comments hide private access", _fixture("""
		class_name Foo
		extends Node
		func _ready() -> void:
			print("class_1._amount")
			print(1.0)
		# class_1._amount
	"""), [])
	_check(failures, "string get and set are out of scope", _fixture("""
		class_name Foo
		extends Node
		func _ready() -> void:
			class_1.set("_amount", 10)
			print(class_1.get("_amount"))
	"""), [])
	_check(failures, "continued self and super stay private", _fixture("""
		class_name Foo
		extends Node
		func _ready() -> void:
			print(self\\
				._amount)
			super\\
				._ready()
	"""), [])
	_check(failures, "continued external access", _fixture("""
		class_name Foo
		extends Node
		func _ready() -> void:
			print(other\\
				._hidden)
	"""), [
		{"line": 5, "message": Guard.MESSAGE_PRIVATE},
	])
	_check(failures, "crlf private access", "extends Node\r\nfunc _ready() -> void:\r\n\tprint(other._value)\r\n", [
		{"line": 1, "message": Guard.MESSAGE_CLASS_NAME},
		{"line": 3, "message": Guard.MESSAGE_PRIVATE},
	])
	_check(failures, "class_name present", _fixture("""
		class_name Class1
		extends Node
	"""), [])
	_check(failures, "class_name omitted", _fixture("""
		extends Node
	"""), [
		{"line": 1, "message": Guard.MESSAGE_CLASS_NAME},
	])
	_check(failures, "class_name ignore comment", _fixture("""
		#class_name ignore
		extends Node
	"""), [])
	_check(failures, "class_name ignore comment with space", _fixture("""
		# class_name ignore
		extends Node
	"""), [])
	_check(failures, "class_name keyword in a comment", _fixture("""
		# class_name Class1
		extends Node
	"""), [
		{"line": 1, "message": Guard.MESSAGE_CLASS_NAME},
	])
	_check(failures, "ignore marker must be its own word", _fixture("""
		#class_name ignore_me
		extends Node
	"""), [
		{"line": 1, "message": Guard.MESSAGE_CLASS_NAME},
	])
	_check(failures, "ignore marker must lead the comment", _fixture("""
		extends Node
		# note: class_name ignore
	"""), [
		{"line": 1, "message": Guard.MESSAGE_CLASS_NAME},
	])
	_check(failures, "strings do not satisfy class_name", _fixture('''
		extends Node
		func _ready() -> void:
			print("class_name")
			print("#class_name ignore")
			var text := """
		class_name Fake
		obj._amount
		@onready var x = $Node
		#class_name ignore
		"""
	'''), [
		{"line": 1, "message": Guard.MESSAGE_CLASS_NAME},
	])
	_check(failures, "dollar node path", _fixture("""
		class_name Foo
		extends Node
		@onready var _sprite: Sprite2D = $ParentNode/MySprite
	"""), [
		{"line": 3, "message": Guard.MESSAGE_ONREADY},
	])
	_check(failures, "unique name", _fixture("""
		class_name Foo
		extends Node
		@onready var _sprite: Sprite2D = %MySprite
	"""), [])
	_check(failures, "quoted dollar path", _fixture("""
		class_name Foo
		extends Node
		@onready var _sprite: Sprite2D = $"Parent/MySprite"
	"""), [
		{"line": 3, "message": Guard.MESSAGE_ONREADY},
	])
	_check(failures, "annotations above the variable", _fixture("""
		class_name Foo
		extends Node
		@export_range(0, 10, 1)
		@export
		@onready
		var _sprite: Sprite2D = $Parent/MySprite
	"""), [
		{"line": 6, "message": Guard.MESSAGE_ONREADY},
	])
	_check(failures, "parenthesized initializer", _fixture("""
		class_name Foo
		extends Node
		@onready var _sprite: Sprite2D = (
			$Parent/MySprite
		)
	"""), [
		{"line": 4, "message": Guard.MESSAGE_ONREADY},
	])
	_check(failures, "dollar elsewhere is allowed", _fixture("""
		class_name Foo
		extends Node
		func _ready() -> void:
			var _sprite := $Parent/MySprite
			print(%MySprite)
		var _other = $Parent
		@onready
		func _enter_tree() -> void:
			pass
		var _later = $Later
	"""), [])
	_check(failures, "get_node and text are not dollar paths", _fixture("""
		class_name Foo
		extends Node
		@onready var _sprite: Sprite2D = get_node("Parent/MySprite")
		@onready var _text: String = "path $Node"
		@onready var _label: Sprite2D = %MySprite # was $Parent/MySprite
	"""), [])
	_check(failures, "only the dollar initializer warns", _fixture("""
		class_name Foo
		extends Node
		@onready var _a: Node = %A
		@onready var _b: Node = $B
	"""), [
		{"line": 4, "message": Guard.MESSAGE_ONREADY},
	])
	_check(failures, "first dollar in an initializer", _fixture("""
		class_name Foo
		extends Node
		@onready var _n: Node = $A if true else $B
	"""), [
		{"line": 3, "message": Guard.MESSAGE_ONREADY},
	])
	_check(failures, "all three rules", _fixture("""
		extends Node
		@onready var _sprite: Sprite2D = $Parent/MySprite
		func _ready() -> void:
			print(other._amount)
	"""), [
		{"line": 1, "message": Guard.MESSAGE_CLASS_NAME},
		{"line": 2, "message": Guard.MESSAGE_ONREADY},
		{"line": 4, "message": Guard.MESSAGE_PRIVATE},
	])
	_check(failures, "camelCase and PascalCase names", _fixture("""
		class_name Foo
		var playerHealth := 1
		var PlayerHealth := 2
		var HEALTH := 3
		static var player_Health := 4
		func takeDamage(playerHealth: int) -> void:
			for playerIndex in playerHealth:
				pass
		func TakeDamage() -> void:
			pass
		func _takeDamage() -> void:
			pass
		class Inner:
			var playerHealth := 1
	"""), [
		{"line": 2, "message": Guard.MESSAGE_SNAKE_CASE},
		{"line": 3, "message": Guard.MESSAGE_SNAKE_CASE},
		{"line": 4, "message": Guard.MESSAGE_SNAKE_CASE},
		{"line": 5, "message": Guard.MESSAGE_SNAKE_CASE},
		{"line": 6, "message": Guard.MESSAGE_SNAKE_CASE},
		{"line": 6, "message": Guard.MESSAGE_SNAKE_CASE},
		{"line": 7, "message": Guard.MESSAGE_SNAKE_CASE},
		{"line": 9, "message": Guard.MESSAGE_SNAKE_CASE},
		{"line": 11, "message": Guard.MESSAGE_SNAKE_CASE},
		{"line": 14, "message": Guard.MESSAGE_SNAKE_CASE},
	])
	_check(failures, "multiline parameters", _fixture("""
		class_name Foo
		func take_damage(
			playerHealth: int,
			otherName: String = "x",
		) -> void:
			pass
	"""), [
		{"line": 3, "message": Guard.MESSAGE_SNAKE_CASE},
		{"line": 4, "message": Guard.MESSAGE_SNAKE_CASE},
	])
	_check(failures, "setter parameter", _fixture("""
		class_name Foo
		var health:
			set(newValue):
				health = newValue
	"""), [
		{"line": 3, "message": Guard.MESSAGE_SNAKE_CASE},
	])
	_check(failures, "lambda parameter", _fixture("""
		class_name Foo
		func _ready() -> void:
			items.map(func(playerHealth): return playerHealth)
	"""), [
		{"line": 3, "message": Guard.MESSAGE_SNAKE_CASE},
	])
	_check(failures, "lambda parameter in a default", _fixture("""
		class_name Foo
		func connect_handler(callback := func(playerHealth: int) -> void:
			pass
		) -> void:
			pass
	"""), [
		{"line": 2, "message": Guard.MESSAGE_SNAKE_CASE},
	])
	_check(failures, "func named set warns once", _fixture("""
		class_name Foo
		func set(newValue: int) -> void:
			pass
	"""), [
		{"line": 2, "message": Guard.MESSAGE_SNAKE_CASE},
	])
	_check(failures, "continued var name", _fixture("""
		class_name Foo
		var \\
			playerHealth := 1
	"""), [
		{"line": 3, "message": Guard.MESSAGE_SNAKE_CASE},
	])
	_check(failures, "snake_case names stay quiet", _fixture("""
		class_name Player
		const MaxHealth := 10
		signal healthChanged(newHealth: int)
		enum State { Idle, Running }
		var _player_health: Node2D = %MySprite
		func take_damage(node: Node2D, items: Array[Item], data: Dictionary[String, int] = {}, other: Foo.Bar = null) -> Sprite2D:
			for index in items:
				node.set(newValue)
			var _unused := 1
		var health:
			set(new_value):
				health = new_value
	"""), [])
	_check(failures, "strings and comments hide camelCase", _fixture("""
		class_name Foo
		func _ready() -> void:
			print("var playerHealth")
			print("func takeDamage")
		# var playerHealth
		# func takeDamage():
	"""), [])
	_check(failures, "onready dollar and camelCase var", _fixture("""
		class_name Foo
		extends Node
		@onready var playerHealth: Sprite2D = $Parent/MySprite
	"""), [
		{"line": 3, "message": Guard.MESSAGE_ONREADY},
		{"line": 3, "message": Guard.MESSAGE_SNAKE_CASE},
	])
	return failures


func _expect_messages(failures: PackedStringArray) -> void:
	if Guard.MESSAGE_PRIVATE != "_ prefixed var or func accessed publicly":
		failures.append("private message mismatch")
	if Guard.MESSAGE_CLASS_NAME != "class_name omitted":
		failures.append("class_name message mismatch")
	if Guard.MESSAGE_ONREADY != "Node tree access by $ instead of %":
		failures.append("onready message mismatch")
	if Guard.MESSAGE_SNAKE_CASE != "var or func name is not snake_case":
		failures.append("snake_case message mismatch")


func _expect_format(failures: PackedStringArray) -> void:
	var formatted := Guard.format_warning("res://scripts/class_2.gd", {
		"line": 4,
		"message": Guard.MESSAGE_CLASS_NAME,
	})
	var expected := "res://scripts/class_2.gd:4 - gd-guard - class_name omitted"
	if formatted != expected:
		failures.append("format: expected '%s', got '%s'" % [expected, formatted])


func _check(failures: PackedStringArray, label: String, source: String, expected: Array) -> void:
	var actual := Guard.scan(source)
	if actual.size() != expected.size():
		failures.append("%s: expected %d findings [%s], got %d [%s]" % [
			label,
			expected.size(),
			_show(expected),
			actual.size(),
			_show(actual),
		])
		return
	for index in expected.size():
		var want: Dictionary = expected[index]
		var got: Dictionary = actual[index]
		if int(got["line"]) != int(want["line"]) or String(got["message"]) != String(want["message"]):
			failures.append("%s: finding %d expected %d:%s, got %d:%s" % [
				label,
				index,
				int(want["line"]),
				String(want["message"]),
				int(got["line"]),
				String(got["message"]),
			])


func _show(findings: Array) -> String:
	var parts: PackedStringArray = []
	for finding in findings:
		var item: Dictionary = finding
		parts.append("%d:%s" % [int(item["line"]), String(item["message"])])
	return " | ".join(parts)


func _fixture(body: String) -> String:
	var lines := body.split("\n")
	if not lines.is_empty() and lines[0].is_empty():
		lines.remove_at(0)
	if not lines.is_empty() and lines[-1].strip_edges().is_empty():
		lines.remove_at(lines.size() - 1)
	var prefix := ""
	for line in lines:
		if line.strip_edges().is_empty():
			continue
		prefix = line.substr(0, line.length() - line.lstrip(" \t").length())
		break
	var out: PackedStringArray = []
	for line in lines:
		if not prefix.is_empty() and line.begins_with(prefix):
			out.append(line.substr(prefix.length()))
		else:
			out.append(line)
	return "\n".join(out)
