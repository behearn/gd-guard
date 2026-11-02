@tool
class_name GdGuard
extends RefCounted

const MESSAGE_PRIVATE := "_ prefixed var or func accessed publicly"
const MESSAGE_CLASS_NAME := "class_name omitted"
const MESSAGE_ONREADY := "Node tree access by $ instead of %"
const MESSAGE_SNAKE_CASE := "var or func name is not snake_case"

enum Kind {
	NEWLINE,
	IDENT,
	DOT,
	DOLLAR,
	PERCENT,
	LPAREN,
	RPAREN,
	LBRACKET,
	RBRACKET,
	LBRACE,
	RBRACE,
	AT,
	COMMENT,
	SEMICOLON,
	EQUALS,
	COMMA,
	COLON,
}

static func scan(source: String) -> Array[Dictionary]:
	var tokens := _tokenize(source)
	var findings: Array[Dictionary] = []
	_find_private(tokens, findings)
	_find_class_name(tokens, findings)
	_find_onready(tokens, findings)
	_find_snake_case(tokens, findings)
	findings.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var line_a := int(a["line"])
		var line_b := int(b["line"])
		if line_a != line_b:
			return line_a < line_b
		return int(a["index"]) < int(b["index"])
	)
	var cleaned: Array[Dictionary] = []
	for finding in findings:
		cleaned.append({
			"line": int(finding["line"]),
			"message": String(finding["message"]),
		})
	return cleaned


static func format_warning(path: String, finding: Dictionary) -> String:
	return "%s:%d - gd-guard - %s" % [path, int(finding["line"]), String(finding["message"])]


static func _add(findings: Array[Dictionary], line: int, message: String) -> void:
	findings.append({
		"line": line,
		"message": message,
		"index": findings.size(),
	})


static func _find_private(tokens: Array[Dictionary], findings: Array[Dictionary]) -> void:
	for index in tokens.size():
		if int(tokens[index]["kind"]) != Kind.DOT:
			continue
		var next_index := _skip_comments(tokens, index + 1, 1)
		if next_index < 0 or next_index >= tokens.size():
			continue
		var next: Dictionary = tokens[next_index]
		if int(next["kind"]) != Kind.IDENT:
			continue
		var member := String(next["text"])
		if not member.begins_with("_"):
			continue
		var prev_index := _skip_comments(tokens, index - 1, -1)
		if prev_index >= 0:
			var prev: Dictionary = tokens[prev_index]
			if int(prev["kind"]) == Kind.IDENT:
				var receiver := String(prev["text"])
				if receiver == "self" or receiver == "super":
					continue
		_add(findings, int(next["line"]), MESSAGE_PRIVATE)


static func _find_class_name(tokens: Array[Dictionary], findings: Array[Dictionary]) -> void:
	var has_class_name := false
	var ignored := false
	for token in tokens:
		var kind := int(token["kind"])
		if kind == Kind.IDENT and String(token["text"]) == "class_name":
			has_class_name = true
		elif kind == Kind.COMMENT and _is_ignore_comment(String(token["text"])):
			ignored = true
	if not has_class_name and not ignored:
		_add(findings, 1, MESSAGE_CLASS_NAME)


static func _is_ignore_comment(text: String) -> bool:
	var trimmed := text.lstrip(" \t")
	var marker := "class_name ignore"
	if not trimmed.begins_with(marker):
		return false
	if trimmed.length() == marker.length():
		return true
	return not _is_ident_continue(trimmed.unicode_at(marker.length()))


static func _find_onready(tokens: Array[Dictionary], findings: Array[Dictionary]) -> void:
	var pending: PackedStringArray = []
	var index := 0
	while index < tokens.size():
		var token: Dictionary = tokens[index]
		var kind := int(token["kind"])
		if kind == Kind.COMMENT or kind == Kind.NEWLINE:
			index += 1
			continue
		if kind == Kind.AT:
			index = _consume_annotation(tokens, index, pending)
			continue
		if kind == Kind.IDENT and String(token["text"]) == "static":
			index += 1
			continue
		if kind == Kind.IDENT and String(token["text"]) == "var":
			if pending.has("onready"):
				var dollar_line := _onready_dollar_line(tokens, index)
				if dollar_line > 0:
					_add(findings, dollar_line, MESSAGE_ONREADY)
			pending.clear()
			index += 1
			continue
		pending.clear()
		index += 1


