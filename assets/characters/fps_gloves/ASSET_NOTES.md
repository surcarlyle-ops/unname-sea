# 第一人称露指手套 — 资产来源与当前状态

## 最新：MVP 手部表现修正（2026-10-24，Codex）

- 掌内绳路补修：用户指出回退后仍从手底下绕过；固定抓绳姿势不再调整，绳体在局部按握柄轴经过入掌/掌心/出掌三点，主长段保持绷直。验证掌内方向/握点及松开，平视和40/63度抬头实机图 `.mvp_qa/rope_recovery/` 已检视；不把旧闭合指姿检查等同于绳体贴合验收。（Codex）
- 当前有效版本：用户否定下述“绳轴重建＋袖长1.8倍”方案，现已撤销。恢复原获认可的闭合抓绳/固定袖口基线，不拉伸袖子或手部；基线求解后整臂仅追加小幅共同旋转（原跟随30%）。抬手/牵引分帧 `.mvp_qa/rope_recovery/` 已检视，15指骨及松开检查、专项26项通过，最终动态待用户试玩。（Codex）
- 最新握绳修正：此前整臂朝袖口转动导致掌内握柄轴错离绳索，用户否定“捏圈”。改以实际绳索对齐握柄X轴、正交袖向构建整臂姿态，取消腕骨反向补偿；闭合指姿不变。裁切袖仅运行时轴向延长1.8倍，手骨反向缩放抵消，保持手部比例及握点；原模型不变。专项26项及左右牵引实机已检查，最终动态待试玩。本条替代下方上一轮腕部补偿方案。（Codex）
- 后续反馈修正：原“前臂转向＋手骨完全抵消”让袖口蒙皮拧折；现将主要转向分配给整个视角手臂，局部腕弯限制20度，仍保留握点及闭合指姿。左右牵引截图已检视，专项22项通过，最终观感待试玩；此条替代下方关于前臂跟随已完成的早期结论。（Codex）
- 状态持剑：保留原待机/走跑/蹬墙跑，新增下蹲左倾45度、滑铲/钩索收剑及跳跃落地下沉，参数 `weapon_motion`；抓绳的袖口不再朝固定肩端抵消转向，整段可见前臂跟随，模型不新增大臂。空手基姿指尖下垂。专项扩为19项通过，实机图 `.mvp_qa/viewmodel_refinement/`；最终动态观感待用户试玩。（Codex）
- 手炮改为独立短后坐，实际发弹时触发：持续0.18秒、后移5cm、上抬1.2cm、俯仰4度，不再进入近战挥动或屏幕剑风分支。空手待机进一步放低，跑步按实际速度/步频低位交替摆臂，允许手自然离开画面。（Codex）
- 抓绳闭合握姿保留，左前臂随锚点方向和侧向运动平滑转动，俯仰/偏航/滚转上限分别10/12/5度；准备和释放回正，不改变钩爪牵引物理。参数 `data/first_person_presentation.json`；专项 `tests/viewmodel_refinement_test.gd` 14项通过，实际画面在 `.mvp_qa/viewmodel_refinement/`，最终手感待用户试玩。未新增全身/脚部模型，未用Blender。（Codex）
- 钩爪保留120ms可取消准备状态，到点按当前视线发射；准备时无绳索/牵引，松右键/暂停取消。快出钩360m/s（16–60ms）、回收80ms，主段绷直，仅握点附近保留15mm局部弯曲、腰段6mm微垂；旧专项和截图见 `.mvp_qa/guardian_regions/`、`.mvp_qa/mvp_upgrade/`。（Codex）
- 专用闭合握姿来自已验证剑握姿的正确左手镜像 `(qx,-qy,-qz,qw)`，避免同帧两次平滑握持相互抵消；前臂/手腕反向补偿保持袖口方向及握点。用户已接受此前闭合握姿，本次只追加受限跟随。（Codex）

