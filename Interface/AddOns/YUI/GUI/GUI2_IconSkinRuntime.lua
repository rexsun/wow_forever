local YUI = _G.YUI
local GUI2 = YUI and YUI.GUI2
local Skins = GUI2 and GUI2.IconSkins
if not Skins then return end

local unpack = unpack or table.unpack
local bindings = setmetatable({}, { __mode = "k" })
local owners = setmetatable({}, { __mode = "k" })
local claims = setmetatable({}, { __mode = "k" })
local groups, pending, eventOwner = {}, {}, {}
local groupLabels = {}
local hookedGroups, groupDB = {}, {}
local swipeTextures = setmetatable({}, { __mode = "k" })
local swipeHooks = setmetatable({}, { __mode = "k" })
local DYNAMIC_LAYERS = { Icon = true, Count = true, HotKey = true, Name = true,
    Cooldown = true, ChargeCooldown = true, CooldownLoC = true }
Skins.bindings, Skins.regionOwners, Skins.claims = bindings, owners, claims
Skins.stats = { attaches = 0, releases = 0, refreshes = 0 }

local function InCombat()
    return InCombatLockdown and InCombatLockdown() == true
end

local function Read(region, method, ...)
    if not region[method] then return nil end
    local values = { pcall(region[method], region, ...) }
    if not values[1] then return nil end
    table.remove(values, 1)
    for _, value in pairs(values) do
        if issecretvalue and issecretvalue(value) then return nil end
    end
    return values
end

local function DynamicState(region)
    local state = {}
    local texture = Read(region, "GetTexture")
    if texture then state.hasTexture = true; state.texture = texture[1] end
    state.color = Read(region, "GetVertexColor")
    local alpha = Read(region, "GetAlpha")
    if alpha then state.alpha = alpha[1] end
    return state
end

local function RestoreDynamic(region, state)
    if state.hasTexture then region:SetTexture(state.texture) end
    if state.color then region:SetVertexColor(unpack(state.color)) end
    if state.alpha ~= nil then region:SetAlpha(state.alpha) end
end

