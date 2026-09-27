"""The command ledger: the tools/hsl_*.py check command each registry task replaces.

check_commands() enumerates every source / evidence / importer check command the gate ran
before the registry existed, from the repository data (per-level chains for each imported
battleNNN directory and each assembled battle level: tracked content/battles/battle_NNN.json or
a content/battles/levels/NNN.json `battle` profile) plus the literal
list below. Nothing runs these commands any more: they are provenance, and
hsltools.registry.all_tasks() enforces that every one of them is `replaces`d by exactly one
task (docs/internal/CONSOLIDATION.md P1). The level enumeration helpers here are shared with
hsltools.levels so the per-level tasks and the ledger enumerate the same levels.
"""
from __future__ import annotations

import json

from hsltools import original_content
from hsltools.paths import ROOT, BATTLES

CHAPTER_IMPORTED = ROOT / "content" / "imported" / "hsl" / "chapter01"
# Levels written for the remake (content/authored/levelNNN/): their battle_NNN.json is
# assembled by hsltools.levels.authored, not by the imported-level chain.
AUTHORED_LEVELS = ROOT / "content" / "authored"
# Per-level profiles (hsltools.levels.profile.DIRECTORY; read here without that module's imports).
LEVEL_PROFILES = BATTLES / "levels"
ENCOUNTER_RANGE = range(501, 579)
SHARED_ACTOR_POOL = 500