- 保留网格/UV/贴图/骨骼，修正分离的皮肤/手套/指甲薄片按各自连通块平滑导致的权重不连续；手指区域改用连续空间权重场。修复脚本 `tools/asset_pipeline/repair_glove_weights.py`（NumPy，无Blender），本轮底稿 `.mvp_qa/mvp_upgrade/original_glove_*.glb`；重新运行旧生成器会覆盖此权重修正，需再执行修复脚本。源文件 `source/` 未改。
- 运行时手部材质双面显示，避免原薄片背面消失；手炮降低独立指节弯曲、剑仍用已适配四元数。非剑手部整体后移0.10m/缩放1.12，降低近眼透视夸张，不改世界FOV。空手待机放低；按实际速度/位移步频交替摆臂，空中/滑铲/攀爬/挂钩停用跑步摆动。参数 `data/first_person_presentation.json`。
- 左手增加抓绳过渡，绳索通过掌心握点接到腰间，不新增手模。新行为27项、原握剑21项通过，实际空手/两步相位/剑/枪/抓绳截图 `.mvp_qa/mvp_upgrade/` 已检视；极限角度与最终握持观感仍待用户验收。以下旧验证只对应当时版本，不代表当前全量回归。（Codex）

## 历史：自有手套接入成熟握姿（2026-10-21）

- **用户验收**：用户实际试玩后认可自有手套持剑效果。只确认当前握持；源包其他动作未适配、不视为已验收。完整复盘已沉淀到工作区 `skills/godot-first-person-hands/`，项目映射和弯路见其 references/unname-sea-case.md。（Codex）

- 用户认可原版近战握持更自然，明确要求保留自有手套并接入主 Demo。现已在 `fps_glove.gd` 读取 `sword_grip_pose.json`，持剑／练习刃采用专用右手姿势，左手、空手与手枪仍走各自原路径；不是替换成模板裸手。现有左右手 GLB、皮手套／布袖贴图、网格和权重未改。（Codex）
- Blender 脚本 `tools/asset_pipeline/retarget_melee_grip.py` 实际导入 CC0 `Arms.fbx`，以 Sword_Idle 第 1 帧为来源，将指节方向从源腕部／解剖掌面转换到现有手套坐标；四指映射源 MCP 开始的三节，拇指保留弯曲平面并按本手掌比例修正到食指接触位置。不直接复制不兼容的骨骼 Euler 角，也不迁移整套挥砍。（Codex）
- 剑柄中心调整为 `(0,-0.037,-0.110)` 米，沿用刃朝拇指／食指侧的跨掌方向，保留现有剑抛接、充能及挥击实现。CodeBuddy 同时调整手枪；本轮保留其最新内容，手枪锚点仍以原 `(0,-0.034,-0.132)` 加独立偏移计算，不跟随本次剑柄校正。（Codex）
- 可编辑工程 `authoring/glove_sword_grip.blend`、带 SwordGrip 姿势动画的 `authoring/glove_authored_grip.glb`；authoring 目录 `.gdignore` 避免引擎重复导入工程。运行时采用现有 GLB＋JSON 指骨姿态，源动作来自前述 CC0 项目。Blender 工程同时装配自有剑，可继续编辑；手套／剑本身不是该 CC0 项目的素材，不混淆其来源。（Codex）
- 主场景实际截屏已检查第一人称、掌心／手背、跑动、滑铲、攀越和挥击，证据 `.mvp_qa/glove_game_*.png` / `glove_grip_*.png`。手套已有自然包握轮廓，近景贴合仍需用户验收，不宣称零穿模。（Codex）
- `authored_glove_grip_test.gd` 21/21，通过真实 Demo 装备路径核对 15 根指骨、空手切换、袖口和手枪分离。旧 glove 测试 28/29，失败是并行修改后默认手枪与旧“空手启动”断言不符；旧战斗 36/41，关闭新握姿对照仍出现相同 5 项失败（启动、第二击击败目标、敌人受击时机、无敌帧、钩爪牵引）。日志与对照脚本 `.mvp_qa/grip_retarget/`。本轮未改物理、伤害和钩爪，旧移动 7 项未重测。证书与 Blender 缓存权限环境报错仍在。（Codex）

