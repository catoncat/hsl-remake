extends RefCounted
## Number checks for rule inputs (scenario JSON, saves, generated tables): JSON numbers
## arrive as floats, so "an integer" means an int or a finite whole float.
## provenance:
##   rules: remake-invented (input validation shared by the rule modules)
const MAX_SIGNED := 2147483647
const MAX_UNSIGNED := 0xffffffff


## `value` as an int in 0..MAX_SIGNED, or -1. With `source_text`, a String holding a
## valid int is read too (the original tables keep some numbers as text).
static func non_negative_int(value: Variant, source_text: bool = false) -> int:
	if source_text and value is String:
		if not value.is_valid_int():
			return -1
		value = int(value)
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)) or value < 0 or value > MAX_SIGNED or value != int(value):
		return -1
	return int(value)


## An int or a finite whole float, any size.
static func is_integer(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) and value == int(value)


## `is_integer` within minimum..maximum (both inclusive).
static func is_integer_in(value: Variant, minimum: int, maximum: int) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) and value >= minimum and value <= maximum and value == int(value)
