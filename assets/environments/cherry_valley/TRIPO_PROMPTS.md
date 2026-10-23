# 樱花山谷 · Tripo 模型提示词（CodeBuddy 编写）

> 目标：替换当前程序化生成的「两种树 + 房屋」。场景侧尺寸/朝向/材质槽要求见第 6 节，交付后由我负责导入与替换。
> 提示词依据 Tripo 社区《Ultimate Tripo AI Guide》的实测结论：**单一主体 + 1~3 个最显著形容词 + 3D 质感短语**，写长不会更准；一次只生成一个物体；颜色只指定 1 种主色最可靠。

---

## 0. 通用写法（每个模型都适用）

- **一次只生成一个物体**。不要写「一棵树和一间房子」，Tripo 会只挑其中一个。
- 提示词控制在 **1~2 句**。主体 + 2 个形容词 + 一句 3D 质感短语就够。
- 结尾固定加：`single object, centered, isolated on white background, no ground plane, no shadow, no scene`
- 需要对称的（房屋、塔）显式写 `symmetry`，Tripo 会照做。
- **不要用透明贴图面片做树叶/花**：项目用卡通着色器 + GL Compatibility，alpha 面片会露白边、叠影严重。所有花和叶子都要**实体几何**（提示词里写 `solid geometry, no alpha cards`）。
- 推荐参数：`Model: v2.5 或 v3.0`｜`Symmetry: on`（建筑）｜`Texture: on`｜`Polygon: 中等`。先用 Draft 试形状，形状对了再 Refine；Refine 可能出「多头」类畸形，所以主体尽量简单。

---

## 1. 樱花树（最优先）

**用途**：山谷主景，全场景 88 棵 + 1 棵主树，靠实例化复用 → 只要 **1 个模型**（可选再做 1 个瘦高变体）。
**目标尺寸**：高 6.5 m（主树放大到 10 m），冠幅 7 m。**面数 ≤ 15000**。

### 英文提示词（主用）

```
A single cherry blossom tree in full bloom, dense clusters of soft pink blossoms, dark slender forking trunk with visible bare branches between the flower clusters, wide flat crown, stylized anime game asset, hand painted, solid geometry with no alpha cards, seamless mesh, artifact-free curvature, single object, centered, isolated on white background, no ground plane, no shadow, no scene
```

### 中文对照（界面支持中文时用）

```
一棵盛开的樱花树，密集的浅粉色花簇，深色细长分叉的树干，花簇之间能看到裸露枝条，宽阔扁平的树冠，二游卡通风格游戏资产，手绘质感，花和叶为实体几何不使用透明面片，网格连续无破面，单一物体，居中，纯白背景，无地面，无投影，无场景
```

### 变体句（想做第二棵时追加）

```
, narrower upright crown, slightly taller trunk, fewer but larger blossom clusters
```

**要点**：现有程序化版本最大的问题是「一坨粉色球」。提示词里 `visible bare branches between the flower clusters` 这一句是关键，不要删。

---

## 2. 针叶树 / 杉（深林背景树）

**用途**：120 棵背景林，远距离填充 → 面数必须低，**≤ 3000**。
**目标尺寸**：高 8.5 m，冠幅 4 m。

### 英文提示词

```
A single Japanese cedar tree, tall narrow conical silhouette, layered dark green foliage tiers, short straight brown trunk, low poly stylized anime game asset, solid geometry with no alpha cards, seamless mesh, single object, centered, isolated on white background, no ground plane, no shadow, no scene
```

### 中文对照

```
一棵日本杉树，高瘦的锥形轮廓，层叠的深绿色枝叶，短而直的棕色树干，低多边形二游卡通风格游戏资产，枝叶为实体几何不使用透明面片，网格连续，单一物体，居中，纯白背景，无地面，无投影，无场景
```

**要点**：现在是「三个圆锥叠起来」，远看像塑料。`layered foliage tiers` + `narrow conical silhouette` 能出真正的杉树剪影。别写「松树」，Tripo 容易给成圆球状的松。

---

## 3. 民居（村屋，4 栋复用）

**用途**：村中 4 栋，靠旋转/缩放做变化 → 只要 **1 个模型** + 2 个变体句。
**目标尺寸**：屋身 7 × 5.5 m，含屋顶总高 5.2 m。**面数 ≤ 12000**。

### 英文提示词

```
A single story Japanese countryside house, gray blue tiled hipped roof, cream plaster walls with dark timber frame, wooden front door, one small warm glowing paper window, low stone plinth, symmetry, stylized anime game asset, hand painted, seamless mesh, single object, centered, isolated on white background, no ground plane, no shadow, no scene
```

