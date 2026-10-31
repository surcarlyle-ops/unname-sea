# CHECKPOINT — 未名之海

> **唯一当前状态入口。** 接手先读本文件；完整历史原文见 [`docs/history/CHECKPOINT_2026-10-24.md`](docs/history/CHECKPOINT_2026-10-24.md)，只在追溯时按需查阅，不作为日常接手的默认读取内容。
> **维护规则**：见 [CLAUDE.md「交接与署名规则」](CLAUDE.md#交接与署名规则)。本文件只保留当前状态、有效共识、待办、未解决问题和入口，不堆积过程。
> **最后整理**：2026-10-24（CodeBuddy，UE5/Fab 试玩武器批次接入 + 泰拉瑞亚式背包；改了 `first_person_hands.gd`、`first_person_player.gd`、`combat_hud.gd`、`combat_mvp.json`、新增 `imported_weapon_viewmodel.gd` 与三处武器资产；有实机截图、攻击与背包搬运验证，未提交代码）

---

## 一、当前状态与启动入口

**唯一正式启动入口**：根目录 `选择地图试玩.cmd`，双击或F5均先到地图选择菜单，地图内按 **B** 返回（右下角"B 返回地图选择"按钮在鼠标可用时也能直接点）。10个独立预览脚本移至 `tools/launchers/` 并已修正相对路径，仅供开发调试。（Codex，2026-10-28；返回键改 B 为 CodeBuddyPro，2026-10-28）

**渲染与项目约束**：Godot 4.7.2，GL Compatibility；`project.godot` 默认主场景已统一为 `scenes/ui/map_select.tscn`（Codex）。主战斗与樱花山谷是两个独立场景，互不引用。

### 1. 主战斗 Demo（第一人称近战 + 钩爪 + 手套）— 当前主线
- **入口**：`选择地图试玩.cmd` / F5 → 地图选择菜单 → 选择训练场 → `scenes/combat_mvp.tscn`（Codex）
- **场地**：程序化训练场，48 × 44 m 平地 + 围墙、蹬墙墙、钩爪柱与横梁、升降平台与矮掩体（机动与钩爪测试用），后墙外新增3棵FBX测试树，其余以占位几何为主，由 `scripts/mvp/combat_arena.gd` 运行时生成
- **当前主 Demo 键位**：WASD默认跑 / Shift走 / Ctrl蹲·滑铲 / 空格跳·翻越·牵引开始后助推 / 左键攻击·开火·钓鱼 / 按住右键钩爪、松开断开 / 1—5或滚轮选物品（药水按数字使用）/ **F统一交互拾取、E剑气、Tab背包、Esc菜单**。试炼/重试/地图/强制鱼与异兽/移动档位改从菜单点击，旧 G/H/J/K/N/M/V/R/T 与主试玩 B/Backspace 快捷操作停用。游戏不显示教学说明。（Codex）
- **已有内容**：第一人称近战与命中反馈、自制手套持剑、钩爪2（含 Apex 式重力与落地僵直、空中攀爬）、HUD、守卫战斗（见下）、伤害飘字
- **UE 素材试玩批（CodeBuddy，2026-10-24）**：默认快捷栏仍是 `1 时钟剑 / 2 空手 / 3 手炮 / 4 M1911 / 5 药水`；**Tab 或 Esc 打开背包**（泰拉瑞亚式，见下），可把 `暗黑骑士长剑`、`长剑08`、`暗影匕首`、`低模斧 / 球棒 / 短刀 / 步枪 / 狙击` 拖进现有 5 格轮流试玩（没有新增快捷栏或展厅）。**98K 已按用户要求移除**（资产、数据、快捷栏标识一并删除，桌面原包仍在）。**用户已要求移出 4 件**：低模左轮、低模霰弹、低模球杆、练习刃，现用 `hidden: true` 从背包隐藏（数据与文件保留，未删除）。冷兵器复用现有挥砍，枪械复用现有直射弹；数值均为试玩占位，未做技能、换弹或弹药。装配参数在 `combat_mvp.json` 的 `weapons.<id>.viewmodel`，每件独立 `scale/rotation/offset`
- **背包（CodeBuddy基础，Codex布局调整，2026-10-24）**：左上角原位展开的 5×4 网格，第一行与收起时坐标/尺寸一致，保持深紫半透明与暖金选中风格、无全屏遮罩（Codex）；**第一行就是快捷栏**（与左上角 5 格、1-5 键同步），下面 3 行放未装备物品；点击拿起、再点格子放下/交换，右键或点面板外放回，Esc/Tab 关闭。物品清单由 `combat_mvp.json` 的 `weapons` 键 + 药水自动生成，新增武器不用再改 UI。实机截图 `.mvp_qa/ue5_weapons/ingame/backpack_*.png`；搬运后 `quick_slots`/`backpack_slots` 变化与装备结果已用脚本核对
- **装备栏 + 饰品（CodeBuddy，2026-10-24）**：按泰拉瑞亚官方 Wiki 的标准做的**竖列布局**——护甲 3 格（头/身/腿，空格子里有淡字提示）+ 饰品 5 格（Classic 标准数量），按用户要求贴**屏幕右边缘**（1280 画布 x=1178，只在背包打开时显示）。社交/染料列没做（没有对应物品）。点格子的搬运逻辑与背包共用，装备栏只接受类型对得上的物品。首件饰品 **疾风之靴**（高级，标记"靴"）默认穿在饰品第 1 格；效果只接了**免疫坠落伤害**，移速加成按用户要求先不生效（`move_speed_bonus: 0`）。实测：穿靴子 15 m 坠落扣 0、脱掉扣 52、再穿上又扣 0
- **鱼与材料的数量背包 + 岸边掉落（CodeBuddy，2026-10-28）**：数量唯一来源是现有 `Inventory`（`scripts/inventory.gd`）；`scripts/mvp/fishing_loot.gd` 只做「一种一格、单格 999、15 格容量」的映射与容量判断，不存第二份数量表（外部直接写 `Inventory` 也会同步显示）。背包打开时，左上角装备格下方是 3×5 的「渔获与材料」区：图标 + 名称 + 数量，点一下常驻页脚说明（鱼：可加工为鱼骨／鱼骨与鳞片），鱼与材料不可搬进快捷栏或装备栏。掉落在 `scripts/mvp/loot_drop.gd`：靠近自动拾取、装满部分后余量留在地面、满包 1.5 s 重试、清空自毁、重复调用只结算一次。**接口**：`count / add_item / try_add / room_for / can_accept / entries / grant`（入包+溢出一次完成）与 `LootDrop.spawn`；最小示例见 `tests/loot_drop_test.gd` 头部。已获得物品在本次运行内跨死亡、R 重试保留（暂不接磁盘存档）。**验证**：`tests/loot_drop_test.gd` 49/49 通过（headless）、`tests/backpack_corner_test.gd` failures=0（武器搬运未受影响）、实机截图 `.mvp_qa/loot_bag/{open,full,shore_drop}.png`。**遗留**：`combat_arena.gd` 的钓获已由 Codex 改为「鱼先落地 → 靠近按 T 拾取」（`_spawn_pickup` + `_collect_nearest_pickup`）；本轮未改 `combat_arena` / `first_person_player` / `first_person_hands`。**2026-10-28 晚补记（并行重构后）**：`fishing_loot.gd` 已被另一会话改为 `bind(player.inventory)` 直写 Inventory，HUD 里旧的 `slot_count` / `item_in_cell` 随之失效——本会话已把 `combat_hud` 改读 `inventory.slot_count` / `inventory.slots`（`_loot_item_id()`）。`Inventory._do_add` 只按 999 截断，**格位满时仍会静默收下新种类**（变成看不见的库存），本会话在 `FishingLoot.add_item` 里补回 `room_for` 容量上限，溢出才会真正落地。`tests/loot_drop_test.gd` 已更新到现流程，**50/50 通过**。另：`Inventory.from_dict` 读的是存档格式 `{items, slots}`，测试里重置数量请用 `inventory.clear()` + `add_item`，不要再传 id→数量。（CodeBuddy）
- **跑动镜头起伏（CodeBuddy 2026-10-24；CodeBuddyPro 2026-10-28 加强）**：与手部 bob 共用同一个 `stride_phase`（一个相位=两步），竖直/前后/**俯仰**每步一次，横向/**偏航**/滚转每两步一次，滑铲/攀爬/蹬墙/空中淡出、幅度随速度缩放。用户反馈原版"不太明显"，**调研 Apex 后按它的头动补齐旋转分量**（Apex 的 `settings.cfg` 有 `bob_yaw` / `bob_pitch` 两个键可关掉头部晃动，说明它的走路视角含偏航与俯仰；纯位移在远景上几乎看不出来，这也是原版不明显的直接原因）。实测（`tests/camera_bob_check.gd`，峰峰值）：冲刺 竖直 2.2 cm / 横向 1.3 cm / 前后 0.6 cm / 俯仰 0.34° / 偏航 0.16° / 滚转 0.38°，走路约为冲刺的 63%，停下精确归零（修了原先残留权重永远不归零的小问题）。**第一版按 Apex 加到 3.2 cm / 俯仰 0.60° / 滚转 0.59°，用户试后反馈"有点太抖"，已整体回退约 1/3；现在比原版少了点位移、但多了俯仰与偏航**。数值在 `combat_mvp.json` 的 `player.camera_bob`，嫌大嫌小直接调；`step_distance` 决定步频（1.9 m，冲刺约 4.3 步/秒），觉得"抖"也可以加大它换成更慢的晃动（会同时放慢脚步声，本轮未动）。**待试玩，未获用户验收**
- **坠落伤害（CodeBuddy，2026-10-24）**：按"离地后的最高点 − 落点"算落差，安全高度取训练场钩爪柱台面 **6.3 m**（`HookCap` 顶面），台子高度以内不扣血；超过后每多 1 m 扣 6 点、封顶 60。数值在 `combat_mvp.json` 的 `player.fall_damage`。攀爬与蹬墙跑不计入落差；坠落只闪红屏 + 血条上方显示"坠落 -N"，**不画受击方向箭头**（没有攻击来源）。实测：6.3 m→0、6.4 m→1、9 m→16、15 m→52、25 m→60（封顶）、原地跳→0
- **状态**：可运行、可试玩；多项手感待用户验收，见第三节

### 2. 守卫（主 Demo 内，Codex 已接入主战斗）
- 绑定资产 `guardian_06_rigid_binding.glb`（13 骨刚性绑定），代码 `scripts/mvp/ruin_guardian_combat.gd` + `guardian_procedural_motion.gd` + `guardian_stone_fist.gd`
- 300 血 / 2 倍体型 / 追击 3.15 m/s / 攻击 1.3 倍；13 骨程序行走、踏步挥拳、蓄力双臂砸地（带可跳过地波）
- 远距 8–22 m 选冲撞：行程按初始距离扣除停靠距离后限 18 m，**不追踪转向**，墙前停止；近距 3.4 m 内挥拳，每第三次近招砸地
- 12 个刚性部件带随骨实体与受击区；剑与直射命中拳部/脚部按 50% 伤害（`combat_mvp.json.guardian.hard_part_damage_multiplier`）

### 3. 守卫（独立测试场景，**未接主战斗**，CodeBuddy）
- **入口**：`tools/launchers/预览遗迹守卫.cmd` → `scenes/tests/ruin_guardian_preview.tscn`
- 使用**另一份资产** `guardian_06_video_lunge_study.glb`（视频动作版"前冲出拳"），与主 Demo 的守卫不是同一份动作
- 比例统一 3.0（0.80 单位 → 2.4 m），单段 4.93 s、关循环；根运动驱动后冲刺 3.08 m
- 场景含平地、可开关的墙、玩家替身（移动 + 0.34 s 无敌闪避）

### 4. 剑姬（独立预览，**未接主战斗**，CodeBuddy）
- **入口**：`tools/launchers/预览剑姬.cmd` → `scenes/tests/katana_girl_preview.tscn`
- CombatGirls 刀剑少女包，100 骨、19 网格、约 5.7 万面、1.68 m；已导 Idle/Walk/Run/Attack1-3/Sp_Skill1 共 7 条
- 用户已选定"剑姬降临"叙事方案（C），第三人称技能演出**尚未实现**

### 5. 樱花山谷（独立场景，Claude Code）
- **入口**：`tools/launchers/启动樱花山谷.cmd` → `scenes/cherry_valley.tscn`
- 平滑二次元风（非体素），含地形、水面、光照、建筑、植被、倒影、导航、运镜、HUD、雨、瀑布、飞鸟、自动巡游、环境音、移动端触控
- 结构检查 64 项通过；实际手感待用户试玩

### 6. 其他入口
`tools/launchers/预览近战手部.cmd`（原版近战手部动作）· `tools/launchers/预览视频动作提取.cmd`（视频动作对照，现默认守卫）· `scenes/portal_ruins_preview.tscn`（遗迹场景候选）

### 7. 岸边钓鱼测试区（场地 CodeBuddyPro，主流程接入 Codex）
- **正式入口**：统一菜单「岸边钓场」→ `scenes/shore_fishing_mvp.tscn`，复用主战斗、鱼竿、数量背包与异兽遭遇；训练场 K 同样进入这份岸边场地。数据边界和异兽出生使用场地公开接口。原独立预览仅供开发比较。（Codex）
- **开发预览**：`tools/launchers/预览岸边测试区.cmd` → `scenes/tests/shore_test_area_preview.tscn`（环境光 + 第一人称玩家 + 调试 HUD + 一份钓鱼状态机）；场地本体是 `scenes/tests/shore_test_area.tscn`，可被主场景单独实例化；坐标全在 `data/shore_test_area.json`
- **读取方式**：`water_bounds()` → x/z 水域矩形（世界坐标）、`water_level()` → 水面高度、`fishing_arena_config()` → 可直接赋给 `FishingMVP.config["arena"]` 的字典；`player_spawn_point()` → 玩家出生点；`encounter_spawn_points()` / `encounter_spawn_markers()` → 8 个候选点（场景内 `Spawns/EncounterSpawn1..8`，分组 `shore_encounter_spawn`）；`pick_encounter_spawn(pos, 5.0)` → 按 ≥5 米、不在水里、胶囊无重叠选点，无解返回 `Vector3.INF`
- **场地**：32×21 m 水面（岸边与钓台末端都能抛 2–12 m）、3 m 宽木钓台（坡道上台，甲板 0.55 m，带金色钓点站位与水面落点环）、24×15 m 平坦战斗空地、2 根 7 m 钩爪石柱 + 后侧岩壁、8 个异兽候选点
- **装饰（CodeBuddy，2026-10-28）**：资源 **Ultimate Stylized Nature（Quaternius，CC0 1.0，可商用免署名）**，只入库 8 个模型（白桦/枫树/枯树/大灌木/小灌木/草丛/两簇花），共 **4.3 MB**；原包 4K 法线图已剥离，导入脚本 `tools/asset_pipeline/import_stylized_nature.py` 可复现，来源与改动见 `assets/environments/stylized_nature/ASSET_NOTES.md`。共 **59 处装饰**（白桦 9 / 枫 5 / 枯树 2 / 灌木 15 / 草丛 17 / 花簇 11），坐标在 `data/shore_test_area.json` 的 `decor`；全部**无碰撞**（Node3D + MeshInstance，不参与抛竿射线、出生点与钩爪判定），按 AABB 自动贴地并水平居中。木台入口新增「钓点 · 上木台」指示牌；开发预览曝光 0.95→0.90、环境光 0.45→0.40
- **山谷化 + 水体/草地重做（CodeBuddy，2026-10-28 晚）**：按用户要求，以 Ultimate Stylized Nature 包根目录的概念图 `Preview.jpg`（下载包内那张湿绿森林山谷）为准，把原来"一块平地 + 三排尖锥远山"改成四面围合的低谷。改动全部在 `scripts/shore/shore_test_area.gd`、`shaders/pond_water.gdshader`、新增 `shaders/grass_wind.gdshader` / `shaders/valley_hill.gdshader`、`data/shore_test_area.json`（2 株水边枯树换白桦/枫）与 `scripts/shore/shore_test_preview.gd`（只改开发预览环境）：
  - **谷底/谷壁**：`_build_valley_floor()` 320 m 见方网格，碰撞盒内严格 y=0（和碰撞面一致），盒外 34 m 升到约 10 m；三面 15 座低丘 + 三排远岭（`valley_hill` 着色器做高度渐变/大块色斑/haze），场地被围成谷。
  - **森林层**：近圈 64 棵 + 中景 44 棵 + 背后 14 棵（放在 BackCliff 前，别再藏到墙后）+ 山坡树约 30 棵（白桦/枫为主，枯树只占少数），水对岸 16 株灌木、6 块青苔石、对岸石拱（`z=-32`，拱肩向中间抬，纯视觉无碰撞）。装饰 `decor` 仍是 59 条。
  - **草**：MultiMesh 5200 → **18000 株**（叶片 0.20 m、宽 0.038），新增 `grass_wind.gdshader`（根不动、梢摆动 + 低频阵风 + 草梢透光），水线外侧 760 簇芦苇、草地里 520 朵野花；全部无碰撞。木台前改成一窄条湿土（原 16×3.4 浅沙在低角度看像一个沙丘，挡水线），坡道补了 3 道横木条，才读得出是木坡道。
  - **水（2026-10-28 深夜重做）**：旧版是三条固定方向 sin 叠加 + 纯漫反射，32 米池面上会露出规则斜带，还会被岸边树的投影切出一条硬边黑带——这就是"假"的来源。现在：
    - **法线**：低频三层值噪声（0.4/1/2 m）+ 运行时生成的 512² 可平铺法线纹理（`NoiseTexture2D(as_normal_map)`，三层 16.7/6.7/2.8 m 不同漂移方向）。程序化噪声到第 5 层会让 GLES3 直接 `Program linking failed / out of memory`，细纹必须走纹理。
    - **光照**：`shadows_disabled`（水面不吃树影）；`ALBEDO = body*0.40 + EMISSION = body*0.60`，避免按漫反射被天光再乘一遍顶成奶白；菲涅尔天空反射取地平线/天顶双色，封顶 0.34、浅滩再 ×0.5；碎金高光方向偏到对岸（主光在玩家背后，真反射时看不到高光）。
    - **透明度与池底**：浅水 α 0.50 / 深水 0.95；池底从岸边 0.6 m 处开始下凹、5.5 m 落到 -0.42 m，顶点色由湿沙过渡到淤泥，浅滩能看见沙坡而不是一张贴图。
    - **岸线**：泡沫收到 10 cm、贴岸白边 3 cm，低频斑驳打散纯渐变。
    - **参数**（`_pond_material()`）：`deep_color (0.03,0.26,0.31)`、`shallow_color (0.15,0.50,0.46)`、`normal_strength 0.55`、`ripple_scale 2.2`、`detail_fade 26→85`。
  - **预览环境**：天空改偏青 + 暖奶油地平线、雾改淡草绿、曝光 0.86→0.90、太阳抬高到 -28°，去掉薰衣草紫。
  - **未动**：碰撞盒、`water_bounds/water_level/fishing_arena_config`、木台、8 个出生点、`decor` 数量与贴地规则全部保持原样。
  - **实际验证**：`tests/shore_test_area_check.gd` **44/44 通过**、`tests/shore_fishing_integration.gd` **failures=0**（本轮最后一次改动后重跑）；开发预览截图 `.mvp_qa/shore_test/`（01 出生点 / 02 钓台末端 / 03 8 m 鱼漂 / 05 战斗空地 / 07 岸线）全部重拍；**真实入口截图** `.mvp_qa/shore_entry/`（`scenes/shore_fishing_mvp.tscn` → mode 4：01 出生点 / 01b 左看 / 01c 右看 / 02 木台看水面+石拱 / 03 战斗空地看岸线），玩家实际出生在 `(300, 0.08, 6.5)`，谷、水、石拱都在正确位置；复现脚本 `tests/_capture_shore_entry.gd`。水面重做后 `02_dock_end` / `07_waterline` 与入口 `02_dock` 都是最新一版；`deep_color` 亮度 0.197，`_check_surface` 仍过。**未人工试玩**：风摆幅度、近景草叶形状、满屏树冠的遮挡感需要用户看。（CodeBuddy）
  - **已知陈旧测试（不是本轮改坏，留给各自 owner）**：`tests/fishing_mvp_test.gd` 与 `tests/capture_fishing_mvp.gd` 仍把 mode 4 的玩家硬放到训练场 `(-8, 0.08, 10)`，而 mode 4 现在把岸边 prefab 放在 `shore_origin=(300,0,0)`、出生点用 prefab 的全局坐标，所以那套用例会从"抛竿命中水面"开始整串失败；改法是改成读 `world.shore_area.player_spawn_point()`（或直接用 `scenes/shore_fishing_mvp.tscn`）。`tests/backpack_corner_test.gd` 的 "Mouse picks storage item" 失败，是因为并行的 `first_person_player.gd` 重构后 `_init_inventory()` 只给快捷栏建记录、不再把未装备武器摆进储物格（`slot_item(1,0)` 为空）；与本轮 SHORE 改动无关。
- **实际验证**：`tests/shore_test_area_check.gd` **43/43 通过**（2–12 m 落点、岸沿不挡水面、出生点→钓点 19 m 通路、候选点合法性、钓到异兽→选点生成端到端，以及装饰 4 项：全部加载 / 不进水面·抛竿走廊·战斗空地·不压出生点·无碰撞 / 全部贴地）；实机截图 `.mvp_qa/shore_test/`（01 出生点 / 02 钓台末端 / 03 8 m 鱼漂 / 04 12 m 鱼漂 / 05 战斗空地 / 06 出生点 / 06b 俯视 / 07 岸线）。**未人工试玩，只跑了检查与截图**
- **未做**：无游泳、天气、NPC、完整灯汀湾（**2026-10-28 晚更正**：已由 Codex 接进 mode 4，菜单「岸边钓场」→ `scenes/shore_fishing_mvp.tscn`；玩家出生在 `shore_origin + spawn = (300, 0.08, 6.5)`，本轮已实机截图确认，见 `.mvp_qa/shore_entry/`）
- **注意**：水面是纯视觉网格、**没有碰撞体**（钩爪射线默认打所有层，有碰撞会被当锚点）；`FishingMVP.resolve_cast` 现按 `config.arena` 的 `pond_min/pond_max/water_level` 做几何判定，挂接时须把 `fishing_arena_config()` 赋给 `fishing.config["arena"]`，否则落点仍按旧训练场水池算

### 8. 试玩地图选择与切换（组件 CodeBuddyPro；界面 Codex，2026-10-28）
- **入口**：`选择地图试玩.cmd` → `scenes/ui/map_select.tscn`，现使用 Codex 的紫金配色正式试玩菜单：左侧三张地图卡、右侧实机图与内容说明、下方进入按钮；800px宽度改为横排卡片，支持鼠标、上下键/1–3选择与Enter进入。F5现同样进入地图选择菜单，其他单图启动脚本已收进 `tools/launchers/`。（Codex）
- **界面文件**：`scripts/ui/trial_hub_menu.gd` 直接复用已有 `SceneSwitcher`，路由仍来自 `data/scene_menu.json`；展示文案/标签/图片在 `data/scene_menu_presentation.json`。实机预览图与SVG在 `assets/ui/trial_menu/`，图来自当前三张地图关闭HUD后的直接截图，复现脚本 `tools/ui/capture_map_previews.gd`。（Codex）
- **连接的三张图**：`combat_mvp`（标「主战斗 Demo」）→ `scenes/combat_mvp.tscn`；`shore_test`（「独立预览」）→ `scenes/tests/shore_test_area_preview.tscn`（带玩家的预览场景，不是只有场地本体的那个）；`cherry_valley`（「独立预览」）→ `scenes/cherry_valley.tscn`。清单在 `data/scene_menu.json`，新增试玩地图只改这份 JSON
- **调用接口（给 Codex 的统一入口 UI）**：`preload("res://scenes/ui/scene_switcher.tscn").instantiate()` 后 —— `maps()`（每项含 id / name / kind / kind_label / status / description / scene）、`enter_map(id)`（返回 false = 未知 id 或正在切换）、`enter_scene(path, label)`、`back_to_menu()`、`is_switching()`、`switching_map_id()`、`session_notice()`、`return_key_name()`；信号 `switch_started(map_id, scene_path)`、`switch_failed(map_id, reason)`。地图内若要放"返回"按钮，用 `root` 下 `SceneReturnHook` 的 `return_to_menu()` / `is_returning()`
- **返回键位**：**B**（`data/scene_menu.json` 的 `return_key`，另接受 **Backspace** 作备用）。用户键盘没有功能键，**F1–F12 全部不再使用**：`return_keycode()` 只认 A–Z 与 Backspace，Tab/Esc 留给各图自己的背包与暂停。地图内右下角是**可点击按钮**"B 返回地图选择"（`scripts/ui/scene_return_hook.gd`，紫金样式沿用 Codex），鼠标可用时（背包打开、山谷里）直接点也能返回；菜单界面文案通过 `return_key_name()` 自动跟着变。（CodeBuddyPro，2026-10-28）
- **实际验证**：`tests/scene_switch_check.gd` **52/52 通过**（清单字段与真实路径、切换中重复点击只受理一次、三张图进入/返回、返回后 0 残留玩家/相机/背景音、坏路径与未知 id 失败后仍停在可点菜单、返回按钮已接点击）；`tests/capture_scene_switch.gd` 实机截图 `.mvp_qa/scene_switch/`，训练场→菜单走真实 **B** 按键事件（`return_key=B ok=true mouse=true`），截图里右下角显示"B 返回地图选择"
- **界面验证**：`tests/trial_hub_smoke.gd` 通过真实鼠标选卡/点击进入、键盘选择、三项实机图片、800/1280布局、加载失败恢复及训练场实际返回键返回；回菜单保留本次选择并释放鼠标。实机与图像检查 `.mvp_qa/trial_menu/`，用户观感待验收；未重复全套三地图切换检查。（Codex；返回键改 B 后由 CodeBuddyPro 复跑，failures=0）
- **遗留**：每次切换仍是整场景重载，不携带背包/装备/进度、不保存，界面明确提示；樱花山谷退出时的2个纹理泄漏告警保留，单独加载山谷亦有，未在本轮处理。（Codex）

---

## 二、已确认共识与重要约束

### 用户已明确认可（仅限所列范围）
| 事项 | 认可依据 | 边界 |
|---|---|---|
| 初版钩爪 v0.1 | 用户试玩："效果出乎意料的好" | 仅该版手感 |
| 钩爪2 定版 | 用户试玩："钩爪的手感挺好的" | 仅该版手感，含配套重力/落地/攀爬 |
| 静态持剑握姿 | 用户试玩认可持剑效果 | **仅静态握持**；此后手部与抓绳多轮改动，不代表当前动态表现已验收 |
| 抓绳闭合握姿 | 用户接受闭合手姿 | 绳索路径仍在改，最终掌内贴合未确认 |
| 灯汀湾主场景风格（概念图） | 用户认可风格 | 仅美术参考，未导入引擎 |

- 守卫异常远距击飞：用户在2026-10-25明确表示“这个早就修好了”，不再列为待修任务；本轮未复测、未核对实际修复者。（Codex）

### 用户明确否定（不要重做）
- 绳轴重建 / 袖长拉伸（已回退，恢复闭合手姿与固定袖口基线）
- 抓绳时袖口扭曲、滑铲持续周期震动
- 抓绳呈现"捏圈"或"张爪"感
- 手炮触发屏幕剑风（手炮已从近战动作分支独立）
- 裸手、机械腕炮两类手部提案（手部选型已定为 04 号露指手套）
- 怪物九宫格前两轮（过于恐怖/虫形、过于 Q 版与动物拟态）
- 主角九宫格除 07 外的其余方案

### 技术约束
- 保持 **GL Compatibility**，不引入 SDFGI、体积雾、SSAO（该渲染器不支持）；樱花山谷与原提示词的渲染器/体素偏差见第四节
- 素材许可：`trailblazer_local` 源包**禁止商用与二次配布**，保留在 `.gitignore`；CombatGirls 为 Asset Store 包，**商用条款待核对**；`portal_ruins` 跨引擎发行许可待核对
- 不替用户消费 Tripo 积分、不配置付费生成（prompt2rig 高清链路含非商用依赖，未部署）
- 手部/手套源模型与贴图不改，只在运行时装配
- 旧第三人称、Tripo 主角、遗迹与历史 2D 系统保留，不删除

---

## 三、当前待办与进行中事项

### 已交付、待用户验收
- **统一试玩入口UI**（2026-10-28）：`选择地图试玩.cmd`；地图卡/实机预览/特色说明/进入与 B 返回流程已接CodeBuddyPro切换组件，支持800px紧凑布局。实际接口与验证见第一节第8项，截图 `.mvp_qa/trial_menu/`；未改正在开发的钓鱼、玩家、背包或地图脚本，观感待用户试玩。（Codex）
- **鱼竿第一人称表现**（2026-10-28）：`tools/launchers/预览钓鱼手部.cmd` → `scenes/tests/fishing_hands_preview.tscn`；自有手套沿用已验证的闭合握柄，新增木竿/缠线握把、持竿/短抛竿/短提竿及微量竿梢弯曲；袖口独立对齐，源手套/贴图不改。实现 `scripts/mvp/fishing_rod_viewmodel.gd`，表现参数 `data/fishing_rod_presentation.json`，`first_person_hands.gd` 已增加工具外观 `fishing_rod`。独立预览只演示动作、鱼漂和鱼线，不抽奖、不入包；主钓鱼流程已由 Claude 完成绑定，岸边完整场地已由 Codex 接入，详见本节最新集成记录。（Codex）
  - **给主工程的实际接入点**：玩家与钓鱼控制器就绪后调用 `player.hands.bind_fishing_controller(fishing)`，被动读取现有 `FishingMVP.state`（0..4映射为idle/casting/waiting/biting/reeling）及 `cast_progress()` / `reveal_progress()`，不驱动玩法；鱼线表现创建后调用场地现有 `set_rod_tip_anchor(player.hands.fishing_tip_anchor())`，每次重建鱼线表现重新绑定。也可手动 `set_fishing_presentation(state, progress)`；`fishing_tip_world()` 返回真实竿尖位置。（Codex）
  - **实际验证**：`tests/fishing_hands_test.gd` 90项通过，覆盖实际蒙皮掌内接触、指姿、抛收端点、换枪/空手/剑、状态接口与控制器释放；GL实机7张图及图像检查通过，已查看第一人称/握柄两侧，证据 `.mvp_qa/fishing_hands/`。测试覆盖独立预览，未验证主钓鱼集成；动态观感待用户试玩，日志/证书/图形缓存告警仍在。（Codex）
- **鱼与材料的数量背包 + 岸边掉落/靠近拾取**（2026-10-28）：见第一节「鱼与材料的数量背包 + 岸边掉落」。**实际验证**：`tests/loot_drop_test.gd` 49/49 通过（headless），覆盖 999 上限、15 格容量、满包落地、部分装入、重复拾取、已销毁掉落、跨死亡/R 重试保留、武器搬运后的数量一致；`tests/backpack_corner_test.gd` failures=0（搬运动作未受影响）；实机截图 `.mvp_qa/loot_bag/open.png`（3 种物品 + 页脚用途）、`full.png`（×999 堆叠已满）、`shore_drop.png`（满包余量落在岸边）。（CodeBuddy）
  - **未试玩**：鼠标点选渔获格的手感、999 满格与 15 格塞满时的观感、掉落物在近处的外观。
  - **遗留（交 CodeBuddy）**：`combat_arena.gd` 的钓鱼收获仍走旧的 `_grant_loot` → `FishingPickup`（已改为本轮组件的薄壳，行为不变）+ 每帧 `_update_pickups`，且死亡/切试炼时 `_clear_pickups()` 会清掉未拾取的岸边掉落；要保留就由 CodeBuddy 改 `combat_arena`，本轮未改它。异兽壳片掉落可直接用 `loot.grant("item_scale", n, spot, arena, player, hud)`（壳片沿用现有材料 id `item_scale`；`item_data.json` 里没有独立的壳片 id）。玩家侧（`first_person_player` / `first_person_hands`）无需改动：鱼与材料只进数量袋，不进快捷栏与装备栏。（附：钓鱼 MVP 主流程 `fishing_mvp.gd` / `data/fishing_mvp.json` 在代码里已存在，但本文件尚无其记录，待该轮执行者补录，不要据本条推定其已验收。）
- **暗黑骑士剑/剑08竖劈**（2026-10-26）：`first_person_hands.gd` 按武器ID走各自的上下竖劈，举起→向前下方砍→回抬，奇偶攻击重复同一动作；黑骑幅度更大、剑08稍轻，握柄与伤害/攻速不改。参数 `sword_viewmodel_motion.json.vertical_swings`，原第一把剑/剑气/其他近战分支保留。`tests/vertical_swords_test.gd` 通过竖直平面、奇偶一致、上下位移/回待机/释放恢复及原剑交替动作检查；实机 `.mvp_qa/vertical_swords/`，动态观感待试玩。（Codex）
- **鸣潮刃充能与横扫剑气**（2026-10-25）：`first_person_hands.gd` 用实际剑身网格+`shaders/tide_blade_energy.gdshader` 流动细纹替代Box充能罩；`tide_wave.gd` 改为尖端收窄的弧形网格、亮刃与两层残影，着色器 `tide_crescent.gdshader`，无Box。满3格按E，新增独立横扫，0.20s前摇后出波，总动作0.68s（时序在 `combat_mvp.json`，轨迹在 `sword_viewmodel_motion.json.wave_swing`）；原18伤/9m射程/单目标一次命中保持，切武器取消待发剑气。`tests/sword_energy_wave_test.gd` 通过蓄能消耗/前摇/单发/伤害/切换；慢速抛接专项通过，GL实机 `.mvp_qa/sword_energy/`，观感待试玩。（Codex）
- **第一把剑抛接切刀**（2026-10-25）：`first_person_hands.gd` 空中旋转由五圈/1.10s放慢至四圈/1.35s，配合握住上抛→张手撤回等待→迎柄接住→合指下沉回稳；空中剑轨迹独立于手臂，释放/接住端点由握持变换对齐。旋转中心适配加长剑，取消时恢复完整pivot变换；攻击/换武器/钩爪/攀爬/格挡/喝药取消抛接。参数在 `data/sword_viewmodel_motion.json.draw`。专项 `tests/sword_draw_catch_test.gd` 通过端点连续、接柄/开合指、切枪/攻击/钩爪/重试恢复；原持枪集成检查通过，实机关键帧 `.mvp_qa/sword_draw/`，未做正式骨骼动画，动态观感待试玩。（Codex）
- **抓绳动态牵引**（2026-10-24）：`first_person_hands.gd` 按实际接近距离前伸→收手，切向速度驱动摆荡收臂/方向跟随；前臂18→33°、摆荡最多36°。新增独立腕部渐变：远端保留现有手向，近端手腕相对前臂约45°，参数 `grapple.reel_wrist_degrees`；收手前后位移由15cm降为7cm，摆荡收手7.5cm降为4cm，实际掌内握点限制在视图前方至少46cm（`closest_grip_depth`），到限不继续靠脸。绳索握点/切线读取实际Hand骨骼世界变换，保持闭合指姿与模型长度。`tests/grapple_dynamic_pose_test.gd` 通过悬挂无时间漂移、接近收手/腕角/握点距离上限、双向摆荡、掌内绳轴/指姿/释放恢复；实机 `.mvp_qa/rope_dynamic/`。用户认为整体效果还行；本轮收手终点调整待试玩；未改钩爪物理。（Codex）
- **背包左上角展开**（2026-10-24）：仅改 `combat_hud.gd` 布局；收起5格、展开4行共用格位，保留搬运/交换与Esc/Tab操作。`tests/backpack_corner_test.gd` 通过格位命中、鼠标交换/取消、开关恢复；实机 `.mvp_qa/backpack_corner/open.png`，视觉待用户验收。（Codex）
- **第一把剑比例与侧角**（2026-10-24）：`first_person_hands.gd` 保留65°剑面方向（原90°侧转25°），换用 `assets/weapons/tide_blade_long.glb`：护手上方剑身长度1.5倍，仅延长Y中段，剑柄/护手/剑尖局部形状及X/Z尺寸保留，原GLB不改；蓝色充能壳同步加长。生成脚本 `tools/asset_pipeline/extend_tide_blade.py`，参数/来源哈希见同名JSON。逐顶点及数据核对长度、宽厚/下段/UV/索引/贴图字节通过；主场景普通/充能截图 `.mvp_qa/sword_length/`，比例观感待试玩，未改攻击距离。（Codex）
- **背包界面**（CodeBuddy，2026-10-24）：Esc/Tab 打开，第一行即快捷栏，可把武器在背包与 5 个快捷格之间搬运/交换；`hidden: true` 的条目不进背包（用户已隐藏低模左轮/霰弹/球杆与练习刃，共 7 件可见）。**实际验证**：脚本点击搬运后 `quick_slots` 从 `["tide_blade","",...]` 变为 `["tide_blade","practice_blade",...]`、背包对应格清空，关闭背包后装备生效；截图 `backpack_open / backpack_holding / backpack_moved / backpack_equipped`。**未试玩**：鼠标手感、快速连点、把药水或空手格搬走后的表现。**注意**：Esc 不再只是暂停，而是打开背包（打开时同样暂停）
- **UE5/Fab 试玩武器批次**（CodeBuddy，2026-10-24）：两把剑（Dark Knight 长剑、Sword_08）+ 低模包 8 件独立武器接入主 Demo，Tab 可选、可装备、可挥砍/射击。**实际验证**：实机逐件装备截图 `.mvp_qa/ue5_weapons/ingame/`（含 Tab 列表与挥击/开火帧），攻击脚本 14 件（10 新 + 4 原）全部 `started=true`，6 件冷兵器各命中 1–3 次、4 把枪各发弹 1 次，原练习刃/时钟剑/手炮/M1911 结果与改动前一致。**未试玩**：连续切换手感、蹲/滑铲/钩爪/蹬墙时的持械表现、长时间观感。**遗留**：低模包枪械沿用原程序握姿；3号手炮与4号M1911已另由Codex接入专用握姿（Codex补注），低模包共用一张卡通图集（斧头红色）、球杆只验证到"握把在手中、杆身朝上"（刃端在画面上方出框），Dark Knight 的 Emissive 贴图几乎全黑
- **专用持枪握姿接入主Demo**（2026-10-24）：3号原手炮/4号M1911使用JSON专用15指骨与腕向、独立握柄装配，手炮掏出时手枪整体抬起、保留专用后坐。`tests/pistol_grip_integration_test.gd` 通过，两枪开火/指姿/方向、其他10件武器切换、回剑/空手与65°剑角检查通过；实机 `.mvp_qa/pistol_integration/`，观感待试玩。独立预览保留，其他导入枪械仍为原握姿，细节 `PISTOL_GRIP_NOTES.md`。（Codex）
- **移动检查修复**（CodeBuddy，2026-10-24）：`tests/first_person_motion_test.gd` **63/63 通过**（此前 12 项失败）。修了 1 处真实故障：攀爬起始的那次跳跃被同一帧登记成"翻越冲刺"，导致每次跳上高台都被额外推力甩过对面掉下去。其余 11 项是测试依据过期：测试车道 x=18 与训练场蹬墙墙（x 17.2–17.8，z 1–11）重叠、默认模式已改为守卫试炼而测试假设无敌人、滑铲震动阈值仍按旧 6 mm、钩爪新增 0.12 s 前摇后仍按 6 帧取样。**未人工试玩**，手感待确认
- **掌内穿绳路径修正**（Codex，2026-10-24）：绳索改为入掌→掌内握点→出掌；**最终掌内贴合待用户实际视角确认**，前条"恢复获认可效果"不能当作已验收
- **守卫主战斗**（Codex）：追击/预告冲刺/拳判定/血条/重力/受击死亡与重试已接入；只有一招，部分动画为占位
- **守卫分部位受击 + 钩爪 0.12 s 前摇**（Codex）：专项 22 项 + 石拳 4 项通过，待试玩
- **守卫独立测试场景**（CodeBuddy）：三模式位移已实测，待用户查看
- **剑姬独立预览**（CodeBuddy）：骨骼轨道全部解析、冒烟无报错，待用户查看
- **樱花山谷**（Claude Code）：结构检查 64 项通过，瀑布/飞鸟位置、触控与巡游手感待试玩
- **钓鱼主流程接入手部表现与竿尖鱼线**（2026-10-28）：接续中断会话只补未完成的两处绑定，改动 `scripts/mvp/combat_arena.gd`：启动时 `player.hands.bind_fishing_controller(fishing)`，表现层每次重建后 `set_rod_tip_anchor(player.hands.fishing_tip_anchor())`；未改 `fishing_mvp.gd` / 手部脚本 / 数值。**实际验证**：既有 `tests/fishing_mvp_test.gd` **62/62** 仍通过；新增 `tests/fishing_integration_check.gd` **22/22**（绑定一次、竿尖即抛竿起点、表现层重建后重新绑定、状态映射、数量袋接口）；实机截图 `.mvp_qa/fishing_mvp/resume/`（r1 鱼线从竿尖出发 / r2 收获提示 / r3 背包渔获面板）。**未做**：未重跑 01–08 全套截图、未人工试玩，抛竿/提竿动态观感待用户验收；此前01—08截图早于本轮改动，不作当前验证依据；旧恢复副本 `.mvp_qa/recovery/fishing_interrupted_2026-10-28.zip` 仅留存备查。（Claude）
- **移动 F3/F4 两档连续移动**：代码已交付并验证，参考游戏实机对照未做
- **04 号露指手套**：绑定与接入完成，待试玩占屏、虎口握持与动作过渡

### 已确定但未开始
- 剑姬技能第三人称演出（"剑姬降临"，固定连招、不可操作）
- 守卫多段招式与 AI 深化（独立测试版无 AI、无受击/死亡）
- 直射与追踪弹
- 掉落、制作、存档闭环
- 手炮正式实现（明确后置）

---

### 岸边主流程集成（2026-10-28，Codex）
- 补齐最后的场地连接：`combat_arena.gd` 实例化岸边 prefab，并从 `fishing_arena_config()` / `pick_encounter_spawn()` 读取水域、出生与遭遇点；保留 Claude 的手部/竿尖绑定和 CodeBuddy 的数量背包。地图位移见 `data/fishing_mvp.json.shore_origin`，与训练场障碍分开。
- `scenes/shore_fishing_mvp.tscn` 是主战斗的钓鱼启动配置；`scene_menu.json` 已指向它，菜单文案同步，N/M 提示纠正。原独立岸边预览保留作开发用途。切换地图仍重载，不承诺跨地图背包；同场景 R 重试保留已入包物品。
- 岸边启动不加载训练场大型遗迹/外侧树，遗迹改为按需加载。首次检查加载阶段发生内存分配失败；调整后正常启动，未动用户进程或渲染器。
- 实际验证：`tests/shore_fishing_integration.gd` 12/12，通过完整鱼→数量袋、异兽≥5m→掉落→拾取、重试保留与切试炼重绑。已查看 GL 截图 `.mvp_qa/fishing_mvp/integrated_shore.png`；日志 `shore_integration.log`，仅有既存系统证书告警。原手部集成测试坐标改用场地钓点，未重复整套回归；操作手感仍待用户试玩。（Codex）


## 四、未解决问题与待验证事项

### 仍有效的当前问题
| 问题 | 现状与范围 | 处理方向 |
|---|---|---|
| 抓绳最终贴合 | 掌内路径已改，极端抬头角度与动态协调未确认 | 待用户实际视角验收 |
| 守卫观感 | 关节接缝、长距滑步、穿插与重量感未审核；近距避障不是完整寻路；绳索不绕障碍 | 逐段观感审核 |
| 剑姬缺口 | 脸部睫毛/眉区脏块、强光下肤色偏白；仅 7 条动作；无根运动提取（急停转向脚滑）；未接碰撞与地形；**商用许可待核对** | 后续单独排期 |
| 樱花山谷与原提示词偏差 | 提示词要求体素 GridMap + Forward+ + SDFGI，现为平滑二次元 + GL Compatibility | **待用户确认**维持现方案或改渲染器/体素；改渲染器会影响主 Demo，需另开分支评估 |
| 减少动态效果 | Godot 4 无跨平台系统接口，现由 `data/cherry_valley.json` 的 `scene.reduce_motion` 控制 | 需要系统级跟随则需原生插件 |
| 主角完整动作缺失 | 高移速与闪避复用行走动画，可能滑步；无跑步/闪避专用动作 | 先试玩，再按同一骨骼补动作 |
| 新武器握姿 | 两把剑仍用原剑握姿，已分别配独立上下竖劈，未做逐把手指适配；四把低模枪沿用原程序持枪姿势，没有专用手部动画，握把与手指贴合度未调 | 需要时再做专用持枪/持械握姿 |
| 新武器装配参数 | `combat_mvp.json` 里的 `viewmodel.scale/rotation/offset` 是逐模型实测后手调的试玩值；Dark Knight 是蒙皮模型，`get_aabb()` 的绑定姿态与实际渲染姿态不一致，不能再用包围盒推算 | 换模型或改比例时用实机截图复核 |
| UE 素材授权 | 本批 Fab 免费素材授权**未核对**，不能按 CC0 处理 | 发行前逐包核对许可 |
| 环境告警 | 系统证书/图形缓存写入报错、退出时对象清理提示仍在 | 环境问题，不影响功能判断 |
| 历史 `scripts/combat.gd` | 仍是回合制，新场景不调用 | 保留历史参考 |

### 待确认（记录冲突，未判定）
- **樱花山谷存在未记入交接的本地改动**：`.cv_qa/codebuddy_polish_round2/` 内有 70 张截图，但本文件与归档原文均无对应条目。这些改动的内容、验证与验收状态**待确认**，不要据目录存在推定已完成或已验收。
- **守卫招式口径**：早期讨论建议为"石臂横扫 / 举臂砸地 / 短距离冲撞"，实际实现为"踏步挥拳 / 蓄力砸地 / 冲撞"。哪套是最终设计未明确。
- **守卫两套资产的分工**：主 Demo 用 `guardian_06_rigid_binding.glb`（程序动作），独立测试用 `guardian_06_video_lunge_study.glb`（视频动作）。两者是否合并、以哪份为准，未决定。
- **翻越冲刺的触发方式已变更**：现在只有攀爬过程中**再次**按跳跃才触发冲刺，起始那一次跳跃不再触发。原实现是起始跳跃同帧置位，等于每次起跳攀爬都会额外 +4.5 m/s 冲出去。若本意就是"起跳攀爬即冲出"，需要回退 `first_person_motion.gd` 的 `started_mantle` 判断。

### 明确后置（不阻塞当前任务）
- 全身动画、正式形象、汤棚—钓台美术样例、植被密度实测
- 传送、完整配方、账号/支付/发布
- 约 5–6 件遗物与 3 槽为暂定数量，示例效果未批准

---

## 五、重要文件与资产入口

| 类别 | 入口 |
|---|---|
| 主战斗场景 / 逻辑 | `scenes/combat_mvp.tscn`、`scripts/mvp/`（`combat_arena` `melee_enemy` `first_person_player` `first_person_hands` `first_person_motion` `grapple_hook` `combat_hud`） |
| 主战斗数据 | `data/combat_mvp.json`、`data/first_person_presentation.json`、`data/sword_viewmodel_motion.json` |
| 数量背包 / 掉落拾取 | `scripts/mvp/fishing_loot.gd`（数量袋，唯一数量源 `scripts/inventory.gd`）、`scripts/mvp/loot_drop.gd`（岸边掉落 + 靠近拾取）、`scripts/mvp/fishing_pickup.gd`（旧钓鱼拾取薄壳）、`combat_hud.gd` 的渔获与材料区；专项 `tests/loot_drop_test.gd` |
| 鱼竿手部表现 | `tools/launchers/预览钓鱼手部.cmd`、`scripts/mvp/fishing_rod_viewmodel.gd`、`data/fishing_rod_presentation.json`；实际接入API见第三节“鱼竿第一人称表现”（Codex） |
| UE 试玩武器 | `assets/weapons/{dark_knight_longsword,sword_08,lowpoly_pack}/`（来源/许可/通道判定见 `assets/weapons/ASSET_NOTES.md`）、`scripts/mvp/imported_weapon_viewmodel.gd` |
| 守卫（主 Demo） | `assets/enemies/ruin_guardian/`（`ASSET_NOTES.md`）、`scripts/mvp/ruin_guardian_combat.gd`、`guardian_procedural_motion.gd`、`guardian_stone_fist.gd` |
| 守卫（独立测试） | `scripts/enemies/ruin_guardian.gd`、`scenes/tests/ruin_guardian_preview.tscn` |
| 剑姬 | `assets/characters/combatgirls/`（`ASSET_NOTES.md`）、`scripts/characters/katana_girl.gd` |
| 岸边钓鱼测试区 | `scenes/tests/shore_test_area.tscn`（本体）、`scenes/tests/shore_test_area_preview.tscn`（独立预览）、`data/shore_test_area.json`、`scripts/shore/shore_test_area.gd`、`scripts/shore/shore_test_preview.gd`、`shaders/{pond_water,grass_wind,valley_hill}.gdshader`、`assets/environments/stylized_nature/`（CC0 植被，`ASSET_NOTES.md`） |
| 试玩地图选择 / 切换 | `选择地图试玩.cmd`、`scenes/ui/map_select.tscn`、`scenes/ui/scene_switcher.tscn`、`data/scene_menu{,_presentation}.json`、`scripts/ui/{scene_switcher,scene_return_hook,scene_menu_data,trial_hub_menu}.gd`；原 `map_select_menu.gd` 仅保留为最小验证版（Codex补注） |
| 手部 / 手套 | `assets/characters/fps_gloves/`、`assets/characters/fps_arms/`（各含 `ASSET_NOTES.md`）、`scripts/mvp/fps_glove.gd` |
| 樱花山谷 | `scenes/cherry_valley.tscn`、`scripts/cherry_valley/`、`data/cherry_valley.json`、`shaders/valley_*` |
| 山谷导入地标 | `assets/environments/pagoda_cherry/`（`ASSET_NOTES.md`）、`data/cherry_valley.json` 的 `landmark` 块、`valley_world.gd::_build_landmark` |
| Blue Archive Miyako | `assets/characters/miyako/`（`ASSET_NOTES.md`，仅检查未接入：无骨骼/动画、346k 面、需放大百倍） |
| 主角模型 | `assets/characters/newcomer_tripo/`（9,992 三角面、65 骨、约 1.75 m） |
| 遗迹场景候选 | `assets/environments/portal_ruins/`（32 网格、58 实例、12 贴图，`ASSET_NOTES.md`） |
| 素材包（唯一主目录） | `docs/art/未名之海_3D建模素材包/`；守卫原始件与工程在 `06_模型回收/怪物/遗迹守卫/{source,authoring,素材说明.md}` |
| 证据 | `.mvp_qa/`（按任务分目录）、`.cv_qa/`（樱花山谷、剑姬、守卫）、`.gdd_qa/`（GDD 排版） |
| 文档 | `PRD.md`、`docs/GDD_未名之海.md`、`docs/plans/2026-10-mvp.md`、`docs/人物模型制作规则.md` |
| 技能 | `../../skills/godot-first-person-hands/SKILL.md`（工作区唯一副本） |
| Godot补充技能 | `../../skills/scenario-godot-{expert,animation,vfx,shaders}/`，完整技能/脚本已安装，Codex用户技能目录以Junction指向工作区；未把其AgentKit装进游戏，保持现有GL Compatibility约束。（Codex） |

---

## 六、最近交付与历史入口

### 近期实际交付（倒序，仅结论）
| 日期 | 执行者 | 事项 | 状态 |
|---|---|---|---|
| 2026-10-28 | Codex | 钓鱼下拽/回收与蓝色光球落地、T显式拾取接入主场景；绑定通用库存，补两处遗漏引用。主集成14项通过，实机截图与限制见末尾交接。 | 已接入，待试玩（Codex） |
| 2026-10-28 | CodeBuddy | 岸边钓场美化：接入 Ultimate Stylized Nature（Quaternius，CC0 1.0）8 个模型、59 处无碰撞装饰，木台入口加「钓点 · 上木台」指示牌，预览曝光 0.95→0.90；检查 43/43、截图 `.mvp_qa/shore_test/`；未人工试玩，菜单「岸边钓场」仍指向 `shore_fishing_mvp.tscn`（combat_mvp mode 4） | 已交付，待试玩（CodeBuddy） |
| 2026-10-28 | CodeBuddyPro | 跑动镜头起伏：按 Apex 头动（含俯仰/偏航）补齐旋转分量；第一版 3.2 cm 被用户判"太抖"，回退后冲刺峰峰 2.2 cm / 俯仰 0.34° / 滚转 0.38° / 偏航 0.16°，走路约 63%，停下归零；新增 `tests/camera_bob_check.gd` 7/7，移动专项 63/63（修掉一条早于起伏功能的过期检查） | 已交付，待试玩（CodeBuddyPro） |
| 2026-10-28 | Codex | 正式启动统一为根目录选择地图试玩.cmd，F5同样进入地图菜单；10个开发预览脚本迁入tools/launchers并修正路径。一次默认启动烟测及路径检查通过；README/CLAUDE与当前入口记录已同步。 | 已完成（Codex） |
| 2026-10-28 | Claude | 接续钓鱼中断会话：补齐 `combat_arena.gd` 手部控制器绑定与竿尖鱼线锚点（含表现层重建后重绑），未改钓鱼逻辑/手部脚本/数值；`fishing_mvp_test` 62/62、新增 `fishing_integration_check` 22/22，实机 `.mvp_qa/fishing_mvp/resume/`。 | 已接入，待试玩（Claude） |
| 2026-10-28 | Codex | 钓鱼任务上下文超限后的恢复核查：确认核心脚本及8张截图落盘，保存22文件快照并补短交接；未改游戏代码、未重跑检查，完成度待接续核实。 | 恢复入口已留，待接续（Codex） |
| 2026-10-28 | CodeBuddy | 岸边钓场山谷化：谷底高度场 + 三面低丘/远岭、约 190 棵分层森林、石拱与青苔石、18000 株带风的草 + 芦苇野花；**水面重做**（法线纹理 + 天空反射 + 池底下凹 + 关闭树影，见第一节）；新增 `grass_wind`/`valley_hill` 着色器；`shore_test_area_check` 44/44、`shore_fishing_integration` 0 失败；开发预览 `.mvp_qa/shore_test/` 与真实入口 `.mvp_qa/shore_entry/` 都已重拍 | 已交付，待试玩（CodeBuddy） |
| 2026-10-28 | CodeBuddy | 鱼与材料数量背包（复用现有 `Inventory`、单格 999、15 格容量）+ 可复用的岸边掉落/靠近拾取组件 `scripts/mvp/loot_drop.gd` + `combat_hud.gd` 渔获与材料区（图标/名称/数量、点选常驻用途说明）；专项 50/50（已适配后续「落地按 T 拾取」流程与 `bind(inventory)` 重构）、背包搬运 0 失败、实机 3 张截图 `.mvp_qa/loot_bag/` | 已接主战斗背包，待试玩（CodeBuddy） |
| 2026-10-28 | Codex | 地图选择改为紫金试玩菜单：地图卡、三张真实场景图、内容说明、进入动作与返回指引；复用CodeBuddyPro路由，800/1280布局、鼠标/键盘、失败恢复及训练场返回验证通过，证据 `.mvp_qa/trial_menu/`。 | 已接统一入口，待试玩（Codex） |
| 2026-10-28 | CodeBuddyPro | 试玩地图选择 + 场景切换组件：训练场/岸边预览/樱花山谷三张现有图接入。**返回键由 F10 改为 B（备用 Backspace），地图内右下角改为可点击按钮**，`return_keycode()` 不再接受任何 F 键；岸边预览调试键 F1–F3 改为 M/N/X。52 项检查、真实 B 按键返回与截图 `.mvp_qa/scene_switch/`，Codex 的 `trial_hub_smoke.gd` 复跑 failures=0 | 已交付，待试玩（CodeBuddyPro） |
| 2026-10-28 | Codex | 木鱼竿与自有手套持竿/抛竿/提竿独立预览，修正袖口朝向；提供钓鱼状态与真实竿尖绑定API。90项检查及GL实机图通过，证据 `.mvp_qa/fishing_hands/`。 | 独立交付，待主流程挂接与试玩（Codex） |
| 2026-10-28 | CodeBuddyPro | 岸边钓鱼测试区：新增场地本体场景 + 独立预览入口 + 布局 JSON；水面 32×21 m、木钓台、钓点标记、24×15 m 战斗空地、8 个异兽候选点与 2 根钩爪石柱。结构检查 40/40、实机截图 `.mvp_qa/shore_test/`；未接主场景，未改 combat_arena/玩家/手部/HUD/渲染配置 | 已交付，待试玩（CodeBuddyPro） |
| 2026-10-26 | Codex | 按用户授权安装Scenario Godot主技能/动画/VFX/Shaders四项到工作区skills并建立Codex发现入口；SKILL文件及8个Python文件语法检查通过，未执行下载的工具包、未改变游戏配置。另评估gamedev-skills仓库，工作区已有多项同名技能，未重复安装。 | 已安装，项目内工具链效果未测（Codex） |
| 2026-10-26 | Codex | 暗黑骑士剑和剑08各配重复上下竖劈，保留原剑动作与两剑伤害/攻速；专项通过，实机 `.mvp_qa/vertical_swords/`。 | 已接入，待试玩（Codex） |
| 2026-10-25 | Codex | 切刀减速为四圈/1.35s；剑身充能改贴面流纹、冲击波改弧形剑气并新增横扫发射动作。剑气/抛接专项通过，实机 `.mvp_qa/sword_energy/`。 | 已接入，待试玩（Codex） |
| 2026-10-25 | Codex | 第一把剑抛接配套手部张合、迎柄与回稳，空中轨迹分离、取消恢复；抛接专项及持枪集成检查通过，实机 `.mvp_qa/sword_draw/`。 | 已接入，待试玩（Codex） |
| 2026-10-24 | Codex | 第一把剑剑身加长至1.5倍，保留宽厚、剑柄/护手和剑尖形状；新GLB保留原件、充能壳同步，几何核对及主场景普通/充能截图 `.mvp_qa/sword_length/`。 | 已接入，待试玩（Codex） |
| 2026-10-24 | Codex | 抓绳按距离收手/摆荡跟随，并新增近端约45°腕角；绳索随真实手骨握点移动。收手终点后移并限制握点距视图46cm；动态专项含腕角/距离上限/掌内绳轴/释放检查通过，远近实机 `.mvp_qa/rope_dynamic/`，未改钩爪物理。 | 已接入，待试玩（Codex） |
| 2026-10-24 | Codex | 背包从居中面板改为左上角快捷栏向下展开，首行位置不跳动、保留原配色及物品交互；专项通过，实机 `.mvp_qa/backpack_corner/`。 | 已接入，待试玩（Codex） |
| 2026-10-24 | Codex | 专用持枪握姿从独立预览接入主Demo的3号手炮/4号M1911，指姿与握柄JSON统一、手炮整体抬手取出；专项检查通过，实机 `.mvp_qa/pistol_integration/`，其他导入武器保留，环境日志/证书告警仍在。 | 已接主Demo，待试玩（Codex） |
| 2026-10-24 | CodeBuddy | 科幻短刀改名 **暗影匕首**、放大 1.5 倍（scale 0.8→1.2）、刀尖由垂直朝上改为朝前上 45°（用户反馈"拿反了"）；实机特写 `ingame/knife_full.png` / `knife_zoom.png`，攻击命中 1 次 | 已修正，待试玩（CodeBuddy） |
| 2026-10-24 | CodeBuddy | 科幻短刀接入并修正装配：实测长轴为 Z（柄 z −0.074…+0.112、刀身 +0.112…+0.298），改为 `rotation [-90,0,0]` + `offset [0,-0.02,0]`；第一版按 Y 轴装导致刀横插在手、只剩一小截。实机截图与攻击验证通过。98K 步枪按用户要求整体移除 | 已修正，待试玩（CodeBuddy） |
| 2026-10-24 | CodeBuddy | 樱花山谷接入 Pagoda Cherry 烘焙庭院：`landmark` 配置 + 压平台地，隐藏包内 200 单位夜空球；包内樱花是原始 38 面 alpha 纸片（材质名 `sakura_billboard`，非导入问题），按用户要求隐藏 `sakuras`，由山谷自己的卡通树围上来 | 已接入，待试玩（CodeBuddy） |
| 2026-10-24 | CodeBuddy | 泰拉瑞亚式装备栏（护甲 3 + 饰品 5，背包右侧竖列）+ 首件饰品"疾风之靴"默认装备；免疫坠落伤害已生效（穿/脱/再穿 = 0/52/0），移速加成按用户要求暂不生效 | 已接入，待试玩（CodeBuddy） |
| 2026-10-24 | CodeBuddy | 坠落伤害：安全高度 6.3 m（钩爪柱台面）、每米 6 点、封顶 60，攀爬/蹬墙不计；实测 6.3→0 / 6.4→1 / 9→16 / 15→52 / 25→60 / 原地跳→0，截图 `ingame/fall_damage.png` | 已接入，待试玩（CodeBuddy） |
| 2026-10-24 | CodeBuddy | Blue Archive Miyako 资产检查：35 网格 / 346k 面 / **无骨骼无动画无形态键** / 尺寸需放大百倍，只能当静态雕像；未接入任何场景 | 仅检查（CodeBuddy） |
| 2026-10-24 | CodeBuddy | 背包 UI：泰拉瑞亚式 5×4 网格，第一行即快捷栏，点击拿起/放下交换，Esc 或 Tab 开关；物品清单自动取 `combat_mvp.json`，替换掉原 OptionButton 菜单；实机截图与搬运逻辑脚本核对通过，未提交 | 已接入，待试玩（CodeBuddy） |
| 2026-10-24 | CodeBuddy | UE素材试玩批次接入：Dark Knight长剑、Sword_08（重接底色/法线/ORM）、低模包8件独立武器；Tab 可选可装备，复用现有挥砍与直射路径，默认快捷栏不变；实机截图+14件攻击验证通过，未提交 | 已接入，待试玩（CodeBuddy） |
| 2026-10-24 | Codex | UE素材接入：训练场后墙外3棵树，修叶片透明/树皮贴图；4号M1911，保留3号手炮，支持现有直射/伤害/后坐。入口 `imported_tree.gd`、`m1911_viewmodel.gd`，两资产目录 ASSET_NOTES；专项及实机 `.mvp_qa/ue5_placement/` 通过，原手部专项26项通过。枪为临时纯色材质/旧程序握姿，未做手部新动画；两把剑/低模武器包未接入，未提交。 | 已接入，待试玩（Codex） |
| 2026-10-24 | Codex | 桌面 ue5 素材5包临时项目试导入：树27,797三角、剑3,044、Dark Knight剑13,468、M1911绑定版12,080/10骨无动画、低模武器独立文件材质可读；树/旧剑需重接贴图，M1911贴图未见，授权待核对。报告 `.mvp_qa/ue5_asset_audit.json`，隔离审计工程 `D:/claude project/tools/asset_audits/ue5_20261024`；未替换游戏资产。 | 导入检查完成，未接入（Codex） |
| 2026-10-24 | CodeBuddy | 移动检查修复：63/63 通过，含 1 处攀爬冲刺误触发 | 待试玩 |
| 2026-10-24 | CodeBuddy | 遗迹守卫独立测试场景（视频动作版，未接主战斗） | 待查看 |
| 2026-10-24 | Codex | 掌内穿绳路径修正 | 待用户确认 |
| 2026-10-24 | Codex | 守卫分部位受击、钩爪 0.12 s 前摇 | 待试玩 |
| 2026-10-24 | Codex | MVP 表现升级：守卫程序行走与三招、腰间编织钩索 | 待试玩 |
| 2026-10-24 | Codex | 守卫接入主战斗（追击/拳判定/血条/死亡） | 待试玩 |
| 2026-10-24 | Codex | 豆包视频动作适配守卫（3 倍冲刺距离） | 待审核 |
| 2026-10-22 | CodeBuddy | 剑姬角色独立预览（C 方案第一步） | 待查看 |
| 2026-10-21 | Claude Code | 樱花山谷场景（结构检查 64 项通过） | 待试玩 |
| 2026-10-21 | CodeBuddy | 钩爪2 定版（用户认可手感） | 已认可 |
| 2026-10-21 | Codex | 自有皮手套持剑接入主 Demo | 静态握持已认可 |

### 历史档案
- **完整原文**：`docs/history/CHECKPOINT_2026-10-24.md`（2026-10-18 至 2026-10-24，242 行 / 51 KB，含全部条目、署名、路径与修改记录）
- 追溯早期过程（如抓绳多轮回退、手部选型、概念图迭代）以该档案为准，本文件不再复述。

---

*本文件由 CodeBuddy 于 2026-10-24 整理：合并同一事项的历次迭代，保留最终有效状态、用户否定约束、遗留问题与证据入口；原文已完整归档，未改任何代码、资产或配置。*

### 钓鱼反馈与背包参考核查（2026-10-28，Codex）
- 已定位收线缺少 REVEAL 回程分支、鱼/装备两套库存及E键冲突；机制来源、真实截图链接与获取限制存于 `docs/art/references/fishing_inventory/钓鱼与背包参考.md`。本轮未改游戏代码、未声称拿到本地参考截图。
- 已生成供用户手动转发的场景优化指令；其余分工同轮输出，尚未确认任何执行者接单。后续由实际执行者局部补交接，不把此记录当作完成或计划。（Codex）

### 钓鱼拉扯、回收与光球拾取（2026-10-28，Codex）
- 已接主场景：鱼漂三段下拽/回弹、同步竿梢弯曲/短音效；收竿时浮漂/鱼线真实回程，普通渔获以蓝色光球随回程出现并落到前下方岸面/钓台。取消等待也回收空钩，取消换装/钩爪则立即清理。去掉结算后的3秒状态锁；随机咬钩算法未改。
- 普通鱼与异兽材料均为蓝色光球（Compatibility 无需 Bloom）；靠近按 **T** 才通过 `try_add` 入包，不自动吸走、不提前发奖，飞行中不可拾取，满包留地。落点射线读取真实岸面/木台高度；同一份掉落不可重复结算。`loot.bind(player.inventory)` 已接通现有通用库存，未改 HUD 或重做库存设计。
- 主要文件：`scripts/mvp/{fishing_presentation,fishing_mvp,fishing_rod_viewmodel,loot_drop,loot_orb_visual,combat_arena}.gd`；手部同步仅补 `bite_progress()`；表现参数 `data/fishing_feedback.json`，结算等待 `data/fishing_mvp.json`。另补两处阻塞引用：玩家 `assign_quick_slot` 的旧 `backpack_slots` 改读 `inventory.slots`、岸边补已有 `valley_mesh_kit.gd` 引用，未覆盖并行功能。
- 实际验证：独立模块11项、主场景反馈12项及更新后的岸边集成14项通过；末次主集成日志 `shore_integration.log` 无脚本错误，覆盖鱼/材料显式拾取、异兽出现与恢复、重试保留。已查看主场景 `feedback_return.png` / `feedback_drop.png`（`.mvp_qa/fishing_mvp/`）。有既存证书/GL缓存告警及退出资源残留；一次贴图加载失败复跑未复现，未重导入资源。动态手感待用户试玩。（Codex）
- 交接：背包 UI 仍由其他 Agent 完成；旧 `fishing_mvp_test.gd` 的场地硬编码与自动拾取断言未迁移，本轮用 `fishing_feedback_check.gd` 和 `shore_fishing_integration.gd` 验证新交互，不声称旧整套回归通过。（Codex）

### 去除教学与操作提示（2026-10-28，Codex）
- 按用户要求，主试玩隐藏钓鱼教学/调试面板、消息浮条、试炼引导与BOSS招式建议；背包移除操作说明，掉落只显示名称×数量，训练场/岸边文字路标不再显示。山谷不再画操作帮助，菜单与返回按钮去掉按键教学；血量、物品、伤害与功能按钮保留。
- 改动 HUD、拾取标签、两处场地标牌、菜单/返回组件及山谷 HUD；未改键位和玩法。实机启动与截图检查通过（`clean_hud.png` / `clean_hud.log`，无脚本错误），未重复战斗回归。后续 Agent 新做 UI 时也遵循用户这项偏好，不重新加教学提示。（Codex）

### 精简键位与命中后牵引延迟（2026-10-28，Codex）
- 已交付：F为统一 `interact`（旧 `fps_pickup` 仅留同键别名）；Tab背包、Esc菜单，背包里Esc只收起背包。新增 `scripts/ui/play_pause_menu.gd`，试炼/重试/开发工具/地图选择都能点击；主试玩停用旧快捷操作和重复返回按钮，保留独立预览的开发键。
- 钩爪原“延迟”只延后加速曲线但立刻给起步拉力；现在实际等待“绳索视觉飞行结束 + 命中后0.2秒”才施加拉力、侧向力或阻尼。等待期间正常移动/重力保留，松开可取消，跳跃助推不得绕过；牵引开始后才开放助推。参数 `data/first_person_presentation.json.grapple.impact_pull_delay_seconds`；`grapple_hook.gd.is_pulling()` 供移动/跳跃判断，`is_attached()` 继续供绳索与手部显示。
- 相关入口：`combat_arena.gd`、玩家/移动模块、HUD暂停时避开背包绘制与鼠标抢占、`scene_return_hook.gd`；`fishing_feedback.json`与项目interact输入同步F。未改变已有武器动作、背包结构或添加教学提示。
- 实际验证：`tests/controls_latch_check.gd` 17项通过，无脚本错误；真实GUI鼠标点击切换试炼和开发选项、F拾取不再跳场、Tab/Esc互不冲突、命中等待无力、助推限制/松开取消。已查看 `.mvp_qa/fishing_mvp/action_menu.png`，日志 `controls_latch.log`；未重复整套旧回归，动态手感待用户试玩。（Codex）

### Agent Dispatch 共享入口（2026-10-28，Codex）
- 正文原已在工作区 `skills/agent-dispatch/SKILL.md`，此次补工作区与游戏项目的 `.claude/skills/agent-dispatch`、`.codebuddy/skills/agent-dispatch` 四个目录链接；Codex原链接保留。所有入口指向同一份正文，修改会共享。
- 已在 `skills/_SOURCE.md` 和根级 AGENTS/CLAUDE 登记；技能措辞改为不限编排者，保留手动调用与精简派工规则。文件结构、四个链接目标与正文哈希检查通过，尚未在 Claude/CodeBuddy 界面验证列表刷新；未修改游戏代码。（Codex）
- 本轮守卫设计共识：大型、笨重、高伤害的基础敌人；允许依战况连续冲撞，不设固定重复次数限制。避免撞墙陷入、装甲脱落、小守卫等额外制作；保留硬部位减伤与低血量狂暴方向，尚未实现。（Codex）

- **钩爪命中等待缩短（2026-10-28，Codex）**：按用户试玩反馈，将 `impact_pull_delay_seconds` 从0.2秒改为其1/3（约0.0667秒），脚本默认值、现有目标检查时间点及README同步。仅校验配置值，未重跑游戏或验证手感；发射前摇、飞行和牵引加速参数不变。（Codex）

### 滑铲腿部视角提案（2026-10-28，Codex）
- 已基于原新来者服装、自有露指手套与当前场景风格生成一张第一人称滑铲效果提案：低机位略低头、左腿前伸/右腿弯曲，深灰卷边裤与棕色短靴，画面无教学文字。已查看输出，保存 `docs/art/未名之海_3D建模素材包/10_第一人称手部/滑铲第一人称_腿部姿态提案_2026-10-28.png`；这是生成概念图，不是实机效果，姿势与露腿比例待用户审核。
- 未调用Tripo、未修改游戏代码；腿部模型复用/新增范围待图确认后核对现有资产。守卫新共识：只有凸起的角可作钩爪锚点，其他身体部位不可钩；该规则尚未实现。（Codex）
