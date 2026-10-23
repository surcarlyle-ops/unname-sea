# 第一人称近战候选：原版 FBX 实测

- **后续状态**：原版预览已完成；用户随后要求保留自有手套并采用此握姿，现已适配指骨姿态、校正拇指接触并接入主 Demo。详见相邻 `../fps_gloves/ASSET_NOTES.md` 最新段落；下文“未替换主游戏”仅描述原版预览阶段，主 Demo 并未换用模板裸手。（Codex）

- 来源：[BigAndCrispy/Unity-First-Person-Melee](https://github.com/BigAndCrispy/Unity-First-Person-Melee)，旧 ItsPogle 地址重定向至此。作者声明模型、音效与动画自制，根许可 CC0；原文存 `reference/LICENSE`。不是本项目已验收手部。（Codex）
- 用户最初反馈 Code 试用时握姿／动作／模型粗糙；之后明确要求 Codex 重试。此次直接使用现有 `Arms.fbx` 和 `Steel Shortsword.fbx`，未覆盖其内容，也未改生产控制器、手套或武器脚本。（Codex）
- Blender 5.2.2 LTS 实际导入：手臂网格 4302 顶点，含独立指骨；9 条动画为 Sword_Idle、Sword_Slash1/2、Sword_Walk、Sword_Block、Fists_Idle/Block、Lefthand_Spell1、Consumable_Drink.001。Godot 4.7.2 同样读取到 9 条动画，末条名称中的点变为下划线。不是只有 Unity meta 中配置的 4 条。（Codex）
- 装配依据：下载作者 `Player.prefab`，武器父节点对应手腕。针对本项目现有 FBX 导入，Unity 局部附着点需反射 X：位置 `(0.0066,0.1093,-0.0544)`，Godot 四元数 `(-0.25174302,0.24411201,0.63064706,0.6923288)`。试验中直接按另一坐标反射会导致剑倒置／偏离，已通过近景检查纠正；不推断 Code 此前失败原因相同。（Codex）
- 预览保留原版动作，使用 `BoneAttachment3D/Wrist.R` 跟随；为完整查看剑与手，整体位移 `(0,0.035,-0.04)`、转角 `(5,180,0)`，相机垂直 FOV 75，区别于作者原相机 FOV 60，不能称作完全复制 Unity 画面。原始装配、调色板 PSD 与材质保留 `reference/`；使用 Pillow 提取 PSD 合成层 PNG 恢复短剑材质。（Codex）
- 入口：项目根 `预览近战手部.cmd` → `scenes/tests/melee_candidate_preview.tscn`，左右键切 9 条动作，空格重播，鼠标左右键播放两次挥砍，C 切第一人称／手背／掌心近景，T 切原版短剑／项目剑。项目剑仅在此场景装配，未替换主游戏。外观仍是原版裸手，不是已适配皮手套。（Codex）
- 实测结论：静态手指能包握，未见旧手套式严重拉尖；网格和皮肤细节简单，指尖贴合仍有限；挥砍与空手动作可见上臂大面积入镜／武器出画，不能作为最终动作直接验收。适合继续评估绑定与静态握姿，不宣称已解决全部问题。（Codex）
- 证据 `.mvp_qa/melee_candidate/`：Blender `source_inspection.json/.blend`，Godot `godot_inspection.log`、`preview.log`、各动作截图、两次挥砍 36 帧、`project_sword.png` 和握持正反近景。导入与截图完成，无 GDScript 错误；系统证书／GL 着色器缓存写入环境报错仍存在。主游戏未改，未重跑主游戏回归。用户观感未验收。（Codex）
- FBX SHA256：Arms `8F1AFD249569249A3420EE4E9F8B48611893CE7987E5A644A634593700452F93`；短剑 `FD7C33C16CAE72129D96C0F9C805E9788791F642943065D70298A97FFC2713CB`。（Codex）
