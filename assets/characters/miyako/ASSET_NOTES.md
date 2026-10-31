# Blue Archive - Miyako（仅资产检查，未接入）

- 来源：用户 Fab 下载 `Blue_Archive_-_Miyako`，桌面原件 `C:/Users/QAQ/Desktop/未名之海_3D建模素材包/ue5/Blue_Archive_-_Miyako-e9dfe6b0/`；作者 Loyalists，Blender 制作、Substance 贴图、Rigify 骨骼。（CodeBuddy）
- 授权：**未核对**。这是第三方 IP（Blue Archive 角色）的同人模型，商用范围必须自行确认，不按 CC0 处理。（CodeBuddy）
- 目录：`blue_archive_miyako.glb`（19.4 MB，Godot 导入时抽出 38 张内嵌贴图）+ `metadata.json`（Fab 商品原始元数据，仅作记录）。
- **实测结论（2026-10-24，`check_miyako.gd`）**：
  - 35 个网格、**346,074 三角面**（很重）
  - **骨骼 0、动画 0、形态键 0** —— 商品描述里提到的 Rigify 骨骼与面部 shapekey **没有进入这份 GLB**；描述本身也写了"不要用 viewer 版 FBX，要用 .blend"
  - 包围盒 0.0052 × 0.0169 × 0.0056，单位不是米，需放大约 100 倍才到 1.7 m
  - 根节点 `Sketchfab_model`
- 因此它现在**只能当静态雕像/摆件**用，不能直接当会动的角色或 NPC。要当角色需要另拿 .blend 重新导出带骨骼的版本（或自行绑定）。（CodeBuddy）
- 当前状态：只做检查，**未放进任何场景**；等用户定用途（静态雕像 / 重新导出骨骼版 / 暂不使用）。
