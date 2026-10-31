# 专用持枪握姿：主 Demo 已接入
- 来源 bukkbeek/GodotFPS-Template，fps_demo_arms.glb 的 pistol_fire t=0；原参考与许可保存在相邻 fps_arms/pistol_reference/。读取到真正手枪射击/换弹轨道，仅迁移静态握姿，不宣称完整动画已移植。（Codex）
- 目标仍为用户原露指手套。按腕部解剖掌面迁移骨骼旋转差值，原2节指骨旋转分配至目标3节；食指保留扳机姿态，拇指用长度约束校正接触。不是统一grip角度。几何、UV、权重、贴图均未改。（Codex）
- 运行时数据 pistol_grip_pose.json：15根指骨、腕向、两把手枪的独立装配。M1911使用临时色材质；原手炮曲柄/扳机接触仍需最终用户判断，不能把静态构图宣称为零穿模。（Codex）
- 入口：项目根“预览持枪握姿.cmd”，1 M1911、2原手炮、3原作者参考；C切第一视角/掌心/手背；左键短后坐。原作者模式播放原pistol_fire；自有手模式仅做整体短后坐，没有换弹玩法。（Codex）
- 可复现迁移：Godot --headless --path 项目 --script res://tools/asset_pipeline/retarget_pistol_grip.gd。输出只写专用JSON，并保留手工武器装配参数。（Codex）
- 验证 tests/pistol_grip_preview_test.gd：15指骨与来源切换/后坐恢复通过，实际截图 `.mvp_qa/pistol_grip/`。现有握剑专项21项通过，不代表新握枪用户验收。（Codex）
- 2026-10-24 用户确认CodeBuddy完成导入后，专用握姿接入 `first_person_hands.gd`，仅用于3号原手炮与4号M1911；15指骨、腕向和握柄装配来自同一JSON。手炮切入改为整只手与枪一起抬起，后坐复用现有专用开火路径。其他导入枪械保持CodeBuddy装配，未改左手抓绳、移动或伤害逻辑。（Codex）
- 主场景验证 `tests/pistol_grip_integration_test.gd` 通过：两枪指姿/前向/实际开火后坐、10件导入武器可见切换、切回剑与空手清除枪姿，剑65°侧角保留；实机截图 `.mvp_qa/pistol_integration/`。非完整动作迁移，未新增换弹；最终贴合和动态手感待用户试玩。（Codex）
- 环境：项目原有左右手贴图ctex缓存报WebP解码，定向重建又报WebP packing failed。已恢复重建前生成缓存，保留备份于 `.mvp_qa/pistol_grip/cache_backup/`；预览采用GLTFDocument直接读取原GLB绕过缓存。退出有material空引用/系统证书/图形缓存提示，未宣称环境问题已根治。（Codex）
