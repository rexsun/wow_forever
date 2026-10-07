-- =============================================================================
-- 无限副本手册 · 详情页「地图」页签（副本内地图 + 首领）
-- 本文件不是生成物，手写维护；toc 里必须排在 Core\DungeonUI.lua 之后。
--
-- 图源 = 客户端自带的世界地图瓦片：12 块 = 4 列 × 3 行、每块 256×256、行优先
--   路径 = Interface\WorldMap\<目录>\<层前缀><n>     例：Ragefire\Ragefire1_1
--   画布 1024×768；有效画面 = 左上 1002×668（右侧 22 / 底部 100 是装饰边，实测）
--
-- 版式（2026-09-30 三版）＝ 左侧地图 + 右侧首领栏，横向两块：
--   · 楼层按钮从「地图下方」挪到**地图右上角悬浮**（用户 2026-09-30 拍板 B 方案）：
--     旧位置只给多层副本预留 30px ⇒ 单层副本的图片区比多层的高 30px，两套版面。
--     悬浮后地图区高度恒定，与层数无关。
--   · **地图左上角 = 「隐藏 boss」开关**（用户 2026-10-01）：与楼层按钮同款悬浮、同一组边距
--     常量，一左一右对称；点一下只收起地图画布上的钉点（连名字），右栏首领列表 / 详情不动。
--     状态存 DungeonsForeverDB.dungeon.mapBossHidden（跨角色共享）；本副本一个钉点都没有时
--     整颗开关不出现（HasPins 判据），与当前层、与隐藏状态都无关。
--   · **地图满高**（用户 2026-09-30）：图高 = FRAME_H、图宽 = 高 × 3/2、右栏宽联动推出。
--   · 首领钉点：ns.BossPos[副本][首领英文名] = { {left%, top%}, … }。
--     坐标只对第 1 层有效（采集时按层出图，只放了第 1 层）⇒ **只在第 1 层画钉点**，
--     切到别的楼层一律不画，不替玩家猜位置。自制的单张手绘图同理 = 看第 1 层
--     （2026-10-01 修：此前「无 ART 层 = 无图」把自制图的钉点一起跳过了）。
--   · 右栏两种模式：首领列表（默认）/ 单个首领详情。
--     详情自上而下 = 首领名 → **掉落**（标题 + N 件 + 卡片行）→ **攻略**（标题 + 正文）；
--     攻略正文 = 首领技能表（ns.BossSkills，一行一条「技能名：说明」）+ 一句话攻略，
--     都没有才回落「攻略待补充」。两块标题同款（14 号金）。
--     点地图钉点或列表行 → 详情；详情里「‹ 全部首领」退回列表。
--
-- 没有客户端内地图的副本共 8 个（35 本 - 27 本有 ART）：其中 3 个用**自制手绘地图**顶上 ——
--   领主大厅 / 洛丹伦废墟（2026-09-30）+ 挖掘场湿地（2026-10-03），都是用户自己画的成品图导
--   TGA 进 Media/，见 CUSTOM；剩下 5 个（沉没之城 / 克罗多克 / 奥卡兹 / 黑喉 / 塑造者）照旧
--   空态，**不拿区域图顶替**（用户 2026-09-30 拍板：旧铁炉堡是通往领主大厅的区域图，
--   不是领主大厅的副本内图）。空态副本照样出右栏首领栏（洛丹伦废墟有攻略、领主大厅有掉落）。
--   ★ 也支持**多层副本只换某一层**：达拉然城（客户端 2 层：城 / 下水道）第 1 层是用户
--     2026-10-02 重绘的成品图 ⇒ 见 CUSTOM_FLOOR；第 2 层下水道没画、仍走客户端瓦片。
--   ★ 自制图与客户端瓦片共用同一块 663×442 画布、同一套百分比坐标 ⇒ **钉点照画**
--     （2026-10-01 修：此前拿「有 ART 层」当地图存在判据，自制图当场被当无图 ⇒
--     两本的 boss 钉点一个都不出，用户实机反馈「boss 图标没放到地图上」）。
--
-- 帧只在 Build 里建一次（12 块贴图 + 楼层按钮池 + 钉点池 + 列表/掉落行池）；
-- Paint / 选中 / 切层只改贴图、文字与显隐，零新建帧。
-- =============================================================================

local _, ns = ...
if type(ns) ~= "table" then return end

local Host = ns.ProfHost
if type(Host) ~= "table" then return end

local L = ns.L
local DG = Host.DG
local U = Host.U          -- ★ 必须显式取：DungeonUI 里的 U 是 local，裸用 U 会是 nil 全局 ⇒ 悬停报错
local MakeFS = Host.MakeFS
local Unpack = Host.Unpack
local C_GREY = Host.C_GREY
local C_GOLD = Host.C_GOLD
local C_TEXT = Host.C_TEXT

local M = {}
ns.MapModule = M

M.COLS, M.ROWS = 4, 3
M.TILE = 256
M.ART_W, M.ART_H = 1002, 668
M.N = M.COLS * M.ROWS

-- ── 版式常量 ──────────────────────────────────────────────────────────────
-- ★ 详情页可用区 = DungeonUI 的固定版式算出来的（960 面板 − 12 内缩 ×2 = 936 宽；
--   648 高 − (ROW_CLASS 30 + 36 二级行) − 12 = 570，再减 hero 120 + 8 = 442）。
--   **不读 GetWidth** —— 离线桩的 GetWidth 恒回 100，读它所有几何断言都成空话；
--   真机这个面板尺寸也是常量（panel:SetSize(CONTENT_W, CONTENT_H)），不会变。
M.FRAME_W = Host.CONTENT_W - Host.PAGE_INSET * 2
M.FRAME_H = Host.CONTENT_H - (Host.ROW_CLASS + 36) - Host.PAGE_INSET - DG.GUIDE_TOP_Y

-- ★ 地图**满高**（2026-09-30 用户：地图再放大一点，高 = 右边卡片的高）：
--   图高 = FRAME_H，图宽 = 高 × 1002/668（恰 3:2）= 663；右栏宽反过来由总宽推出
--   （936 − 663 − 10 = 263）。这三者是一组**联动值**：改图宽必须同步改栏宽。
M.SIDE_GAP = 10
M.MAP_W = math.floor(M.FRAME_H * M.ART_W / M.ART_H)   -- 满高时的图宽（442 × 3/2 = 663）
M.SIDE_W = M.FRAME_W - M.MAP_W - M.SIDE_GAP           -- 右栏宽（联动推出，不再是写死的 300）
M.SIDE_PAD = 8

M.MAX_LAYERS = 8                 -- 楼层按钮池大小（本客户端最多 7 层）
M.LAYER_W, M.LAYER_GAP = 46, 4
M.BAR_H = 20                     -- 楼层按钮条高度（★ 悬浮：不再从地图高度里扣）
M.FLOOR_INSET = 6                -- 楼层按钮距地图右上角的边距
-- ★ 左上角「隐藏 boss」开关（2026-10-01 用户）——与楼层按钮**同一套悬浮版面**、
--   同一组边距常量（FLOOR_INSET / BAR_H），一左一右对称；宽度取 72 是因为
--   「隐藏boss / 显示boss」（enUS: Hide bosses / Show bosses）四种文案等宽 ⇒ 点击切换不跳字。
M.BOSS_BTN_W = 72

M.MAX_PINS = 24                  -- 钉点池（实测最多 14：监狱 boss 钉 5 首领 14 刷点，2026-10-05 fc 补德克斯伦·沃德）
-- 四类钉点的贴图：boss / 稀有共用骷髅（金 / 银染色）；任务 = 黄色「!」；
-- 入口 = 自制石门（客户端 POIIcons 图集的格子坐标未实测，等数据 pin 刷新后
--      可换 Interface\Minimap\POIIcons 子矩形，只改本常量）；物品 = 客户端图标。
M.PIN_BOSS_TEX = "Interface\\AddOns\\DungeonsForever\\Media\\BossSkull"
M.PIN_QUEST_TEX = "Interface\\GossipFrame\\AvailableQuestIcon"
M.PIN_DOOR_TEX = "Interface\\AddOns\\DungeonsForever\\Media\\MapDoor"
M.PIN_SIZE = 48
M.PIN_MIN = 27                   -- 钉点直径占位（未选中 / 选中都按它居中；用户 2026-09-30：地图钉点改回 75%）

M.MAX_LIST = 30                  -- 右栏首领列表行池（实测最多 27：黑石深渊）

-- ★ 首领身份色板（2026-09-30 用户定：「颜色即身份」）——按副本内首领顺序取色、循环使用；
--   第 N 个首领 = 第 N 色，列表行图标/边框、地图钉点、钉点名字三处同色。≥ 12 色是硬要求。
M.BOSS_PALETTE = {
    { 0.94, 0.30, 0.28 },   -- 1 红
    { 1.00, 0.58, 0.19 },   -- 2 橙
    { 1.00, 0.82, 0.00 },   -- 3 黄
    { 0.42, 0.88, 0.34 },   -- 4 绿
    { 0.30, 0.84, 0.84 },   -- 5 青
    { 0.36, 0.55, 1.00 },   -- 6 蓝
    { 0.70, 0.45, 0.95 },   -- 7 紫
    { 0.95, 0.42, 0.78 },   -- 8 品红
    { 0.91, 0.89, 0.82 },   -- 9 骨白
    { 0.56, 0.65, 0.75 },   -- 10 冷钢灰
    { 0.79, 0.55, 0.35 },   -- 11 铜棕
    { 0.78, 0.90, 0.30 },   -- 12 黄绿
}
M.MAX_LOOT = 30                  -- 右栏掉落行池（实测单个首领最多 29 件）
M.MAX_SKILL = 8                  -- 右栏技能行池（实测单个首领最多 5 条：重拳先生）
M.LIST_H = 38                    -- 行高随 32px 图标走（图标放大 2 倍）
M.LIST_GAP = 8                   -- 行间距（用户 2026-09-30：太密了）

-- ★ 详情页三张分组卡片（2026-10-01 用户：「掉落增加一个卡片，boss技能增加一个卡片，
--   攻略增加一个卡片」）—— 卡片 = 1px 描边 + 淡底，卡头只有 14 号金标题（用户点名**不要分隔线**），
--   卡内条目**扁平化**（不再各自带边框，只在 hover 时浮出，避免卡片套卡片）。
M.BLK_PAD = 8                    -- 卡片左右内缩（内容区宽 = innerW − 2×8）
M.BLK_HDR = 26                   -- 卡头顶部 → 内容区顶部（标题 18 高 + 上下留白）
M.BLK_TITLE_TOP = 5              -- 标题顶部距卡顶
M.BLK_GAP = 8                    -- 卡片之间的竖直间距
M.ROW_GAP = 4                    -- 卡片内条目间距（掉落行 / 技能行共用同一值）

-- ★★ 卡头可点折叠（用户 2026-10-01：「这三张卡片呢，我希望都可以支持展开和折叠的」）——
--   热区 = 整条卡头（宽随卡、高 = 卡头高），点它收起 / 展开；箭头在最左（arrow.tga 原生朝上），
--   标题整体右让出箭头位。折叠状态**存进配置**（用户点名「记住，存进配置」）：
--   DB().ui.mapCards.<loot|skill|guide> —— true = 收起，缺省 / nil = 展开（老存档照样三张全展开）。
M.BLK_MIN_H = M.BLK_HDR         -- 折叠后卡高 = 一行卡头（同一来源，不写第二个 26）
M.BLK_TITLE_X = 24               -- 卡标题左缩 = BLK_PAD(8) + 箭头(10) + 间距(6)
M.BLK_ARROW = 10                 -- 折叠箭头边长

