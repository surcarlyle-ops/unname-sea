# 《未名之海》Combos AI 原型生成 Prompt

> **历史简化提示词，非当前开发指令（2026-10-20）**：下文 2D Web 方案只保留作参考。现已改为第一人称、Godot 简模 MVP；执行前以 GDD 第 13 章当轮目标为准，不直接把本页交给工具生成当前游戏。（Codex）

> 用途：复制下方 prompt 到 https://combos.ai 生成简化玩法原型，验证钓鱼与自由实时攻击的基本关系。
> 现行依据：[GDD](GDD_未名之海.md)。本提示词保留 2D 简化表现，用于验证自由移动、攻击、闪避及三类武器的差异，不验证最终 3D 镜头。
> 注意：下文 Web 简化原型不能验证当前第一人称移动、近战距离与手持遮挡，必须在 Godot 3D 小场景验证。（Codex）

---

## 中文版 Prompt（直接复制）

```
做一个 2D 钓鱼游戏原型，主题是"未知异世界的水域"。

【画面】
- 俯视或侧视角，一片淡紫渐变天空下的水面，色调温暖明亮
- 玩家是一个小小的角色，站在水面边缘，手持一根简陋的树枝鱼竿
- 水面有缓慢的波纹动画，水下偶尔有微弱的光点闪过

【核心玩法：30 秒钓鱼循环】
1. 按空格键抛竿 —— 鱼漂落入水中
2. 等待 3-8 秒（随机），鱼漂上下轻微起伏
3. 鱼漂突然下沉 —— 屏幕出现提示"！"
4. 在 0.5 秒内按空格键 —— 成功则收线，失败则脱钩（鱼跑了）
5. 收线成功后，随机获得一样东西

【随机结果（每次钓鱼）】
- 50% 普通鱼（显示为一条小鱼图标，+10 分）
- 25% 垃圾（显示为一只破鞋，+1 分）
- 20% 任务物品（显示为一个发光碎片，+50 分）
- 5% 异兽（屏幕震动，进入战斗）

【战斗（简化自由实时原型）】
- 出现一只怪异生物，用简单形状占位；敌人实时移动和攻击，不按回合行动
- WASD 自由移动，鼠标选择攻击方向，左键攻击，Shift 闪避；相机和角色不持续朝向某个敌人
- 按 1/2/3 切换测试武器，攻击无需先锁定目标
- 武器 1：范围近战，以可见的挥击或扇形范围提供命中宽容度
- 武器 2：直射攻击，提供轻度辅助瞄准；不得明显抢走玩家选择的攻击方向
- 武器 3：追踪弹，仅此类武器具备追踪能力；目标选择应符合发射方向与玩家预期
- 辅助力度、追踪能力、攻击范围和闪避冷却按实时秒数调试，不预设固定命中率
- 提供命中、受击、击败和掉落反馈；击败敌人后掉落鱼骨，返回钓鱼；玩家血量归零则重置本次战斗
- 提供单敌、多敌、敌人横向移动、近距离交错四种测试场景，检查辅助抢方向、追错目标和特效遮挡

【炼化（合成试验）】
- 收集 3 个鱼骨后，屏幕下方出现"炼化"按钮
- 点击炼化 → 播放一个短暂的发光动画 → 获得"骨制鱼竿"
- 装备骨制鱼竿后：等待时间从 3-8 秒缩短到 2-5 秒，脱钩率从 30% 降到 15%

【UI】
- 左上角：分数
- 右上角：当前鱼竿等级
- 底部：物品栏（显示已获得的物品图标）

【整体氛围】
温暖、安静、略带神秘。不要卡通搞笑风格，要一种"美丽中藏着未知"的感觉。
```

---

## English Version Prompt (Copy & Paste)