### 中文对照

```
一栋单层日式乡村民居，灰蓝色瓦片四坡屋顶，米色灰泥墙面配深色木构框架，木质正门，一扇透出暖光的小纸窗，低矮的石砌基座，对称，二游卡通风格游戏资产，手绘质感，网格连续，单一物体，居中，纯白背景，无地面，无投影，无场景
```

### 变体句（第 2、3、4 栋各用一个，避免四栋一样）

```
# 变体 A（略小、带侧披屋）
, smaller footprint, one side lean-to extension, no veranda
# 变体 B（茅草顶）
, straw thatch roof instead of tiles, wider eaves
# 变体 C（两层半）
, two story with a narrow wooden balcony on the upper floor
```

**要点**：`symmetry` 必须写，否则屋脊容易歪。屋顶颜色写成 `gray blue`，和场景里 `#6f7a74` 的冷灰瓦一致。

---

## 4. 茶屋（带外廊，单栋）

**用途**：出生点视野内的近景建筑，需要能看清外廊和暖光窗。
**目标尺寸**：屋身 10 × 7 m，总高 6.4 m，外廊宽 2.6 m。**面数 ≤ 18000**。

### 英文提示词

```
A single Japanese tea house, wide open veranda with slim wooden posts, cream plaster walls and dark timber beams, warm glowing paper window screens, reddish brown curved hipped roof with upturned eaves, cloth awning over the veranda, symmetry, stylized anime game asset, hand painted, seamless mesh, single object, centered, isolated on white background, no ground plane, no shadow, no scene
```

### 中文对照

```
一间日式茶屋，宽阔的开放式外廊配细木柱，米色灰泥墙与深色木梁，透出暖光的纸窗格，红棕色曲面四坡屋顶且檐角上翘，外廊上方有布制遮阳篷，对称，二游卡通风格游戏资产，手绘质感，网格连续，单一物体，居中，纯白背景，无地面，无投影，无场景
```

---

## 5. 神社 / 五重塔（次要，有余力再做）

**用途**：对岸远景地标，玩家主要在中远距离观看。

### 5.1 神社（目标：屋身 9 × 7 m，总高 6.8 m，≤ 12000 面）

```
A single small Japanese shrine, vermilion pillars, white plaster walls, dark stone tiled curved roof, golden double door, small torii gate standing in front, symmetry, stylized anime game asset, seamless mesh, single object, centered, isolated on white background, no ground plane, no shadow, no scene
```

### 5.2 五重塔（目标：总高 18 m，底层宽 8.6 m，≤ 20000 面）

```
A five story Japanese pagoda, vermilion body, dark tiled eaves with upturned corners, tapering levels, gold spire on top, symmetry, stylized anime game asset, seamless mesh, single object, centered, isolated on white background, no ground plane, no shadow, no scene
```

---

## 6. 交付要求（这几点决定我能不能直接用）

| 项目 | 要求 | 原因 |
|---|---|---|
| 格式 | **GLB**，贴图内嵌或同目录 | Godot 直接导入 |
| 朝向 | 正面朝 **-Z**，Y 轴向上 | 场景里 `rotation.y` 靠这个对齐 |
| 原点 | 放在**底部中心**（树根 / 房屋地面中点） | 现在是按地形高度直接摆放，原点在中心会半埋 |
| 尺寸 | 按上表真实米制，别用厘米 | 缩放写错会整体比例失调 |
| 树 | 1 个模型即可，靠实例化做 88 棵 | 面数是硬指标：樱花 ≤15000、杉 ≤3000 |
| 材质槽 | 优先 1 个材质；**樱花树如果方便，请把「树干/枝条」和「花簇」拆成 2 个槽** | 花簇要按实例染色（粉→白渐变），树皮要单独套 toon |
| 透明 | 禁止 alpha 面片 / 镂空贴图 | Compatibility + 卡通着色器会露边 |
| 命名 | `cherry_tree.glb` / `conifer.glb` / `house_a.glb` / `tea_house.glb` | 我按名字接进 `valley_flora.gd` / `valley_architecture.gd` |

放好后告诉我文件路径，我负责：套项目 toon 材质 → 替换程序化网格 → 保留现有实例化与碰撞 → 同机位出对照截图。

---

## 7. 一句话优先级

樱花树 → 针叶树 → 民居 → 茶屋 → 神社/塔。
前两个做完，山谷的整体观感变化最大；后三个是近景细节。