-- ★★ 条目图标尺寸**掉落与技能共用同一个常量**（用户 2026-10-01：「掉落里面的物品图标
--   大小我需要和 BOSS 技能图标大小一致」）—— 不写两个各自为政的数字，改一处两边同时变，
--   「一致性」由代码结构保证，而不是靠两条常量碰巧相等。行高随它走（图标上下各留 4）。
M.CARD_ICON = 32
M.CARD_H = 40                    -- 掉落行高（32 图标 + 上下各 4）
M.CARD_FS_NAME = 13
M.CARD_FS_META = 11

-- ★ 圆角（用户 2026-10-01：「所有的卡片都需要倒圆角」）—— 三张分组卡片 / 右栏面板 / 卡内条目
--   （hover 态）一律走 HUI 原语 ns.hui.BuildRoundedBG（弧盘填充 + 主题描边），
--   半径与本插件其它页的卡片同一套（卡片 6、条目 4）。
M.BLK_RADIUS = 6
M.ROW_RADIUS = 4
M.BLK_BG = 0.03                  -- 卡片底（叠在右栏面板 0.03 之上 ⇒ 隐约比栏底亮一档）

local WM = "Interface\\WorldMap\\"

-- ns.hui.BuildRoundedBG 返回 (填充片, 描边片, 角内盘片) 三组 —— 拍平成一维，
-- 便于 hover 时一次 SetShown（卡片内条目扁平化后，圆角高亮是它唯一的底色来源）。
local function FlattenPieces(...)
    local out = {}
    for i = 1, select("#", ...) do
        local v = select(i, ...)
        if type(v) == "table" then
            for j = 1, #v do out[#out + 1] = v[j] end
        end
    end
    return out
end

local function PiecesSetShown(t, on)
    for i = 1, #(t or {}) do t[i]:SetShown(on) end
end

-- ★★ 卡片折叠状态：真源 = 配置（DB().ui.mapCards），缺档整档补齐（老存档没这个键 ⇒ 三张全展开）。
--   收起写 true、展开写 nil —— 与「隐藏boss」同口径：存档里不留 false，读侧一律「非 true 即展开」。
function M.CardClosed()
    local ui = ns.DB().ui
    local c = ui.mapCards
    if type(c) ~= "table" then c = {} ui.mapCards = c end
    return c
end

-- 共享目录：厄运 3 区 / 斯坦索姆 2 区 各共用同一套层
local DM = { "DireMaul",
    { "DireMaul1_", "DireMaul2_", "DireMaul3_", "DireMaul4_", "DireMaul5_", "DireMaul6_", "DireMaul" } }
local ST = { "Stratholme", { "Stratholme1_", "Stratholme2_" } }

-- ★★ 血色 4 分区**不共享层**（2026-10-01 用户纠正）——客户端 ScarletMonasteryOld 的 4 层
--   不是「一个副本的 4 个楼层」，而是**四个分区各一张**：
--     第 1 层 = 墓园 / 第 2 层 = 图书馆 / 第 3 层 = 军械库 / 第 4 层 = 大教堂。
--   所以每个血色副本只挂**自己那一张**（都成了单层 ⇒ 不出楼层按钮）；
--   此前把 4 层整挂给 4 个副本 ⇒ 每个副本都能切出别的分区的地图，是错的。
local SM_DIR = "ScarletMonasteryOld"
local function SMW(pre) return { SM_DIR, { pre } } end

-- id = { 目录, { 层前缀按层号升序 } }；层前缀第 1 项 = 默认层
local ART = {
    ragefire_chasm        = { "Ragefire", { "Ragefire1_" } },
    wailing_caverns       = { "WailingCaverns", { "WailingCaverns1_" } },
    the_deadmines         = { "TheDeadmines", { "TheDeadmines1_", "TheDeadmines2_" } },
    shadowfang_keep       = { "ShadowfangKeep",
        { "ShadowfangKeep1_", "ShadowfangKeep2_", "ShadowfangKeep3_", "ShadowfangKeep4_",
          "ShadowfangKeep5_", "ShadowfangKeep6_", "ShadowfangKeep7_" } },
    blackfathom_deeps     = { "BlackfathomDeeps",
        { "BlackfathomDeeps1_", "BlackfathomDeeps2_", "BlackfathomDeeps3_" } },
    the_stockade          = { "TheStockade", { "TheStockade1_" } },
    gnomeregan            = { "Gnomeregan",
        { "Gnomeregan1_", "Gnomeregan2_", "Gnomeregan3_", "Gnomeregan4_", "Gnomeregan10_" } },
    razorfen_kraul        = { "RazorfenKraul", { "RazorfenKraul1_" } },
    razorfen_downs        = { "RazorfenDowns", { "RazorfenDowns1_" } },
    sm_graveyard          = SMW("ScarletMonastery1_"),   -- 墓园
    sm_library            = SMW("ScarletMonastery2_"),   -- 图书馆
    sm_armory             = SMW("ScarletMonastery3_"),   -- 军械库
    sm_cathedral          = SMW("ScarletMonastery4_"),   -- 大教堂
    uldaman               = { "Uldaman", { "Uldaman1_", "Uldaman2_", "Uldaman18_" } },
    zul_farrak            = { "ZulFarrak", { "ZulFarrak" } },
    maraudon              = { "Maraudon", { "Maraudon1_", "Maraudon2_" } },
    sunken_temple         = { "TheTempleofAtalHakkar", { "TheTempleofAtalHakkar1_" } },
    blackrock_depths      = { "BlackrockDepths", { "BlackrockDepths1_", "BlackrockDepths2_" } },
    dire_maul_east        = DM,
    dire_maul_north       = DM,
    dire_maul_west        = DM,
    lower_blackrock_spire = { "BlackrockSpire",
        { "BlackrockSpire1_", "BlackrockSpire2_", "BlackrockSpire3_", "BlackrockSpire4_",
          "BlackrockSpire5_", "BlackrockSpire6_", "BlackrockSpire7_" } },
    upper_blackrock_spire = { "UpperBlackrockSpire",
        { "UpperBlackrockSpire1_", "UpperBlackrockSpire2_", "UpperBlackrockSpire3_" } },
    scholomance           = { "ScholomanceOld",
        { "ScholomanceOld1_", "ScholomanceOld2_", "ScholomanceOld3_", "ScholomanceOld4_" } },
    stratholme_main       = ST,
    stratholme_service    = ST,
    city_of_dalaran       = { "Dalaran", { "Dalaran1_", "Dalaran2_" } },
}
M.ART = ART

-- ── 自制副本图（客户端没画的，用户手绘成品导 TGA 进 Media/；2026-09-30）────
--   贴图 = **663×442** 24 位 RLE TGA（2026-10-03 定稿：用户「按游戏中实际画布的大小制作」）。
--   画布 = M.MAP_W × M.FRAME_H = 663×442、恰 3:2 ⇒ **贴图就是画面**：
--   没有黑边、没有留白，显示时 SetTexCoord 取满 (0, 1, 0, 1)，
--   满铺到与客户端图同一块 663×442 画布 ⇒ 几何 / 钉点坐标系完全一致。
--   ★ 历次规格（钉点百分比坐标**一次都没动过**）：
--     512×512（画面占顶 341 行）→ 1024×1024（占顶 682 行）→ **663×442 全画面**（现在）。
--     前两者 v 上限同为 0.666015625；与现在的 442/663 = 0.66666… 只差 0.07%（<0.3px）。
--   ★ 2× 提档版（1326×884）常驻 _temp/_tga2x_bak/ —— 换尺寸**不用改本文件**（UV 恒 1）。
--   ★ 转换口径（_temp/_map_tga.py）：**整幅映射**到 3:2 画面区（源图≈3:2 时与「中心裁」
--     等价）。2026-10-03 挖掘场湿地源图 1.383、带完整装饰边框 ⇒ 若按中心裁会切掉上下边框，
--     故统一用整幅映射（只横向拉伸 8.5%，边框四面完整，观感与既有两张一致）。
M.CUSTOM_W = 663                        -- 贴图宽 = M.MAP_W（画布实际像素）
M.CUSTOM_H = 442                        -- 贴图高 = M.FRAME_H
local CUSTOM = {
    hall_of_thanes      = "Interface\\AddOns\\DungeonsForever\\Media\\Maps\\HallOfThanes",
    ruins_of_lordaeron  = "Interface\\AddOns\\DungeonsForever\\Media\\Maps\\RuinsOfLordaeron",
    excavation_wetlands = "Interface\\AddOns\\DungeonsForever\\Media\\Maps\\ExcavationSite",
}
M.CUSTOM = CUSTOM

-- ★ 多层副本**只换其中某一层**用自制图（2026-10-02 加：达拉然城用户重新手绘了第 1 层，
--   第 2 层「达拉然下水道」没画 ⇒ 那一层仍走客户端瓦片）。
--   键 = **层号**（与 M.LayersFor 的序号一致，不是前缀里的数字）；整图副本走上面的 CUSTOM。
--   ★ 与 CUSTOM 互斥：同一副本两边都登记没有意义（CUSTOM 分支压根不看层），别这么写。
local CUSTOM_FLOOR = {
    city_of_dalaran = { [1] = "Interface\\AddOns\\DungeonsForever\\Media\\Maps\\Dalaran" },
}
M.CUSTOM_FLOOR = CUSTOM_FLOOR

-- 某副本的自制图路径（没有 → nil）；第 2 返回值 = 贴图纵向 UV 上限（贴图即画面 ⇒ 恒 1）
function M.CustomFor(id)
    local path = id and CUSTOM[id]
    if not path then return nil end
    return path, 1
end

-- 某副本**第 idx 层**的自制图路径（不是自制层 → nil）；返回值同 CustomFor
function M.CustomFloorFor(id, idx)
    local row = id and CUSTOM_FLOOR[id]
    if type(row) ~= "table" or type(idx) ~= "number" then return nil end
    local path = row[idx]
    if not path then return nil end
    return path, 1
end

-- 某副本的层前缀数组（无图 → nil）
function M.LayersFor(id)
    local row = id and ART[id]
    if not row then return nil end
    return row[2]
end

-- 默认层（第 1 层）的完整路径；无图 → nil。老的调用点/断言按这个口径。
function M.PathFor(id)
    local layers = M.LayersFor(id)
    if not (layers and layers[1]) then return nil end
    return WM .. ART[id][1] .. "\\" .. layers[1]
end

-- 第 i 层的完整路径；越界 → nil
function M.PathAt(id, i)
    local layers = M.LayersFor(id)
    if not (layers and layers[i]) then return nil end
    return WM .. ART[id][1] .. "\\" .. layers[i]
end

-- ── 首领数据（只读 ns.DungeonLoot / ns.DungeonGuide / ns.BossPos）──────────

