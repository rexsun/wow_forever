-- Talents Forever: the bridge to the game. Reads what the character really has through C_Traits (the beta's talent API),
-- counts unspent points, and, only when asked by a click, buys a rank. Everything is guarded: a function the client lacks
-- turns into a note in the log, never an error box.
local _, TF = ...
local D = TalentsForeverBookData
local G = {}
TF.Game = G
G.live = nil     -- { cls, configID, treeID, nodes = { [nodeID] = {rank, max, entry, spell} }, bySpell = {}, byNode = {} }
G.legacy = nil   -- { ranks = { {..}, {..}, {..} }, talented = n }
G.points = nil   -- { unspent, spent, max, source }

local Try = TF.Try

local function rankOf(n)
  return n.activeRank or n.ranksPurchased or n.currentRank or 0
end

function G.Available() return C_Traits ~= nil and C_Traits.GetTreeNodes ~= nil end

-- the config that holds a tree: the active class config first, then the tree's own, then a scan of the system ids
function G.ConfigFor(treeID)
  local function holds(cfg)
    if not cfg or cfg <= 0 then return false end
    local info = Try("GetConfigInfo", C_Traits.GetConfigInfo, cfg)
    if not info then return false end
    for _, t in ipairs(info.treeIDs or {}) do if t == treeID then return true end end
    return false
  end
  if C_ClassTalents and C_ClassTalents.GetActiveConfigID then
    local cfg = Try("GetActiveConfigID", C_ClassTalents.GetActiveConfigID)
    if holds(cfg) then return cfg end
  end
  if C_Traits.GetConfigIDByTreeID then
    local cfg = Try("GetConfigIDByTreeID", C_Traits.GetConfigIDByTreeID, treeID)
    if holds(cfg) then return cfg end
  end
  if C_Traits.GetConfigIDBySystemID then
    for sys = 1, 40 do local cfg = Try("GetConfigIDBySystemID", C_Traits.GetConfigIDBySystemID, sys); if holds(cfg) then return cfg end end
  end
  return nil
end

local function readTree(cfg, treeID)
  local nodes, byNode, bySpell = {}, {}, {}
  local ids = Try("GetTreeNodes", C_Traits.GetTreeNodes, treeID) or {}
  for _, nodeID in ipairs(ids) do
    local n = Try("GetNodeInfo", C_Traits.GetNodeInfo, cfg, nodeID)
    if n then
      local entry = n.activeEntry and n.activeEntry.entryID or (n.entryIDs and n.entryIDs[1])
      local spell
      if entry then
        local e = Try("GetEntryInfo", C_Traits.GetEntryInfo, cfg, entry)
        local d = e and e.definitionID and Try("GetDefinitionInfo", C_Traits.GetDefinitionInfo, e.definitionID)
        spell = d and (d.spellID or d.overriddenSpellID)
      end
      local rec = { id = nodeID, rank = rankOf(n), max = n.maxRanks or 0, entry = entry, spell = spell, visible = n.isVisible, available = n.isAvailable, x = n.posX, y = n.posY,
                    canBuy = n.canPurchaseRank, canRefund = n.canRefundRank }
      nodes[#nodes + 1] = rec; byNode[nodeID] = rec
      if spell then bySpell[spell] = rec end
    end
  end
  return nodes, byNode, bySpell
end

-- points: the tree's currency when the client tells us, else the level rule
local function readPoints(cfg, treeID, cls)
  local c = D.classes[cls]
  if C_Traits.GetTreeCurrencyInfo then
    local cur = Try("GetTreeCurrencyInfo", C_Traits.GetTreeCurrencyInfo, cfg, treeID, false)
    local cinfo = cur and cur[1]
    if cinfo and (cinfo.quantity or cinfo.spent) then
      return { unspent = cinfo.quantity or 0, spent = cinfo.spent or 0, max = cinfo.maxQuantity or 51, source = "currency" }
    end
  end
  local spent = 0
  if G.live then for _, n in ipairs(G.live.nodes) do spent = spent + n.rank end end
  local pool = math.min(51, math.max(0, UnitLevel("player") - 9 + (G.legacy and G.legacy.talented or 0)))
  return { unspent = math.max(0, pool - spent), spent = spent, max = 51, source = "level" }
end

function G.Refresh()
  if not G.Available() then G.live = nil; return false end
  local cls = TF.PlayerClass()
  local c = D.classes[cls]
  if not c then G.live = nil; return false end
  local cfg = G.ConfigFor(c.tree)
  if not cfg then TF.Log("no config holds tree %d", c.tree); G.live = nil; return false end
  local nodes, byNode, bySpell = readTree(cfg, c.tree)
  G.live = { cls = cls, configID = cfg, treeID = c.tree, nodes = nodes, byNode = byNode, bySpell = bySpell, when = GetTime() }
  G.RefreshLegacy()
  G.points = readPoints(cfg, c.tree, cls)
  return true
end

-- the three Legacy trees, matched to the site's perks by spell id. Gives us the real Talented rank.
function G.RefreshLegacy()
  if not G.Available() or not D.legacy then return end
  local out = { ranks = {}, talented = 0, found = false }
  for li, tree in ipairs(D.legacy.trees) do
    out.ranks[li] = {}
    for i in ipairs(tree.perks) do out.ranks[li][i] = 0 end
    local cfg = G.ConfigFor(tree.id)
    if cfg then
      local _, _, bySpell = readTree(cfg, tree.id)
      for i, perk in ipairs(tree.perks) do
        local rec = perk.spell and bySpell[perk.spell]
        if rec then out.ranks[li][i] = rec.rank; out.found = true end
        if perk.name == "Talented" and rec then out.talented = rec.rank end
      end
    end
  end
  if out.found then G.legacy = out; TF.CharDB().talented = out.talented end
end

-- the game's record for a talent of the plan's class (node id first, spell id second)
function G.Node(ti, i, cls)
  local live = G.live; if not live then return nil end
  local c = D.classes[cls or live.cls]; if not c or (cls and cls ~= live.cls) then return nil end
  local t = c.trees[ti].talents[i]
  return (t.node and live.byNode[t.node]) or (t.spell and live.bySpell[t.spell]) or nil
end
function G.Rank(ti, i) local n = G.Node(ti, i); return n and n.rank or nil end
function G.Unspent() return G.points and G.points.unspent or 0 end
function G.CanApply() return G.live ~= nil and C_Traits.PurchaseRank ~= nil end

-- commit staged changes: the game's own window calls C_Traits.CommitConfig and then casts for a few seconds
function G.Commit()
  if not G.live then return false, "no config" end
  local cfg = G.live.configID
  local staged = true
  if C_Traits.ConfigHasStagedChanges then local ok, s = pcall(C_Traits.ConfigHasStagedChanges, cfg); if ok then staged = s and true or false end end
  if not staged then return true, "nothing staged" end
  local commit = C_Traits.CommitConfig or (C_ClassTalents and C_ClassTalents.CommitConfig)
  if not commit then return false, "no commit function" end
  local ok, res = pcall(commit, cfg)
  local diag = TF.db.diag; diag.applies = diag.applies or {}
  table.insert(diag.applies, { when = date("%H:%M:%S"), commit = true, result = tostring(ok and res or ("err " .. tostring(res))) })
  if not ok then return false, "The game refused the commit: " .. tostring(res) end
  if res == false then return false, "The game did not accept the changes." end
  G.committing = GetTime()
  C_Timer.After(1.5, function() G.Refresh(); TF.Fire("GAME_CHANGED", "commit") end)
  C_Timer.After(5, function() G.committing = nil; G.Refresh(); TF.Fire("GAME_CHANGED", "commit2") end)
  return true
end
function G.IsCommitting() return G.committing ~= nil and (GetTime() - G.committing) < 8 end

-- buy one rank of a talent. Only ever called from a click. Returns ok, message. With noCommit the change stays staged.
function G.Learn(ti, i, noCommit)
  if not G.live then return false, "The game has not answered about your talents yet." end
  if not C_Traits.PurchaseRank then return false, "This client gives addons no way to place talent points. Place it in the talent window: the plan shows you where." end
  if InCombatLockdown and InCombatLockdown() then return false, "Not in combat." end
  local t = D.classes[G.live.cls].trees[ti].talents[i]
  local n = G.Node(ti, i)
  if not n then return false, "The game does not list " .. t.name .. "." end
  if n.rank >= n.max then return false, t.name .. " is already at max rank." end
  if G.Unspent() <= 0 then return false, "No unspent talent points." end
  if G.IsCommitting() then return false, "The last change is still being applied. A moment." end
  local cfg = G.live.configID
  local diag = TF.db.diag; diag.applies = diag.applies or {}
  local rec = { when = date("%H:%M:%S"), talent = t.name, node = n.id, entry = n.entry, steps = {} }
  table.insert(diag.applies, rec); if #diag.applies > 30 then table.remove(diag.applies, 1) end
  if C_Traits.CanPurchaseRank and n.entry then
    local ok, can = pcall(C_Traits.CanPurchaseRank, cfg, n.id, n.entry)
    rec.steps[#rec.steps + 1] = "CanPurchaseRank " .. tostring(ok and can or ("err " .. tostring(can)))
    if ok and can == false then return false, "The game says " .. t.name .. " cannot take a point right now (its row or the talent it needs is not ready)." end
  end
  local ok, res = pcall(C_Traits.PurchaseRank, cfg, n.id)
  rec.steps[#rec.steps + 1] = "PurchaseRank " .. tostring(ok and res or ("err " .. tostring(res)))
  if not ok then return false, "The game refused: " .. tostring(res) end
  if res == false then return false, "The game did not take the point for " .. t.name .. "." end
  -- the purchase is staged; the window's Apply is C_Traits.CommitConfig, which casts for a few seconds
  G.Refresh()
  if noCommit then return true, t.name end
  local okC, msgC = G.Commit()
  rec.steps[#rec.steps + 1] = "commit " .. tostring(okC) .. " " .. tostring(msgC)
  if not okC then return false, "Placed but not applied: " .. tostring(msgC) end
  return true, t.name
end

-- give one rank back, when the client says the node can be refunded. Only ever from a click. Returns ok, message.
function G.CanRefund() return G.live ~= nil and C_Traits.RefundRank ~= nil end
function G.Refund(ti, i)
  if not G.live then return false, "The game has not answered about your talents yet." end
  if not C_Traits.RefundRank then return false, "This client gives addons no way to take a point back." end
  if InCombatLockdown and InCombatLockdown() then return false, "Not in combat." end
  local t = D.classes[G.live.cls].trees[ti].talents[i]
  local n = G.Node(ti, i)
  if not n then return false, "The game does not list " .. t.name .. "." end
  if n.rank <= 0 then return false, t.name .. " has no points to give back." end
  if n.canRefund == false then return false, t.name .. " cannot be refunded here. Talents come back at the trainer." end
  local cfg = G.live.configID
  local diag = TF.db.diag; diag.applies = diag.applies or {}
  local rec = { when = date("%H:%M:%S"), talent = t.name, node = n.id, refund = true, steps = {} }
  table.insert(diag.applies, rec); if #diag.applies > 30 then table.remove(diag.applies, 1) end
  local ok, res = pcall(C_Traits.RefundRank, cfg, n.id)
  rec.steps[#rec.steps + 1] = "RefundRank " .. tostring(ok and res or ("err " .. tostring(res)))
  if not ok then return false, "The game refused: " .. tostring(res) end
  if res == false then return false, "The game did not give the point back for " .. t.name .. "." end
  local staged = false
  if C_Traits.ConfigHasStagedChanges then local ok2, s2 = pcall(C_Traits.ConfigHasStagedChanges, cfg); staged = ok2 and s2 or false; rec.steps[#rec.steps + 1] = "staged " .. tostring(s2) end
  if staged then
    local commit = (C_ClassTalents and C_ClassTalents.CommitConfig) or C_Traits.CommitConfig
    if commit then local ok3, r3 = pcall(commit, cfg); rec.steps[#rec.steps + 1] = "CommitConfig " .. tostring(ok3 and r3 or ("err " .. tostring(r3))); if not ok3 then return false, "Refunded but not committed: " .. tostring(r3) end end
  end
  C_Timer.After(0.3, function() G.Refresh(); TF.Fire("GAME_CHANGED") end)
  return true, t.name
end

-- ---------- diagnostics, so the addon can be tuned from a SavedVariables read after /reload ----------
function G.Probe()
  local diag = TF.db.diag
  local v, b, _, toc = GetBuildInfo()
  local _, cls = UnitClass("player")
  diag.char = { name = UnitName("player"), realm = GetRealmName(), level = UnitLevel("player"), class = cls, race = (UnitRace("player")), build = tostring(v) .. "." .. tostring(b), toc = toc, when = date("%Y-%m-%d %H:%M"), addon = TF.VERSION }
  local api = {}
  local function has(tbl, name, label) api[label or name] = (tbl and type(tbl[name]) == "function") and true or false end
  for _, n in ipairs({ "GetTreeNodes", "GetNodeInfo", "GetEntryInfo", "GetDefinitionInfo", "GetConfigInfo", "GetConfigIDByTreeID", "GetConfigIDBySystemID", "GetTreeCurrencyInfo", "GetTreeInfo",
    "PurchaseRank", "RefundRank", "RefundAllRanks", "CanPurchaseRank", "CanRefundRank", "CommitConfig", "RollbackConfig", "StageConfig", "ConfigHasStagedChanges", "GetStagedChangesCount", "ResetTree", "ResetTreeByCurrency", "SetSelection", "GetNodeCost", "GetLoadoutSerializationVersion", "GenerateImportString", "GenerateInspectImportString", "GetConditionInfo", "GetTraitCurrencyInfo", "CascadeRepurchaseRanks", "HasValidInspectData" }) do has(C_Traits, n, "C_Traits." .. n) end
  for _, n in ipairs({ "GetActiveConfigID", "CommitConfig", "LoadConfig", "GetConfigIDsBySpecID", "GetActiveHeroTalentSpec", "SaveConfig", "UpdateLastSelectedSavedConfigID", "GetStarterBuildActive", "HasUnspentTalentPoints", "GetNextStarterBuildPurchase", "InitializeViewLoadout", "ViewLoadout", "CanChangeTalents", "CanCreateNewConfig" }) do has(C_ClassTalents, n, "C_ClassTalents." .. n) end
  for _, n in ipairs({ "GetSpellTexture", "GetSpellInfo", "GetSpellName", "GetSpellDescription", "RequestLoadSpellData" }) do has(C_Spell, n, "C_Spell." .. n) end
  for _, n in ipairs({ "GetTraitEntry", "GetSpellByID" }) do has(C_TooltipInfo, n, "C_TooltipInfo." .. n) end
  for _, n in ipairs({ "GetSpellTexture", "GetSpellInfo", "LearnTalent", "GetTalentInfo", "GetNumTalentTabs", "GetUnspentTalentPoints", "UnitCharacterPoints", "PlaySound", "InCombatLockdown", "CreateColor", "GetAddOnMetadata" }) do has(_G, n) end
  api["GameTooltip.SetTraitEntry"] = GameTooltip.SetTraitEntry ~= nil
  api["GameTooltip.SetSpellByID"] = GameTooltip.SetSpellByID ~= nil
  api["Texture.SetGradient"] = UIParent:CreateTexture().SetGradient ~= nil
  api["Animation.SetScaleFrom"] = UIParent:CreateAnimationGroup():CreateAnimation("Scale").SetScaleFrom ~= nil
  api["BackdropTemplateMixin"] = BackdropTemplateMixin ~= nil
  api["SOUNDKIT"] = SOUNDKIT ~= nil
  api["TooltipUtil.SurfaceArgs"] = TooltipUtil and TooltipUtil.SurfaceArgs ~= nil or false
  diag.api = api
  -- events: which of these does this client know
  local ev, f = {}, CreateFrame("Frame")
  for _, e in ipairs({ "TRAIT_CONFIG_UPDATED", "TRAIT_NODE_CHANGED", "TRAIT_NODE_ENTRY_UPDATED", "TRAIT_TREE_CURRENCY_INFO_UPDATED", "TRAIT_CONFIG_LIST_UPDATED", "TRAIT_TREE_CHANGED", "TRAIT_NODE_CHANGED_PARTIAL", "ACTIVE_COMBAT_CONFIG_CHANGED", "CONFIG_COMMIT_FAILED", "SELECTED_LOADOUT_CHANGED", "STARTER_BUILD_ACTIVATION_FAILED", "CHARACTER_POINTS_CHANGED", "PLAYER_TALENT_UPDATE", "SPELLS_CHANGED", "LEARNED_SPELL_IN_TAB", "PLAYER_LEVEL_UP", "PLAYER_LEVEL_CHANGED", "TRAINER_SHOW", "ADDON_LOADED" }) do
    local ok = pcall(f.RegisterEvent, f, e); ev[e] = ok and true or false; if ok then f:UnregisterEvent(e) end
  end
  diag.events = ev
  -- textures: which of the classic talent art files exist here
  local tex, t = {}, UIParent:CreateTexture()
  local c = D.classes[cls]
  local list = { "Interface\\TalentFrame\\TalentFrame-RankBorder", "Interface\\TalentFrame\\UI-TalentArrows", "Interface\\TalentFrame\\UI-TalentFrame-BotLeft", "Interface\\Buttons\\UI-Quickslot2", "Interface\\Buttons\\UI-ActionButton-Border", "Interface\\Buttons\\WHITE8X8", "Interface\\Buttons\\CheckButtonHilight", "Interface\\Tooltips\\UI-Tooltip-Background", "Interface\\AddOns\\TalentsForeverBook\\Media\\book.tga", "Interface\\AddOns\\TalentsForeverBook\\Media\\book.png", "Interface\\AddOns\\TalentsForeverBook\\Media\\glow.tga", "Interface\\AddOns\\TalentsForeverBook\\Media\\ring.tga" }
  if c then for _, tr in ipairs(c.trees) do list[#list + 1] = "Interface\\TalentFrame\\" .. (tr.bg or "?") .. "-TopLeft"; list[#list + 1] = "Interface\\Icons\\" .. tr.icon end end
  for _, p in ipairs(list) do local ok, r = pcall(t.SetTexture, t, p); tex[p] = ok and (r == nil and "set" or tostring(r)) or ("err " .. tostring(r)); pcall(t.SetTexture, t, nil) end
  local fs = UIParent:CreateFontString(); local okf, rf = pcall(fs.SetFont, fs, "Interface\\AddOns\\TalentsForeverBook\\Fonts\\Cinzel.ttf", 14, ""); tex["font Cinzel.ttf"] = okf and tostring(rf) or ("err " .. tostring(rf))
  diag.textures = tex
  -- frames: what the game's own talent window is called here
  local fr = {}
  for _, n in ipairs({ "PlayerTalentFrame", "ClassTalentFrame", "PlayerSpellsFrame", "TalentFrame", "SpellBookFrame", "PlayerSpellsFrame_TalentsFrame", "TalentMicroButton", "PlayerSpellsMicroButton", "SpellbookMicroButton", "CharacterFrame", "LegacyTalentFrame", "TraitFrame", "GenericTraitFrame" }) do fr[n] = _G[n] and (_G[n].GetObjectType and _G[n]:GetObjectType() or type(_G[n])) or false end
  local loaded = {}
  for _, a in ipairs({ "Blizzard_ClassTalentUI", "Blizzard_PlayerSpells", "Blizzard_TalentUI", "Blizzard_GenericTraitUI", "Blizzard_ClassicTalentUI", "Blizzard_SpellBookUI" }) do
    local isl = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
    local ok, r = pcall(isl, a); loaded[a] = ok and (r and true or false) or "?"
  end
  fr.blizzardAddons = loaded
  diag.frames = fr
  -- the trainer window and its functions (Train all depends on them), and which other talent addons sit next to us
  local tr = {}
  for _, n in ipairs({ "ClassTrainerFrame", "TrainerFrame", "ClassTrainerTrainButton", "BuyTrainerService", "GetTrainerServiceCost", "GetNumTrainerServices", "GetTrainerServiceInfo", "SetItemRef", "ChatFrame_AddMessageEventFilter", "ChatEdit_InsertLink" }) do tr[n] = _G[n] and type(_G[n]) or false end
  tr.C_TooltipInfo_GetTraitEntry = (C_TooltipInfo and C_TooltipInfo.GetTraitEntry) and true or false
  diag.trainer = tr
  local sib = {}
  for _, a in ipairs({ "WhatsTraining", "TalentsForever", "Talented", "TalentTreeTweaks", "TitanPanel", "Bartender4", "ElvUI", "TalentsForeverSim", "TalentsForeverCheck" }) do
    local isl = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
    local ok, r = pcall(isl, a); sib[a] = ok and (r and true or false) or "?"
  end
  sib.otherTalentsForeverFrame = _G["TalentsForever_MainFrame"] and true or false
  diag.siblings = sib
  -- a chat link only the real client can judge: if the gold text below is clickable, addon links work here
  if TF.ShareURL then local ok, url = pcall(TF.ShareURL, TF.plan); if ok and url and TF.LinkifyChat then local okl, line = pcall(TF.LinkifyChat, nil, nil, "Click this if it is gold: " .. url); if okl and line then TF.Print(line) end end end
  -- the live config and currency
  if G.Available() and c then
    local cfg = G.ConfigFor(c.tree)
    local info = cfg and Try("GetConfigInfo", C_Traits.GetConfigInfo, cfg)
    diag.config = { id = cfg, name = info and info.name, type = info and info.type, trees = info and info.treeIDs, usesSharedActionBars = info and info.usesSharedActionBars }
    if cfg and C_Traits.GetTreeCurrencyInfo then
      local cur = Try("GetTreeCurrencyInfo", C_Traits.GetTreeCurrencyInfo, cfg, c.tree, false)
      local out = {}
      for k, ci in ipairs(cur or {}) do out[k] = { id = ci.traitCurrencyID, quantity = ci.quantity, max = ci.maxQuantity, spent = ci.spent } end
      diag.currency = out
    end
    if cfg and C_Traits.GetTreeInfo then local ti = Try("GetTreeInfo", C_Traits.GetTreeInfo, cfg, c.tree); if ti then diag.config.treeInfo = { id = ti.ID, gates = ti.gates and #ti.gates, hideSingleRankNumbers = ti.hideSingleRankNumbers, buttonSize = ti.buttonSize } end end
    G.Refresh()
    if G.live and G.live.nodes[1] then
      local n = G.live.nodes[1]
      local raw = Try("GetNodeInfo", C_Traits.GetNodeInfo, cfg, n.id)
      local keys = {}
      if raw then for k, v in pairs(raw) do keys[k] = type(v) == "table" and ("table(" .. #v .. ")") or tostring(v) end end
      diag.sample = { node = n.id, rank = n.rank, max = n.max, entry = n.entry, spell = n.spell, rawKeys = keys, points = G.points, legacy = G.legacy and { talented = G.legacy.talented, found = G.legacy.found } }
      local cost = C_Traits.GetNodeCost and Try("GetNodeCost", C_Traits.GetNodeCost, cfg, n.id)
      if cost and cost[1] then diag.sample.cost = { id = cost[1].ID, amount = cost[1].amount } end
    end
  end
  diag.log = TF.log
  TF.Print("probe written. /reload to save it, then run addon/tools/diag.py on the PC.")
end

-- ---------- events ----------
local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("PLAYER_LEVEL_UP")
pcall(f.RegisterEvent, f, "ZONE_CHANGED_NEW_AREA")
for _, e in ipairs({ "TRAINER_SHOW", "TRAINER_UPDATE", "TRAINER_CLOSED", "INSPECT_READY", "PLAYER_XP_UPDATE", "SPELLS_CHANGED", "LEARNED_SPELL_IN_SKILL_LINE", "LEARNED_SPELL_IN_TAB", "PLAYER_MONEY" }) do pcall(f.RegisterEvent, f, e) end
local moneySoon
for _, e in ipairs({ "TRAIT_CONFIG_UPDATED", "TRAIT_NODE_CHANGED", "TRAIT_NODE_ENTRY_UPDATED", "TRAIT_TREE_CURRENCY_INFO_UPDATED", "TRAIT_CONFIG_LIST_UPDATED", "ACTIVE_COMBAT_CONFIG_CHANGED", "CHARACTER_POINTS_CHANGED", "PLAYER_TALENT_UPDATE", "SPELLS_CHANGED", "CONFIG_COMMIT_FAILED" }) do pcall(f.RegisterEvent, f, e) end
local pending
local function later(reason, secs)
  if pending then return end
  pending = true
  C_Timer.After(secs or 0.3, function()
    pending = nil
    G.Refresh()
    TF.Fire("GAME_CHANGED", reason)
  end)
end
f:SetScript("OnEvent", function(_, ev, arg1)
  if ev == "PLAYER_ENTERING_WORLD" then
    later("login", 2)
    C_Timer.After(8, function() G.Refresh(); TF.Fire("GAME_CHANGED", "login2") end)
  elseif ev == "PLAYER_LEVEL_UP" then
    later("levelup", 1.5)
    C_Timer.After(2, function() TF.Fire("LEVEL_UP", tonumber(arg1)) end)
  elseif ev == "INSPECT_READY" then TF.OnInspectReady(arg1)
  elseif ev == "PLAYER_XP_UPDATE" then TF.Fire("XP")
  elseif ev == "SPELLS_CHANGED" or ev == "LEARNED_SPELL_IN_SKILL_LINE" or ev == "LEARNED_SPELL_IN_TAB" then TF.ForgetBook(); later(ev, 0.5)   -- the spellbook's names are read again next time they are asked for
  elseif ev == "PLAYER_MONEY" then   -- gold moved: once the bursts settle, whoever waits on it (the trainer card) hears
    if not moneySoon then moneySoon = true; C_Timer.After(2, function() moneySoon = nil; TF.Fire("MONEY") end) end
  elseif ev == "TRAINER_SHOW" then TF.TrainerEvent("show")
  elseif ev == "TRAINER_UPDATE" then TF.TrainerEvent("update")
  elseif ev == "TRAINER_CLOSED" then TF.TrainerEvent("closed"); later("trainer", 0.5)
  elseif ev == "ZONE_CHANGED_NEW_AREA" then
    C_Timer.After(3, function() TF.Fire("ZONE", (GetRealZoneText and GetRealZoneText()) or (GetZoneText and GetZoneText()) or "") end)
  elseif ev == "CONFIG_COMMIT_FAILED" then
    G.committing = nil
    TF.Log("commit failed")
    later("commitfailed", 0.3)
    TF.Fire("COMMIT_FAILED")
  else
    later(ev, 0.3)
  end
end)