static func _consume_annotation(tokens: Array[Dictionary], index: int, pending: PackedStringArray) -> int:
	index += 1
	while index < tokens.size():
		var kind := int(tokens[index]["kind"])
		if kind != Kind.NEWLINE and kind != Kind.COMMENT:
			break
		index += 1
	if index < tokens.size() and int(tokens[index]["kind"]) == Kind.IDENT:
		pending.append(String(tokens[index]["text"]))
		index += 1
	if index < tokens.size() and int(tokens[index]["kind"]) == Kind.LPAREN:
		index = _skip_group(tokens, index, Kind.LPAREN, Kind.RPAREN)
	return index


static func _skip_group(tokens: Array[Dictionary], index: int, open_kind: int, close_kind: int) -> int:
	var depth := 0
	while index < tokens.size():
		var kind := int(tokens[index]["kind"])
		if kind == open_kind:
			depth += 1
		elif kind == close_kind:
			depth -= 1
			if depth == 0:
				return index + 1
		index += 1
	return index


static func _onready_dollar_line(tokens: Array[Dictionary], var_index: int) -> int:
	var depth := 0
	var seen_equals := false
	var dollar_line := -1
	var index := var_index + 1
	while index < tokens.size():
		var token: Dictionary = tokens[index]
		var kind := int(token["kind"])
		if kind == Kind.LPAREN or kind == Kind.LBRACKET or kind == Kind.LBRACE:
			depth += 1
		elif kind == Kind.RPAREN or kind == Kind.RBRACKET or kind == Kind.RBRACE:
			depth = max(depth - 1, 0)
		elif kind == Kind.EQUALS and depth == 0 and not seen_equals:
			seen_equals = true
		elif kind == Kind.DOLLAR and seen_equals and dollar_line < 0:
			dollar_line = int(token["line"])
		elif (kind == Kind.NEWLINE or kind == Kind.SEMICOLON) and depth == 0:
			break
		index += 1
	return dollar_line


static func _skip_comments(tokens: Array[Dictionary], index: int, step: int) -> int:
	var cursor := index
	while cursor >= 0 and cursor < tokens.size() and int(tokens[cursor]["kind"]) == Kind.COMMENT:
		cursor += step
	return cursor


static func _find_snake_case(tokens: Array[Dictionary], findings: Array[Dictionary]) -> void:
	for index in tokens.size():
		if int(tokens[index]["kind"]) != Kind.IDENT:
			continue
		var prev := _skip_comments(tokens, index - 1, -1)
		if prev >= 0 and int(tokens[prev]["kind"]) == Kind.DOT:
			continue
		var text := String(tokens[index]["text"])
		if text == "var" or text == "for":
			_warn_decl_name(tokens, index, findings)
		elif text == "func":
			_warn_func(tokens, index, findings)
		elif text == "set":
			_warn_setter(tokens, index, findings)


static func _warn_decl_name(tokens: Array[Dictionary], keyword_index: int, findings: Array[Dictionary]) -> void:
	var name := _next_ident(tokens, keyword_index)
	if name.is_empty():
		return
	_warn_unless_snake(name, findings)


static func _warn_func(tokens: Array[Dictionary], keyword_index: int, findings: Array[Dictionary]) -> void:
	var cursor := keyword_index + 1
	while cursor < tokens.size() and int(tokens[cursor]["kind"]) == Kind.COMMENT:
		cursor += 1
	if cursor >= tokens.size():
		return
	if int(tokens[cursor]["kind"]) == Kind.IDENT:
		_warn_unless_snake(tokens[cursor], findings)
		cursor += 1
		while cursor < tokens.size() and int(tokens[cursor]["kind"]) == Kind.COMMENT:
			cursor += 1
	if cursor < tokens.size() and int(tokens[cursor]["kind"]) == Kind.LPAREN:
		for name in _param_names(tokens, cursor):
			_warn_unless_snake(name, findings)


