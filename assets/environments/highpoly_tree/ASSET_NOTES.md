# 围墙外三棵测试树
- 来源：用户从 Fab 下载的 HighPoly Tree Model；桌面原包 `C:/Users/QAQ/Desktop/未名之海_3D建模素材包/ue5/HighPoly_Tree_Model-2f1f43fe/`，原件未改。（Codex）
- 游戏副本：tree.fbx、三张2K PNG；单树27,797三角面。`scripts/mvp/imported_tree.gd` 重新连接叶片/树皮底色和树皮法线，叶片使用双面透明裁切；不沿用 UE 专用材质。（Codex）
- `combat_arena.gd` 生成 ExteriorTrees 下3棵树，位置(-14,0,-30)/(0,0,-34)/(14,0,-31)，比例0.56/0.64/0.60，高约15–18米；均在后墙外，纯装饰，不加碰撞/风摆。当前没有额外LOD或密集植被性能优化。（Codex）
- 已在真实训练场截图检查，`.mvp_qa/ue5_placement/`。仅少量试摆，最终风格待用户试玩；不据下载免费推断CC0，发行授权待按账号领取许可核对。（Codex）
