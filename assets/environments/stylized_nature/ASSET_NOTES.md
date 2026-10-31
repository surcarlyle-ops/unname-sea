# Ultimate Stylized Nature（岸边测试区装饰）

## 来源与授权
- 原始包：**Ultimate Stylized Nature — May 2022**，作者 **Quaternius**（https://www.patreon.com/quaternius）
- 授权：**CC0 1.0 Universal（公有领域）**，可商用、可修改、无需署名。原文见原始包内 `License.txt`。
- 原始包位置（未入库）：`C:\Users\QAQ\Downloads\Ultimate Stylized Nature - May 2022-20261028T081630Z-1-001\`

## 入库内容
只挑了岸边测试区用得到的 8 个模型（原包 63 个 FBX / 36 个 glTF，449 MB 未整体入库）：

| 文件 | 用途 | 原始尺寸（m） |
|---|---|---|
| `BirchTree_1.gltf` | 远景白桦 | 1.8 × 4.9 × 1.2 |
| `MapleTree_2.gltf` | 远景枫树 | 6.1 × 6.3 × 5.0 |
| `DeadTree_3.gltf` | 岸边枯树 | 4.2 × 5.0 × 1.7 |
| `Bush_Large.gltf` / `Bush_Small.gltf` | 灌木 | 2.0 × 1.3 / 1.8 × 1.3 |
| `Grass_Large_Extruded.gltf` | 草丛 | 0.75 × 0.51 |
| `Flower_2_Clump.gltf` / `Flower_3_Clump.gltf` | 花簇/苇草 | 0.57 × 0.60 |

贴图只保留漫反射/叶片图集（`BirchTree_Bark.jpg`、`MapleTree_Bark.jpg`、`NormalTree_Bark.jpg`、`*_Leaves.png`、`Bush_Leaves.png`、`Grass.png`、`Flowers.png`），共 8 张。

## 做过什么改动
- 原包每个模型都引用 4K 法线贴图（单张 8–22 MB），测试区不需要，脚本 `tools/asset_pipeline/import_stylized_nature.py` 把 glTF 里的 `normalTexture` 去掉并裁掉未引用的 image/texture，只复制漫反射。
- 几何、UV、材质命名、贴图内容**未改**，`.bin` 原样复制。
- 运行时把叶片/灌木/花的 BLEND 材质改成 **alpha scissor（0.4）**，避免多层透明排序闪烁（只在 `shore_test_area.gd` 里改材质副本，不改文件）。

## 复现
```bash
python tools/asset_pipeline/import_stylized_nature.py
"D:\claude project\Godot_v4.7.2-stable_win64.exe" --headless --path "D:\claude project\projects\unname_sea" --import
```

## 注意
- 装饰全部是**无碰撞**的 Node3D/MeshInstance3D，水面与地面碰撞体没有变化。
- 树/灌木在 `shore_test_area.gd` 里按 AABB 自动贴地并水平居中，换模型不用手调 y。