-- 某首领的坐标点数组（{ {left%, top%[, 层号]}, … }）；没有 → nil。
-- floor = 客户端层号：给了就只回该层的点；nil = 任意层（首领名单判定用）。
-- 点第 3 位 = 客户端层号（缺省第 1 层；多层副本按层放钉点，2026-09-30）。
function M.PosFor(id, en, floor)
    local all = id and ns.BossPos and ns.BossPos[id]
    local pts = all and en and all[en]
    if type(pts) ~= "table" or #pts == 0 then return nil end
    if floor == nil then return pts end
    local out
    for i = 1, #pts do
        local p = pts[i]
        if (p[3] or 1) == floor then
            out = out or {}
            out[#out + 1] = p
        end
    end
    return out
end

-- 副本的首领名单：掉落来源里「有 npcid 的真首领」，外加**有坐标**的来源
-- （个别首领我方没登记 npcid，如怒焰的奥格弗林特，但有坐标就得进名单），
-- 再加**有一句话攻略**的来源（洛丹伦废墟 6 个 boss 都没登记 npcid，但攻略齐全 ——
-- 不过这一条就选不到、攻略白写）。三者取并集，名字是唯一的连接键。
function M.BossesFor(id)
    local loot = (ns.DungeonLoot or {})[id]
    if type(loot) ~= "table" then return nil end
    local out
    for i = 1, #loot do
        local s = loot[i]
        if type(s) == "table"
           and ((s[4] and s[4] ~= "") or M.PosFor(id, s[1]) or M.GuideFor(id, s[1])) then
            out = out or {}
            out[#out + 1] = { en = s[1], zh = s[2] or s[1], npc = s[4] or "", items = s[5] or {} }
        end
    end
    return out
end

-- 扁平钉点表：{ {en, zh, left, top}, … }（只在第 1 层有意义）
-- 扁平钉点表：{ {en, zh, left, top}, … }（floor = 客户端层号；nil = 全层，仅老调用点/断言用）
function M.PinsFor(id, floor)
    local bosses = M.BossesFor(id)
    if not bosses then return nil end
    local out
    for i = 1, #bosses do
        local pts = M.PosFor(id, bosses[i].en, floor)
        if pts then
            for k = 1, #pts do
                out = out or {}
                out[#out + 1] = {
                    en = bosses[i].en, zh = bosses[i].zh,
                    left = pts[k][1], top = pts[k][2],
                }
            end
        end
    end
    return out
end

-- 「入口 / 任务 / 物品 / 稀有」钉点（ns.MapPins，_temp/fc_pins.py 产物）：
-- 返回扁平列表 { { kind=, left=, top=, id=, name= }, … }（boss 钉之外的其余类型）。
-- floor = 客户端层号：数据未写层号的一律按第 1 层（与 ns.BossPos 同口径）；
-- nil = 不分层（HasPins 判据用）。
function M.ExtraPinsFor(id, floor)
    local row = id and ns.MapPins and ns.MapPins[id]
    if type(row) ~= "table" then return nil end
    local out
    for _, kind in ipairs({ "entrance", "quest", "object", "rare" }) do
        local arr = row[kind]
        if type(arr) == "table" then
            for i = 1, #arr do
                local p = arr[i]
                if type(p) == "table" and p[1] and p[2] then
                    -- 层号：entrance/quest/object 第 4 位、rare 第 5 位（数据省略 = 第 1 层）。
                    -- 2026-10-04：乌尔之书实锤「只落第 1 层」不够 —— 任务物品有自己所在的层。
                    local pf = p[(kind == "rare") and 5 or 4] or 1
                    if floor == nil or pf == floor then
                        out = out or {}
                        out[#out + 1] = {
                            kind = kind, left = p[1], top = p[2], id = p[3],
                            name = (kind == "rare") and p[4] or nil,
                        }
                    end
                end
            end
        end
    end
    return out
end

-- 本副本**有没有钉点可画**（任意层）——「隐藏图钉」开关的显隐判据。
-- ★ 与当前层无关：切层不该让开关闪没（本层无点时钉点本来就是空的，开关仍该在）。
-- ★ 与 hideBoss 无关：隐藏状态不能把开关自己也藏掉（否则再点不到 ⇒ 开关死锁）。
function M.HasPins(id)
    if not id then return false end
    if not (M.LayersFor(id) or M.CustomFor(id)) then return false end
    local list = M.PinsFor(id, nil)
    local n = list and #list or 0
    local ex = M.ExtraPinsFor(id, nil)
    if ex then n = n + #ex end
    return (n > 0) and true or false
end

-- 某首领的一句话攻略；没整理 → nil（界面显示「攻略待补充」）
function M.GuideFor(id, en)
    local g = (ns.DungeonGuide or {})[id]
    local bs = g and g.bosses
    if type(bs) ~= "table" then return nil end
    for i = 1, #bs do
        if bs[i] and bs[i].en == en then return bs[i].text end
    end
    return nil
end

-- 某首领的技能表（wowhead 能力表口径，三语各一份；名字/说明运行期按 id 取自客户端）：
--   { { 技能名, 说明[, 法术id] }, … }；没有 → nil
--   第 3 位 = wowhead 给的法术 id：悬停行时 SetSpellByID 出法术提示框；没有 id 的行纯文本。
function M.SkillsFor(id, en)
    local row = (ns.BossSkills or {})[id]
    local sk = row and en and row[en]
    if type(sk) ~= "table" or #sk == 0 then return nil end
    return sk
end

-- 法术提示框正文抓取（说明的**兜底层**：C_Spell.GetSpellDescription / GetSpellDescription
-- 都拿不到才走这里）：SetSpellByID 后第 1 行是法术名，正文从第 2 行起取第一段**非元信息**文本。
-- ★ 2026-09-30 实机：现代提示框第 2/3 行是「40码距离」「2秒施法时间」这类元信息，
--   说明正文在其后（如「每秒钟吸取目标35点生命值…」）—— 旧逻辑把元信息当正文（卡片显示成
--   「40码距离」）。逐行跳过元信息行取正文；全是元信息 → 返回 nil 回落数据侧说明。
-- 不依赖 NumLines（别处场景会把它置换/置 nil），逐行读全局 FontString 到缺失为止；
-- 只读不显（抓完 ClearLines）—— 真正的显示由悬停的 ShowSpellTip 负责（2026-09-30 用户）。
local SKILL_TIP_META = {
    "码距离$", "施法时间$", "^瞬发$", "^冷却时间", "法力值$", "^%d+%.?%d*%%基础法力值$",
    " yd range$", " sec cast$", " sec cooldown$", " of base mana$", "^Instant$",
    "^法术 ID$", "^图标 ID$", "^Spell ID$", "^Icon ID$",
}
function M.SpellTipDesc(sid)
    if type(sid) ~= "number" then return nil end
    if not (GameTooltip and GameTooltip.SetSpellByID) then return nil end
    local ok = pcall(GameTooltip.SetSpellByID, GameTooltip, sid)
    if not ok then return nil end
    local out
    for i = 2, 32 do
        local fs = _G["GameTooltipTextLeft" .. i]
        if not (fs and fs.GetText) then break end
        local t = fs:GetText()
        if type(t) == "string" and t ~= "" then
            local meta = false
            for _, p in ipairs(SKILL_TIP_META) do
                if t:find(p) then meta = true break end
            end
            if not meta then out = t break end
        end
    end
    GameTooltip:ClearLines()
    return out
end

-- 技能行三件套（名字 / 图标 / 说明，全部来自游戏客户端，一次抓取后缓存）。
-- 图标按 ID 全链取（2026-09-30 用户点名「技能 ID 能返回图标」）：
--   GetSpellInfo → C_Spell.GetSpellInfo(.iconID) → C_Spell.GetSpellTexture → GetSpellTexture；
--   客户端全是数字 fileID 也收（本客户端暴雪 UI 就是拿数字 SetTexture 的）。
-- 说明按 ID 直取（2026-09-30 用户定「图标、名称、文本都由客户端获取」）：
--   C_Spell.GetSpellDescription → GetSpellDescription 全局 → 提示框抓取（SpellTipDesc，兜底）。
--   直取文本里的 |c…|r 颜色码剥离后再用；三层都拿不到 → 回落数据侧说明（自制副本专用）。
-- fbIcon = 数据侧兜底图标（wowhead 图标 slug 拼的 Interface/Icons 路径）：
--   客户端技能库查不到（无限服缺这些经典技能）时用它 —— 2026-09-30 实机空白图标即此因。
-- 客户端不认识（没有法术 id、全链查不到）→ 回落数据里的名字与说明。
M._spellCache = {}
function M.SpellRowFor(sid, fbName, fbDesc, fbIcon)
    if type(sid) ~= "number" then return fbName, fbIcon, fbDesc end
    local c = M._spellCache[sid]
    if c == nil then
        local nm, ic
        if GetSpellInfo then
            local ok, n1, _r, n3 = pcall(GetSpellInfo, sid)
            if ok then nm, ic = n1, n3 end
        end
        if not nm and C_Spell and C_Spell.GetSpellInfo then
            local ok, info = pcall(C_Spell.GetSpellInfo, sid)
            if ok and type(info) == "table" then
                nm, ic = info.name, info.iconID
            end
        end
        if not ic and C_Spell and C_Spell.GetSpellTexture then
            local ok, tid = pcall(C_Spell.GetSpellTexture, sid)
            if ok then ic = tid end
        end
        if not ic and GetSpellTexture then
            local ok, tid = pcall(GetSpellTexture, sid)
            if ok then ic = tid end
        end
        -- 说明直取：客户端 API 优先（比提示框抓取稳，不依赖 GameTooltip 行结构）
        local d
        if C_Spell and C_Spell.GetSpellDescription then
            local ok, t = pcall(C_Spell.GetSpellDescription, sid)
            if ok and type(t) == "string" then d = t end
        end
        if not d and GetSpellDescription then
            local ok, t = pcall(GetSpellDescription, sid)
            if ok and type(t) == "string" then d = t end
        end
        if d then
            d = d:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
            d = d:gsub("^%s+", ""):gsub("%s+$", "")
            if d == "" then d = nil end
        end
        if not d then d = M.SpellTipDesc(sid) end
        c = {
            name = (type(nm) == "string" and nm ~= "" and nm) or nil,
            icon = ((type(ic) == "string" and ic ~= "" and ic)
                    or (type(ic) == "number" and ic > 0 and ic)) or nil,
            desc = d,
        }
        M._spellCache[sid] = (c.name or c.icon or c.desc) and c or false
    end
    if c == false then return fbName, fbIcon, fbDesc end
    return c.name or fbName, c.icon or fbIcon, c.desc or fbDesc
end

-- 技能提示框（形态照 ShowItemTip：SetSpellByID 优先、SetHyperlink 兜底，双 pcall）。
function M.ShowSpellTip(owner, sid)
    if not sid then return end
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:ClearLines()
    local native = false
    if GameTooltip.SetSpellByID then
        local ok = pcall(GameTooltip.SetSpellByID, GameTooltip, sid)
        if ok then
            GameTooltip:Show()
            local n = GameTooltip.NumLines and GameTooltip:NumLines() or 0
            native = (type(n) == "number" and n > 1)
        end
    end
    if not native and GameTooltip.SetHyperlink then
        local ok = pcall(GameTooltip.SetHyperlink, GameTooltip, "spell:" .. tostring(sid))
        if ok then
            GameTooltip:Show()
            local n = GameTooltip.NumLines and GameTooltip:NumLines() or 0
            native = (type(n) == "number" and n > 1)
        end
    end
    if native then
        GameTooltip:Show()
    else
        -- 客户端两条原生路都出不了内容的法术 → 直接收起（本地无兜底文案，不弹空壳）。
        GameTooltip:Hide()
    end
end

-- ── 几何 ──────────────────────────────────────────────────────────────────

function M.FitBox(aw, ah)
    if type(aw) ~= "number" or type(ah) ~= "number" or aw <= 0 or ah <= 0 then return 1, 1, 0, 0 end
    local s = math.min(aw / M.ART_W, ah / M.ART_H)
    local w = math.floor(M.ART_W * s)
    local h = math.floor(M.ART_H * s)
    if w < 1 then w = 1 end
    if h < 1 then h = 1 end
    return w, h, math.floor((aw - w) / 2), math.floor((ah - h) / 2)
end

-- 左侧地图区：返回 可用宽, 图宽, 图高, 图左偏移, 图上偏移
-- ★ 满高排（2026-09-30）：图高 = FRAME_H、图宽 = MAP_W、x/y = 0（不留居中边）。
--   不再走 FitBox —— 663/1002 与 442/668 数学上相等，但浮点末位可能把图宽压成 662。
function M.Box()
    return M.MAP_W, M.MAP_W, M.FRAME_H, 0, 0
end

function M.Layout(cw, ch)
    local out = {}
    if type(cw) ~= "number" or type(ch) ~= "number" or cw <= 0 or ch <= 0 then return out end
    local sx, sy = cw / M.ART_W, ch / M.ART_H
    for n = 1, M.N do
        local col = (n - 1) % M.COLS
        local row = math.floor((n - 1) / M.COLS)
        local x0, x1 = col * M.TILE, (col + 1) * M.TILE
        local y0, y1 = row * M.TILE, (row + 1) * M.TILE
        if x1 > M.ART_W then x1 = M.ART_W end
        if y1 > M.ART_H then y1 = M.ART_H end
        if x1 > x0 and y1 > y0 then
            out[#out + 1] = {
                n = n,
                x = x0 * sx, y = y0 * sy,
                w = (x1 - x0) * sx, h = (y1 - y0) * sy,
                u0 = (x0 - col * M.TILE) / M.TILE, u1 = (x1 - col * M.TILE) / M.TILE,
                v0 = (y0 - row * M.TILE) / M.TILE, v1 = (y1 - row * M.TILE) / M.TILE,
            }
        end
    end
    return out
end

-- ── 构建（外壳同步 + 重池逐帧；渲染路径零新建帧）────────────────────────────
--
-- ★★★ 2026-10-03「点副本就卡死」第四刀：整页一次 Build 实测 **138 帧 / 1153 纹理 /
--   202 字体串**，且其中 **30 条首领行 + 30 条掉落行 + 16 个钉点 + 3 张分组卡**占绝对多数，
--   而它们绝大多数时间根本用不上（列表模式看不见卡片；没切到地图页时整页都看不见）。
--   于是改成「外壳同步 + 四个重池逐帧 + 收尾补渲染」：
--     · 外壳（画布 / 12 块瓦片 / 空态 / 钉点容器 / 楼层面条 / 隐藏 boss 开关 / 右栏三容器）
--       同步建 —— 只有几十个对象，切到地图页那一刻不吃力，地图画面也立刻出得来；
--     · 四个重池走 DG.PushStep 逐帧建：钉点 → 首领列表行 → 三张分组卡 → 掉落行 / 技能行；
--     · 每块幂等；**池没建好时 SyncPins / SyncSide 一律安全空转**（各自开头的就绪旗标），
--       所以「刚切到地图页、池还在建」的那几帧既不报错、也不会画出半吊子内容
--       （楼层面条 / 隐藏 boss 开关 / 右栏容器都在外壳里，不受影响）；
--     · 最后一块（M.EnsureFinal）建完补一次渲染 —— 右栏与钉点最坏 ~0.1s 内补齐。
--   ★ 离线（C_Timer 不可用）由 DG.PushStep 的同步兜底一次跑完 ⇒ 断言看到的仍是全量。
--   ★ 顺序有依赖：卡片块必须排在行块之前 —— 掉落行 / 技能行的父帧就是那三张卡。
--
-- 帧只在 Build / Ensure* 里建一次（12 块贴图 + 楼层按钮池 + 钉点池 + 列表/掉落/技能行池）；
-- Paint / 选中 / 切层只改贴图、文字与显隐，零新建帧。

-- ① 钉点池（16 个 boss 钉点：骷髅贴图 + 圆角遮罩 + 名字）
local function BuildPins()
    -- ★ 注意：DG.PushStep(fn) 里的 fn 是**无参**调用的 ⇒ 这里必须自己取 M.frame
    --   （写成 BuildPins(frame) 参数形式 = 拿到 nil，pump 里被 pcall 吞掉、静默不建）。
    local frame = M.frame
    if not frame or frame.__pinsReady then return end
    frame.__pinsReady = true
    local pins = frame.pins
    local pinBtns = {}
    -- ★ 文字层（2026-10-04 第二轮）：全部钉的名字挂这一个低层容器——
    --   图标（按钮本体）压过全部文字，跨钉也成立
    --   （入口钉「副本入口」四个字不许糊掉旁边任务钉的黄「!」）。
    --   ★★ 第三轮（实机再反馈）：仅「先建」不够——同层级下 FontString 渲染在兄弟 Frame
    --   之后（引擎文字后画），必须显式 SetFrameLevel 压低：pinText = 父容器层，
    --   按钮保持默认 = 父层+1 ⇒ 图标严格高于全部文字。
    --   ㊟ pinText 挂 pins 之下，随容器整体显隐；池按钮单独 Hide 时须同步清文字（见 SyncPins）。
    local pinText = CreateFrame("Frame", nil, pins)
    pinText:SetAllPoints()
    pinText:SetFrameLevel(math.max(pins:GetFrameLevel(), 0))
    frame.pinText = pinText
    for i = 1, M.MAX_PINS do
        local bt = CreateFrame("Button", nil, pins)
        bt:SetSize(M.PIN_SIZE, M.PIN_SIZE)
        bt.__idx = i
        -- ★ 图层：文字先建、图标后建 + dot 提 OVERLAY —— 图标必须盖得住文字（含相邻钉溢出的长名），
        --   否则 14px 名字会把任务「!」/入口门等小材质糊掉（2026-10-04 实机反馈）。
        -- 挂文字层：图标永远盖得住（跨钉也是）
        bt.nm = MakeFS(pinText, 14, C_GOLD, "CENTER")
        -- 名字压在地图上：细描边（OUTLINE）+ 1px 阴影，任何底色都可读
        local nfp, _, nff = bt.nm:GetFont()
        bt.nm:SetFont(nfp, 14, "OUTLINE")
        bt.nm:SetShadowColor(0, 0, 0, 1)
        bt.nm:SetShadowOffset(1, -1)
        bt.dot = bt:CreateTexture(nil, "OVERLAY")
        bt.dot:SetAllPoints()
        -- BOSS 骷髅钉点（Media/BossSkull.tga 256x256 32位带alpha；本色骨白，金色由 SetVertexColor 染）
        bt.dot:SetTexture("Interface\\AddOns\\DungeonsForever\\Media\\BossSkull")
        bt.dot:SetVertexColor(1, 0.82, 0)
        if ns.hui and ns.hui.RoundIcon then ns.hui.RoundIcon(bt.dot) end
        bt.nm:SetPoint("TOP", bt.dot, "BOTTOM", 0, -2)
        bt:SetScript("OnClick", function(self) M.Select(self.__en) end)
        bt:Hide()
        pinBtns[i] = bt
    end
    frame.pinBtns = pinBtns
end

-- ② 右栏「首领列表」行池（30 行）
local function BuildListRows()
    local frame = M.frame
    if not frame or frame.__listReady then return end
    frame.__listReady = true
    local listChild, innerW = frame.listChild, frame.innerW
    local listRows = {}
    for i = 1, M.MAX_LIST do
        -- ★ 每行都是带 1px 圆角描边的按钮（2026-09-30 用户：「所有的按钮都需要加上边框」+「倒圆角」），
        --   描边色 = 该行 boss 的身份色（Paint 时重染）；行首放 32px 骷髅身份图标（与地图钉点同色同贴图）
        local r = CreateFrame("Button", nil, listChild)
        r:SetSize(innerW, M.LIST_H)
        r.icon = r:CreateTexture(nil, "ARTWORK")
        r.icon:SetSize(32, 32)
        r.icon:SetTexture("Interface\\AddOns\\DungeonsForever\\Media\\BossSkull")
        if ns.hui and ns.hui.RoundIcon then ns.hui.RoundIcon(r.icon) end
        r.icon:SetPoint("LEFT", r, "LEFT", 6, 0)
        r.fs = MakeFS(r, 14, C_TEXT, "LEFT")
        r.fs:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
        r.fs:SetPoint("RIGHT", r, "RIGHT", -6, 0)
        -- 1px 圆角描边（HUI 原语）；片元存 __borderPieces，Paint 时按身份色重染
        if ns.hui and ns.hui.BuildRoundBorder then
            r.__borderPieces = ns.hui.BuildRoundBorder(r, 6, { 1, 1, 1, 0.9 }, r, "BORDER", "both", 1)
        end
        r.__idx = i
        r:SetScript("OnClick", function(self) M.Select(self.__en) end)
        r:Hide()
        listRows[i] = r
    end
    frame.listRows = listRows
end

-- ③ 右栏详情模式的三张分组卡（卡帧 + 卡头热区 + 折叠箭头 + 标题）
local function BuildBlocks()
    local frame = M.frame
    if not frame or frame.__blocksReady then return end
    frame.__blocksReady = true
    local detChild, innerW = frame.detChild, frame.innerW
    local blocks = {}
    for i = 1, 3 do
        local b = CreateFrame("Frame", nil, detChild)
        b:EnableMouse(false)          -- 不拦鼠标：卡内空白处的滚轮照样穿透到 detScroll
        if ns.hui and ns.hui.BuildRoundedBG then
            ns.hui.BuildRoundedBG(b, M.BLK_RADIUS, { 1, 1, 1, M.BLK_BG }, "both", true, 1)
        end
        -- ★ 卡头热区（整条卡头可点）+ 折叠箭头两态（▾ 展开中 / ▴ 收起中，arrow.tga 原生朝上）。
        --   热区只盖卡头那一条 ⇒ 展开时不挡下面的条目；收起时卡只剩这一条，正好铺满。
        b.hit = CreateFrame("Button", nil, b)
        b.hit:RegisterForClicks("LeftButtonUp")
        b.hit:SetHeight(M.BLK_MIN_H)
        b.arrD = b:CreateTexture(nil, "ARTWORK")
        b.arrD:SetSize(M.BLK_ARROW, M.BLK_ARROW)
        b.arrD:SetTexture("Interface\\AddOns\\DungeonsForever\\Media\\textures\\arrow.tga")
        b.arrD:SetRotation(math.pi)
        b.arrU = b:CreateTexture(nil, "ARTWORK")
        b.arrU:SetSize(M.BLK_ARROW, M.BLK_ARROW)
        b.arrU:SetTexture("Interface\\AddOns\\DungeonsForever\\Media\\textures\\arrow.tga")
        for _, at in ipairs({ b.arrD, b.arrU }) do
            at:SetVertexColor(Unpack(C_GOLD))
            at:SetPoint("TOPLEFT", b, "TOPLEFT", M.BLK_PAD, -(M.BLK_TITLE_TOP + 4))
        end
        b.hit:SetScript("OnClick", function(self)
            local key = self.__key
            if not key then return end
            local c = M.CardClosed()
            -- 收起 = true；展开 = nil（存档里不留 false）
            c[key] = not c[key] or nil
            ns.PlaySound(1)
            M.SyncSide()
        end)
        b.hit:SetScript("OnEnter", function(self)
            if not self.__key then return end
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:ClearLines()
            GameTooltip:AddLine(L["点击折叠 / 展开该组"], 1, 1, 1, true)
            GameTooltip:Show()
        end)
        b.hit:SetScript("OnLeave", function() GameTooltip:Hide() end)
        -- ★ 热区是 EnableMouse 的按钮（压在滚动容器里）⇒ 显式把滚轮转发给详情滚动条，
        --   否则鼠标停在卡头上时整页滚不动（项目铁律：子控件一律显式转发滚轮）。
        b.hit:EnableMouseWheel(true)
        b.hit:SetScript("OnMouseWheel", function(self, delta)
            M.WheelScroll(detScroll, detChild, delta)
        end)
        b:Hide()
        blocks[i] = b
    end
    local blkLoot, blkSkill, blkGuide = blocks[1], blocks[2], blocks[3]
    -- ★ 折叠键挂在**热区**上（热区才是 OnClick 的 self；挂卡帧上 ⇒ self.__key 恒 nil、点了没反应）
    blkLoot.hit.__key, blkSkill.hit.__key, blkGuide.hit.__key = "loot", "skill", "guide"

    -- 卡片 ①「掉落」：标题（14 金，与其余两张同款）+ 右上角件数 + 空态注释
    local detLtTtl = MakeFS(blkLoot, 14, C_GOLD, "LEFT")
    detLtTtl:SetText(L["掉落"])
    local detLtCnt = MakeFS(blkLoot, 12, C_GREY, "RIGHT")
    local detLtNote = MakeFS(blkLoot, 13, C_GREY, "LEFT")
    detLtNote:SetText(L["暂无掉落数据"])
    detLtNote:Hide()

    -- 卡片 ②「boss技能」：只有标题（技能行走下面的池）
    local detSkTtl = MakeFS(blkSkill, 14, C_GOLD, "LEFT")
    detSkTtl:SetText(L["boss技能"])

    -- 卡片 ③「攻略」：标题 + 正文（wowhead 汉化稿 →「攻略待补充」兜底）
    local detGdTtl = MakeFS(blkGuide, 14, C_GOLD, "LEFT")
    detGdTtl:SetText(L["攻略"])
    local detGd = MakeFS(blkGuide, 14, C_TEXT, "LEFT")
    detGd:SetWidth(innerW - M.BLK_PAD * 2)
    detGd:SetWordWrap(true)
    frame.blkLoot, frame.blkSkill, frame.blkGuide = blkLoot, blkSkill, blkGuide
    frame.detLtTtl, frame.detLtCnt, frame.detLtNote = detLtTtl, detLtCnt, detLtNote
    frame.detSkTtl = detSkTtl
    frame.detGdTtl, frame.detGd = detGdTtl, detGd
end

-- ④ 掉落行池 + 技能行池（父 = 「掉落」/「boss技能」两张卡）
local function BuildSideRows()
    local frame = M.frame
    if not frame or frame.__rowsReady then return end
    frame.__rowsReady = true
    local innerW = frame.innerW
    local blkLoot, blkSkill = frame.blkLoot, frame.blkSkill
    -- 掉落行池（父 = 掉落卡片）：**扁平化** —— 条目不再自带边框底色，只在 hover 时浮出圆角高亮
    --   （用户 2026-10-01：卡片内条目扁平化，避免「卡片套卡片」两层描边）。
    --   行宽 = 卡片内容宽；条目内左缩 6 ⇒ 图标左沿 = 卡片左沿 + BLK_PAD + 6，与技能行取齐。
    local rowW = innerW - M.BLK_PAD * 2
    local lootRows = {}
    for i = 1, M.MAX_LOOT do
        local r = CreateFrame("Button", nil, blkLoot)
        r:SetSize(rowW, M.CARD_H)
        r.icon = r:CreateTexture(nil, "ARTWORK")
        r.icon:SetSize(M.CARD_ICON, M.CARD_ICON)
        r.icon:SetPoint("LEFT", r, "LEFT", 6, 0)
        r.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        if ns.hui and ns.hui.RoundIcon then ns.hui.RoundIcon(r.icon) end
        r.name = MakeFS(r, M.CARD_FS_NAME, C_TEXT, "LEFT")
        r.name:SetPoint("TOPLEFT", r, "TOPLEFT", 6 + M.CARD_ICON + 6, -7)
        r.name:SetWordWrap(false)
        r.tp = MakeFS(r, M.CARD_FS_META, C_GREY, "LEFT")
        r.tp:SetPoint("TOPLEFT", r, "TOPLEFT", 6 + M.CARD_ICON + 6, -24)
        r.ch = MakeFS(r, M.CARD_FS_META, C_GREY, "RIGHT")
        r.ch:SetPoint("TOPRIGHT", r, "TOPRIGHT", -6, -7)
        r.tag = MakeFS(r, M.CARD_FS_META, { 0.42, 0.94, 0.62 }, "RIGHT")
        r.tag:SetText(L["新"])
        r.tag:SetPoint("TOPRIGHT", r, "TOPRIGHT", -6, -24)
        r.name:SetWidth(rowW - (6 + M.CARD_ICON + 6) - 34)
        -- hover 圆角高亮（弧盘 + 1px 描边；noRepaint ⇒ 不被主题重绘冲掉悬停态）
        if ns.hui and ns.hui.BuildRoundedBG then
            r.__hl = FlattenPieces(ns.hui.BuildRoundedBG(r, M.ROW_RADIUS,
                { 1, 1, 1, DG.LOOT_CARD_BG_HOVER }, "both", true, 1, true))
            PiecesSetShown(r.__hl, false)
        end
        r:SetScript("OnEnter", function(self)
            U.dungeonMapHover = self
            PiecesSetShown(self.__hl, true)
            if self.__it then DG.ShowItemTip(self, self.__it) end
        end)
        r:SetScript("OnLeave", function(self)
            if U.dungeonMapHover == self then U.dungeonMapHover = nil end
            PiecesSetShown(self.__hl, false)
            GameTooltip:Hide()
        end)
        r:SetScript("OnClick", function(self, button) DG.ItemShiftClick(self, button) end)
        r:Hide()
        lootRows[i] = r
    end

    -- 技能行池（父 = boss技能卡片）：左侧技能图标（与掉落图标**共用 M.CARD_ICON** ⇒ 天然同尺寸），
    -- 右侧两行 —— 第 1 行 = 技能名，第 2 行 = 客户端提示框内容；名字与正文**同色**（不单独染蓝）。
    -- 行内左缩 6 ⇒ 图标左沿与掉落行取齐（同为卡片左沿 + BLK_PAD + 6）。
    local skW = rowW - 6
    local skillRows = {}
    for i = 1, M.MAX_SKILL do
        local r = CreateFrame("Button", nil, blkSkill)
        r:SetSize(skW, M.CARD_H)
        r.icon = r:CreateTexture(nil, "ARTWORK")
        r.icon:SetSize(M.CARD_ICON, M.CARD_ICON)
        r.icon:SetPoint("TOPLEFT", r, "TOPLEFT", 0, 0)
        r.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        if ns.hui and ns.hui.RoundIcon then ns.hui.RoundIcon(r.icon) end
        r.fs = MakeFS(r, 14, C_TEXT, "LEFT")
        r.fs:SetWidth(skW - M.CARD_ICON - 6)
        r.fs:SetWordWrap(true)
        r.fs:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", 6, 0)
        r.ds = MakeFS(r, 12, C_TEXT, "LEFT")
        r.ds:SetWidth(skW - M.CARD_ICON - 6)
        r.ds:SetWordWrap(true)
        r.ds:SetPoint("TOPLEFT", r.fs, "BOTTOMLEFT", 0, -2)
        r:SetScript("OnEnter", function(self)
            if self.__sid then M.ShowSpellTip(self, self.__sid) end
        end)
        r:SetScript("OnLeave", function() GameTooltip:Hide() end)
        r:Hide()
        skillRows[i] = r
    end
    frame.lootRows, frame.skillRows = lootRows, skillRows
end

-- ⑤ 收尾：池全部就位。此刻若正停在地图页，补一次渲染
--   （分帧窗口内的 SyncBar / SyncPins / SyncSide 都空转了，右栏与钉点还空着）
local function BuildFinal()
    local frame = M.frame
    if not frame or frame.__poolsReady then return end
    frame.__poolsReady = true
    if frame:IsShown() then M.Paint(M.curD) end
end
-- 供 harness / 变异测试点名调用（也是 M.Build 内排队用的就是这几个引用）
M.EnsurePins = BuildPins
M.EnsureListRows = BuildListRows
M.EnsureBlocks = BuildBlocks
M.EnsureSideRows = BuildSideRows
M.EnsureFinal = BuildFinal

function M.Build(detail, hero)
    local frame = CreateFrame("Frame", nil, detail)
    frame:SetPoint("TOPLEFT", detail, "TOPLEFT", 0, -DG.GUIDE_TOP_Y)
    frame:SetPoint("BOTTOMRIGHT", detail, "BOTTOMRIGHT", 0, 0)
    if hero then frame:SetFrameLevel(hero:GetFrameLevel() + 1) end
    frame:Hide()

    -- 地图画布（12 块瓦片）
    local canvas = CreateFrame("Frame", nil, frame)
    canvas:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    canvas:SetSize(1, 1)
    canvas:Hide()

    local tiles = {}
    for n = 1, M.N do
        local t = canvas:CreateTexture(nil, "ARTWORK")
        t:SetTexCoord(0, 1, 0, 1)
        t:Hide()
        tiles[n] = t
    end

    -- 自制图（CUSTOM 副本用；单张整图 + UV 裁顶，Build 一次建好、Paint 只换贴图）
    local customTex = canvas:CreateTexture(nil, "ARTWORK")
    customTex:SetTexCoord(0, 1, 0, 1)
    customTex:Hide()

    -- 空态（居左半区）
    local empty = MakeFS(frame, 14, C_GREY, "CENTER")
    empty:SetPoint("CENTER", frame, "TOPLEFT", (M.FRAME_W - M.SIDE_W - M.SIDE_GAP) / 2, -M.FRAME_H / 2)
    empty:SetText(L["这个副本没有客户端自带的地图。"])
    empty:Hide()

    -- 钉点容器（与画布同锚同尺寸，百分比坐标直接换算）
    local pins = CreateFrame("Frame", nil, frame)
    pins:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    pins:SetSize(1, 1)
    pins:Hide()
    -- 楼层按钮条（常驻池；★ 悬浮在地图右上角，不再占地图高度 ⇒ 单层/多层同一版面）
    local bar = CreateFrame("Frame", nil, frame)
    bar:SetHeight(M.BAR_H)
    bar:SetWidth(M.MAX_LAYERS * (M.LAYER_W + M.LAYER_GAP))
    bar:Hide()

    local btns = {}
    for i = 1, M.MAX_LAYERS do
        local bt = Host.NewButton(bar, "", M.LAYER_W, M.BAR_H, 12)
        bt:SetFrameLevel(frame:GetFrameLevel() + 2)
        bt.__idx = i
        Host.MakeOutline(bt, 1, 0.82, 0)
        bt.__huiKeepTextColor = true
        bt:SetScript("OnClick", function(self) M.SetLayer(self.__idx) end)
        bt:Hide()
        btns[i] = bt
    end

    -- ★ 左上角「隐藏 boss」开关（2026-10-01 用户）—— 与右上角楼层按钮同款外观、同为悬浮层，
    --   一左一右；只切换**地图画布上的钉点**显隐，右栏首领列表 / 详情不受影响
    --   （那两处是文字与卡片，不是「地图上的 boss 按钮」）。文案随状态双向切换，
    --   隐藏时描边点亮（复用楼层按钮选中态那一套视觉语言：金描边 = 开关已打开）。
    --   显隐由 M.HasPins(副本) 决定（本副本压根没钉点 → 不出开关），在 SyncPins 里刷。
    local bossBtn = Host.NewButton(frame, "", M.BOSS_BTN_W, M.BAR_H, 12)
    bossBtn:SetFrameLevel(frame:GetFrameLevel() + 2)
    bossBtn.__idx = -1                       -- 非楼层按钮（-1 = 开关；层池 1..MAX_LAYERS）
    Host.MakeOutline(bossBtn, 1, 0.82, 0)
    bossBtn.__huiKeepTextColor = true
    bossBtn:SetScript("OnClick", function() M.ToggleBoss() end)
    bossBtn:Hide()

    -- 右栏（首领列表 ↔ 单个首领详情）
    local side = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    side:SetPoint("TOPLEFT", frame, "TOPLEFT", M.FRAME_W - M.SIDE_W, 0)
    side:SetSize(M.SIDE_W, M.FRAME_H)
    -- ★ 右栏面板同样倒圆角（用户 2026-10-01：「所有的卡片都需要倒圆角」）——
    --   与三张分组卡片同一套 HUI 原语（圆角填充底 + 主题描边）；无 HUI 时退回直角 backdrop。
    if ns.hui and ns.hui.BuildRoundedBG then
        ns.hui.BuildRoundedBG(side, M.BLK_RADIUS, { 1, 1, 1, 0.03 }, "both", true, 1)
    else
        side:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
        })
        side:SetBackdropColor(1, 1, 1, 0.03)
        side:SetBackdropBorderColor(1, 1, 1, 0.10)
    end
    side:Hide()

    local innerW = M.SIDE_W - M.SIDE_PAD * 2

    -- 列表模式
    local listScroll = CreateFrame("ScrollFrame", nil, side)
    listScroll:SetPoint("TOPLEFT", side, "TOPLEFT", M.SIDE_PAD, -M.SIDE_PAD)
    listScroll:SetPoint("BOTTOMRIGHT", side, "BOTTOMRIGHT", -M.SIDE_PAD, M.SIDE_PAD)
    local listChild = CreateFrame("Frame", nil, listScroll)
    listChild:SetSize(innerW, 10)
    listScroll:SetScrollChild(listChild)
    listScroll:EnableMouseWheel(true)
    listScroll:SetScript("OnMouseWheel", function(self, delta)
        M.WheelScroll(self, listChild, delta)
    end)
    local listHdr = MakeFS(listChild, 14, C_GOLD, "LEFT")
    listHdr:SetPoint("TOPLEFT", listChild, "TOPLEFT", 2, 0)
    listHdr:SetText(L["首领"])

    local listNote = MakeFS(listChild, 13, C_GREY, "LEFT")
    listNote:SetPoint("TOPLEFT", listChild, "TOPLEFT", 2, -26)
    listNote:SetWidth(innerW - 4)
    listNote:SetWordWrap(true)
    listNote:SetText(L["尚未收录这个副本的 boss 名单，数据补上后会自动出现。"])
    listNote:Hide()
    -- 详情模式
    local detScroll = CreateFrame("ScrollFrame", nil, side)
    detScroll:SetPoint("TOPLEFT", side, "TOPLEFT", M.SIDE_PAD, -M.SIDE_PAD)
    detScroll:SetPoint("BOTTOMRIGHT", side, "BOTTOMRIGHT", -M.SIDE_PAD, M.SIDE_PAD)
    local detChild = CreateFrame("Frame", nil, detScroll)
    detChild:SetSize(innerW, 10)
    detScroll:SetScrollChild(detChild)
    detScroll:EnableMouseWheel(true)
    detScroll:SetScript("OnMouseWheel", function(self, delta)
        M.WheelScroll(self, detChild, delta)
    end)

    local detBack = Host.NewButton(detChild, L["‹ 全部首领"], 84, 20, 12)
    detBack:SetScript("OnClick", function() M.ShowList() end)
    -- ★ 右上角（2026-09-30 用户点名）：此前无锚点 → 默认落父容器中心被内容盖住「消失」
    detBack:SetPoint("TOPRIGHT", detChild, "TOPRIGHT", 0, 0)

    local detName = MakeFS(detChild, 16, C_GOLD, "LEFT")
    detName:SetWordWrap(false)

    -- ── 池化字段（外壳部分；四个重池的字段由各自的分帧块补）──
    frame.canvas = canvas
    frame.tiles = tiles
    frame.customTex = customTex
    frame.empty = empty
    frame.pins = pins
    frame.bar = bar
    frame.btns = btns
    frame.bossBtn = bossBtn
    frame.innerW = innerW
    frame.side = side
    frame.listScroll = listScroll
    frame.listChild = listChild
    frame.listHdr = listHdr
    frame.listNote = listNote
    frame.detScroll = detScroll
    frame.detChild = detChild
    frame.detBack = detBack
    frame.detName = detName
    frame.detChildW = innerW - M.BLK_PAD * 2
    -- 「隐藏 boss」开关状态：与 dungeonTab / dungeonView 同一张存档表（跨角色共享）；
    -- 缺省 nil = 不隐藏。**布尔化再存 M**（存档里可能是任意历史值，直接当条件用会埋雷）。
    M.hideBoss = (DungeonsForeverDB and DungeonsForeverDB.dungeon
                  and DungeonsForeverDB.dungeon.mapBossHidden) and true or false
    M.frame = frame
    -- ── 重活一律不占当前帧：四个池 + 收尾全部排队 ──
    local queued = (type(DG) == "table" and type(DG.PushStep) == "function")
    if queued then
        DG.PushStep(BuildPins)
        DG.PushStep(BuildListRows)
        DG.PushStep(BuildBlocks)
        DG.PushStep(BuildSideRows)
        DG.PushStep(BuildFinal)
        DG.RunSteps()
    else
        -- 同步兜底（离线桩 / 极端环境）：调用方返回时一切就绪
        BuildPins()
        BuildListRows()
        BuildBlocks()
        BuildSideRows()
        BuildFinal()
    end
    return frame