```
Create a 2D fishing game prototype. Theme: "waters of an unknown other world".

【Visuals】
- Top-down or side view. A water surface under a pale-purple gradient sky, warm and bright palette
- A small player character stands at the water's edge holding a crude branch fishing rod
- Water surface has slow ripple animation; faint light spots flicker underwater occasionally

【Core Loop: 30-Second Fishing Cycle】
1. Press SPACE to cast -- the bobber lands in the water
2. Wait 3-8 seconds (random); bobber bobs gently up and down
3. Bobber suddenly sinks -- an "!" prompt appears
4. Press SPACE within 0.5 seconds -- success pulls the line in, failure means the fish escapes
5. On success, randomly receive one item

【Random Outcomes (per cast)】
- 50% common fish (small fish icon, +10 points)
- 25% junk (a worn shoe, +1 point)
- 20% quest item (a glowing shard, +50 points)
- 5% creature (screen shakes, enters combat)

【Combat (Simplified Free Real-Time Prototype)】
- Spawn a strange creature represented by simple shapes. Enemies move and attack in real time, with no turns
- Use WASD to move freely, the mouse to choose attack direction, left click to attack, and Shift to dodge. Do not keep the character or camera facing an enemy
- Use 1/2/3 to switch test weapons. Attacks require no target lock
- Weapon 1: area melee, with a visible swing or cone that provides forgiving hit coverage
- Weapon 2: direct fire with mild aim assistance that preserves the player's intended direction
- Weapon 3: homing projectiles, exclusive to this weapon type. Target selection should match the firing direction and player expectations
- Tune assistance strength, tracking, attack coverage and real-time cooldowns through playtests. Do not promise a fixed hit rate
- Show hit, damage, defeat and loot feedback. Defeated creatures drop fish bones, then return to fishing. Reset the encounter if the player's HP reaches zero
- Provide single-enemy, multiple-enemy, lateral-moving-enemy and close-crossing scenarios. Check unwanted aim redirection, wrong-target homing and visual obstruction

【Refining (Crafting Test)】
- After collecting 3 fish bones, a "Refine" button appears at the bottom
- Click Refine -> brief glowing animation -> receive "Bone Rod"
- With Bone Rod equipped: wait time shortens from 3-8s to 2-5s, escape rate drops from 30% to 15%

【UI】
- Top-left: score
- Top-right: current rod level
- Bottom: inventory (shows collected item icons)

【Overall Mood】
Warm, quiet, slightly mysterious. Not cartoonish or comedic -- aim for a feeling of "beauty hiding the unknown".
```

---

## 使用说明

1. 打开 https://combos.ai
2. 把上面的 prompt（中文或英文）粘贴进去
3. 等待生成
4. 试玩钓鱼循环与三类攻击，重点感受：
   - 等待时的"期待感"够不够
   - 咬钩瞬间的"紧张感"够不够
   - 收获时的"惊喜感"够不够
   - 炼化时的"上瘾感"够不够
5. 记录三类攻击在四种测试场景中的方向理解、距离判断、命中反馈、辅助行为和遮挡问题。
6. 历史流程仅供参考；现行第一人称与 3D 战斗验证以 GDD 为准。（Codex）

## 验证重点

| 维度 | 要问自己的问题 |
|---|---|
| 等待感 | 等待的 3-8 秒是"无聊"还是"期待"？ |
| 咬钩感 | 0.5 秒的按键窗口是"紧张"还是"烦躁"？ |
| 收获感 | 看到"获得一条鱼"时有没有一丝开心？ |
| 稀有度 | 5% 的异兽出现时有没有"哇"一下？ |
| 炼化感 | 凑齐 3 个鱼骨去炼化时有没有"想试试"的冲动？ |
| 自由战斗 | 能否自由移动、转向、攻击和闪避，无需先锁定敌人？ |
| 武器差异 | 范围近战、辅助直射、追踪弹是否有不同的操作体验？ |
| 命中辅助 | 是否抢走攻击方向或频繁追错目标？ |
| 可读性 | 单敌、多敌、横向移动和近距离交错时，目标与命中反馈是否清楚？ |

> 记录上述问题的具体行为与反馈，先修正手感和命中辅助问题，再扩内容；Web 原型反馈不能替代 Godot 3D 试玩。
