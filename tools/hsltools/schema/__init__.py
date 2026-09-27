"""JSON data contracts shared by the Python generators and the GDScript runtime.

unit.py derives content/schema/unit.schema.json (registry task unit_schema); validate.py is
the dependency-free validator the generators run against it. game/sim/UnitSchema.gd
implements the same JSON Schema subset for the runtime.
"""
