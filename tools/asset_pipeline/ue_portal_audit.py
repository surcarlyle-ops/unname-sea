"""Read the UE level without saving it and report reusable scene objects."""
import json
import traceback
from pathlib import Path

import unreal

OUTPUT = Path(r"D:\claude project\projects\unname_sea\docs\art\ue_portal_import")
OUTPUT.mkdir(parents=True, exist_ok=True)


def vector(value):
    return [value.x, value.y, value.z]


def main():
    world = unreal.EditorLoadingAndSavingUtils.load_map("/Game/landscape_text")
    if not world:
        raise RuntimeError("Could not load /Game/landscape_text")
    subsystem = unreal.get_editor_subsystem(unreal.EditorActorSubsystem)
    records = []
    for actor in subsystem.get_all_level_actors():
        center, extent = actor.get_actor_bounds(False)
        meshes = []
        for component in actor.get_components_by_class(unreal.StaticMeshComponent):
            mesh = component.static_mesh
            if mesh:
                meshes.append({
                    "component": component.get_name(),
                    "mesh": mesh.get_path_name(),
                    "materials": [material.get_path_name() if material else None
                                  for material in component.get_materials()],
                })
        records.append({
            "name": actor.get_name(),
            "label": actor.get_actor_label(),
            "class": actor.get_class().get_name(),
            "location_cm": vector(actor.get_actor_location()),
            "bounds_center_cm": vector(center),
            "bounds_extent_cm": vector(extent),
            "meshes": meshes,
        })
    report = {"source_project": unreal.Paths.get_project_file_path(),
              "map": world.get_path_name(), "actors": records}
    (OUTPUT / "level_inventory.json").write_text(
        json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    unreal.log("PORTAL_AUDIT_COMPLETE actors=" + str(len(records)))


try:
    main()
except Exception:
    (OUTPUT / "audit_error.txt").write_text(traceback.format_exc(), encoding="utf-8")
    raise
