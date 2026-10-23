"""Export a bounded ruin sample; edits affect only the commandlet's memory."""
import json
import traceback
from pathlib import Path

import unreal

ROOT = Path(r"D:\claude project\projects\unname_sea")
OUTPUT = ROOT / "assets/environments/portal_ruins"
REPORTS = ROOT / "docs/art/ue_portal_import"
OUTPUT.mkdir(parents=True, exist_ok=True)
REPORTS.mkdir(parents=True, exist_ok=True)
REGION = (-15000.0, 17000.0, 47000.0, 76000.0)


def intersects(center, extent):
    return (center.x + extent.x >= REGION[0]
            and center.x - extent.x <= REGION[1]
            and center.y + extent.y >= REGION[2]
            and center.y - extent.y <= REGION[3])


def export_base_colors(actors):
    material_sources = {}
    texture_directory = OUTPUT / "textures"
    texture_directory.mkdir(exist_ok=True)
    for actor in actors:
        for component in actor.get_components_by_class(unreal.StaticMeshComponent):
            for material in component.get_materials():
                if not material or material.get_name() in material_sources:
                    continue
                textures = []
                if isinstance(material, unreal.MaterialInstanceConstant):
                    for parameter in unreal.MaterialEditingLibrary.get_texture_parameter_names(material):
                        texture = unreal.MaterialEditingLibrary.get_material_instance_texture_parameter_value(material, parameter)
                        if texture:
                            textures.append((str(parameter), texture))
                elif isinstance(material, unreal.Material):
                    textures = [(texture.get_name(), texture) for texture in
                                unreal.MaterialEditingLibrary.get_used_textures(material)]
                def score(pair):
                    label = (pair[0] + " " + pair[1].get_name()).lower()
                    positive = sum(10 for term in ("albedo", "basecolor", "base_color", "diffuse", "_d ", "_d", "_ca") if term in label)
                    negative = sum(20 for term in ("normal", "rough", "_n", "_orm", "_ard", "mask", "displacement") if term in label)
                    return positive - negative
                textures = [pair for pair in textures if isinstance(pair[1], unreal.Texture2D)
                            and pair[1].get_path_name().startswith("/Game/") and score(pair) > 0]
                textures.sort(key=score, reverse=True)
                record = {"asset": material.get_path_name(),
                          "candidate_textures": [texture.get_path_name() for _, texture in textures]}
                if textures:
                    texture = textures[0][1]
                    path = texture_directory / (texture.get_name() + ".png")
                    if not path.exists():
                        task = unreal.AssetExportTask()
                        task.object = texture
                        task.filename = str(path)
                        task.automated = True
                        task.prompt = False
                        task.replace_identical = True
                        unreal.log("PORTAL_TEXTURE_EXPORT " + texture.get_path_name())
                        unreal.Exporter.run_asset_export_task(task)
                    if path.exists():
                        record["base_color_file"] = "textures/" + path.name
                material_sources[material.get_name()] = record
                (REPORTS / "material_sources.json").write_text(
                    json.dumps(material_sources, ensure_ascii=False, indent=2), encoding="utf-8")
    return material_sources


def main():
    world = unreal.EditorLoadingAndSavingUtils.load_map("/Game/landscape_text")
    actors = unreal.get_editor_subsystem(unreal.EditorActorSubsystem).get_all_level_actors()
    selected = set()
    report = {"source_project": unreal.Paths.get_project_file_path(),
              "map": "/Game/landscape_text", "region_cm": REGION,
              "actors": [], "terrain_components": [],
              "source_saved": False, "license_status": "Source asset licenses not yet verified for release."}
    for actor in actors:
        if isinstance(actor, unreal.LandscapeProxy):
            actor.set_editor_property("export_lod", 2)
            for component in actor.get_components_by_class(unreal.LandscapeComponent):
                center, extent, _ = unreal.SystemLibrary.get_component_bounds(component)
                keep = intersects(center, extent)
                component.set_hidden_in_game(not keep)
                if keep:
                    report["terrain_components"].append(component.get_name())
            selected.add(actor)
        elif isinstance(actor, unreal.StaticMeshActor):
            if actor.get_actor_label() in ("SM_SkySphere", "Plane", "Rectangle"):
                continue
            center, extent = actor.get_actor_bounds(False)
            if intersects(center, extent):
                selected.add(actor)
                report["actors"].append(actor.get_actor_label())
    if not report["actors"] or not report["terrain_components"]:
        raise RuntimeError("Empty sample; refusing to export the complete world")
    (REPORTS / "export_selection.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    options = unreal.GLTFExportOptions()
    options.export_uniform_scale = 0.01
    options.export_lights = False
    options.export_cameras = False
    options.export_hidden_in_game = False
    options.export_lightmaps = False
    options.export_level_sequences = False
    options.export_animation_sequences = False
    options.default_level_of_detail = 1
    options.bake_material_inputs = unreal.GLTFMaterialBakeMode.DISABLED
    options.texture_image_format = unreal.GLTFTextureImageFormat.NONE
    path = OUTPUT / "portal_ruins_geometry.glb"
    unreal.log("PORTAL_EXPORT_BEGIN actors=" + str(len(selected)))
    messages = unreal.GLTFExporter.export_to_gltf(world, str(path), options, selected)
    success = path.exists() and path.stat().st_size > 20 and messages is not None
    report["success"] = success
    report["messages"] = str(messages)
    if success:
        report["material_sources"] = export_base_colors(selected)
    (REPORTS / "export_result.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    if not success:
        raise RuntimeError("GLTF export returned false")
    unreal.log("PORTAL_EXPORT_COMPLETE " + str(path))


try:
    main()
except Exception:
    (REPORTS / "export_error.txt").write_text(traceback.format_exc(), encoding="utf-8")
    raise