end

function M.WheelScroll(scroll, child, delta)
    if not (scroll and child) then return end
    local ch = child:GetHeight()
    local sh = scroll:GetHeight()
    if type(ch) ~= "number" or type(sh) ~= "number" then return end
    local maxScroll = math.max(0, ch - sh)
    scroll:SetVerticalScroll(math.max(0, math.min(maxScroll, scroll:GetVerticalScroll() - delta * 48)))
end

-- ── 楼层按钮 ──────────────────────────────────────────────────────────────

-- 显/隐 + 文案 + 选中态 + 排布；多层才出现，单层整条收起
function M.SyncBar(layers, cur)
    local frame = M.frame
    if not frame then return end
    local n = layers and #layers or 0
    local multi = (n > 1)
    frame.bar:SetShown(multi)
    if not multi then
        for i = 1, M.MAX_LAYERS do frame.btns[i]:Hide() end
        return
    end
    local W, GAP = M.LAYER_W, M.LAYER_GAP
    local fmt = L["第 %d 层"] or "第 %d 层"
    for i = 1, M.MAX_LAYERS do
        local bt = frame.btns[i]
        if i <= n then
            bt:SetText(fmt:format(i))
            bt:ClearAllPoints()
            bt:SetPoint("TOPRIGHT", frame.bar, "TOPRIGHT", -((n - i) * (W + GAP)), 0)
            local sel = (i == cur)
            Host.SetOutline(bt, sel, 1, 0.82, 0)
            local fs = bt:GetFontString()
            if fs then fs:SetTextColor(Unpack(sel and C_GOLD or C_GREY)) end
            bt:Show()
        else
            bt:Hide()
        end
    end
