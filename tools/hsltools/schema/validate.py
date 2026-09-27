"""Minimal JSON Schema (draft 2020-12 subset) validator with no third-party dependency.

Supported keywords: type (string or list), required, properties, additionalProperties
(boolean), enum, items (one schema), minItems, maxItems, plus `default` (ignored by
error(); apply_defaults() fills it in). error() returns the first violation as
"<path>: <reason>" or "" — the same shape as game/sim/UnitSchema.gd input_error(), so
the two sides report the same first error for the same document.
"""
from __future__ import annotations

import copy

KEYWORDS = ('type', 'required', 'properties', 'additionalProperties', 'enum', 'items', 'minItems', 'maxItems',
            'default', '$schema', '$id', 'title', 'description')


def apply_defaults(value: object, schema: dict) -> object:
    """A copy of value with every missing property that declares a `default` filled in,
    recursively through object properties (the same rule as BattleScenario.apply_defaults)."""
    if not isinstance(value, dict) or schema.get('type') != 'object':
        return value
    result = dict(value)
    for key, subschema in schema.get('properties', {}).items():
        if key not in result and 'default' in subschema:
            result[key] = copy.deepcopy(subschema['default'])
        if key in result:
            result[key] = apply_defaults(result[key], subschema)
    return result


def json_type(value: object) -> str:
    if value is None:
        return 'null'
    if isinstance(value, bool):
        return 'boolean'
    if isinstance(value, int):
        return 'integer'
    if isinstance(value, float):
        return 'integer' if value.is_integer() else 'number'
    if isinstance(value, str):
        return 'string'
    if isinstance(value, list):
        return 'array'
    if isinstance(value, dict):
        return 'object'
    return type(value).__name__


def _type_matches(value: object, expected: str) -> bool:
    actual = json_type(value)
    if expected == 'number':
        return actual in ('integer', 'number')
    return actual == expected


def error(value: object, schema: dict, path: str = '$') -> str:
    """First violation of value against schema as "<path>: <reason>", or "" when valid."""
    unknown = sorted(set(schema) - set(KEYWORDS))
    if unknown:
        return f'{path}: unsupported schema keyword(s) {unknown}'
    expected = schema.get('type')
    if expected is not None:
        allowed = expected if isinstance(expected, list) else [expected]
        if not any(_type_matches(value, kind) for kind in allowed):
            return f'{path}: expected {"|".join(allowed)}, got {json_type(value)}'
    if 'enum' in schema and value not in schema['enum']:
        return f'{path}: {value!r} not in enum {schema["enum"]}'
    if isinstance(value, dict):
        for key in schema.get('required', ()):
            if key not in value:
                return f'{path}: missing required key {key!r}'
        properties = schema.get('properties', {})
        for key in value:
            if key in properties:
                found = error(value[key], properties[key], f'{path}.{key}')
                if found:
                    return found
            elif schema.get('additionalProperties', True) is False:
                return f'{path}: unexpected key {key!r}'
    if isinstance(value, list):
        if 'minItems' in schema and len(value) < schema['minItems']:
            return f'{path}: expected at least {schema["minItems"]} items, got {len(value)}'
        if 'maxItems' in schema and len(value) > schema['maxItems']:
            return f'{path}: expected at most {schema["maxItems"]} items, got {len(value)}'
        if 'items' in schema:
            for index, item in enumerate(value):
                found = error(item, schema['items'], f'{path}[{index}]')
                if found:
                    return found
    return ''