local function Snapshot(region, layoutOnly)
    local state = { points = {}, masks = {} }
    local count = Read(region, "GetNumPoints")
    if count then
        for i = 1, count[1] do
            local point = Read(region, "GetPoint", i)
            if point then state.points[#state.points + 1] = point end
        end
    end
    state.size, state.layer, state.coords = Read(region, "GetSize"), Read(region, "GetDrawLayer"), Read(region, "GetTexCoord")
    if not layoutOnly then
        local texture, atlas, blend, alpha = Read(region, "GetTexture"), Read(region, "GetAtlas"), Read(region, "GetBlendMode"), Read(region, "GetAlpha")
        if texture then state.restoreTexture = true; state.texture = texture[1] end
        if atlas then state.atlas = atlas[1] end
        if blend then state.blend = blend[1] end
        if alpha then state.alpha = alpha[1] end
        state.color = Read(region, "GetVertexColor")
        state.rotation = Read(region, "GetRotation")
        state.desaturated = Read(region, "IsDesaturated")
    end
    count = Read(region, "GetNumMaskTextures")
    if count then
        for i = 1, count[1] do
            local mask = Read(region, "GetMaskTexture", i)
            if mask then state.masks[#state.masks + 1] = mask[1] end
        end
    end
    return state
end

local function ClearMasks(region)
    local count = Read(region, "GetNumMaskTextures")
    if count and region.RemoveMaskTexture then
        for i = count[1], 1, -1 do
            local mask = Read(region, "GetMaskTexture", i)
            if mask and mask[1] then region:RemoveMaskTexture(mask[1]) end
        end
        -- Masque 的 Action 默认外观会保留区域遮罩缓存；移除实际遮罩后同步失效，
        -- 否则下次换肤会跳过挂载。保留 _MSQ_Mask 对象供后续复用。
        region._MSQ_ButtonMask, region._MSQ_RegionMask = nil, nil
    end
end

local function Restore(region, state)
    ClearMasks(region)
    for _, mask in ipairs(state.masks) do region:AddMaskTexture(mask) end
    if state.atlas then region:SetAtlas(state.atlas)
    elseif state.restoreTexture then region:SetTexture(state.texture) end
    if state.coords then region:SetTexCoord(unpack(state.coords)) end
    if state.rotation and region.SetRotation then region:SetRotation(unpack(state.rotation)) end
    if state.desaturated and region.SetDesaturated then region:SetDesaturated(unpack(state.desaturated)) end
    if state.color then region:SetVertexColor(unpack(state.color)) end
    if state.blend then region:SetBlendMode(state.blend) end
    if state.layer then region:SetDrawLayer(unpack(state.layer)) end
    if state.size then region:SetSize(unpack(state.size)) end
    if region.ClearAllPoints then
        region:ClearAllPoints()
        for _, point in ipairs(state.points) do region:SetPoint(unpack(point)) end
    end
    if state.alpha ~= nil then region:SetAlpha(state.alpha) end
    if state.shown ~= nil then region:SetShown(state.shown) end
end

local function HideDecorations(binding)
    if binding.host then binding.host:Hide() end
    for region in pairs(binding.ownedRegions or {}) do region:Hide() end
end

-- 旧客户端的冷却 hook 只在相应绘制分支开启时清空；临时打开后卸载，再恢复业务开关。
local function PrepareCooldowns(binding)
    local flags = {}
    for _, cooldown in ipairs(binding.cooldowns or {}) do
        local swipe, edge = Read(cooldown, "GetDrawSwipe"), Read(cooldown, "GetDrawEdge")
        if swipe and edge then
            local bling = Read(cooldown, "GetDrawBling")
            flags[cooldown] = { swipe[1], edge[1], bling and bling[1] }
            cooldown:SetDrawSwipe(true)
            cooldown:SetDrawEdge(true)
        end
    end
    return flags
end

local function RestoreCooldownFlags(flags)
    for cooldown, values in pairs(flags) do
        cooldown:SetDrawSwipe(values[1]); cooldown:SetDrawEdge(values[2])
        if values[3] ~= nil then cooldown:SetDrawBling(values[3]) end
    end
end

local function RemoveButton(binding)
    local flags = PrepareCooldowns(binding)
    local ok, problem = pcall(binding.group.RemoveButton, binding.group, binding.host)
    -- Disabled 组的 RemoveButton 不再重绘；清掉 12.1.7 旧客户端残留的材质 hook 输入。
    for _, cooldown in ipairs(binding.cooldowns or {}) do
        cooldown._MSQ_Color, cooldown._MSQ_Edge = nil, nil
    end
    RestoreCooldownFlags(flags)
    if not ok then Skins.lastError = problem end
    return flags
end

local function RestoreCooldowns(binding)
    for _, cooldown in ipairs(binding.cooldowns or {}) do
        if binding.spec.style then GUI2:ApplyCooldownChrome(cooldown, binding.spec.style, {}) end
    end
end

local ANIMATION_FIELDS = { "Duration", "FlipBookRows", "FlipBookColumns", "FlipBookFrames", "FlipBookFrameWidth", "FlipBookFrameHeight" }
local function SaveEffect(binding, effect)
    if not effect or binding.saved[effect] then return end
    binding.saved[effect] = Snapshot(effect)
    local regions = { effect.ProcStartFlipbook, effect.ProcLoopFlipbook, effect.ProcAltGlow, effect.Flipbook }
    for _, region in pairs(regions) do binding.saved[region] = Snapshot(region) end
    local animationGroups = { effect.ProcStartAnim, effect.ProcLoopAnim, effect.ProcLoop, effect.Flipbook and effect.Flipbook.Anim }
    for _, group in pairs(animationGroups) do
        if group.GetAnimations then
            for _, animation in ipairs({ group:GetAnimations() }) do
                local saved = {}
                for _, field in ipairs(ANIMATION_FIELDS) do
                    if animation["Get" .. field] and animation["Set" .. field] then saved[field] = animation["Get" .. field](animation) end
                end
                binding.animations[animation] = saved
            end
        end
    end
end

local function ResetEffectTransform(texture)
    if not texture then return end
    if texture.SetRotation then texture:SetRotation(0) end
    if texture.SetDesaturated then texture:SetDesaturated(false) end
    if texture.SetVertexColor then texture:SetVertexColor(1, 1, 1, 1) end
end

-- 冷配置快照。轮廓由 Masque 提供，动画实例和触发状态由调用方持有。
-- Style=None 表示不替换暴雪材质；显式选择皮肤发光时使用 Modern，
-- 不改写 Masque 的全局设置，也不共享它按按钮缓存的动画更新标记。
local function ResolveProcRecipe(binding)
    local masque = Skins:GetMasque()
    local cfg = binding.host and binding.host._MSQ_CFG
    if not (binding.active and cfg and masque and masque.GetSpellAlertFlipBook) then return nil end
    local style = type(cfg.SpellAlertStyle) == "string" and cfg.SpellAlertStyle or "Modern"
    local data = masque:GetSpellAlertFlipBook(style, cfg.Shape or "Square")
    if not (data and data.LoopTexture) then return nil end
    local skin = cfg.Skin and cfg.Skin.SpellAlert
    skin = skin and (skin[style] or skin)
    local width, height = binding.spec.width, binding.spec.height
    if skin and cfg.GetScaleSize then width, height = cfg:GetScaleSize(skin.Width, skin.Height) end
    return { texture = data.LoopTexture, startTexture = data.StartTexture,
        rows = data.Rows or 6, columns = data.Columns or 5, frames = data.Frames or 30,
        frameWidth = data.FrameWidth or 0, frameHeight = data.FrameHeight or 0,
        width = width * 1.4, height = height * 1.4, style = style }
end

function GUI2:GetIconSkinProcRecipe(owner)
    local binding = bindings[owner]
    return binding and binding.active and binding.procRecipe or nil
end

local function ApplyFlipbook(group, texture, path, recipe)
    if not (group and texture and group.GetAnimations) then return end
    texture:SetTexture(path)
    texture:ClearAllPoints()
    texture:SetAllPoints()
    for _, animation in ipairs({ group:GetAnimations() }) do
        if animation.SetFlipBookRows then
            animation:SetFlipBookRows(recipe.rows)
            animation:SetFlipBookColumns(recipe.columns)
            animation:SetFlipBookFrames(recipe.frames)
            animation:SetFlipBookFrameWidth(recipe.frameWidth)
            animation:SetFlipBookFrameHeight(recipe.frameHeight)
        end
    end
end

local function ApplyProcRecipe(frame, recipe)
    if not (recipe and frame.ProcLoopFlipbook) then return false end
    if frame.gui2IconSkinProcRecipe == recipe then return true end
    ApplyFlipbook(frame.ProcLoopAnim or frame.ProcLoop, frame.ProcLoopFlipbook, recipe.texture, recipe)
    ApplyFlipbook(frame.ProcStartAnim, frame.ProcStartFlipbook, recipe.startTexture or recipe.texture, recipe)
    frame:SetSize(recipe.width, recipe.height)
    frame._Loop_Only = not recipe.startTexture or nil
    frame.gui2IconSkinProcRecipe = recipe
    return true
end

-- 自定义发光只复用材质；它不注册为 host.SpellActivationAlert。
-- 可在受限后代初始化阶段调用，后续显示/隐藏仍由原有门控负责。
function GUI2:ConfigureIconSkinGlow(glow, width, height)
    local frame = glow.gui2MasqueProcGlow
    if not frame then
        frame = self:CreateManagedProcGlow(glow, "square", width, height,
            glow.gui2GlowFrameLevel or (glow.gui2RestrictedParent and 0 or nil), glow.gui2GlowFrameStrata)
        glow.gui2MasqueProcGlow = frame
    end
    if not frame then return nil end
    frame.gui2ProcRestricted = glow.gui2RestrictedParent == true
    local recipe = glow.gui2GlowSkinRecipe
    if frame.gui2IconSkinProcRecipe ~= recipe then
        self:SetManagedProcGlowShown(frame, false)
        frame.gui2IconSkinProcRecipe = nil
        if not recipe then
            -- 恢复创建时的材质，不能让卸载皮肤后残留上一次的轮廓。
            for region, state in pairs(frame.gui2MasqueBaseline or {}) do Restore(region, state) end
            for animation, state in pairs(frame.gui2MasqueAnimations or {}) do
                for field, value in pairs(state) do animation["Set" .. field](animation, value) end
            end
        end
    end
    if not frame.gui2MasqueBaseline then
        local saved = { saved = {}, animations = {} }
        SaveEffect(saved, frame)
        frame.gui2MasqueBaseline, frame.gui2MasqueAnimations = saved.saved, saved.animations
    end
    frame._Loop_Only = true
    if not ApplyProcRecipe(frame, recipe) then
        self:LayoutManagedProcGlow(frame, glow, width, height,
            glow.gui2GlowFrameLevel or (glow.gui2RestrictedParent and 0 or nil), glow.gui2GlowFrameStrata)
    end
    -- 持续条件使用循环段；颜色与透明度可调，几何和节奏跟随皮肤。
    frame._Loop_Only = true
    local r, g, b = glow.gui2GlowResolvedR or 1, glow.gui2GlowResolvedG or 1, glow.gui2GlowResolvedB or 1
    local alpha = glow.gui2GlowResolvedAlpha or 1
    for _, texture in pairs({ frame.ProcStartFlipbook, frame.ProcLoopFlipbook, frame.gui2ProcBorder, frame.gui2ProcSoft }) do
        if texture.SetDesaturated then texture:SetDesaturated(true) end
        texture:SetVertexColor(r, g, b, alpha)
    end
    return frame
end

local function Drain()
    if InCombat() then return end
    if YUI.Event then YUI.Event:OffOwner(eventOwner) end
    for owner, operation in pairs(pending) do
        pending[owner] = nil
        local binding = bindings[owner]
        if operation == "release" then GUI2:ReleaseIconSkin(owner)
        elseif binding then
            local refresh = binding.deferredRefresh or (binding.spec and binding.spec.refresh)
            binding.deferredRefresh = nil
            if refresh then refresh(owner) end
        end
    end
    for owner, binding in pairs(bindings) do
        if binding.waiting and binding.spec and binding.spec.refresh and Skins:GetMasque() then
            binding.waiting = nil
            binding.spec.refresh(owner)
        end
    end
    Skins:SyncEvents()
end

function Skins:SyncEvents()
    if not YUI.Event then return end
    YUI.Event:OffOwner(eventOwner)
    if next(pending) then YUI.Event:On("PLAYER_REGEN_ENABLED", Drain, eventOwner) end
    for _, binding in pairs(bindings) do
        if binding.waiting then YUI.Event:On("ADDON_LOADED", Drain, eventOwner); break end
    end
end

local function RefreshGroup(group, host)
    if type(host) ~= "table" then host = nil end
    for owner, binding in pairs(bindings) do
        if binding.group == group and (not host or binding.host == host)
            and binding.spec and binding.spec.refresh and not binding.refreshing and not binding.attaching
            and pending[owner] ~= "release" then
            if InCombat() then pending[owner] = "refresh"
            else
                binding.refreshing = true
                Skins.stats.refreshes = Skins.stats.refreshes + 1
                binding.spec.refresh(owner)
                binding.refreshing = nil
            end
        end
    end
    Skins:SyncEvents()
    groupDB[group] = group.db
end

local function GroupCallback(group, option, value)
    -- ReSkin 的后置回调已处理这些选项，避免同一次设置重复卸载/注册。
    if hookedGroups[group] and (option == "SkinID" or option == "Scale" or option == "Reset"
        or option == "UseScale" or option == "Disabled" and value == false) then return end
    RefreshGroup(group)
end

function Skins:FindGroup(product, id)
    return groups[product .. ":" .. tostring(id)]
end

function Skins:GetGroup(product, id, label)
    local masque = self:GetMasque()
    if not masque then return nil end
    local key = product .. ":" .. tostring(id)
    local name = type(label) == "string" and label ~= "" and label or tostring(id)
    local group = groups[key]
    if not group then
        group = masque:Group(product, name, tostring(id))
        group:RegisterCallback(GroupCallback)
        if hooksecurefunc and group.ReSkin then
            hooksecurefunc(group, "ReSkin", RefreshGroup)
            hookedGroups[group] = true
            -- 12.1.7 的 profile 切换（特别是 Disabled）不发公共组回调。
            -- 仅监听这一兼容入口，不替换方法或写入其数据库。
            if group.__Update then
                hooksecurefunc(group, "__Update", function(current)
                    if groupDB[current] ~= current.db then RefreshGroup(current) end
                end)
            end
            if group.__SetColor then hooksecurefunc(group, "__SetColor", RefreshGroup) end
        end
        groupDB[group] = group.db
        groups[key] = group
    end
    -- 显示名可以翻译或改名；StaticID 和已保存的皮肤配置始终保持不变。
    if groupLabels[key] ~= name then
        if group.SetName then group:SetName(name) end
        groupLabels[key] = name
    end
    return group
end

function GUI2:ClaimIconSkin(owner)
    if claims[owner] then return true end
    if InCombat() then return false end
    claims[owner] = true
    if Skins.onClaim then Skins.onClaim(owner) end
    return true
end

function GUI2:IsIconSkinManaged(region)
    return owners[region] ~= nil
end

function GUI2:RefreshIconSkinRegion(owner, key, region)
    local binding = bindings[owner]
    if not (binding and binding.active and binding.spec and binding.spec.refresh)
        or binding.spec.regions[key] == region then return end
    if InCombat() then self:DeferIconSkin(owner, binding.spec.refresh)
    else binding.spec.refresh(owner) end
end

local function CaptureSwipeTexture(cooldown, texture)
    if not (issecretvalue and issecretvalue(texture)) and type(texture) == "string" then
        swipeTextures[cooldown] = texture
    end
end

function GUI2:GetIconSkinSwipeAlpha(cooldown)
    local binding = owners[cooldown]
    if binding and binding.group.GetColor then return select(4, binding.group:GetColor("Cooldown")) end
end

-- 原生 sink 直接消费透明度（可能是 secret），不比较、不计算、不缓存。
-- SetSwipeTexture 保留皮肤材质，避免旧客户端的 SetSwipeColor hook 把业务透明度重置。
function GUI2:ApplyIconSkinSwipeAlpha(cooldown, alpha)
    local binding = owners[cooldown]
    local texture = binding and swipeTextures[cooldown]
    if not (texture and binding.group.GetColor) then return false end
    local r, g, b = binding.group:GetColor("Cooldown")
    cooldown:SetSwipeTexture(texture, r, g, b, alpha)
    return true
end

function GUI2:DeferIconSkin(owner, refresh)
    local binding = bindings[owner]
    if not binding then binding = {}; bindings[owner] = binding end
    binding.deferredRefresh = refresh
    pending[owner] = "refresh"
    Skins:SyncEvents()
end

-- 先恢复本插件的冷配置基线，再由调用方重建；不能把 Masque 的默认皮肤当作原样恢复。
function GUI2:BeginIconSkin(owner)
    local binding = bindings[owner]
    if not binding or not binding.registered then return true end
    if InCombat() and not (binding.spec and binding.spec.preview) then pending[owner] = "refresh"; Skins:SyncEvents(); return false end
    local live = {}
    for region in pairs(binding.dynamic or {}) do live[region] = DynamicState(region) end
    local flags = RemoveButton(binding)
    binding.registered, binding.active = nil, nil
    binding.procRecipe = nil
    for region, state in pairs(binding.saved) do
        owners[region] = nil
        Restore(region, state)
    end
    for animation, state in pairs(binding.animations or {}) do
        for field, value in pairs(state) do animation["Set" .. field](animation, value) end
    end
    for region, state in pairs(live) do RestoreDynamic(region, state) end
    RestoreCooldowns(binding)
    RestoreCooldownFlags(flags)
    if binding.proc then
        binding.proc.gui2IconSkinHost = nil
        binding.proc.gui2IconSkinBinding = nil
        binding.proc.gui2IconSkinProcRecipe = nil
        binding.proc._No_Start, binding.proc._Loop_Only = nil, nil
    end
    if binding.assisted then binding.assisted.gui2IconSkinHost = nil end
    binding.proc, binding.assisted = nil, nil
    binding.host.SpellActivationAlert, binding.host.AssistedCombatHighlightFrame, binding.host.AutoCastOverlay = nil, nil, nil
    HideDecorations(binding)
    return true
end

-- regions 是显式 Region Map。代理 Frame 不接收安全点击，也不向原生按钮写注册字段。
function GUI2:ApplyIconSkin(owner, spec)
    if not owner then return false end
    if not self:ClaimIconSkin(owner) then
        self:DeferIconSkin(owner, spec.refresh)
        return false
    end
    local binding = bindings[owner]
    if not binding and spec.id ~= "masque" then return false end
    if binding and binding.registered and not self:BeginIconSkin(owner) then return binding.active == true end
    if not binding then binding = {}; bindings[owner] = binding end
    binding.spec, binding.waiting = spec, nil
    if spec.id ~= "masque" then binding.group = nil; pending[owner] = nil; Skins:SyncEvents(); return false end
    if InCombat() then pending[owner] = "refresh"; Skins:SyncEvents(); return binding.active == true end
    local group = spec.preview and Skins:FindGroup(spec.product, spec.groupId)
        or (not spec.preview and Skins:GetGroup(spec.product, spec.groupId, spec.groupLabel))
    if not group then
        if not spec.preview then binding.waiting = true; Skins:SyncEvents() end
        return false
    end
    binding.group = group
    if not binding.host then
        binding.host = self:CreateFrame(spec.parent or owner, { mouse = false })
        binding.normal = self:CreateTexture(binding.host, { layer = "OVERLAY" })
    end
    local host = binding.host
    host:ClearAllPoints()
    host:SetPoint("CENTER", spec.anchor or owner, "CENTER", 0, 0)
    host:SetSize(spec.width, spec.height)
    host:SetFrameLevel((spec.parent or owner):GetFrameLevel())
    local regions = spec.regions
    regions.Normal = binding.normal
    binding.saved, binding.cooldowns, binding.animations, binding.dynamic = {}, {}, {}, {}
    for key, region in pairs(regions) do
        if region and region ~= binding.normal then
            if self.RestoreIconCooldownLayout then self:RestoreIconCooldownLayout(region) end
            binding.saved[region] = Snapshot(region, DYNAMIC_LAYERS[key])
            if key == "Backdrop" then
                local shown = Read(region, "IsShown")
                if shown then binding.saved[region].shown = shown[1] end
            end
            if DYNAMIC_LAYERS[key] then binding.dynamic[region] = true end
            if key == "Cooldown" or key == "ChargeCooldown" or key == "CooldownLoC" then
                binding.cooldowns[#binding.cooldowns + 1] = region
                if hooksecurefunc and region.SetSwipeTexture and not swipeHooks[region] then
                    hooksecurefunc(region, "SetSwipeTexture", CaptureSwipeTexture)
                    swipeHooks[region] = true
                end
            end
            ClearMasks(region)
        end
    end
    host.AutoCastOverlay = spec.autoCast
    for _, region in ipairs(spec.extraRegions or {}) do binding.saved[region] = Snapshot(region) end
    local live = {}
    for region in pairs(binding.dynamic) do live[region] = DynamicState(region) end
    local flags = PrepareCooldowns(binding)
    binding.attaching = true
    local ok, problem = pcall(function()
        group:AddButton(host, regions, spec.buttonType or "Action", true)
        -- 显式提供公开配置尺寸，兼容受限父级导致 GetSize 返回 secret 的情形。
        if group.SetFrameSize then group:SetFrameSize(spec.width, spec.height, host) end
    end)
    binding.attaching = nil
    RestoreCooldownFlags(flags)
    if not ok then
        Skins.lastError = problem
        RemoveButton(binding)
        for region, state in pairs(binding.saved) do Restore(region, state) end
        for region, state in pairs(live) do RestoreDynamic(region, state) end
        RestoreCooldowns(binding)
        RestoreCooldownFlags(flags)
        HideDecorations(binding)
        if spec.afterApply then spec.afterApply(owner) end
        return false
    end
    binding.registered = true
    -- 仅在适配器读取当前注册状态；不向 Masque 的内部配置写值。
    binding.active = host._MSQ_CFG and host._MSQ_CFG.Enabled == true or false
    if not binding.active then
        for region, state in pairs(binding.saved) do Restore(region, state) end
        for region, state in pairs(live) do RestoreDynamic(region, state) end
        RestoreCooldowns(binding)
        RestoreCooldownFlags(flags)
        HideDecorations(binding)
        if spec.afterApply then spec.afterApply(owner) end
        return false
    end
    for region in pairs(binding.saved) do owners[region] = binding end
    binding.shape = host._MSQ_CFG.Shape == "Circle" and "circle" or "square"
    binding.procRecipe = ResolveProcRecipe(binding)
    -- Masque 的 Backdrop/Shadow/Gloss 是它自己创建的纹理，不是 Region Map 的输入。
    -- 将这些自有纹理放到图标所在父框体，才能遵守同一绘制层顺序；不移动原生区域。
    local masque = Skins:GetMasque()
    local parent = regions.Icon and Read(regions.Icon, "GetParent")
    parent = parent and parent[1] or spec.parent or owner
    binding.ownedRegions, binding.decorations = binding.ownedRegions or {}, {}
    binding.ownedRegions[binding.normal] = true
    for _, method in ipairs({ "GetNormal", "GetBackdrop", "GetShadow", "GetGloss" }) do
        if masque[method] then
            local okRegion, region = pcall(masque[method], masque, host)
            if okRegion and region then
                binding.ownedRegions[region] = true
                if region.SetParent then region:SetParent(parent) end
                binding.decorations[region] = region:IsShown()
            end
        end
    end
    host:Show()
    binding.visible = nil
    self:SetIconSkinVisible(owner, spec.visible ~= false)
    if spec.hideBuiltin then spec.hideBuiltin(owner) end
    self:AdoptIconSkinEffects(owner, spec.proc, spec.assisted)
    if spec.afterApply then spec.afterApply(owner) end
    Skins.stats.attaches = Skins.stats.attaches + 1
    return true
end

function GUI2:SetIconSkinVisible(owner, shown)
    local binding = bindings[owner]
    if not (binding and binding.active) or binding.visible == shown then return end
    binding.visible = shown
    binding.host:SetShown(shown)
    for region, visible in pairs(binding.decorations or {}) do region:SetShown(shown and visible) end
end

function GUI2:AdoptIconSkinEffects(owner, proc, assisted)
    local binding = bindings[owner]
    if not (binding and binding.active) then return false end
    if (not proc or proc == binding.proc) and (not assisted or assisted == binding.assisted) then return true end
    local masque, host = Skins:GetMasque(), binding.host
    if proc and proc ~= binding.proc and masque.UpdateSpellAlert then
        SaveEffect(binding, proc)
        ResetEffectTransform(proc.ProcStartFlipbook)
        ResetEffectTransform(proc.ProcLoopFlipbook)
        binding.proc, host.SpellActivationAlert = proc, proc
        proc.gui2IconSkinHost = host
        proc.gui2IconSkinBinding = binding
        masque:UpdateSpellAlert(host, proc)
        -- UpdateSpellAlert 同时读取当前全局样式；None 仍使用匹配轮廓的 Modern。
        binding.procRecipe = ResolveProcRecipe(binding)
        ApplyProcRecipe(proc, binding.procRecipe)
        if proc.gui2ProcPlaying and proc.ProcLoopFlipbook then proc.ProcLoopFlipbook:SetAlpha(1) end
    end
    if assisted and assisted ~= binding.assisted and masque.UpdateAssistedCombatHighlight then
        SaveEffect(binding, assisted)
        ResetEffectTransform(assisted.Flipbook)
        binding.assisted, host.AssistedCombatHighlightFrame = assisted, assisted
        assisted.gui2IconSkinHost = host
        masque:UpdateAssistedCombatHighlight(host)
    end
    return true
end

-- 只在新的激活提示开始时同步动画设置，不在逐帧或持续显示路径查询皮肤。
function GUI2:RefreshIconSkinProc(frame)
    local host = frame and frame.gui2IconSkinHost
    local masque = host and Skins:GetMasque()
    if masque and masque.UpdateSpellAlert then
        masque:UpdateSpellAlert(host, frame)
        local binding = owners[frame]
        -- 效果不是 Region Map 的必填项，延迟创建的提示同样可定位到绑定。
        binding = binding or frame.gui2IconSkinBinding
        if binding then
            local style = host._MSQ_CFG and host._MSQ_CFG.SpellAlertStyle
            style = type(style) == "string" and style or "Modern"
            if not binding.procRecipe or binding.procRecipe.style ~= style then
                binding.procRecipe = ResolveProcRecipe(binding)
            end
            ApplyProcRecipe(frame, binding.procRecipe)
        end
    end
end

function GUI2:GetIconSkinEffectShape(owner, fallback)
    local binding = bindings[owner]
    return binding and binding.active and binding.shape or fallback
end

function GUI2:ReleaseIconSkin(owner)
    local binding = bindings[owner]
    if InCombat() and claims[owner] and not (binding and binding.spec and binding.spec.preview) then
        pending[owner] = "release"; Skins:SyncEvents(); return false
    end
    if not self:BeginIconSkin(owner) then pending[owner] = "release"; return false end
    if binding then
        binding.spec, binding.group, binding.waiting = nil, nil, nil
        binding.deferredRefresh = nil
        binding.saved, binding.cooldowns = nil, nil
        binding.dynamic, binding.animations, binding.proc, binding.assisted = nil, nil, nil, nil
    end
    pending[owner] = nil
    if claims[owner] then
        claims[owner] = nil
        if Skins.onRelease then Skins.onRelease(owner) end
    end
    Skins.stats.releases = Skins.stats.releases + 1
    Skins:SyncEvents()
    return true
end