- 范围：只做用户选中的九宫格 04 号手部，棕色露指皮手套、布袖；本轮不制作手炮。Codex 已处理网格、骨骼、基础姿态与游戏接入。（Codex）
- 状态：2026-10-21 已接入第一人称，替换方块手臂；左右手各 22 骨，支持张手、放松、握持的程序姿态，以及原有跑动、滑铲、攀越与挥击的手臂过渡。不是录制动画包，观感待用户验收。（Codex）
- 参考目录：`docs/art/未名之海_3D建模素材包/10_第一人称手部/`。上传使用 `03_04号露指手套_单图上传_Tripo.png`；`04_04号露指手套_结构三视图_仅供核对.png` 仅用于核对手背、掌心与侧面，不能作为一张图上传重建三个手臂。（Codex）
- 用户原件：`C:\Users\QAQ\Desktop\未名之海_3D建模素材包\01_人物\leather gauntlet 3d model.glb`，已完整复制为 `source/hand_glove_04_raw.glb`，桌面原件未改。SHA256：`2fd52c7fe8d7131d5fb98479018fd03e14d9019048a5fb1c4623812da98617fa`。用户下载的生成结果，未另行核验账号许可文件。（Codex）
- 原件：10,654 顶点、10,298 三角面，内嵌底色贴图，无骨骼或动画；游戏左右手共 20,596 三角面，保留 UV 与贴图。左右手副本为 `glove_right.glb` / `glove_left.glb`；左手镜像烘焙并反转三角形绕序，不使用负缩放。（Codex）

## 当前处理与验证

- `tools/asset_pipeline/prepare_fps_glove.py` 使用 NumPy 重建米制游戏副本；关节位置见 `rig_layout.json`。自建前臂、手腕、五指三节及指尖共 22 骨；沿三角形连通关系平滑权重、焊合 UV 重复点，修复初版握拳拉尖。来源与统计见 `source_audit.json` / `import_report.json`。（Codex）
- `scripts/mvp/fps_glove.gd` 驱动真实指骨并调整拇指对掌；`first_person_hands.gd` 按跨掌 -X 轴放置剑柄（刃在拇指／食指侧，剑首在小指侧，避免反握），中心 `(0,-0.034,-0.132)` 米，武器统一缩放 0.65，真实剑按原模型握柄 Y=0.18 对齐，不再重复平移／倾斜。默认空手、待机低位，取剑右手侧握，挥击旋转连续。兼容 CodeBuddy 抛接动画并处理取消；关闭第一人称投影。本轮未制作手炮。（Codex）
- `tests/first_person_glove_test.gd` 29 项通过，战斗 41 项通过。移动 56/63，停用所有手部更新后同样 7 项失败，详见 CHECKPOINT；不以此前全通过记录替代现状。日志 `.mvp_qa/glove_verification.log` / `motion_verification.log` / `combat_verification.log` / `motion_without_viewmodel.log`。（Codex）
- `tools/asset_pipeline/check_glove_deformation.py` 检查张手／放松／握持／最大弯曲：顶点有限、袖口稳定，最大三角边额外伸长约 10.53mm（检查上限 12mm）。结果见 `deformation_report.json`；几何检查不能替代观感验收。（Codex）
- 原件四视角、绑定三姿态和实际空手／持刃截图均已检视，证据 `.mvp_qa/glove_source_*.png` / `glove_rig_*.png` / `glove_game_*.png`。截屏脚本 `tests/capture_glove_poses.gd`。无 GDScript 错误；日志仍有系统证书读取／图形着色器缓存环境报错。（Codex）
- 后续：已按 CodeBuddy 导入的新剑适配并检查握柄正反面近景；虎口和指节极限变形仍可精修。尚无手指 IK、手指碰撞、布料物理或专用钩爪发射动画；先试玩位置、占屏与动作，再决定下一轮调整。（Codex）

## 握姿质量反馈与替代路线调研（2026-10-21）