static func _warn_setter(tokens: Array[Dictionary], keyword_index: int, findings: Array[Dictionary]) -> void:
	var prev := _skip_comments(tokens, keyword_index - 1, -1)
	if prev >= 0 and int(tokens[prev]["kind"]) == Kind.IDENT and String(tokens[prev]["text"]) == "func":
		return
	var cursor := keyword_index + 1
	while cursor < tokens.size() and int(tokens[cursor]["kind"]) == Kind.COMMENT:
		cursor += 1
	if cursor >= tokens.size() or int(tokens[cursor]["kind"]) != Kind.LPAREN:
		return
	var names := _param_names(tokens, cursor)
	var after := _after_group(tokens, cursor)
	while after < tokens.size():
		var kind := int(tokens[after]["kind"])
		if kind != Kind.COMMENT and kind != Kind.NEWLINE:
			break
		after += 1
	if after >= tokens.size() or int(tokens[after]["kind"]) != Kind.COLON:
		return
	for name in names:
		_warn_unless_snake(name, findings)


static func _next_ident(tokens: Array[Dictionary], keyword_index: int) -> Dictionary:
	var cursor := keyword_index + 1
	while cursor < tokens.size() and int(tokens[cursor]["kind"]) == Kind.COMMENT:
		cursor += 1
	if cursor < tokens.size() and int(tokens[cursor]["kind"]) == Kind.IDENT:
		return tokens[cursor]
	return {}


static func _param_names(tokens: Array[Dictionary], lparen_index: int) -> Array[Dictionary]:
	var names: Array[Dictionary] = []
	var depth := 0
	var expect_name := true
	var index := lparen_index
	while index < tokens.size():
		var kind := int(tokens[index]["kind"])
		if kind == Kind.COMMENT or kind == Kind.NEWLINE:
			index += 1
			continue
		if kind == Kind.LPAREN or kind == Kind.LBRACKET or kind == Kind.LBRACE:
			depth += 1
			index += 1
			continue
		if kind == Kind.RPAREN or kind == Kind.RBRACKET or kind == Kind.RBRACE:
			depth -= 1
			if depth == 0:
				return names
			index += 1
			continue
		if depth == 1:
			if kind == Kind.COMMA:
				expect_name = true
			elif kind == Kind.COLON or kind == Kind.EQUALS:
				expect_name = false
			elif kind == Kind.IDENT and expect_name:
				names.append(tokens[index])
				expect_name = false
		index += 1
	return names


static func _after_group(tokens: Array[Dictionary], open_index: int) -> int:
	var depth := 0
	var index := open_index
	while index < tokens.size():
		var kind := int(tokens[index]["kind"])
		if kind == Kind.LPAREN or kind == Kind.LBRACKET or kind == Kind.LBRACE:
			depth += 1
		elif kind == Kind.RPAREN or kind == Kind.RBRACKET or kind == Kind.RBRACE:
			depth -= 1
			if depth == 0:
				return index + 1
		index += 1
	return index


static func _warn_unless_snake(token: Dictionary, findings: Array[Dictionary]) -> void:
	var name := String(token["text"])
	for index in name.length():
		var code := name.unicode_at(index)
		if code >= 65 and code <= 90:
			_add(findings, int(token["line"]), MESSAGE_SNAKE_CASE)
			return


static func _tokenize(source: String) -> Array[Dictionary]:
	var tokens: Array[Dictionary] = []
	var index := 0
	var line := 1
	var length := source.length()
	while index < length:
		var code := source.unicode_at(index)
		if code == 32 or code == 9:
			index += 1
			continue
		if code == 10 or code == 13:
			if code == 13 and index + 1 < length and source.unicode_at(index + 1) == 10:
				index += 2
			else:
				index += 1
			_push(tokens, Kind.NEWLINE, line)
			line += 1
			continue
		if code == 92:
			var next_index := index + 1
			if next_index < length and source.unicode_at(next_index) == 13:
				next_index += 1
			if next_index < length and source.unicode_at(next_index) == 10:
				line += 1
				index = next_index + 1
				continue
			index += 1
			continue
		if code == 35:
			var start := index + 1
			index += 1
			while index < length:
				var comment_code := source.unicode_at(index)
				if comment_code == 10 or comment_code == 13:
					break
				index += 1
			_push(tokens, Kind.COMMENT, line, source.substr(start, index - start))
			continue
		if code == 34 or code == 39:
			var skipped := _skip_string(source, index, line)
			index = skipped.x
			line = skipped.y
			continue
		if code == 36:
			_push(tokens, Kind.DOLLAR, line)
			index += 1
			continue
		if code == 37:
			if index + 1 < length and source.unicode_at(index + 1) == 61:
				index += 2
				continue
			_push(tokens, Kind.PERCENT, line)
			index += 1
			continue
		if code == 46:
			_push(tokens, Kind.DOT, line)
			index += 1
			continue
		if _is_ident_start(code):
			var start := index
			index += 1
			while index < length and _is_ident_continue(source.unicode_at(index)):
				index += 1
			_push(tokens, Kind.IDENT, line, source.substr(start, index - start))
			continue
		if _is_digit(code):
			index = _skip_number(source, index)
			continue
		if code == 61:
			if index + 1 < length and source.unicode_at(index + 1) == 61:
				index += 2
				continue
			_push(tokens, Kind.EQUALS, line)
			index += 1
			continue
		if code == 33 or code == 60 or code == 62 or code == 43 or code == 45 or code == 42 or code == 47 or code == 38 or code == 124 or code == 94:
			if index + 1 < length and source.unicode_at(index + 1) == 61:
				index += 2
				continue
			index += 1
			continue
		if code == 40:
			_push(tokens, Kind.LPAREN, line)
		elif code == 41:
			_push(tokens, Kind.RPAREN, line)
		elif code == 91:
			_push(tokens, Kind.LBRACKET, line)
		elif code == 93:
			_push(tokens, Kind.RBRACKET, line)
		elif code == 123:
			_push(tokens, Kind.LBRACE, line)
		elif code == 125:
			_push(tokens, Kind.RBRACE, line)
		elif code == 64:
			_push(tokens, Kind.AT, line)
		elif code == 59:
			_push(tokens, Kind.SEMICOLON, line)
		elif code == 44:
			_push(tokens, Kind.COMMA, line)
		elif code == 58:
			_push(tokens, Kind.COLON, line)
		index += 1
	return tokens