# Checks that are not per-level.
LITERAL_CHECKS = (
    "tools/hsl_native_map_binding_probe.py",
    "tools/hsl_source_map_binding.py --check",
    "tools/hsl_attack_ranges.py --check",
    "tools/hsl_actor_audio.py --check",
    "tools/hsl_interface_audio.py --check",
    "tools/hsl_command_frames.py --check",
    "tools/hsl_panel_assets.py --check",
    "tools/hsl_menu_layout.py --check",
    "tools/hsl_presentation_reference.py check",
    "tools/hsl_gameplay_reference.py",
    "tools/hsl_actor_portraits.py --check",
    "tools/hsl_combat_animation.py --check",
    "tools/hsl_animal_programs.py --check",
    "tools/hsl_consumables.py --check",
    "tools/hsl_equipment_data.py --check",
    "tools/hsl_inventory_equipment_evidence.py",
    "tools/hsl_item_action_evidence.py",
    "tools/hsl_give_evidence.py",
    "tools/hsl_action_state_evidence.py",
    "tools/hsl_offense_completion_evidence.py",
    "tools/hsl_native_turn_select_probe.py",
    "tools/hsl_native_skill_cost_probe.py",
    "tools/hsl_skill_target_data.py --check",
    "tools/hsl_native_skill_target_probe.py",
    "tools/hsl_initial_skill_book.py --check",
    "tools/hsl_status_evidence.py",
    "tools/hsl_native_status_roll_probe.py",
    "tools/hsl_native_status_lifecycle_probe.py",
    "tools/hsl_native_support_probe.py",
    "tools/hsl_native_magic_damage_probe.py",
    "tools/hsl_native_water_strike_probe.py",
    "tools/hsl_water_strike.py --check",
    "tools/hsl_water_strike_trial.py --check",
    "tools/hsl_native_ohm_growth_probe.py",
    "tools/hsl_native_bow_range_probe.py",
    "tools/hsl_native_poison_arrow_probe.py",
    "tools/hsl_ohm_assets.py --check",
    "tools/hsl_poison_arrow.py --check",
    "tools/hsl_ohm_village_data.py --check",
    "tools/hsl_native_player_install_probe.py",
    "tools/hsl_gol_road_data.py --check",
    "tools/hsl_native_treasure_probe.py",
    "tools/hsl_treasure_data.py --check",
    "tools/hsl_native_experience_probe.py",
    "tools/hsl_native_physical_probe.py",
    "tools/hsl_native_special_damage_probe.py",
    "tools/hsl_ai_profiles.py --check",
    "tools/hsl_native_ai_probe.py",
    "tools/hsl_native_ai_call_probe.py",
    "tools/hsl_native_ai_priority_probe.py",
    "tools/hsl_native_ai_skill_probe.py",
    "tools/hsl_native_ai_support_probe.py",
    "tools/hsl_native_ai_navigation_probe.py",
    "tools/hsl_native_movement_probe.py",
    "tools/hsl_native_extra_attack_probe.py",
    "tools/hsl_native_extra_action_probe.py",
    "tools/hsl_native_mobility_probe.py",
    "tools/hsl_native_traversal_probe.py",
    "tools/hsl_native_job_stats_probe.py",
    "tools/hsl_native_recovery_probe.py",
    "tools/hsl_native_casting_equipment_probe.py",
    "tools/hsl_native_position_equipment_probe.py",
    "tools/hsl_native_paralysis_probe.py",
    "tools/hsl_paralysis_assets.py --check",
    "tools/hsl_native_large_actor_probe.py",
    "tools/hsl_large_actor_data.py --check",
    "tools/hsl_native_weapon_effect_probe.py",
    "tools/hsl_weapon_effect_trial.py --check",
    "tools/hsl_native_priest_probe.py",
    "tools/hsl_native_priest_motion_probe.py",
    "tools/hsl_native_mana_item_probe.py",
    "tools/hsl_priest_data.py --check",
    "tools/hsl_priest_assets.py --check",
    "tools/hsl_native_moon_dance_probe.py",
    "tools/hsl_moon_dance_data.py --check",
    "tools/hsl_native_stat_magic_probe.py",
    "tools/hsl_native_ai_stat_probe.py",
    "tools/hsl_stat_magic_data.py --check",
    "tools/hsl_native_tactical_items_probe.py",
    "tools/hsl_native_item_cure_route_probe.py",
    "tools/hsl_native_item_magic_probe.py",
    "tools/hsl_tactical_items_data.py --check",
    "tools/hsl_native_permanent_items_probe.py",
    "tools/hsl_permanent_items_data.py --check",
    "tools/hsl_native_mobile_jobs_probe.py",
    "tools/hsl_native_mana_strike_probe.py",
    "tools/hsl_native_departure_probe.py",
    "tools/hsl_native_script_wait_probe.py",
    "tools/hsl_native_auto_growth_probe.py",
    "tools/hsl_entry_growth_data.py --check",
    "tools/hsl_native_growth_lifecycle_probe.py",
    "tools/hsl_native_job_up_learning_probe.py",
    "tools/hsl_growth_lifecycle_data.py --check",
    "tools/hsl_growth_lifecycle_trial.py --check",
    "tools/hsl_native_mobile_motion_probe.py",
    "tools/hsl_native_mobile_source_probe.py",
    "tools/hsl_mobile_jobs_data.py --check",
    "tools/hsl_mobile_jobs_assets.py --check",
    "tools/hsl_native_world_town_probe.py",
    "tools/hsl_role_data.py --check",
    "tools/hsl_native_campaign_actor_probe.py",
    "tools/hsl_campaign_actor_data.py --check",
    "tools/hsl_terrain_heights.py",
    "tools/hsl_native_stamina_probe.py",
    "tools/hsl_item_art.py --check",
    "tools/hsl_first_skill.py --check",
    "tools/hsl_mage_magic.py --check",
    "tools/hsl_skill_coverage.py --check",
    "tools/hsl_support_magic.py --check",
    "tools/hsl_progression_data.py --check",
    "tools/hsl_combat_aftermath_data.py --check",
    "tools/hsl_battle_rewards.py --check",
    "tools/hsl_reward_evidence.py",
    "tools/hsl_fire_animation.py --check",
    "tools/hsl_title_assets.py --check",
    "tools/hsl_movie_import.py --check",
    "tools/hsl_first_battle_formation.py --check",
    "tools/hsl_winfail_coverage.py --check",
    "tools/hsl_big_map_flow.py --check",
    "tools/hsl_core_logic_check.py",
    "tools/hsl_generated_metadata_check.py content/generated/hsl/chapter01",
    "tools/hsl_static_index_check.py content/generated/hsl/static/hsl01/index.json",
    "tools/hsl_function_catalog.py --check",
    "tools/hsl_imported_script_ir_check.py content/imported/hsl/chapter01/script_ir_index.json",
    "tools/hsl_imported_content_check.py content/imported/hsl/chapter01",
    "tools/hsl_visual_evidence_index_check.py",
    "tools/hsl_actor_walk_manifest_check.py content/imported/hsl/chapter01/actor_walk_frames/actor_walk_manifest.json --actors 001 021 023 024 025 026 039",
    "tools/hsl_actor_walk_manifest_check.py content/imported/hsl/shared/actor_walk_frames/actor_walk_manifest.json --actors 010 011 012 013 014 015 016 017 019 020 052",
    "tools/hsl_actor_walk_contact_sheet_check.py content/imported/hsl/chapter01/actor_walk_frames/contact_sheets/actor_walk_contact_sheet_manifest.json --actors 001 021 023 024 026",
    "tools/hsl_opening_timeline_check.py",
    "tools/hsl_opening_timeline_compile.py --check",
    "tools/hsl_message_text_evidence_check.py",
    "tools/hsl_scope_inventory.py --check",
    "tools/hsl_campaign_overview.py --check",
    "tools/hsl_town_assets.py --check",
    "tools/hsl_secret_man_goods.py --check",
    "tools/hsl_world_map.py --check",
    "tools/hsl_town_initial_trees.py --check",
    "tools/hsl_story_token_coverage.py --check",
    "tools/hsl_story_corpus.py --check",
    "tools/hsl_opening_choreography_packet_check.py",
    "tools/hsl_evidence_index.py --check",
    # Born as a registry task (docs/internal/PLAYABILITY.md R1); the ledger entry is its CLI form.
)


