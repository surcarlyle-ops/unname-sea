"""Inspect source art support and try the matching texture file exporters."""
import json
from pathlib import Path
import unreal

root = Path(r"D:\claude project\projects\unname_sea")
output = root / "assets/environments/portal_ruins/textures"
output.mkdir(parents=True, exist_ok=True)
sources = json.loads((root / "docs/art/ue_portal_import/material_sources.json").read_text(encoding="utf-8"))
paths = {texture for record in sources.values() for texture in record["candidate_textures"][:1]}
paths.update([
    "/Game/portal/PORTAL_材质_001_BaseColor",
    "/Game/portal/tex/portal3_low_材质_002_BaseColor",
])
records = []
for path in sorted(paths):
    texture = unreal.load_asset(path)
    if not texture:
        continue
    record = {"asset": path, "class": texture.get_class().get_name()}
    try:
        record["import_file"] = texture.get_editor_property("asset_import_data").get_first_filename()
    except Exception as error:
        record["import_error"] = str(error)
    try:
        record["source"] = str(texture.get_editor_property("source"))
    except Exception as error:
        record["source_error"] = str(error)
    for extension in ("tga", "exr"):
        task = unreal.AssetExportTask()
        task.object = texture
        task.filename = str(output / (texture.get_name() + "." + extension))
        task.automated = True
        task.prompt = False
        task.replace_identical = True
        record[extension] = unreal.Exporter.run_asset_export_task(task)
    records.append(record)
(root / "docs/art/ue_portal_import/texture_probe.json").write_text(
    json.dumps(records, ensure_ascii=False, indent=2), encoding="utf-8")
unreal.log("TEXTURE_PROBE_COMPLETE")
