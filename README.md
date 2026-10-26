# gd-guard

Opinionated linter for GDScript.

Copy `addons/gd-guard` into a project and enable it under **Project > Project Settings > Plugins**. It checks a script on save, and the whole project from **Project > Tools > gd-guard: Scan Project**. Scripts in `res://addons/` are skipped.

## Private members stay in their script

By convention a leading `_` means private. Reading or writing `_` members on another object is a warning. The same script may use them, including through `self` and `super`.

```gdscript
class_name Class1
var _amount: int = 0
var amount: int:
    get:
        return _amount

func _ready() -> void:
    print(_amount) # valid
    print(self._amount) # valid
    super._ready() # valid
```

```gdscript
class_name Class2
extends Node
@export var class_1: Class1

func _ready() -> void:
    print(class_1._amount) # invalid
    class_1._amount = 10 # invalid
    class_1._hide() # invalid
    print(class_1.amount) # valid
```

`_ prefixed var or func accessed publicly`

## Every script has a class_name

A script needs `class_name`, unless a comment opts out. The comment is how an autoload, which already has a name, is allowed through.

```gdscript
# class1.gd
class_name Class1
extends Node
```

```gdscript
# autoload.gd
#class_name ignore
extends Node
```

```gdscript
# class3.gd
extends Node
```

`class_name omitted`

## Node references use unique names

An `@onready` assignment must reach a node with `%UniqueName`, not a `$` path. `$` anywhere else is left alone.

```gdscript
@onready var _sprite: Sprite2D = $ParentNode/MySprite # invalid
@onready var _sprite: Sprite2D = %MySprite # valid

func _ready() -> void:
    var _sprite := $ParentNode/MySprite # not checked
```

`Node tree access by $ instead of %`

## AI disclaimer

gd-guard was written by an AI to check scripts written by hand.

Copyright (c) 2026 Brian Hearn. [MIT License](LICENSE).