static func _skip_string(source: String, index: int, line: int) -> Vector2i:
	var quote := source.unicode_at(index)
	var length := source.length()
	var triple := index + 2 < length and source.unicode_at(index + 1) == quote and source.unicode_at(index + 2) == quote
	index += 3 if triple else 1
	while index < length:
		var code := source.unicode_at(index)
		if code == 92 and index + 1 < length:
			var escaped := source.unicode_at(index + 1)
			index += 2
			if escaped == 10:
				line += 1
			elif escaped == 13:
				if index < length and source.unicode_at(index) == 10:
					index += 1
				line += 1
			continue
		if code == quote:
			if triple:
				if index + 2 < length and source.unicode_at(index + 1) == quote and source.unicode_at(index + 2) == quote:
					return Vector2i(index + 3, line)
				index += 1
				continue
			return Vector2i(index + 1, line)
		if not triple and (code == 10 or code == 13):
			return Vector2i(index, line)
		if code == 10 or (code == 13 and (index + 1 >= length or source.unicode_at(index + 1) != 10)):
			line += 1
			index += 1
			continue
		if code == 13:
			line += 1
			index += 2
			continue
		index += 1
	return Vector2i(index, line)


static func _skip_number(source: String, index: int) -> int:
	var length := source.length()
	while index < length:
		var code := source.unicode_at(index)
		if _is_digit(code):
			index += 1
			continue
		if code == 95 and index + 1 < length and _is_digit(source.unicode_at(index + 1)):
			index += 1
			continue
		break
	if index < length and source.unicode_at(index) == 46 and index + 1 < length and _is_digit(source.unicode_at(index + 1)):
		index += 1
		while index < length:
			var fraction := source.unicode_at(index)
			if _is_digit(fraction):
				index += 1
				continue
			if fraction == 95 and index + 1 < length and _is_digit(source.unicode_at(index + 1)):
				index += 1
				continue
			break
	if index < length and (source.unicode_at(index) == 101 or source.unicode_at(index) == 69):
		var exponent := index + 1
		if exponent < length and (source.unicode_at(exponent) == 43 or source.unicode_at(exponent) == 45):
			exponent += 1
		if exponent < length and _is_digit(source.unicode_at(exponent)):
			index = exponent
			while index < length and _is_digit(source.unicode_at(index)):
				index += 1
	return index


static func _push(tokens: Array[Dictionary], kind: int, line: int, text: String = "") -> void:
	tokens.append({
		"kind": kind,
		"line": line,
		"text": text,
	})


static func _is_ident_start(code: int) -> bool:
	return code == 95 or (code >= 65 and code <= 90) or (code >= 97 and code <= 122) or code > 127


static func _is_ident_continue(code: int) -> bool:
	return _is_ident_start(code) or _is_digit(code)


static func _is_digit(code: int) -> bool:
	return code >= 48 and code <= 57
