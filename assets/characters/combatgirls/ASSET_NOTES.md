# CombatGirls 刀剑少女：导入与装配记录（CodeBuddy）

- **来源**：桌面 `未名之海_3D建模素材包/战斗3D/CombatGirlsKatanaCharacterPack1.1.unitypackage`（2025-12-24 版，Asset Store）。原始 unitypackage 未改动；解包副本在 `.mvp_qa/combatgirls_audit/unpacked/`（该目录带 `.gdignore`，Godot 不扫描）。
- **许可待确认**：Asset Store 标准 EULA 一般允许用于游戏成品，但禁止转售/再分发原始资源。用于商业发布前请核对订单页的许可条款；本记录不代表已核实。
- **接入范围**：仅新增独立预览入口 `预览剑姬.cmd`，**未修改**主游戏战斗、手部、钩爪与 `combat_mvp.tscn`。这是"剑姬"第三人称演出的第一步，尚未接入技能系统。

## 已导入内容

| 文件 | 用途 |
|---|---|
| `School_Katana_FullBody.fbx` | 角色本体，100 骨骼、19 个网格、约 5.7 万三角面，身高 1.68 m |
| `animations/Idle.fbx` | `Katana_Idle`，3.00 s，循环 |
| `animations/Walk.fbx` | `Katana_Walk_fix`，1.13 s，循环 |
| `animations/Run.fbx` | `Katana_Run`，0.67 s，循环 |
| `animations/Attack1.fbx` | `Katana_Attack1`，2.03 s |
| `animations/Attack2.fbx` | `Katana_Attack2`，1.83 s |
| `animations/Attack3.fbx` | `Katana_Attack3`，2.27 s（源帧范围 25–93） |
| `animations/Sp_Skill1.fbx` | `Sp_Skill1`，3.2 s（下一轮做"剑姬降临"演出用，暂未接） |
| `textures/**` | 身体、脸、眼、5 套校服、运动服、头发、刀、眼镜 |

## 导入时踩到的坑（复现用）

1. **贴图全部失效**。FBX 里的贴图路径是原作者本机绝对路径（`../../Desktop/Dev_New_Character/...`），导入后 8 个材质全空。解决：`scripts/characters/katana_girl.gd` 按**材质名**重新绑定 `textures/` 下的图，不依赖 FBX 内的路径。材质名与贴图的对应关系已用 Unity `.mat` 里的 `_MainTex` GUID 反查确认，不是猜的。
2. **动画是分离文件**。模型 FBX 不含动画，7 条动作各自是独立 FBX。解决：加载时把每条 clip 合并进同一个 `AnimationPlayer` 的动画库；轨道路径形如 `Skeleton3D:pelvis`，因此 `AnimationPlayer.root_node` 必须指向模型根节点。
3. **有根运动**。Walk/Run/Attack1-3 都带 `root` 骨骼的位置轨道。角色由代码驱动位移，故加载时删掉 `root` 的位置轨道，否则网格会在胶囊里自己往前滑、循环时回弹。
4. **眼睛分层**。眼珠网格在脸部网格内侧，直接渲染只露出一个红圈。解决：把眼珠顶点沿法线推出 1.5 mm。**不能**用 `no_depth_test`——那样从背后会看到眼睛穿透后脑。
5. **模型朝向 +Z**（不是 Godot 常见的 -Z），移动朝向用 `atan2(dir.x, dir.z)`，`MODEL_YAW_OFFSET` 保持 0。

## 已知缺口

- **脸部仍是半成品**：睫毛/眉毛区域有脏块，肤色在强光下偏白。脸部贴图是"皮肤底 + 眼部叠加"的双层结构，还需要按 UTS 的分层规则再调。
- 只接了 idle / walk / run / attack1-3 / skill1 共 7 条；包里还有受击、闪避、四方向 Quickshift、Sp_ 姿态组未导入。
- 运动是代码驱动 + 动画速度对齐，**没有做根运动提取**，急停/转向时仍会有脚滑。
- 未接碰撞胶囊与地形；预览里是平地自由移动。

## 验证

- `.cv_qa/combatgirls/`：7 张动作截图、脸部近景与背面视角；`bone_probe.log` 显示三条 clip 的骨骼轨道 **100% 解析成功**（53/53、67/67、64/64）。
- 入口 `预览剑姬.cmd`：WASD 移动、Shift 走、左键连招、1/2/3 单段、4 技能、Tab 换装、F 换脸、R 重置。