- 用户否定当前“鸡爪”式握姿。现有脚本主要用单个 grip 参数统一缩放指节转角，29 项功能检查不代表握姿自然；外观未验收，停止把小幅转角调整当成已解决。（Codex）
- 建议路线：成熟的第一人称手部网格与绑定 → 剑柄放入虎口、逐指调整专用握姿 → 保存握持姿势／动作 → 用骨骼附着点跟随 → 第一人称及掌心近景验收。先交付一把剑的自然静态握持，再接待机、取出、挥击；整套动作与模型尚未替换。（Codex）
- [CG Cookie 第一人称动画制作](https://blog.cgcookie.com/posts/how-great-first-person-animations-are-made-10-tips-for-animating-fps-characters-in-blender/)：复用姿势库、独立动作、手与武器层级及保持中央视野；[Epic 姿势资产](https://dev.epicgames.com/documentation/en-us/unreal-engine/animation-pose-assets-in-unreal-engine)与[骨骼附着点](https://dev.epicgames.com/documentation/en-us/unreal-engine/skeletal-mesh-sockets-in-unreal-engine)提供同类工作流参考。（Codex）
- Godot 可用 [BoneAttachment3D](https://docs.godotengine.org/en/stable/classes/class_boneattachment3d.html) 附着武器；[动画重定向](https://docs.godotengine.org/en/stable/tutorials/assets_pipeline/retargeting_3d_skeletons.html)需要匹配骨骼与初始姿态，不能假定把动作套入本手套即可解决变形。IK 可定位手腕，不自动补好手指接触和错误权重。（Codex）
- 候选 [WRAD ARMS](https://wriks.itch.io/wrad-arms)：作者标明 CC0、完整 IK 绑定、GLB/FBX/OBJ、1200 三角面；适合作为低成本结构基准，但页面未承诺现成持剑动画，低模外观不作为最终手套方案。[PSX FPS Arms Free](https://heyheythere.itch.io/psx-fps-arms-free)：作者标明 CC BY 4.0、GLB 和 Godot 支持，含空手及刀具等动作；同时披露模型／动画使用 AI 代码生成，仅列候选，不能凭“有动画”判定优于当前效果。（Codex）
- [GDQuest FPS arms](https://github.com/gdquest-demos/godot-4-FPS-arms)可参考 Godot 接入与动画结构；[根许可证](https://github.com/gdquest-demos/godot-4-FPS-arms/blob/main/LICENSE)区分代码 MIT 与美术 CC-BY-NC-SA 4.0，不能因仓库开源便直接把默认美术用于商业版。（Codex）
- 本轮只查阅作者／官方资料并核对现有脚本，未下载或购买替代素材、未改模型和游戏代码、未重跑游戏。上述候选均未经过本地导入和动作观感验证。（Codex）

### 补充：优先 Godot 原生与 GitHub 实例

- 首选测试候选 [bukkbeek/GodotFPS-Template](https://github.com/bukkbeek/GodotFPS-Template)：README 标注 Godot 4.6、使用 Cursor、作者自制手臂动画；已查阅真实 [knife.tscn](https://github.com/bukkbeek/GodotFPS-Template/blob/main/weapons/knife.tscn)，存在近战标记、knife 动画、独立指骨姿势与持物节点，当前刀具显示在左手，并非本项目右手剑的直接替代。根 LICENSE 为 MIT，README 另有禁止转售素材条款，采用时需保留原文并核对素材复用条件。尚未本地运行，不承诺质量或直接兼容。（Codex）
- 备选 [Ayush-Mohanty/FPS-Arms-3D](https://github.com/Ayush-Mohanty/FPS-Arms-3D)：Godot 4 手臂场景、待机／射击／换弹。模型子目录 [license.txt](https://github.com/Ayush-Mohanty/FPS-Arms-3D/blob/main/Models/fps_ak-74m_animations/license.txt)实际为 Cransh 的 CC BY 4.0，需署名，不能只按根目录 MIT 处理；以枪械持握为主，未确认持剑动作。（Codex）
- [Chafmere/Godot4-FPS-Template](https://github.com/Chafmere/Godot4-FPS-Template) 可参考独立武器资源和动画引用结构，未核实适合替换本手套的现成模型／握剑姿态，不作为已确认的手部资产推荐。（Codex）
- 下一步建议：单独运行候选原版手臂与刀具，先看握姿和动画，再替换当前剑验证握柄尺寸与动作；通过后只整合手部表现，保持当前主控制器与钩爪。本轮外部仓库文件只通过网页读取；终端网络请求未成功，没有本地下载、运行或更换游戏资产。（Codex）

### 小红书原帖核查（2026-10-21）

登录后用站内搜索核查了以下 6 篇正文／作者回复，部分视频只抽看可播放片段；不声称完整看完所有视频，不把经验分享视为资产许可或现成功能验证。本轮未发评论、关注、购买、下载素材或修改游戏。（Codex）

| 作者／原帖 | 实际读到的内容与用途 |
|---|---|
| plane17：[Codex做游戏｜搭地图+角色动作+手柄控制](https://www.xiaohongshu.com/explore/6aa8b1af000000001103ac7a) | 正文描述 GPT 操作 Blender 与 Godot，另找免费动作库绑定角色，再接控制与交互；该视频当时无法播放，未确认具体动作库及近景手指质量。证明有同平台工具分工实例，不是第一人称握剑成品。 |
| 树懒TV：[Howto｜AI+Godot制作3D游戏完整流程分享](https://www.xiaohongshu.com/explore/6a674381000000000f01e982) | 作者置顶回复明确使用 Hi3D 做模型；另一回复建议先审参考图再生成 3D，强调素材质量。已读回复并查看视频片段，未核实完整手部绑定流程。 |
| Leoqoi：[用Godot开发的第一人称射击游戏模板](https://www.xiaohongshu.com/explore/6a966fb3000000000b0028e7) | 正文介绍现成移动、武器、反馈和模块扩展，视频可见手臂与武器演示；该帖未给出明确仓库和模型授权，不能认定为 bukkbeek 的同一项目，也不能仅凭“源码”宣传采用。 |
| 麦壳思LAB技研：[手部动画为什么对第一人称射击动画很重要](https://www.xiaohongshu.com/explore/6a1ecb7f000000003503a1ae) | 正文为专门手部动画讲解，抽看片段可见持枪／重新抓握设计；未完整观看，不据此推导可直接套用的握剑资源。 |
| 木易毛毛：[第一人称视角移动交互动画用Blender怎么做](https://www.xiaohongshu.com/explore/6755a39a000000000202439c) | 正文介绍 OmniStep 的 Blender 第一人称控制／交互原型用途，未提供手指抓握解决方案，不作为本次修手插件推荐。 |
| ThyLoveCode：[Godot3D第一人称射击游戏源码](https://www.xiaohongshu.com/explore/6ad8141d000000002b001d01) | 正文以整套游戏内容介绍为主，未找到可核验的开源仓库与手部工作流，不列为直接采用候选。 |

结论：未找到经核实能一键修复当前 Tripo 手部握剑的 Godot 插件；小红书实际经验支持将模型、动作库与引擎接入分工。下一步仍优先实测已查到的 GitHub 原版手臂／近战动作，合格后再适配剑和手套，不能用“AI 自动绑定”替代近景验收。（Codex）

### 专用近战候选补查（2026-10-21）

- **后续实测覆盖下方筛选状态**：用户随后授权重试 Unity-First-Person-Melee；Codex 已在独立 Godot 场景验证 9 条动画、原版短剑和项目剑装配。入口 `预览近战手部.cmd`，实际效果、限制和来源见相邻 `../fps_arms/ASSET_NOTES.md`。静态包握可继续评估，裸手细节及挥砍占屏未达最终验收，生产手套未替换。（Codex）

- **最新筛选结论优先于下方历史推荐**：用户反馈 Code 已试过 BigAndCrispy 与 PSX Medieval Weapons Free，两套均不合适；具体原因待补，不重复测试或推荐。继续免费优先，WRAD ARMS 仅提供低模绑定基础，不能当作已完成握剑动画的替代。本轮没有确认可直接采用的第三套免费近战成品。（Codex）
- 付费候选 [Kubold FPP Melee Animset](https://www.fab.com/listings/bca2eb05-3e35-4d38-8a54-79e8206aaf12)：官方列 360 条第一人称剑／斧／锤、双手剑、矛、长柄及匕首动作，明确包含 FBX、不含控制器；[作者 FAQ](https://www.kubold.com/unreal-faq-2)说明源 FBX 可在 Blender 等软件修改。[官方卖家页](https://www.fab.com/sellers/Kubold)检索显示起价 US$74.99，结账价格与许可以实际页面为准。该包是动画候选，不能承诺自带符合要求的手套网格、当前手套无需重绑或已经兼容 Godot；未购买／下载／实测。（Codex）

- 更正上文优先级：bukkbeek 是射击模板，含刀具不足以证明适合右手持剑，降为结构参考。优先验证 [BigAndCrispy/Unity-First-Person-Melee](https://github.com/BigAndCrispy/Unity-First-Person-Melee)（旧 ItsPogle 地址重定向至此）。作者声明自制模型／动画，已核实根 LICENSE 为 CC0，Models 下存在 Arms.fbx、Steel Shortsword.fbx；Arms.fbx.meta 的导入配置明确列有 Sword_Idle、Sword_Slash1/2、Sword_Walk，名称表另含防御、空手、左手施法等。未读取 FBX 二进制或实际播放，不能把名称表等同全部动作已验证。（Codex）
- Unity 控制器不能直接用于 Godot；复用对象是模型、骨骼和动画。下一步先用原版手臂和剑做独立 Godot 导入验证，检查手指、握柄和挥击，再适配本项目剑；当前手套外观不能假定无成本套用。（Codex）
- Godot 备选 [PSX Medieval Weapons Free](https://heyheythere.itch.io/psx-medieval-weapons-free)：作者列明剑／斧第一人称手部与待机、取出、挥击、检视等动作，GLB／FBX、Godot 4.3—4.7、CC BY 4.0；属于代码生成的 PS1 低模素材，仅作待测基准，不自动满足精细手套要求。（Codex）
- 成品参考 [Sword and Shield First Person Animation Set](https://www.fab.com/listings/ced87ee2-dbfa-4b7b-9af8-fd1f19ed9ab8)：35 条专用剑盾动作，页面仅列 Unreal Engine 格式，手部网格、跨引擎导出和具体许可未确认，不能当作 Godot 即用包。DOM6543/3D-RPG-Godot 未确认手部与许可证；Silver Delivery 的 Low World 页面标明暂不可下载，均不优先采用。本轮仅网页调研、记录；未下载、购买、修改游戏或运行测试。（Codex）

## 原生成步骤（留作来源，当前无需重复生成）

1. 图生 3D，上传上面的 03 单图；先生成 **一个独立手和前臂**，不上传九宫格或整页三视图。若有智能网格／P 系列可选，先用游戏资产路线，保留五指细节，不激进减面。
2. 旋转检查五指数量、指缝、拇指与腕部、掌心、袖口；手指粘连或缺失时先把结果交给 Codex 评估，不连续盲目重抽。
3. 本轮先导出静态模型，不选人形自动绑定或动作包；独立前臂的骨骼需要单独处理。避免把整个人形绑定流程当成已验证适用。
4. 纹理优先 2K；若界面只有更高分辨率，保留原纹理后续由 Codex 处理。导出 **GLB** 并保留材质与贴图；只有 FBX 时使用 FBX 并保留贴图文件及原 ZIP。
5. 文件放本目录的 `source/`；建议文件名 `hand_glove_04_raw.glb`。下载是 ZIP 时保留 ZIP 即可，不把 ZIP 改成 GLB 后缀。原件由 Codex 保管和检查后再生成游戏用副本。

## 验收原则

验收顺序：轮廓、左右手身份和指缝 → 纹理与近景 → 几何与左右手适配 → 骨骼与权重 → 独立近景 → 握持与移动过渡 → 实际游戏与回归。不能只凭“带骨骼”判断手指能自然活动。

Tripo 单图生成不保证掌心与关节拓扑正确；基础程序姿态不等于完整动作库。

官方说明（2026-10-21 已核对）：[生成教程](https://www.tripo3d.ai/blog/tripo-studio-tutorial-english)、[支持格式](https://www.tripo3d.ai/product-doc/support/faq)、[人形／动物自动绑定范围](https://www.tripo3d.ai/product-doc/module-post-processing/rigging-animation)。

## 两种挥砍迁移（2026-10-21，CodeBuddy）

- 目标：把 CC0 `Arms.fbx` 的 `Sword_Slash1/2` 迁到自有手套，形成交替挥砍，让手腕、手指与剑一起动。按 `skills/godot-first-person-hands` 的诊断顺序执行，先读本目录与 `fps_arms/ASSET_NOTES.md` 交接，未重复既有结论。
- 工具：`tools/asset_pipeline/extract_slash_tracks.gd`（Godot headless，不依赖 Blender）。本机 Blender 不可用，因此把原 `retarget_melee_grip.py` 的解剖掌面算法移植到 GDScript，逐帧采样源动作。
- 关键坑一：headless 下 `AnimationPlayer.seek()` 与 `Skeleton3D.force_update_all_bone_transforms()` 都不会刷新 `get_bone_global_pose()`，必须手动计算全局变换，否则所有帧读到同一姿势。
- 关键坑二（Codex 审查后修正）：`Skeleton3D` 的 `bone_pose` 已是完整局部变换（已含 rest），链乘时**不能再乘 rest**。错误写法 `result * rest * pose` 会让手腕基准偏移约 1 米、旋转差约 50°。正确写法是 `local = Transform3D(Basis(pose_rotation), pose_position)` 再 `local.basis.scaled(pose_scale)`，逐级相乘；修正后与内置 `get_bone_global_pose()` 逐骨误差小于 1e-7。
- 输出：`assets/characters/fps_gloves/sword_slash_tracks.json`，含 `Sword_Idle` 基准帧 + 两段各 51 帧的手腕位置／四元数与 15 根指骨局部四元数。
- 接入：`fps_glove.gd` 新增 `apply_pose_override()` / `clear_pose_override()`，攻击期间直接写入迁移姿势、绕开统一 grip 与 authored 混合；`first_person_hands.gd` 新增 `_apply_slash_arm()`，按相对基准的增量叠加到 `right_arm`。
- 幅度：公式修正后两段轨迹幅度接近（手腕 X 约 0.7 米），统一用 `SLASH_POS_SCALE=0.24`、`SLASH_ROT_WEIGHT=0.25`，不再分段处理。源动作按第三人称录制，位移与旋转都要压低，否则手臂会甩到镜头前。
- 现状：`Sword_Slash1` 右下上撩到中上、`Sword_Slash2` 右下下劈收招，两段都保持在画面内，逐指包握正常。
- 审查修复（Codex 提出三项）：①提取公式重复叠加 rest 已修正并重新生成轨迹；②手枪开火误播挥砍已加 `sword_equipped` 判断，仅剑类武器生效；③出招收招手指跳变已改为首尾各 18% 区间按权重 slerp 混合到基础握姿，不再瞬间覆盖。
- 未做：命中时序、音效与特效未接；主 Demo 未跑完整回归；观感待用户验收。（CodeBuddy）

## 其余四项手部动作（2026-10-21，CodeBuddy）

- 工具：`tools/asset_pipeline/extract_action_tracks.gd`（Godot headless），一次导出五个动作到 `action_tracks.json`（775 KB）。复用挥砍已验证的手动链式采样与解剖掌面迁移，左手额外做 X 轴镜像（源骨架左手为真实左手，目标 `glove_left.glb` 是右手镜像烘焙）。
- 持剑行走：源 `Sword_Walk` 的手腕**位移只有毫米级**，摆动几乎全在旋转（约 5°）。因此**没有**按原计划替换 bob——替换后手臂会完全不动。改为保留现有 bob 提供上下起伏，叠加放大 2.6 倍的源旋转，参数 `WALK_ROT_GAIN=2.6`、`WALK_POS_GAIN=3.0`。
- 格挡：`Sword_Block` / `Fists_Block` 只有 0.13 秒，且**第 0 帧即基准帧、delta 为零**，必须取末帧才是到位姿势。两者源幅度差约 20 倍（持剑 0.047 米、空手 0.224 米），需分开增益：持剑 `4.0/2.2`，空手 `1.4/1.32`。接口为 `set_block_preview(kind, weight)`，未接按键与判定。
- 左手施法：`Lefthand_Spell1` 2.92 秒。左手待机位置在画面下方外，需放大位移 `SPELL_POS_SCALE=1.7`；且源坐标 Z 正向是远离躯干，目标相机空间需取反，再向中间收 0.12。接口 `start_left_spell()` / `stop_left_spell()`，未接玩法。
- 喝药：`Consumable_Drink_001` 0.46 秒，`DRINK_POS_SCALE=1.5`。瓶子为程序化网格（`scripts/mvp/potion_bottle.gd`），首尾各 18% 淡入淡出，饮用段液面下降。快捷栏第 5 格 `potion`，按 5 直接使用（不切武器），回血 35、冷却 3 秒，喝药期间 `request_attack` 返回 false。配置在 `data/combat_mvp.json` 的 `player.potion_heal` / `potion_cooldown`。
- 审查修复（Codex 提出四项）：①格挡源末帧旋转接近 180°，放大后会翻转、袖口截面朝镜头，已把最终旋转用 `_clamp_quaternion_angle` 限制在 35° 内；②喝药手指 override 设在 `set_grip` 之后、下一帧被 `else: clear_pose_override()` 清空，已并入 `update_pose` 的 override 分支并新增 `_drink_progress()`；③攻击进行中喝药时武器隐藏但判定继续，已在 `_update_attack` 加 `hands.drink_active()` 判断，并在 `use_potion` 里打断当前攻击；④重试未清新增状态，已在 `reset_motion` 清空格挡、施法、喝药与左右手 override。（CodeBuddy）
- 挥砍观感调整：`SLASH_POS_SCALE` 0.24→0.52（原值手臂几乎不动、够不到怪）、`SLASH_ROT_WEIGHT` 0.12→0.35（旋转过低只剩平移，看不出"砍"）；源位移 Z 分量压到 0.3 倍，避免起手时剑贴脸。
- 挥砍方向修正（最终）：源 Chest 空间与相机空间的**左右与前后都相反**——源 `+X` 是左手边、`+Z` 是前方，相机空间 `+X` 是右手边、`-Z` 是前方。位移 `X`/`Z` **只取反一次**即可，**不要再对第二段额外取反 X**：那会双重取反让两段回到同向，表现为"只剩一个动作"。两段的区分交给源轨迹本身的差异。
- 挥砍旋转改为程序化：源手腕旋转在镜像坐标系里方向不可靠（试过直接叠加、降权重、取反，都会让剑尖朝内或翻面）。现在用 `sin(progress * PI)` 曲线 × 48°，第一段正向、第二段反向，配合源位移形成两套方向相反的动作。
- "挥剑砍自己"的真正原因：摆动旋转用了**右乘** `right_arm.quaternion * Quaternion(UP, angle)`，等于绕手臂自身轴转，剑会翻转指向镜头。必须**左乘** `Quaternion(UP, angle) * right_arm.quaternion`，才是绕相机竖直轴做水平挥砍。（CodeBuddy）
- 持剑行走抖动调整：`stride_phase` 每步一圈而源动画 0.92 秒是两步一循环，进度乘以 0.5 使频率减半；增益 `WALK_ROT_GAIN` 2.6→1.1、`WALK_POS_GAIN` 3.0→1.0，速度权重上限 1.4→1.0。（CodeBuddy）
- 已知缺口：持剑格挡时手臂仍偏上、会挡到部分画面；左手施法位置偏左；行走摆动因测试时移动撞墙触发蹬墙跑，未取得干净的实机对照图。三项均按 Skill“不改善就停”保留，未继续加补丁。（CodeBuddy）

### 2026-10-21 向前挥砍适配（Codex）

- 用户仍否定上述正弦绕竖轴版本；左／右乘只决定轴的参考空间，不能单独保证挥砍方向。现行运行时使用 `data/sword_viewmodel_motion.json` 的相机空间关键姿势，分开蓄力、向前斜劈／反斩、随势收招与恢复；原提取数据保留溯源，不再驱动剑挥砍或指姿。两段有效攻击窗口的剑轴均指向前半空间、腕部伸到待机前方，保持原伤害与时长。（Codex）
- 用剑轴与袖臂参考方向共同建立姿态，避免只对齐单轴导致绕剑翻腕。现有 Forearm 骨骼另朝画面下方的肩部参考点，Hand 施加反向补偿并固定腕原点，所以手指／剑柄接触不随袖臂修正移动；起止混合，切武器／重置恢复，不改用户 GLB、贴图及其他动作。（Codex）
- 实机截图两段各 6 阶段：`.mvp_qa/outward_slash/after/contact_sheet.jpg`；专项 3449/3449、原握姿 21/21，战斗 40/41（默认空手断言冲突）。未重测移动，手感待用户确认，未提交代码。（Codex）