end

-- 点楼层按钮：只改当前层再重画，帧不动
function M.SetLayer(i)
    local layers = M.LayersFor(M.curId)
    if not (layers and layers[i]) then return end
    if i == M.curLayer then return end
    M.curLayer = i
    M.Paint(M.curD)
end

-- ── 钉点 ──────────────────────────────────────────────────────────────────

-- 显示层序号 → 客户端层号（ART 前缀的尾数字，如 ShadowfangKeep7_ → 7、
-- Gnomeregan10_ → 10）；没有数字后缀 / 无图 → 按序号本身。
function M.FloorNumAt(id, idx)
    local layers = M.LayersFor(id)
    local lay = layers and layers[idx or 1]
    if not lay then return idx or 1 end
    return tonumber(lay:match("(%d+)_")) or idx or 1
end

-- 首领身份色：en 在 BossesFor(id) 里的序号 → 色板（循环）；查不到回白色兜底
function M.BossColor(id, en)
    local bs = M.BossesFor(id)
    if bs and en then
        for i = 1, #bs do
            if bs[i].en == en then
                local c = M.BOSS_PALETTE[((i - 1) % #M.BOSS_PALETTE) + 1]
                return c[1], c[2], c[3]
            end
        end
    end
    return 1, 1, 1
end

-- 有图就画钉点：客户端瓦片图按**当前层**取（多层副本按层放钉点，2026-09-30）；
-- 自制手绘图是单张整图、没有楼层概念 ⇒ 固定第 1 层（数据里自制副本的钉点全是两位式坐标）。
-- 真无图（空态）不画 —— 没有坐标系，不替玩家猜位置。
function M.SyncPins()
    local frame = M.frame
    if not frame then return end
    -- ★ 分帧窗口保护：钉点池由 BuildPins 排队建；没到货就安全空转（BuildFinal 会补渲染）。
    --   ★ 判据必须是 `__` 前缀旗标而不是 `frame.pinBtns` 本身 —— 离线桩的万能壳会把
    --     缺失的普通字段**现造成 function**（function 为真 ⇒ 兜不住，随后索引它就崩），
    --     而 `__xxx` 字段桩里一律回 nil（与真机一致）。踩过一次，别改回去。
    if not frame.__pinsReady then return end
    local list, n = nil, 0
    local floor
    if M.curId and M.LayersFor(M.curId) then
        floor = M.FloorNumAt(M.curId, M.curLayer or 1)
    elseif M.curId and M.CustomFor(M.curId) then
        floor = 1
    end
    if M.curId and floor then
        list = M.PinsFor(M.curId, floor)
        local ex = M.ExtraPinsFor(M.curId, floor)
        if ex then
            for i = 1, #ex do
                list = list or {}
                list[#list + 1] = ex[i]
            end
        end
    end
    if list and #list > 0 then
        local cw, ch = frame.pinW, frame.pinH
        for i = 1, #list do
            if i > M.MAX_PINS then break end
            n = n + 1
            local p = list[i]
            local bt = frame.pinBtns[n]
            local kind = p.kind or "boss"
            bt.__kind, bt.__p = kind, p
            bt.__en, bt.__zh = p.en, p.zh
            bt:ClearAllPoints()
            bt:SetPoint("CENTER", frame.pins, "TOPLEFT",
                        (p.left / 100) * cw, -(p.top / 100) * ch)
            -- 名字 / 颜色先算：boss 专属色即身份（**图标与文字同色**，2026-10-04 用户定——
            -- 之前钉体恒定金，用户问「怎么全是黄色」）；其余类型按类别固定色
            local nm, cr, cg, cb
            if kind == "boss" then
                nm = p.zh or p.en or ""
                cr, cg, cb = M.BossColor(M.curId, p.en)
            elseif kind == "quest" then
                -- 2026-10-04 用户定：任务钉只显图标不显下方名字（名字在悬停 tooltip）
                nm = ""
                cr, cg, cb = Unpack(C_GOLD)
            elseif kind == "object" then
                nm = DG.ItemName(p.id)
                cr, cg, cb = Unpack(C_TEXT)
            elseif kind == "entrance" then
                nm = L["副本入口"]
                cr, cg, cb = Unpack(C_GOLD)
            else
                nm = p.name or ""
                cr, cg, cb = 0.72, 0.76, 0.85
            end
            -- 贴图按类型走：boss = 骷髅染身份色（与文字同色）/ 稀有 = 骷髅银染；
            -- 任务 = 黄「!」；入口 = 石门；物品 = 客户端物品图标（铁律：外观运行期问客户端）。
            if kind == "quest" then
                bt.dot:SetTexture(M.PIN_QUEST_TEX)
                bt.dot:SetVertexColor(1, 1, 1)
            elseif kind == "entrance" then
                bt.dot:SetTexture(M.PIN_DOOR_TEX)
                bt.dot:SetVertexColor(1, 1, 1)
            elseif kind == "object" then
                bt.dot:SetTexture(DG.ItemIcon(p.id))
                bt.dot:SetVertexColor(1, 1, 1)
            else
                bt.dot:SetTexture(M.PIN_BOSS_TEX)
                bt.dot:SetVertexColor(cr, cg, cb)
            end
            bt.nm:SetText(nm or "")
            -- 名字常驻显示在钉点正下方；选中（仅 boss）16 / 未选 14
            local sel = (kind == "boss") and (M.detailEn == p.en) or false
            local fpath, _, fflags = bt.nm:GetFont()
            bt.nm:SetFont(fpath, sel and 16 or 14, fflags)
            bt.nm:SetTextColor(cr, cg, cb)
            bt.dot:ClearAllPoints()
            bt.dot:SetPoint("CENTER", bt, "CENTER", 0, 0)
            bt.dot:SetSize(sel and M.PIN_SIZE or M.PIN_MIN, sel and M.PIN_SIZE or M.PIN_MIN)
            bt:SetScript("OnClick", M.PinOnClick)
            bt:SetScript("OnEnter", M.PinOnEnter)
            bt:SetScript("OnLeave", M.PinOnLeave)
            bt:Show()
        end
    end
    for i = n + 1, M.MAX_PINS do
        frame.pinBtns[i]:Hide()
        frame.pinBtns[i].nm:SetText("") -- 文字不随按钮 Hide，必须同步清（否则残留压图标）
    end
    -- ★ 左上角「隐藏 boss」开关打开时：钉点池**连名字一起**整体收起。
    --   只藏地图上这一片（右栏首领列表 / 详情不跟着动 —— 用户要的是藏掉地图上的 boss 按钮）。
    --   注意容器与每个钉点**都要 Hide**：容器隐藏靠父级裁剪，实机稳，但离线断言看得见的是
    --   每个 pinBtns[i].__shown，两处一起收才不会「容器藏了、池子还亮着」这种半吊子状态。
    local show = (n > 0) and not M.hideBoss
    if not show then
        for i = 1, M.MAX_PINS do
            frame.pinBtns[i]:Hide()
            frame.pinBtns[i].nm:SetText("") -- 同上：文字层不随按钮收，同步清
        end
    end
    frame.pins:SetShown(show)
    -- 开关自身的显隐 / 文案 / 选中态 —— 挂在 SyncPins 末尾，任何重画路径（换副本、切层、选中）都同步
    M.SyncBossBtn()
end

-- ── 钉点点击 / 悬停（按 __kind 分派）─────────────────────────────────────────
-- boss = 右栏选中；任务 = 切到详情任务区并选中该任务（SetDungeonTab 内部先
-- EnsureQuestLane 再渲染，「先补建再切显隐」顺序由它负责）；物品 = 物品提示框
-- （走 DG.ShowItemTip，自带重入守卫）；入口 / 稀有 = 一行说明。
function M.PinOnClick(self)
    local kind, p = self.__kind, self.__p
    if kind == "boss" and p and p.en then
        M.Select(p.en)
    elseif kind == "quest" and p and p.id then
        U.dungeonQuestSel = p.id
        U:SetDungeonTab("quest")
    end
end

function M.PinOnEnter(self)
    local p = self.__p
    if not p or self.__kind == "boss" then return end
    if self.__kind == "object" then
        DG.ShowItemTip(self, { p.id })
        return
    end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:ClearLines()
    if self.__kind == "quest" then
        GameTooltip:AddLine(DG.QuestName(p.id) or L["任务"], 1, 0.82, 0, true)
        GameTooltip:AddLine(L["点击查看任务详情"], 0.7, 0.7, 0.7, true)
    elseif self.__kind == "entrance" then
        GameTooltip:AddLine(L["副本入口"], 1, 0.82, 0, true)
    elseif self.__kind == "rare" then
        GameTooltip:AddLine(L["稀有"] .. "：" .. (p.name or ""), 0.72, 0.76, 0.85, true)
    end
    GameTooltip:Show()
end

function M.PinOnLeave()
    GameTooltip:Hide()
end

-- ── 左上角「隐藏图钉」开关 ────────────────────────────────────────────────

-- 三件事：显隐（本副本有钉点才出）/ 文案（隐藏boss ↔ 显示boss）/ 选中态（金描边 = 已隐藏）
-- ★ 文案两向都走 L[]：zhCN 客户端回退键名即文案，enUS / zhTW 走各自的覆盖表 ——
--   不写字面量，免得加了一处漏掉两处本地化。
function M.SyncBossBtn()
    local frame = M.frame
    local bt = frame and frame.bossBtn
    if not bt then return end
    local off = M.hideBoss and true or false
    bt:SetText(off and L["显示图钉"] or L["隐藏图钉"])
    Host.SetOutline(bt, off, 1, 0.82, 0)
    local fs = bt:GetFontString()
    if fs then fs:SetTextColor(Unpack(off and C_GOLD or C_GREY)) end
    bt:SetShown(M.HasPins(M.curId))
end

-- 点开关：改状态 → 存盘（跨角色）→ 重画钉点。SyncPins 末尾会刷开关外观，这里不再重复调。
-- 帧不动、右栏不碰 —— 纯显隐切换，零新建帧。
function M.ToggleBoss()
    M.hideBoss = not M.hideBoss
    local s = DungeonsForeverDB and DungeonsForeverDB.dungeon
    if type(s) == "table" then s.mapBossHidden = M.hideBoss or nil end
    M.SyncPins()
end

-- ── 右栏 ──────────────────────────────────────────────────────────────────

-- 摆一张掉落条目（坐标相对**掉落卡片**：内容左缩 M.BLK_PAD，行宽 rowW）
--   ★ 2026-10-01 卡片化：条目不再自带边框底色（避免卡片套卡片两层描边），
--   只在 hover 时浮出圆角高亮。
local function layoutLootRow(r, it, y, rowW)
    local id = it[1]
    r.icon:SetTexture(DG.ItemIcon(id))
    local nm, hasName = DG.ItemName(id)
    r.name:SetText(nm)
    if hasName then
        r.name:SetTextColor(DG.QColor(DG.QualOf(id)))
    else
        r.name:SetTextColor(Unpack(C_GREY))
    end
    r.tp:SetText(DG.ItemMeta(id))
    r.ch:SetText(DG.Pct(it[2]) or "")
    r.tag:SetShown(it[3] and true or false)
    r.__it = it
    -- 行会被复用 / 重新布局 ⇒ 先复位悬停高亮（Hide 不触发 OnLeave，不复位会残留到新行）
    PiecesSetShown(r.__hl, false)
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", r:GetParent(), "TOPLEFT", M.BLK_PAD, y)
    r:SetSize(rowW, M.CARD_H)
    r:Show()
end

-- 摆一张卡片的卡头：热区铺满卡宽（左 + 右两条锚点）+ 箭头两态互斥 + 标题让出箭头位。
--   ★ 标题必须每轮重锚（清空后不锚定 ⇒ 落父容器中心、被卡内内容盖住 = 实机「标题消失」）。
local function LayoutCardHead(blk, ttl, isClosed)
    blk.hit:ClearAllPoints()
    blk.hit:SetPoint("TOPLEFT", blk, "TOPLEFT", 0, 0)
    blk.hit:SetPoint("TOPRIGHT", blk, "TOPRIGHT", 0, 0)
    blk.hit:Show()
    blk.arrD:SetShown(not isClosed)
    blk.arrU:SetShown(isClosed)
    ttl:ClearAllPoints()
    ttl:SetPoint("TOPLEFT", blk, "TOPLEFT", M.BLK_TITLE_X, -M.BLK_TITLE_TOP)
end

function M.SyncSide()
    local frame = M.frame
    if not frame then return end
    -- ★ 分帧窗口保护：右栏的**行池与卡片**都由 Build 排队建；没到货时整块空转
    --   （BuildFinal 建完补渲染，详见 M.Build 头的注释）。
    --   ★ 判据用 `__` 前缀旗标（桩里回 nil、真机也是 nil），不能判 `frame.listRows`
    --     —— 桩会把缺失字段现造成 function（真值），随后索引它当场崩。
    if not (frame.__listReady and frame.__blocksReady and frame.__rowsReady) then return end
    local id = M.curId
    local bosses = M.BossesFor(id)
    frame.side:SetShown(true)

    -- 详情模式
    if M.detailEn then
        local zh, items
        for i = 1, #(bosses or {}) do
            if bosses[i].en == M.detailEn then
                zh = bosses[i].zh
                items = bosses[i].items
                break
            end
        end
        if not zh then M.detailEn = nil end
        if zh then
            frame.listScroll:Hide()
            frame.detScroll:Show()
            frame.detBack:Show()
            frame.detName:SetText(zh)
            -- ★ 整体上移（2026-09-30 用户）：boss 名与右上角「‹ 全部首领」按钮同排，
            --   内容从按钮行下 8px 起（旧版 -50 起，现 -28 起，上移约 22px）
            frame.detName:ClearAllPoints()
            frame.detName:SetPoint("TOPLEFT", frame.detChild, "TOPLEFT", 0, -1)
            frame.detName:SetWidth(frame.innerW - 90)

            -- ★★ 版式（2026-10-01 卡片化）：三张分组卡片自上而下 —— ① 掉落 ② boss技能 ③ 攻略。
            --   卡片高度**先按内容全算完再摆**：技能行高依赖换行结果，必须两遍。
            local rowW = frame.detChildW or (frame.innerW - M.BLK_PAD * 2)
            local closed = M.CardClosed()

            -- ① 掉落件数（受行池上限截断）
            local nLoot = 0
            for _i = 1, #(items or {}) do
                if nLoot >= M.MAX_LOOT then break end
                nLoot = nLoot + 1
            end

            -- ② 技能行：内容与高度一起定下来（宽度已在 Build 里设好，高度依赖换行）
            local sk = M.SkillsFor(id, M.detailEn)
            local nSk = 0
            for _i = 1, #(sk or {}) do
                if nSk >= M.MAX_SKILL then break end
                nSk = nSk + 1
            end
            local srow = {}
            for i = 1, nSk do
                local r = frame.skillRows[i]
                local nm = sk[i][1] or ""
                local ds = sk[i][2] or ""
                local sid = sk[i][3]
                -- ★ 第 3 位也可能是**图标 slug 字符串**（自制副本无法术 id，2026-09-30 新形态）
                --   —— 数字 = 法术 id（图标走 [4] 兜底）；字符串 = 直接当 slug 用。
                --   ⚠ 只许一个 slug：曾有两个 local slug 相互覆盖，第 3 位形态图标从未生效（实锤 2026-09-30）
                local sidN = (type(sid) == "number") and sid or nil
                local slug = (type(sid) == "string" and sid ~= "") and sid or sk[i][4]
                local fbIcon = (type(slug) == "string" and slug ~= "")
                    and ("Interface\\Icons\\" .. slug) or nil
                local cn, ic, cd = M.SpellRowFor(sidN, nm, ds ~= "" and ds or nil, fbIcon)
                -- id 行数据侧不存名（wowhead id 唯一来源，名字由客户端出，2026-09-30 v3）：
                --   客户端也不认识 → 「法术 #id」占位，避免空行
                if sidN and (cn == nil or cn == "") then cn = "法术 #" .. sidN end
                r.__sid = sidN
                r.fs:SetText(cn or "")
                r.ds:SetText(cd or "")
                r.ds:SetShown(type(cd) == "string" and cd ~= "")
                local nh = r.fs:GetStringHeight()
                local dh = r.ds:GetStringHeight()
                local rh = math.max(M.CARD_ICON,
                    (type(nh) == "number" and nh or 18)
                    + ((type(cd) == "string" and cd ~= "")
                        and ((type(dh) == "number" and dh or 15) + 2) or 0))
                srow[i] = { ic = ic, h = rh }
            end

            -- ③ 攻略正文（wowhead 汉化稿 →「攻略待补充」兜底）
            local guide = M.GuideFor(id, M.detailEn)
            local hasGuide = (type(guide) == "string" and guide ~= "")
            local showGd = hasGuide or (nSk == 0)
            frame.detGd:SetText(hasGuide and guide or L["攻略待补充"])
            local gh = frame.detGd:GetStringHeight()
            local gdTextH = (type(gh) == "number") and gh or 18

            -- ④ 卡片高度 = 卡头 + 内容 + 下内缩
            local ltContentH = (nLoot > 0) and (nLoot * M.CARD_H + (nLoot - 1) * M.ROW_GAP) or 18
            local skContentH = 0
            for i = 1, nSk do
                skContentH = skContentH + srow[i].h
                if i < nSk then skContentH = skContentH + M.ROW_GAP end
            end
            local ltH = closed.loot and M.BLK_MIN_H or (M.BLK_HDR + ltContentH + M.BLK_PAD)
            local skH = closed.skill and M.BLK_MIN_H or (M.BLK_HDR + skContentH + M.BLK_PAD)
            local gdH = closed.guide and M.BLK_MIN_H or (M.BLK_HDR + gdTextH + M.BLK_PAD)

            -- ⑤ 自上而下摆三张卡片（掉落 → boss技能 → 攻略）
            local y = -26
            local by
            local blkLoot = frame.blkLoot
            blkLoot:ClearAllPoints()
            blkLoot:SetPoint("TOPLEFT", frame.detChild, "TOPLEFT", 0, y)
            blkLoot:SetSize(frame.innerW, ltH)
            blkLoot:Show()
            LayoutCardHead(blkLoot, frame.detLtTtl, closed.loot)
            frame.detLtCnt:ClearAllPoints()
            frame.detLtCnt:SetPoint("TOPRIGHT", blkLoot, "TOPRIGHT", -M.BLK_PAD, -(M.BLK_TITLE_TOP + 1))
            frame.detLtCnt:SetText((L["%d 件"] or "%d 件"):format(#(items or {})))
            by = -M.BLK_HDR
            -- 收起 ⇒ 上界取 0（一条不摆），尾循环从 1 起把所有行收回池里（含上一轮显示过的）
            for i = 1, (closed.loot and 0 or nLoot) do
                layoutLootRow(frame.lootRows[i], items[i], by, rowW)
                by = by - (M.CARD_H + M.ROW_GAP)
            end
            for i = (closed.loot and 1 or nLoot + 1), M.MAX_LOOT do frame.lootRows[i]:Hide() end
            frame.detLtNote:SetShown(nLoot == 0 and not closed.loot)
            frame.detLtNote:ClearAllPoints()
            frame.detLtNote:SetPoint("TOPLEFT", blkLoot, "TOPLEFT", M.BLK_PAD, by)
            y = y - ltH - M.BLK_GAP

            -- 卡片 ②「boss技能」：没技能就整卡不出（沿用旧规则）
            local blkSkill = frame.blkSkill
            if nSk > 0 then
                blkSkill:ClearAllPoints()
                blkSkill:SetPoint("TOPLEFT", frame.detChild, "TOPLEFT", 0, y)
                blkSkill:SetSize(frame.innerW, skH)
                blkSkill:Show()
                LayoutCardHead(blkSkill, frame.detSkTtl, closed.skill)
                by = -M.BLK_HDR
                -- 收起 ⇒ 上界取 0（一条不摆）；下面的尾循环从 1 起收回池里
                for i = 1, (closed.skill and 0 or nSk) do
                    local r = frame.skillRows[i]
                    if srow[i].ic then
                        r.icon:SetTexture(srow[i].ic)
                        r.icon:Show()
                    else
                        r.icon:Hide()
                    end
                    r:ClearAllPoints()
                    -- 行内左缩 6 ⇒ 图标左沿 = 卡片左沿 + BLK_PAD + 6，与掉落行取齐
                    r:SetPoint("TOPLEFT", blkSkill, "TOPLEFT", M.BLK_PAD + 6, by)
                    r:SetHeight(srow[i].h)
                    r:Show()
                    by = by - srow[i].h - M.ROW_GAP
                end
                y = y - skH - M.BLK_GAP
            else
                blkSkill:Hide()
            end
            for i = (closed.skill and 1 or nSk + 1), M.MAX_SKILL do
                frame.skillRows[i].__sid = nil
                frame.skillRows[i]:Hide()
            end

            -- 卡片 ③「攻略」：没攻略**且有技能**时整卡不出（沿用旧规则）
            local blkGuide = frame.blkGuide
            if showGd then
                blkGuide:ClearAllPoints()
                blkGuide:SetPoint("TOPLEFT", frame.detChild, "TOPLEFT", 0, y)
                blkGuide:SetSize(frame.innerW, gdH)
                blkGuide:Show()
                LayoutCardHead(blkGuide, frame.detGdTtl, closed.guide)
                if closed.guide then
                    frame.detGd:Hide()
                else
                    frame.detGd:ClearAllPoints()
                    frame.detGd:SetPoint("TOPLEFT", blkGuide, "TOPLEFT", M.BLK_PAD, -M.BLK_HDR)
                    frame.detGd:Show()
                end
                y = y - gdH - M.BLK_GAP
            else
                blkGuide:Hide()
                frame.detGd:Hide()
            end
            y = y + M.BLK_GAP

            frame.detChild:SetHeight(math.max(30, -y + 10))
            frame.detScroll:SetVerticalScroll(0)
            return
        end
    end

    -- 列表模式
    frame.detScroll:Hide()
    frame.listScroll:Show()
    local n = 0
    local y = -26
    for i = 1, #(bosses or {}) do
        if n >= M.MAX_LIST then break end
        n = n + 1
        local r = frame.listRows[n]
        r.__en = bosses[i].en
        r.fs:SetText(bosses[i].zh or bosses[i].en)
        -- 颜色即身份：图标 + 1px 描边 = boss 专属色；名字保持白字（列表里靠图标对色）
        local cr, cg, cb = M.BossColor(id, bosses[i].en)
        r.icon:SetVertexColor(cr, cg, cb)
        for _, t in ipairs(r.__borderPieces or {}) do t:SetVertexColor(cr, cg, cb) end
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", frame.listChild, "TOPLEFT", 0, y)
        r:Show()
        y = y - (M.LIST_H + M.LIST_GAP)
    end
    for i = n + 1, M.MAX_LIST do frame.listRows[i]:Hide() end
    frame.listNote:SetShown(n == 0)
    frame.listChild:SetHeight(math.max(30, -y + 8))
    frame.listScroll:SetVerticalScroll(0)
end

-- 选中某首领（点钉点或点列表行）
function M.Select(en)
    local id = M.curId
    if not (id and en) then return end
    local bosses = M.BossesFor(id)
    local hit = false
    for i = 1, #(bosses or {}) do
        if bosses[i].en == en then hit = true break end
    end
    if not hit then return end
    if M.detailEn == en then en = nil end   -- 再点一次 = 取消选中
    M.detailEn = en
    M.SyncPins()
    M.SyncSide()
end

function M.ShowList()
    M.detailEn = nil
    M.SyncPins()
    M.SyncSide()
end

-- ── 重画 ──────────────────────────────────────────────────────────────────

function M.Paint(d)
    local frame = M.frame
    if not frame then return end
    M.curD = d
    local id = d and d.id
    local layers = M.LayersFor(id)
    local leftW, cw, ch, cx, cy = M.Box()
    frame.pinW, frame.pinH = cw, ch

    -- 换副本 → 回到默认层、取消选中；同一个副本重画则保留用户选的层与首领
    if M.curId ~= id then
        M.curId, M.curLayer, M.detailEn = id, 1, nil
    end

    frame.canvas:ClearAllPoints()
    frame.canvas:SetPoint("TOPLEFT", frame, "TOPLEFT", cx, -cy)
    frame.canvas:SetSize(cw, ch)
    frame.pins:ClearAllPoints()
    frame.pins:SetPoint("TOPLEFT", frame, "TOPLEFT", cx, -cy)
    frame.pins:SetSize(cw, ch)
    -- 楼层按钮条贴地图右上角（跟随实际图像框，不写死在 frame 右上角）
    frame.bar:ClearAllPoints()
    frame.bar:SetPoint("TOPRIGHT", frame, "TOPLEFT",
                       cx + cw - M.FLOOR_INSET, -(cy + M.FLOOR_INSET))
    -- 「隐藏 boss」开关贴地图**左上角**内侧（与右上角楼层按钮对称，同一组边距常量）
    frame.bossBtn:ClearAllPoints()
    frame.bossBtn:SetPoint("TOPLEFT", frame, "TOPLEFT",
                           cx + M.FLOOR_INSET, -(cy + M.FLOOR_INSET))

    if not layers then
        M.curLayer = nil
        for n = 1, M.N do frame.tiles[n]:Hide() end
        local cpath, cv1 = M.CustomFor(id)
        if cpath then
            -- 自制图：满铺同一块画布（几何与客户端图一致），贴图即画面 ⇒ UV 取满
            frame.canvas:Show()
            frame.customTex:SetTexture(cpath)
            frame.customTex:SetTexCoord(0, 1, 0, cv1)
            frame.customTex:ClearAllPoints()
            frame.customTex:SetPoint("TOPLEFT", frame.canvas, "TOPLEFT", 0, 0)
            frame.customTex:SetSize(cw, ch)
            frame.customTex:Show()
            frame.empty:Hide()
        else
            frame.canvas:Hide()
            frame.customTex:Hide()
            frame.empty:Show()
        end
        frame.pins:Hide()
        M.SyncBar(nil, nil)
        M.SyncPins()
        M.SyncSide()
        return
    end
    frame.empty:Hide()
    frame.customTex:Hide()

    local idx = M.curLayer or 1
    if idx < 1 or idx > #layers then idx = 1 end
    M.curLayer = idx

    frame.canvas:Show()
    local lay = M.Layout(cw, ch)
    local path = M.PathAt(id, idx)
    local cpath, cv1 = M.CustomFloorFor(id, idx)   -- 本层被用户手绘图顶掉？（达拉然城第 1 层）
    for n = 1, M.N do frame.tiles[n]:Hide() end
    if cpath then
        -- 自制层：整张满铺同一块画布（几何与客户端图一致），贴图即画面 ⇒ UV 取满；
        -- ★ 与 12 块瓦片**互斥**：瓦片上面刚全隐、这儿也不补画（收起由上面那句统一做）
        frame.customTex:SetTexture(cpath)
        frame.customTex:SetTexCoord(0, 1, 0, cv1)
        frame.customTex:ClearAllPoints()
        frame.customTex:SetPoint("TOPLEFT", frame.canvas, "TOPLEFT", 0, 0)
        frame.customTex:SetSize(cw, ch)
        frame.customTex:Show()
    else
        for _, p in ipairs(lay) do
            local t = frame.tiles[p.n]
            t:SetTexture(path .. p.n)
            t:SetTexCoord(p.u0, p.u1, p.v0, p.v1)
            t:ClearAllPoints()
            t:SetPoint("TOPLEFT", frame.canvas, "TOPLEFT", p.x, -p.y)
            t:SetSize(p.w, p.h)
            t:Show()
        end
    end
    M.SyncBar(layers, idx)
    M.SyncPins()
    M.SyncSide()
end
