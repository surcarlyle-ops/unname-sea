# 新来者：Tripo 主角

- 来源：用户提供的 `anime+character+3d+model.glb`，生成器标记为 Tripo。桌面已整理为 `未名之海_3D建模素材包/01_人物/主角/新来者_Tripo_待机行走_原始.glb`；原件 SHA256 见 `import_report.json`。（Codex）
- `source/newcomer_tripo_original.glb` 保存完整原始下载，`.gdignore` 防止源文件重复导入；`newcomer.glb` 是游戏使用的副本，只把 `idle.001` / `walk.001` 改名为 `idle` / `walk`，未重做骨骼、蒙皮、动作或纹理。（Codex）
- 65 根骨骼、12,502 个顶点、9,992 个三角面；原始高度约 1 米，在公共角色场景中等比缩放到约 1.75 米，沿用现有碰撞体与第三人称镜头。（Codex）
- 实际动画：`idle` 15.375 秒，`walk` 2.375 秒；两者循环。原数据的骨盆水平位移仅有浮点误差，位移继续由 Godot 控制。（Codex）
- 岸边与遗迹共用 `scenes/mvp/player_3d.tscn`，均已切换到本主角。跑步与闪避暂复用真实行走动画；尚无专用跑步、闪避、战斗或钓鱼动画，当前效果待用户试玩验收。（Codex）
- 验证：`verification.log` 中 35 项实际场景检查通过，覆盖骨骼与动画播放、移动、镜头、碰撞、闪避与落水返回；`preview_back.png` / `preview_front.png` / `preview_walk.png` 为 Godot 实际渲染，不代表用户已认可动作自然程度。（Codex）
- 旧穹模型仅保留于原目录以便追溯，已从公共角色场景解除引用；其来源限制仍适用于旧文件，不随本次角色替换改变。（Codex）