def imported_levels() -> list[int]:
    # The folders on disk plus those the tracked original-derived manifest names: the list is the
    # same while the content is absent (public checkout) or half imported (hsl generate from empty).
    names = {path.name for path in CHAPTER_IMPORTED.glob("battle[0-9][0-9][0-9]") if path.is_dir()}
    names |= {name for name in original_content.manifest_dirs("content/imported/hsl/chapter01/")
              if len(name) == 9 and name.startswith("battle") and name[6:].isdigit()}
    levels = sorted(int(name[6:]) for name in names)
    return [level for level in levels if level != SHARED_ACTOR_POOL]


def authored_levels() -> list[int]:
    return sorted(int(path.name[5:]) for path in AUTHORED_LEVELS.glob("level[0-9][0-9][0-9]") if path.is_dir())


def assembled_battle_levels() -> list[int]:
    """Every tracked content/battles/battle_NNN.json plus every level profile
    (content/battles/levels/NNN.json) with a `battle` section, authored levels excluded: a new
    level registers `level_battle:N` from its profile, so its first `hsl generate level_battle:N`
    creates the scenario file."""
    authored = set(authored_levels())
    tracked = {int(path.stem[7:]) for path in BATTLES.glob("battle_[0-9][0-9][0-9].json")}
    tracked |= {int(name[7:10]) for name in original_content.manifest_files("content/battles/")  # as imported_levels
                if len(name) == 15 and name.startswith("battle_") and name.endswith(".json") and name[7:10].isdigit()}
    profiled = {int(path.stem) for path in LEVEL_PROFILES.glob("[0-9][0-9][0-9].json")
                if "battle" in json.loads(path.read_text(encoding="utf-8"))}
    return sorted(level for level in tracked | profiled if level not in authored)


def check_commands() -> list[str]:
    commands = list(LITERAL_CHECKS)
    levels = imported_levels()
    story_levels = [level for level in levels if level not in ENCOUNTER_RANGE]
    for level in levels:
        tag = f"{level:03d}"
        commands.append(f"tools/hsl_battle_seed.py --level {level} --check")
        commands.append(
            f"tools/hsl_opening_timeline_compile.py content/generated/hsl/chapter01/battle{tag}_seed.json"
            f" --message-evidence content/imported/hsl/chapter01/battle{tag}/message_text_evidence.json"
            f" --output content/imported/hsl/chapter01/battle{tag}/opening_timeline.json --check")
        commands.append(f"tools/hsl_opening_timeline_check.py content/imported/hsl/chapter01/battle{tag}/opening_timeline.json --source-script story{tag}")
        commands.append(f"tools/hsl_message_text_evidence_check.py --level {level}")
        commands.append(f"tools/hsl_level_map_objects.py --level {level} --check")
    for level in story_levels:
        commands.append(f"tools/hsl_level_sounds.py --level {level} --check")
        commands.append(f"tools/hsl_level_source_texts.py --level {level} --check")
        commands.append(f"tools/hsl_level_actors.py --level {level} --check")
        commands.append(f"tools/hsl_story_scene.py --level {level} --check")
    commands.append(f"tools/hsl_level_actors.py --level {SHARED_ACTOR_POOL} --check")
    for level in assembled_battle_levels():
        commands.append(f"tools/hsl_level_battle.py --level {level} --check")
    seen: set[str] = set()
    unique = []
    for command in commands:
        if command not in seen:
            seen.add(command)
            unique.append(command)
    return unique
