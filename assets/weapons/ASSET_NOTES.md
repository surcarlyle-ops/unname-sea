# UE5/Fab 试玩武器批次（两把剑 + 低模武器包）

- 来源：用户从 Fab 下载的同一批 UE 素材，桌面原件 `C:/Users/QAQ/Desktop/未名之海_3D建模素材包/ue5/`；本轮经临时审计工程 `D:/claude project/tools/asset_audits/ue5_20261024` 定位文件后复制进项目，桌面原件未改。临时审计工程只作测量用途，不是运行时依赖。（CodeBuddy）
- 授权状态：**未核对**。Fab 免费素材授权各不相同，本文件不把本批统一写成 CC0；需按账号实际领取的许可逐包核对后再用于发行。（CodeBuddy）
- 目录：
  - `dark_knight_longsword/`：`LongSword.fbx`（13,468 三角面、2 骨、无动画）+ BaseColor / Normal / Roughness / Metallic / OcclusionRoughnessMetallic / Emissive / Height 贴图。只接 FBX 自带的 BaseColor 与法线，另用 ORM 打包图补粗糙度/金属度/AO。
  - `sword_08/`：`Sword_08.fbx`（3,044 三角面、无骨骼）+ `T_SWORD_08_4k_D/M/N.tga`。
  - `lowpoly_pack/`：`axe_001` `baseball_bat_001` `hockey_stick_001` `knife_001` `pistol_001` `rifle_001` `shotgun_001` `sniper_rifle_001` 八件独立武器 + 共用 `Texture_1.png`。未使用包含全部武器的总场景 `Weapons_FREE.fbx`，也未把 `LongSwordLODS.fbx` 的 LOD 当成多把剑。
- 通道判定（按文件实测，不按文件名猜）：`T_SWORD_08_4k_M.tga` 是 R=AO / G=Roughness / B=Metallic 的打包图 —— 与底色交叉采样后，B=0 的孤岛落在棕色皮革握把上、G 高值同样落在握把上、R 暗部只出现在缝隙。因此没有把金属图当粗糙度接。
- 导入设置：4K TGA 在无头导入时 WebP 打包失败（缓存只有 56 字节），改为 VRAM 压缩 + `process/size_limit=2048` + 开 mipmap，实测 2048² 正常加载；源文件未改。
- 装配：每件武器在 `data/combat_mvp.json` 的 `weapons.<id>.viewmodel` 里有独立 `scale` / `rotation` / `offset`，由 `scripts/mvp/imported_weapon_viewmodel.gd` 按配置生成，不共用偏移常量。这些数值是试玩占位，不是最终美术。
## 追加两件（CodeBuddy，2026-10-24 第二轮）

- `mauser98k/`：**已按用户要求删除**（2026-10-24）。曾试接入：`glb/converted/mauser98k.glb` 5,381 面、1.112 m、带内嵌 PBR 贴图，枪口朝 -X（需绕 Y 转 180°）。项目内资产目录、JSON 条目与快捷栏标识均已移除；桌面原包仍在，需要时可重新复制。
- `scifi_knife/`：来源 `ue5/Sci-fi_Weapon_-_Game_Ready_Knife_-_FREE_SAMPLE-464f3427/`，只有 `sm_knife.fbx`（7,122 面），**原包无贴图**，用 `combat_mvp.json` 里的纯色占位材质（深灰金属），不冒充原作者 PBR。
  - 真实结构（截面实测）：长轴是 **Z**，全长 0.371 m；刀柄 z −0.074…+0.112（截面 0.032 × 0.049），刀身 z +0.112…+0.298（厚 0.006）。握把中心约在 z +0.02。
  - 装配（2026-10-24 第二次调整，用户改名"暗影匕首"并要求放大 1.5 倍、修正握持方向）：`rotation [-45,180,0]` 让刀尖朝**前上方 45°**（原 `[-90,0,0]` 是刀尖垂直朝上，用户反馈"拿反了"），`offset [0,0,0]`，`scale 1.2` → 全长约 0.45 m。
  - 第一版按 Y 轴装是错的（刀横着插进手里、只剩一小截露出来），已按实测值修正。
- `scale/rotation/offset` 同样是试玩占位；实机截图 `.mvp_qa/ue5_weapons/ingame/scifi_knife.png`，攻击验证通过。授权同样**待核对**。

- 已知遗留：`Dark Knight` 是蒙皮模型，`MeshInstance3D.get_aabb()` 给的是绑定姿态包围盒，与实际渲染姿态不一致，装配值由实机截图迭代确定；`Emissive` 贴图几乎全黑，接了但基本无效果；低模包八件共用一张 1024 图集，颜色偏卡通（斧头为红色）；手枪类沿用现有程序持枪姿势，没有配套手部动画。（CodeBuddy）
