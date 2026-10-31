# Pagoda Cherry 烘焙庭院（导入地标）

- 来源：用户 Fab 下载 `pagoda_and_cherry_blossom_game_scene_baked`，桌面原件 `C:/Users/QAQ/Desktop/未名之海_3D建模素材包/ue5/pagoda_and_cherry_blossom_game_scene_baked-1053db66/`；原件未改。（CodeBuddy）
- 授权：**未核对**，Fab 免费素材许可各异，不按 CC0 处理。（CodeBuddy）
- 目录：`source/japanese_cherrybake.glb`（47.9 MB）+ `textures/` 12 张原贴图（同时被 GLB 内嵌，Godot 导入时抽成 `japanese_cherrybake_*` 系列）。
- 实测内容：29 个网格 / 57,182 三角面 / 无灯光；去掉夜空球后占地 34.7 × 34.8 m、高 20.8 m；部件为 `Pagoda_bake`、`sakuras`、`Stairs_1`、`Grass`、`Lantern_pole_111` 与 12 个灯笼实例。
- 整包**自带一个 200 单位的夜空球**（`Sphere`），直接放进来会把整个樱花山谷罩进黑球里，接入时按 `data/cherry_valley.json` 的 `landmark.hide_nodes` 关掉。
- 包里的樱花树是**透明纸片**：整个樱花林只有 76 顶点 / 38 三角面，材质在原始 GLB 里就叫 `sakura_billboard`（`alphaMode=MASK`、`doubleSided=true`），不是导入造成的。用户要求"树删掉、建筑留下"，已把 `sakuras` 加进 `hide_nodes`，改由山谷自己的卡通樱花树围上来。
- 接入方式：`data/cherry_valley.json` 的 `landmark` 块（中心 `-56, 24`、yaw 24°、footprint 36）+ `valley_world.gd::_build_landmark()`；地面由 `valley_terrain.gd::_build_pads()` 按同一坐标压平一块台地，避免四角悬空。
- 已知遗留：这是按夜景烘焙的素材，放进山谷的蓝调时刻后**宝塔偏黑**、树下有大片暗面，和山谷本身的卡通渲染风格不一致；未做材质调亮，等用户决定是否要调。（CodeBuddy）
