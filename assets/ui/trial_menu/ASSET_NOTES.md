# 试玩入口界面资源

- `compass.svg`、`arrow.svg`、`close.svg`、`backdrop.svg`：Codex 为本项目绘制的 SVG 图标与界面背景，2026-10-28；未调用图片生成或外部素材服务。
- `combat.png`、`shore.png`、`valley.png`：从项目当前训练场、岸边测试区、樱花山谷直接运行截图，关闭 HUD 后保存，未进行图片编辑。复现入口：`tools/ui/capture_map_previews.gd`。
- 场景截图所含底层资产沿用各自原许可；本说明不替代导入资产的授权记录。
- 地图路由来自 `data/scene_menu.json`；本菜单的展示文案、特色标签和图片对应关系位于 `data/scene_menu_presentation.json`，两者分别维护。
