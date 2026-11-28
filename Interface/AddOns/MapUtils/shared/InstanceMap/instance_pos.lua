local addonName, D4 = ...
local VERSION = 4
local TAXI_PIN = Enum and Enum.SuperTrackingMapPinType and Enum.SuperTrackingMapPinType.TaxiNode or 2
local TRACK = Enum and Enum.SuperTrackingType or {}
local TRACK_QUEST = TRACK.Quest or 0
local TRACK_WAYPOINT = TRACK.UserWaypoint or 1
local TRACK_CONTENT = TRACK.Content or 4
local TRACK_PIN = TRACK.MapPin or 6
local TRACK_VIGNETTE = TRACK.Vignette or 7
local ARROW_SIZE = 24
local POS_MAX_AGE = 3.0
local GROUP_PREFIX = "D4InstPos"
local GROUP_LEASE = "_D4GroupShare"
local TEX_POINTER = "Interface\\AddOns\\" .. addonName .. "\\shared\\InstanceMap\\player_pointer.blp"
local CFG = {
	["activeCount"] = 5,
	["minFix"] = 4,
	["stepActive"] = 0.03,
	["stepSleep"] = 0.25,
	["sleepPing"] = 2.0,
	["sleepDrift"] = 2.5,
	["sleepResidual"] = 2.5,
	["settleBase"] = 0.26,
	["settleMax"] = 0.85,
	["movingGap"] = 0.055,
	["idleGap"] = 0.11,
	["timeout"] = 0.4,
	["pinCheck"] = 0.08,
	["maxAge"] = 1.6,
	["rateSpan"] = 2.0,
	["gateMin"] = 8,
	["gateMax"] = 70,
	["heightSlack"] = 50,
	["acquireSlack"] = 0.6,
	["acquireMaxRes"] = 25,
	["residualGood"] = 2.0,
	["residualLimit"] = 14,
	["rejectsLose"] = 4,
	["missesLose"] = 3,
	["sameDist"] = 2.5,
	["sameDrift"] = 8,
	["sameWindow"] = 5,
	["confirmWait"] = 1.6,
	["maxSpeed"] = 45,
	["minSpeed"] = 0.4,
	["headingSpeed"] = 1.2,
	["arrowDelay"] = 0.5,
	["headingMaxAge"] = 2.5,
	["extrapolate"] = 0.25,
	["ageWeight"] = 3,
	["zBufSize"] = 5,
}
local reg = _G["D4_InstancePos"]
if reg == nil then
	reg = {
		["version"] = 0,
		["data"] = nil,
		["leases"] = {},
		["driver"] = nil,
		["motionFrame"] = nil,
		["groupFrame"] = nil,
		["groupTicker"] = nil,
		["group"] = {
			["peers"] = {},
			["roster"] = {},
			["rosterDirty"] = true,
			["watchUntil"] = 0,
			["lastWatchSent"] = 0,
			["lastWatchInst"] = nil,
			["lastSendTime"] = 0,
			["lastSendInst"] = nil,
			["lastSendX"] = nil,
			["lastSendY"] = nil,
			["lastSendZ"] = nil,
			["lastSendFacing"] = nil,
			["lastSendMoving"] = nil,
			["forceSend"] = false,
			["sendBackoff"] = 0,
			["shareEnabled"] = true,
			["elapsed"] = 0,
		},
		["pos"] = {
			["active"] = false,
			["instID"] = nil,
			["phase"] = 0,
			["activeCount"] = 0,
			["slots"] = {},
			["pool"] = {},
			["poolCount"] = 0,
			["ours"] = {},
			["bad"] = {},
			["work"] = {},
			["zBuf"] = {0, 0, 0, 0, 0},
			["zSorted"] = {0, 0, 0, 0, 0},
			["zCount"] = 0,
			["zHead"] = 0,
			["curIdx"] = 1,
			["prevSlot"] = nil,
			["pending"] = false,
			["switchAt"] = 0,
			["switchedAt"] = 0,
			["lastSwitch"] = 0,
			["pinChecked"] = false,
			["pinRefused"] = false,
			["outranked"] = false,
			["settle"] = CFG.settleBase,
			["acqStart"] = 0,
			["acqFrom"] = 0,
			["acquiredAt"] = 0,
			["uncert"] = 0,
			["interval"] = 0,
			["lastDist"] = 0,
			["lastTime"] = 0,
			["lastAnchorID"] = 0,
			["misses"] = 0,
			["rejects"] = 0,
			["lastOk"] = 0,
			["moving"] = false,
			["moveStart"] = 0,
			["motionSince"] = 0,
			["settleLeft"] = 0,
			["nextSleepPing"] = 0,
			["blockedUntil"] = 0,
			["stopAt"] = 0,
			["elapsed"] = 0,
			["fix"] = {
				["valid"] = false,
				["confirmed"] = false,
				["x"] = 0,
				["y"] = 0,
				["z"] = 0,
				["zMed"] = 0,
				["vx"] = 0,
				["vy"] = 0,
				["heading"] = nil,
				["headingTime"] = 0,
				["time"] = 0,
				["residual"] = 999,
				["count"] = 0,
			},
			["saved"] = {
				["has"] = false,
				["quest"] = 0,
				["waypoint"] = false,
				["contentType"] = nil,
				["contentID"] = nil,
				["vignette"] = nil,
				["pinType"] = nil,
				["pinID"] = nil,
				["priority"] = nil,
			},
		},
	}
	_G["D4_InstancePos"] = reg
end

local POS = reg.pos
if reg.group == nil then
	reg.group = {
		["peers"] = {},
		["roster"] = {},
		["rosterDirty"] = true,
		["watchUntil"] = 0,
		["lastWatchSent"] = 0,
		["lastWatchInst"] = nil,
		["lastSendTime"] = 0,
		["lastSendInst"] = nil,
		["lastSendX"] = nil,
		["lastSendY"] = nil,
		["lastSendZ"] = nil,
		["lastSendFacing"] = nil,
		["lastSendMoving"] = nil,
		["forceSend"] = false,
		["sendBackoff"] = 0,
		["shareEnabled"] = true,
		["elapsed"] = 0,
	}
end
local GROUP = reg.group

local function IsSecret(v)
	return issecretvalue ~= nil and issecretvalue(v) == true
end

local function GetPlayerMovingKnown()
	if GetUnitSpeed == nil then return nil end
	local s = GetUnitSpeed("player")
	if IsSecret(s) or type(s) ~= "number" then return nil end
	return s > 0
end

local function GetCurrentInstanceID()
	if IsInInstance == nil or GetInstanceInfo == nil then return nil end
	local inInst = IsInInstance()
	if not inInst then return nil end
	local instID = select(8, GetInstanceInfo())
	if IsSecret(instID) or type(instID) ~= "number" or instID <= 0 then return nil end
	return instID
end

local function ExtractArtKey(artKey)
	if artKey == nil then return nil end
	local s = tostring(artKey)
	if strfind(s, "[\\/]") ~= nil then
		s = strmatch(s, "([^\\/]+)$") or s
	end
	s = gsub(s, "%.[^%.]+$", "")
	return s
end

local function Dist3(slot, x, y, z)
	local dx = x - slot.x
	local dy = y - slot.y
	local dz = z - slot.z
	return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function SolveSym3(s11, s12, s13, s22, s23, s33, b1, b2, b3)
	local c11 = s22 * s33 - s23 * s23
	local c12 = s13 * s23 - s12 * s33
	local c13 = s12 * s23 - s13 * s22
	local det = s11 * c11 + s12 * c12 + s13 * c13
	if det == 0 or det ~= det then return nil end
	local inv = 1 / det
	local c22 = s11 * s33 - s13 * s13
	local c23 = s12 * s13 - s11 * s23
	local c33 = s11 * s22 - s12 * s12
	local x = (c11 * b1 + c12 * b2 + c13 * b3) * inv
	local y = (c12 * b1 + c22 * b2 + c23 * b3) * inv
	local z = (c13 * b1 + c23 * b2 + c33 * b3) * inv
	if x ~= x or y ~= y or z ~= z then return nil end
	return x, y, z
end

local function EstimatePos(now)
	local f = POS.fix
	local dt = now - f.time
	if dt < 0 then
		dt = 0
	elseif dt > CFG.extrapolate then
		dt = CFG.extrapolate
	end
	return f.x + f.vx * dt, f.y + f.vy * dt, f.z
end

local function ResetMotion(now)
	POS.fix.vx = 0
	POS.fix.vy = 0
	POS.fix.headingTime = 0
	POS.motionSince = now
end

local function RoundTime()
	return POS.interval * POS.activeCount
end

local function PushHeight(z)
	local head = (POS.zHead % CFG.zBufSize) + 1
	POS.zHead = head
	POS.zBuf[head] = z
	if POS.zCount < CFG.zBufSize then POS.zCount = POS.zCount + 1 end
	local n = POS.zCount
	local s = POS.zSorted
	for i = 1, n do
		local v = POS.zBuf[i]
		local j = i - 1
		while j >= 1 and s[j] > v do
			s[j + 1] = s[j]
			j = j - 1
		end
		s[j + 1] = v
	end
	return s[math.ceil(n * 0.5)]
end

local function GatherSlots(now, maxAge, since)
	local w = POS.work
	local n = 0
	local slots = POS.slots
	for i = 1, POS.activeCount do
		local s = slots[i]
		if not s.disabled and s.time > 0 and (now - s.time) <= maxAge and s.time >= since then
			n = n + 1
			w[n] = s
		end
	end
	return n
end

local function PrepareWork(n, now, adjust)
	local w = POS.work
	local f = POS.fix
	local hasVel = adjust and f.valid and (f.vx ~= 0 or f.vy ~= 0)
	for i = 1, n do
		local s = w[i]
		local d = s.dist
		local age = now - s.time
		if age < 0 then age = 0 end
		if hasVel then
			local r = Dist3(s, f.x, f.y, f.z)
			if r > 0 then
				d = d + ((f.x - s.x) * f.vx + (f.y - s.y) * f.vy) / r * age
			end
		end
		s.useDist = d
		s.weight = adjust and (1 / (1 + CFG.ageWeight * age)) or 1
	end
end

local function SolveLinear3(n)
	local w = POS.work
	local s0 = w[1]
	local base = s0.x * s0.x + s0.y * s0.y + s0.z * s0.z - s0.useDist * s0.useDist
	local s11, s12, s13, s22, s23, s33 = 0, 0, 0, 0, 0, 0
	local b1, b2, b3 = 0, 0, 0
	for i = 2, n do
		local s = w[i]
		local ax = 2 * (s.x - s0.x)
		local ay = 2 * (s.y - s0.y)
		local az = 2 * (s.z - s0.z)
		local rhs = s.x * s.x + s.y * s.y + s.z * s.z - s.useDist * s.useDist - base
		s11 = s11 + ax * ax
		s12 = s12 + ax * ay
		s13 = s13 + ax * az
		s22 = s22 + ay * ay
		s23 = s23 + ay * az
		s33 = s33 + az * az
		b1 = b1 + ax * rhs
		b2 = b2 + ay * rhs
		b3 = b3 + az * rhs
	end
	return SolveSym3(s11, s12, s13, s22, s23, s33, b1, b2, b3)
end

local function CalcResidual(x, y, z, n)
	local w = POS.work
	local sum = 0
	local wsum = 0
	for i = 1, n do
		local s = w[i]
		local err = Dist3(s, x, y, z) - s.useDist
		sum = sum + s.weight * err * err
		wsum = wsum + s.weight
	end
	if wsum <= 0 then return 999 end
	return math.sqrt(sum / wsum)
end

local function RefineGN(x, y, z, n)
	local w = POS.work
	for _ = 1, 3 do
		local s11, s12, s13, s22, s23, s33 = 0, 0, 0, 0, 0, 0
		local b1, b2, b3 = 0, 0, 0
		for i = 1, n do
			local s = w[i]
			local dx = x - s.x
			local dy = y - s.y
			local dz = z - s.z
			local r = math.sqrt(dx * dx + dy * dy + dz * dz)
			if r > 0 then
				local wt = s.weight
				local ux = dx / r
				local uy = dy / r
				local uz = dz / r
				local err = r - s.useDist
				s11 = s11 + wt * ux * ux
				s12 = s12 + wt * ux * uy
				s13 = s13 + wt * ux * uz
				s22 = s22 + wt * uy * uy
				s23 = s23 + wt * uy * uz
				s33 = s33 + wt * uz * uz
				b1 = b1 - wt * ux * err
				b2 = b2 - wt * uy * err
				b3 = b3 - wt * uz * err
			end
		end
		local sx, sy, sz = SolveSym3(s11, s12, s13, s22, s23, s33, b1, b2, b3)
		if sx == nil then break end
		x = x + sx
		y = y + sy
		z = z + sz
		if (sx * sx + sy * sy + sz * sz) < 1e-4 then break end
	end
	return x, y, z, CalcResidual(x, y, z, n)
end

local function UpdateVelocity(now)
	local f = POS.fix
	if not f.valid or not POS.moving then return end
	local maxAge = math.max(CFG.maxAge, 1.3 * RoundTime())
	local maxSpan = math.max(CFG.rateSpan, 1.5 * RoundTime())
	local s11, s12, s22, t1, t2 = 0, 0, 0, 0, 0
	local used = 0
	local slots = POS.slots
	for i = 1, POS.activeCount do
		local s = slots[i]
		local pt = s.prevTime
		if not s.disabled and s.time > 0 and pt > 0 and pt >= POS.motionSince and (now - s.time) <= maxAge and s.time > pt and (s.time - pt) <= maxSpan then
			local r = Dist3(s, f.x, f.y, f.z)
			if r > 0 then
				local ux = (f.x - s.x) / r
				local uy = (f.y - s.y) / r
				local rate = (s.dist - s.prevDist) / (s.time - pt)
				s11 = s11 + ux * ux
				s12 = s12 + ux * uy
				s22 = s22 + uy * uy
				t1 = t1 + ux * rate
				t2 = t2 + uy * rate
				used = used + 1
			end
		end
	end
	local det = s11 * s22 - s12 * s12
	if used < 3 or det < 1e-6 then return end
	local vx = (t1 * s22 - t2 * s12) / det
	local vy = (s11 * t2 - s12 * t1) / det
	local speed = math.sqrt(vx * vx + vy * vy)
	if speed > CFG.maxSpeed or speed < CFG.minSpeed then
		f.vx = 0
		f.vy = 0
		return
	end
	f.vx = vx
	f.vy = vy
	if speed >= CFG.headingSpeed then
		f.heading = math.atan2(vy, vx)
		f.headingTime = now
	end
end

local function AcceptFix(x, y, z, residual, count, now)
	local f = POS.fix
	f.valid = true
	f.x = x
	f.y = y
	f.z = z
	f.zMed = PushHeight(z)
	f.time = now
	f.residual = residual
	f.count = count
	POS.rejects = 0
	if count >= 5 and residual < CFG.residualGood then
		POS.uncert = POS.uncert > 1 and POS.uncert * 0.5 or 0
		f.confirmed = true
	elseif (now - POS.acquiredAt) >= CFG.confirmWait and residual < CFG.residualLimit then
		f.confirmed = true
	end
end

local function Solve(now)
	if POS.phase == 1 then
		local n = GatherSlots(now, CFG.minFix * POS.settle + CFG.acquireSlack, POS.acqStart)
		if n < CFG.minFix then return end
		PrepareWork(n, now, false)
		local x, y, z = SolveLinear3(n)
		if x == nil then return end
		local res
		x, y, z, res = RefineGN(x, y, z, n)
		if res > CFG.acquireMaxRes then return end
		POS.zCount = 0
		POS.zHead = 0
		ResetMotion(now)
		POS.phase = 2
		POS.acquiredAt = now
		POS.uncert = 30
		POS.fix.confirmed = false
		POS.settleLeft = POS.moving and 0 or POS.activeCount
		AcceptFix(x, y, z, res, n, now)
		return
	end

	local n = GatherSlots(now, math.max(CFG.maxAge, 1.3 * RoundTime()), 0)
	if n < CFG.minFix then return end
	UpdateVelocity(now)
	PrepareWork(n, now, true)
	local ex, ey, ez = EstimatePos(now)
	local x, y, z, res = RefineGN(ex, ey, ez, n)
	if res <= CFG.residualLimit + POS.uncert * 0.5 then
		AcceptFix(x, y, z, res, n, now)
		if not POS.moving then
			if POS.settleLeft > 0 then POS.settleLeft = POS.settleLeft - 1 end
			if POS.settleLeft <= 0 and POS.fix.confirmed and res <= CFG.sleepResidual then
				POS.phase = 3
				POS.fix.vx = 0
				POS.fix.vy = 0
				POS.pending = false
				POS.nextSleepPing = now + CFG.sleepPing
			end
		end
	else
		POS.rejects = POS.rejects + 1
	end
end

local function InitSlot(slot, id, node)
	slot.id = id
	slot.x = node[1]
	slot.y = node[2]
	slot.z = node[3]
	slot.dist = 0
	slot.time = 0
	slot.prevDist = 0
	slot.prevTime = 0
	slot.misses = 0
	slot.missedAt = 0
	slot.disabled = false
	slot.useDist = 0
	slot.weight = 1
end

local function CountEnabledSlots()
	local c = 0
	for i = 1, POS.activeCount do
		if not POS.slots[i].disabled then c = c + 1 end
	end
	return c
end

local function SwapFromPool(idx, markBad)
	if POS.poolCount <= 0 or reg.data == nil or reg.data.nodes == nil then return false end
	local slot = POS.slots[idx]
	local oldID = slot.id
	local nextID = table.remove(POS.pool, 1)
	POS.poolCount = POS.poolCount - 1
	local node = reg.data.nodes[nextID]
	if node == nil then return false end
	if markBad then
		POS.bad[oldID] = true
	else
		POS.poolCount = POS.poolCount + 1
		POS.pool[POS.poolCount] = oldID
	end
	InitSlot(slot, nextID, node)
	if POS.prevSlot == slot then POS.prevSlot = nil end
	return true
end

local function IsInInitialBatch(idx)
	local seen = 0
	local total = POS.activeCount
	for off = 0, total - 1 do
		local c = ((POS.acqFrom + off) % total) + 1
		if not POS.slots[c].disabled then
			seen = seen + 1
			if c == idx then return seen <= CFG.minFix end
		end
	end
	return false
end

local function NextSlotIndex()
	local idx = POS.curIdx
	local total = POS.activeCount
	for _ = 1, total do
		idx = (idx % total) + 1
		if not POS.slots[idx].disabled and (POS.phase ~= 1 or IsInInitialBatch(idx)) then
			return idx
		end
	end
	return POS.curIdx
end

local function SwitchSlot(idx, now)
	POS.prevSlot = POS.slots[POS.curIdx]
	POS.curIdx = idx
	POS.pending = false
	POS.pinChecked = false
	POS.pinRefused = false
	POS.outranked = false
	local ok = pcall(C_SuperTrack.SetSuperTrackedMapPin, TAXI_PIN, POS.slots[idx].id)
	if not ok then POS.blockedUntil = now + 2 end
	POS.switchedAt = now
	POS.lastSwitch = now
end

local function CheckPinRefused(slot)
	if C_SuperTrack.GetSuperTrackedMapPin ~= nil then
		local ok, kind, id = pcall(C_SuperTrack.GetSuperTrackedMapPin)
		if ok and id ~= nil and (kind ~= TAXI_PIN or id ~= slot.id) then return true, false end
	end
	if C_SuperTrack.GetHighestPrioritySuperTrackingType ~= nil then
		local ok, top = pcall(C_SuperTrack.GetHighestPrioritySuperTrackingType)
		if ok and top ~= nil and top ~= TRACK_PIN then return true, true end
	end
	return false, false
end

local function LoseFix(now)
	if (now - POS.acquiredAt) < 2 then
		POS.settle = math.min(POS.settle * 1.4, CFG.settleMax)
		POS.acqFrom = (POS.acqFrom + 1) % math.max(1, POS.activeCount)
	else
		POS.settle = CFG.settleBase
	end
	POS.phase = 1
	POS.acqStart = now
	POS.fix.confirmed = false
	POS.misses = 0
	POS.rejects = 0
	POS.lastTime = 0
	ResetMotion(now)
end

local function RecordReading(slot, dist, now)
	if slot.time > 0 and slot.time >= POS.motionSince then
		slot.prevDist = slot.dist
		slot.prevTime = slot.time
	else
		slot.prevDist = 0
		slot.prevTime = 0
	end
	slot.dist = dist
	slot.time = now
	slot.misses = 0
	if POS.lastTime > 0 and (now - POS.lastTime) < 1 then
		local dt = now - POS.lastTime
		POS.interval = POS.interval > 0 and (POS.interval + 0.25 * (dt - POS.interval)) or dt
	end
	POS.lastDist = dist
	POS.lastTime = now
	POS.lastAnchorID = slot.id
	POS.misses = 0
	POS.lastOk = now
end

local function RecordMiss(slot, now)
	if slot.misses == 0 then slot.missedAt = now end
	slot.misses = slot.misses + 1
	POS.misses = POS.misses + 1
	if slot.misses >= 2 then
		local alone = POS.lastOk > slot.missedAt
		if alone or POS.phase == 1 then
			if SwapFromPool(POS.curIdx, alone) then
				POS.misses = 0
				return
			elseif alone and CountEnabledSlots() > CFG.minFix then
				slot.disabled = true
				POS.misses = 0
				return
			end
			slot.misses = 0
		end
	end
	if POS.phase ~= 1 and POS.misses >= CFG.missesLose then LoseFix(now) end
end

local function ReadDistance()
	local ok, d = pcall(C_Navigation.GetDistance)
	if not ok or IsSecret(d) then return nil, true end
	if type(d) ~= "number" then return 0, false end
	return d, false
end

local function StepSleep(now)
	if now < POS.nextSleepPing then return end
	POS.nextSleepPing = now + CFG.sleepPing
	local slot = POS.slots[POS.curIdx]
	if slot == nil then
		LoseFix(now)
		return
	end
	local refused, outranked = CheckPinRefused(slot)
	if refused then
		if outranked then
			POS.blockedUntil = now + 1.5
		else
			POS.phase = 2
			POS.settleLeft = POS.activeCount
			SwitchSlot(POS.curIdx, now)
		end
		return
	end
	local d, blocked = ReadDistance()
	if blocked then
		POS.blockedUntil = now + 3
		return
	end
	local f = POS.fix
	local expected = Dist3(slot, f.x, f.y, f.z)
	if d > 0 and math.abs(d - expected) <= CFG.sleepDrift then
		f.time = now
		return
	end
	POS.phase = 2
	POS.settleLeft = POS.activeCount
	POS.uncert = 15
	SwitchSlot(NextSlotIndex(), now)
end

local function Step(now)
	if POS.phase == 3 then
		StepSleep(now)
		return
	end
	if POS.pending then
		if now >= POS.switchAt then SwitchSlot(NextSlotIndex(), now) end
		return
	end
	local slot = POS.slots[POS.curIdx]
	if slot == nil then return end
	local d, blocked = ReadDistance()
	if blocked then
		POS.blockedUntil = now + 3
		return
	end

	local waited = now - POS.switchedAt
	local other = POS.prevSlot ~= slot and POS.prevSlot or nil
	local outcome = nil
	if not POS.pinChecked and waited >= CFG.pinCheck then
		POS.pinChecked = true
		local refused, outranked = CheckPinRefused(slot)
		POS.pinRefused = refused
		POS.outranked = outranked
	end
	if POS.pinRefused then
		outcome = "miss"
		if POS.outranked then POS.blockedUntil = now + 1.2 end
	elseif POS.phase == 1 or not POS.fix.valid then
		if d > 0 and waited >= POS.settle then
			local since = POS.lastTime > 0 and (now - POS.lastTime) or nil
			if since ~= nil and since < CFG.sameWindow and POS.lastAnchorID ~= slot.id and math.abs(d - POS.lastDist) <= (CFG.sameDist + CFG.sameDrift * since) then
				if waited >= POS.settle + CFG.timeout then outcome = "miss" end
			else
				outcome = "reading"
			end
		elseif waited >= POS.settle + CFG.timeout then
			outcome = "miss"
		end
	else
		local ex, ey, ez = EstimatePos(now)
		local expected = Dist3(slot, ex, ey, ez)
		local gate = math.min(CFG.gateMax, CFG.gateMin + POS.uncert + 3 * POS.fix.residual + 14 * (now - POS.fix.time)) + CFG.heightSlack * math.abs(ez - slot.z) / math.max(expected, 1)
		local prevExp = other ~= nil and Dist3(other, ex, ey, ez) or nil
		if d > 0 and math.abs(d - expected) <= gate then
			if prevExp == nil or math.abs(prevExp - expected) > 2 * gate or waited >= POS.settle then
				outcome = "reading"
			end
		elseif d > 0 and waited >= POS.settle and not (prevExp ~= nil and math.abs(d - prevExp) <= gate) then
			LoseFix(now)
			outcome = "lost"
		elseif waited >= CFG.timeout then
			outcome = "miss"
		end
	end

	if outcome == nil then return end
	if outcome == "reading" then
		RecordReading(slot, d, now)
		Solve(now)
		if POS.phase == 2 and POS.rejects >= CFG.rejectsLose then LoseFix(now) end
	elseif outcome == "miss" then
		RecordMiss(slot, now)
	end
	if POS.phase == 3 then return end

	POS.pending = true
	local fast = POS.moving or POS.phase == 1 or POS.fix.vx ~= 0 or POS.fix.vy ~= 0
	POS.switchAt = math.max(now, POS.lastSwitch + (fast and CFG.movingGap or CFG.idleGap))
	if now >= POS.switchAt then SwitchSlot(NextSlotIndex(), now) end
end

local function SetMarkerAlpha(visible)
	local frame = SuperTrackedFrame
	local states = Enum and Enum.NavigationState
	if type(frame) ~= "table" or frame.SetTargetAlphaForState == nil or states == nil then return end
	if states.Occluded ~= nil then pcall(frame.SetTargetAlphaForState, frame, states.Occluded, visible and 0.6 or 0) end
	if states.InRange ~= nil then pcall(frame.SetTargetAlphaForState, frame, states.InRange, visible and 1 or 0) end
end

local function SaveSuperTrack()
	local sv = POS.saved
	sv.has = true
	sv.quest = 0
	sv.waypoint = false
	sv.contentType = nil
	sv.contentID = nil
	sv.vignette = nil
	sv.pinType = nil
	sv.pinID = nil
	sv.priority = nil
	local st = C_SuperTrack
	if st == nil then return end
	if st.GetSuperTrackedQuestID ~= nil then
		local ok, q = pcall(st.GetSuperTrackedQuestID)
		if ok and q ~= nil and q ~= 0 then sv.quest = q end
	end
	if st.IsSuperTrackingUserWaypoint ~= nil then
		local ok, w = pcall(st.IsSuperTrackingUserWaypoint)
		if ok and w == true then sv.waypoint = true end
	end
	if st.GetSuperTrackedContent ~= nil then
		local ok, ct, cid = pcall(st.GetSuperTrackedContent)
		if ok and ct ~= nil and cid ~= nil then
			sv.contentType = ct
			sv.contentID = cid
		end
	end
	if st.GetSuperTrackedVignette ~= nil then
		local ok, v = pcall(st.GetSuperTrackedVignette)
		if ok and v ~= nil then sv.vignette = v end
	end
	if st.GetSuperTrackedMapPin ~= nil then
		local ok, pt, pid = pcall(st.GetSuperTrackedMapPin)
		if ok and pt ~= nil and pid ~= nil and not (pt == TAXI_PIN and POS.ours[pid]) then
			sv.pinType = pt
			sv.pinID = pid
		end
	end
	if st.GetHighestPrioritySuperTrackingType ~= nil then
		local ok, pr = pcall(st.GetHighestPrioritySuperTrackingType)
		if ok then sv.priority = pr end
	end
end

local function RestoreEntry(kind)
	local sv = POS.saved
	local st = C_SuperTrack
	if st == nil then return end
	if kind == TRACK_QUEST and sv.quest ~= 0 and st.SetSuperTrackedQuestID ~= nil then
		local ok, cur = pcall(st.GetSuperTrackedQuestID)
		if not ok or cur ~= sv.quest then pcall(st.SetSuperTrackedQuestID, sv.quest) end
	elseif kind == TRACK_WAYPOINT and sv.waypoint and st.SetSuperTrackedUserWaypoint ~= nil then
		local ok, cur = pcall(st.IsSuperTrackingUserWaypoint)
		if not ok or cur ~= true then pcall(st.SetSuperTrackedUserWaypoint, true) end
	elseif kind == TRACK_CONTENT and sv.contentType ~= nil and st.SetSuperTrackedContent ~= nil then
		local ok, ct, cid = pcall(st.GetSuperTrackedContent)
		if not ok or ct ~= sv.contentType or cid ~= sv.contentID then pcall(st.SetSuperTrackedContent, sv.contentType, sv.contentID) end
	elseif kind == TRACK_VIGNETTE and sv.vignette ~= nil and st.SetSuperTrackedVignette ~= nil then
		local ok, cur = pcall(st.GetSuperTrackedVignette)
		if not ok or cur ~= sv.vignette then pcall(st.SetSuperTrackedVignette, sv.vignette) end
	elseif kind == TRACK_PIN and sv.pinType ~= nil and st.SetSuperTrackedMapPin ~= nil then
		local ok, pt, pid = pcall(st.GetSuperTrackedMapPin)
		if not ok or pt ~= sv.pinType or pid ~= sv.pinID then pcall(st.SetSuperTrackedMapPin, sv.pinType, sv.pinID) end
	end
end

local function RestoreSuperTrack()
	local st = C_SuperTrack
	if st ~= nil and st.GetSuperTrackedMapPin ~= nil and st.ClearSuperTrackedMapPin ~= nil then
		local ok, pt, pid = pcall(st.GetSuperTrackedMapPin)
		if ok and pt == TAXI_PIN and POS.ours[pid] then pcall(st.ClearSuperTrackedMapPin) end
	end
	local sv = POS.saved
	if not sv.has then return end
	sv.has = false
	local order = {TRACK_QUEST, TRACK_WAYPOINT, TRACK_CONTENT, TRACK_VIGNETTE, TRACK_PIN}
	for i = 1, #order do
		if order[i] ~= sv.priority then RestoreEntry(order[i]) end
	end
	if sv.priority ~= nil then RestoreEntry(sv.priority) end
end

local function PlayerFactionBit()
	if UnitFactionGroup == nil then return 3 end
	local f = UnitFactionGroup("player")
	if f == "Alliance" then return 1 end
	if f == "Horde" then return 2 end
	return 3
end

local function BuildAnchorOrder(instID)
	local store = reg.data
	if store == nil or store.nodes == nil then return 0 end
	local raw = (store.anchors ~= nil and store.anchors[instID]) or store.fallback
	if raw == nil then return 0 end
	local fBit = PlayerFactionBit()
	local pref = {}
	local alt = {}
	local late = {}
	for i = 1, #raw do
		local id = raw[i]
		local node = store.nodes[id]
		if node ~= nil then
			if POS.bad[id] then
				late[#late + 1] = id
			else
				local nf = node[4] or 3
				if nf == 3 or nf == fBit then
					pref[#pref + 1] = id
				else
					alt[#alt + 1] = id
				end
			end
		end
	end
	if (#pref + #alt + #late) < CFG.minFix then return 0 end
	wipe(POS.ours)
	wipe(POS.pool)
	POS.poolCount = 0
	POS.activeCount = 0
	local function PushID(id)
		POS.ours[id] = true
		if POS.activeCount < CFG.activeCount then
			POS.activeCount = POS.activeCount + 1
			local slot = POS.slots[POS.activeCount]
			if slot == nil then
				slot = {}
				POS.slots[POS.activeCount] = slot
			end
			InitSlot(slot, id, store.nodes[id])
		else
			POS.poolCount = POS.poolCount + 1
			POS.pool[POS.poolCount] = id
		end
	end
	for i = 1, #pref do PushID(pref[i]) end
	for i = 1, #alt do PushID(alt[i]) end
	for i = 1, #late do PushID(late[i]) end
	return POS.activeCount
end

local impl = {}

local function OnStartMoving(now)
	if POS.moving then return end
	POS.moving = true
	POS.moveStart = now
	ResetMotion(now)
	if POS.active and POS.phase == 3 then
		POS.phase = 2
		POS.settleLeft = 0
		POS.elapsed = CFG.stepActive
		SwitchSlot(NextSlotIndex(), now)
	end
end

local function OnStopMoving(now)
	if not POS.moving then return end
	POS.moving = false
	POS.moveStart = 0
	ResetMotion(now)
	if POS.active and POS.phase == 2 then POS.settleLeft = POS.activeCount end
end

local function BindMotionScript(mf)
	mf:SetScript("OnEvent", function(_, event)
		local now = GetTime()
		if event == "PLAYER_STARTED_MOVING" then
			OnStartMoving(now)
		elseif event == "PLAYER_STOPPED_MOVING" then
			OnStopMoving(now)
		elseif event == "PLAYER_ENTERING_WORLD" then
			if GetCurrentInstanceID() == nil then
				wipe(reg.leases)
				GROUP.watchUntil = 0
				GROUP.lastWatchInst = nil
				GROUP.lastSendInst = nil
				wipe(GROUP.peers)
				GROUP.rosterDirty = true
				if reg.groupTicker ~= nil then reg.groupTicker:Hide() end
				impl.Stop()
			elseif POS.active and POS.phase == 3 then
				POS.nextSleepPing = now
			end
		elseif POS.active and POS.phase == 3 then
			POS.nextSleepPing = now
		end
	end)
end

local function EnsureMotionFrame()
	if reg.motionFrame == nil then
		if CreateFrame == nil then return end
		local mf = CreateFrame("Frame")
		mf:RegisterEvent("PLAYER_STARTED_MOVING")
		mf:RegisterEvent("PLAYER_STOPPED_MOVING")
		mf:RegisterEvent("PLAYER_ENTERING_WORLD")
		mf:RegisterEvent("ZONE_CHANGED_INDOORS")
		mf:RegisterEvent("ZONE_CHANGED")
		BindMotionScript(mf)
		reg.motionFrame = mf
	end
end

local function EnsureFrames()
	if reg.driver == nil then
		local drv = CreateFrame("Frame")
		drv:Hide()
		drv:SetScript("OnUpdate", function(_, elapsed)
			local step = (POS.phase == 3 and POS.stopAt == 0) and CFG.stepSleep or CFG.stepActive
			POS.elapsed = POS.elapsed + elapsed
			if POS.elapsed < step then return end
			POS.elapsed = 0
			local now = GetTime()
			if POS.stopAt > 0 then
				if now >= POS.stopAt then impl.Stop() end
				return
			end
			if now < POS.blockedUntil then return end
			local ok = pcall(Step, now)
			if not ok then POS.blockedUntil = now + 1.5 end
		end)
		reg.driver = drv
	end
	EnsureMotionFrame()
end

function impl.IsAvailable()
	return C_SuperTrack ~= nil and C_SuperTrack.SetSuperTrackedMapPin ~= nil and C_Navigation ~= nil and C_Navigation.GetDistance ~= nil and reg.data ~= nil
end

function impl.Start(instID)
	if not impl.IsAvailable() or instID == nil then return false end
	if POS.active and POS.instID == instID then return true end
	if POS.active then impl.Stop() end
	if BuildAnchorOrder(instID) < CFG.minFix then return false end

	EnsureFrames()
	SaveSuperTrack()
	SetMarkerAlpha(false)
	local now = GetTime()
	POS.active = true
	POS.instID = instID
	POS.phase = 1
	POS.acqStart = now
	POS.acqFrom = 0
	POS.acquiredAt = 0
	POS.settle = CFG.settleBase
	POS.uncert = 0
	POS.interval = 0
	POS.lastDist = 0
	POS.lastTime = 0
	POS.lastAnchorID = 0
	POS.misses = 0
	POS.rejects = 0
	POS.lastOk = 0
	local knownMoving = GetPlayerMovingKnown()
	if knownMoving ~= nil then
		POS.moving = knownMoving
		if knownMoving then
			if (POS.moveStart or 0) == 0 then POS.moveStart = now end
		else
			POS.moveStart = 0
		end
	end
	POS.blockedUntil = 0
	POS.stopAt = 0
	POS.elapsed = 0
	POS.settleLeft = 0
	POS.zCount = 0
	POS.zHead = 0
	local f = POS.fix
	f.valid = false
	f.confirmed = false
	f.heading = nil
	f.headingTime = 0
	f.residual = 999
	f.count = 0
	ResetMotion(now)
	POS.curIdx = 1
	POS.prevSlot = nil
	SwitchSlot(1, now)
	reg.driver:Show()
	return true
end

function impl.Stop()
	POS.stopAt = 0
	if not POS.active then return end
	POS.active = false
	POS.instID = nil
	POS.phase = 0
	if reg.driver ~= nil then reg.driver:Hide() end
	POS.fix.valid = false
	POS.fix.confirmed = false
	POS.fix.headingTime = 0
	RestoreSuperTrack()
	SetMarkerAlpha(true)
end

function impl.Request(ownerKey, instID)
	if ownerKey == nil or instID == nil then return false end
	if not impl.IsAvailable() then return false end
	reg.leases[ownerKey] = instID
	POS.stopAt = 0
	return impl.Start(instID)
end

function impl.Release(ownerKey)
	if ownerKey == nil or reg.leases[ownerKey] == nil then return end
	reg.leases[ownerKey] = nil
	local nextInst = nil
	for _, id in pairs(reg.leases) do
		nextInst = id
		break
	end
	if nextInst == nil then
		if POS.active and GetCurrentInstanceID() == POS.instID then
			POS.stopAt = GetTime() + 0.2
		else
			impl.Stop()
		end
	elseif POS.instID ~= nextInst then
		POS.stopAt = 0
		impl.Start(nextInst)
	end
end

function impl.Get()
	if not POS.active or not POS.fix.valid or not POS.fix.confirmed then return nil end
	local now = GetTime()
	local x, y = EstimatePos(now)
	local f = POS.fix
	return x, y, f.zMed, f.heading, now - f.time, f.residual, POS.phase
end

function impl.GetArtBounds(artKey)
	local store = reg.data
	if store == nil or store.art == nil or artKey == nil then return nil end
	local key = ExtractArtKey(artKey)
	if key == nil then return nil end
	return store.art[key]
end

function impl.GetLive(ownerKey, instID, enabled)
	local curInst = GetCurrentInstanceID()
	if curInst == nil or instID == nil or curInst ~= instID or enabled == false then
		impl.Release(ownerKey)
		return nil
	end
	EnsureMotionFrame()
	local now = GetTime()
	local knownMoving = GetPlayerMovingKnown()
	if knownMoving == true then
		OnStartMoving(now)
	elseif knownMoving == false and POS.moving and (now - (POS.moveStart or 0)) > 0.2 then
		OnStopMoving(now)
	end
	local wx, wy, wz, heading, age
	local usedTrilateration = false
	if UnitPosition ~= nil then
		local nx, ny = UnitPosition("player")
		if not IsSecret(nx) and not IsSecret(ny) and type(nx) == "number" and type(ny) == "number" then
			impl.Release(ownerKey)
			wx, wy, age = nx, ny, 0
		end
	end
	if wx == nil then
		usedTrilateration = true
		impl.Request(ownerKey, curInst)
		local fx, fy, fz, fhead, fage = impl.Get()
		if fx ~= nil and fage ~= nil and fage <= POS_MAX_AGE then
			wx, wy, wz, heading, age = fx, fy, fz, fhead, fage
		end
	end
	if wx == nil then return nil end
	local liveFacing = nil
	if GetPlayerFacing ~= nil then
		local f = GetPlayerFacing()
		if not IsSecret(f) and type(f) == "number" then liveFacing = f end
	end
	local facing = liveFacing
	if facing == nil then facing = heading end
	local movedLongEnough = POS.moving == true and (POS.moveStart or 0) > 0 and (now - POS.moveStart) >= CFG.arrowDelay
	local showArrow = false
	if movedLongEnough and facing ~= nil then
		if liveFacing ~= nil then
			showArrow = true
		elseif usedTrilateration then
			local ht = POS.fix.headingTime or 0
			if ht > 0 and ht >= POS.motionSince and (now - ht) <= CFG.headingMaxAge then
				showArrow = true
			end
		end
	end
	return wx, wy, wz, facing, age, showArrow
end

local grp = {}

function grp.GetChannel()
	if LE_PARTY_CATEGORY_INSTANCE ~= nil and IsInGroup ~= nil and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then return "INSTANCE_CHAT" end
	if IsInRaid ~= nil and IsInRaid() then return "RAID" end
	if IsInGroup ~= nil and IsInGroup() then return "PARTY" end
	return nil
end

function grp.IsRaidSize()
	if GetNumGroupMembers == nil then return false end
	local n = GetNumGroupMembers()
	if IsSecret(n) or type(n) ~= "number" then return false end
	return n > 5
end

function grp.IsChatLocked()
	if C_ChatInfo ~= nil and C_ChatInfo.InChatMessagingLockdown ~= nil then
		local ok, locked = pcall(C_ChatInfo.InChatMessagingLockdown)
		if ok and locked == true then return true end
	end
	return false
end

function grp.Send(msg, now)
	if msg == nil or now < (GROUP.sendBackoff or 0) then return false end
	if C_ChatInfo == nil or C_ChatInfo.SendAddonMessage == nil then return false end
	if grp.IsChatLocked() then return false end
	local ch = grp.GetChannel()
	if ch == nil then return false end
	local ok, res = pcall(C_ChatInfo.SendAddonMessage, GROUP_PREFIX, msg, ch)
	if not ok or (type(res) == "number" and res ~= 0) then
		GROUP.sendBackoff = now + 2.5
		return false
	end
	return true
end

function grp.IsSelfSender(sender)
	if type(sender) ~= "string" or sender == "" then return true end
	if D4.GetPlayerCharacterKey ~= nil then
		local key, ownName = D4:GetPlayerCharacterKey()
		if key ~= nil and (sender == key or sender == ownName) then return true end
	end
	if UnitFullName ~= nil then
		local name, realm = UnitFullName("player")
		if not IsSecret(name) and not IsSecret(realm) and type(name) == "string" and name ~= "" and (sender == name or (type(realm) == "string" and realm ~= "" and sender == name .. "-" .. realm)) then
			return true
		end
	end
	if UnitName ~= nil then
		local first, second = UnitName("player", true)
		if not IsSecret(first) and type(first) == "string" and first ~= "" then
			if sender == first then return true end
			if not IsSecret(second) and type(second) == "string" and second ~= "" and (sender == first .. " " .. second or sender == first .. "-" .. second) then
				return true
			end
		end
	end
	return false
end

function grp.RebuildRoster()
	GROUP.rosterDirty = false
	local r = GROUP.roster
	wipe(r)
	if grp.GetChannel() == nil then return end
	local isRaid = IsInRaid ~= nil and IsInRaid()
	local count = isRaid and (GetNumGroupMembers ~= nil and GetNumGroupMembers() or 0) or 4
	if IsSecret(count) or type(count) ~= "number" or count <= 0 then return end
	local prefix = isRaid and "raid" or "party"
	for i = 1, count do
		local unit = prefix .. i
		if (UnitExists == nil or UnitExists(unit)) and (UnitIsUnit == nil or not UnitIsUnit(unit, "player")) then
			if UnitFullName ~= nil then
				local fn, fr = UnitFullName(unit)
				if not IsSecret(fn) and type(fn) == "string" and fn ~= "" then
					r[strlower(fn)] = unit
					if not IsSecret(fr) and type(fr) == "string" and fr ~= "" then
						r[strlower(fn .. "-" .. fr)] = unit
					end
				end
			end
			if UnitName ~= nil then
				local n1, n2 = UnitName(unit, true)
				if not IsSecret(n1) and type(n1) == "string" and n1 ~= "" then
					r[strlower(n1)] = unit
					if not IsSecret(n2) and type(n2) == "string" and n2 ~= "" then
						r[strlower(n1 .. " " .. n2)] = unit
						r[strlower(n1 .. "-" .. n2)] = unit
					end
				end
			end
		end
	end
end

function grp.FindUnit(sender)
	if GROUP.rosterDirty then grp.RebuildRoster() end
	if type(sender) ~= "string" or sender == "" then return nil end
	local r = GROUP.roster
	local u = r[strlower(sender)]
	if u ~= nil then return u end
	local short = strmatch(sender, "^([^%-]+)")
	if short ~= nil and short ~= "" then return r[strlower(short)] end
	return nil
end

grp.style = {
	["mask"] = "Interface\\CharacterFrame\\TempPortraitAlphaMask",
	["crownAtlas"] = "UI-HUD-UnitFrame-Player-Group-LeaderIcon",
	["crownTex"] = "Interface\\GroupFrame\\UI-Group-LeaderIcon",
	["deadMark"] = "Interface\\RaidFrame\\ReadyCheck-NotReady",
	["taxiHorde"] = 132268,
	["taxiAlliance"] = 132239,
	["raceAliases"] = {
		["scourge"] = "undead",
		["highmountaintauren"] = "highmountain",
		["lightforgeddraenei"] = "lightforged",
		["zandalaritroll"] = "zandalari",
		["harronir"] = "haranir",
		["earthendwarf"] = "earthen",
	},
}

function grp.HasAtlas(name)
	return name ~= nil and C_Texture ~= nil and C_Texture.GetAtlasInfo ~= nil and C_Texture.GetAtlasInfo(name) ~= nil
end

function grp.GetCrownMarkup()
	if CreateAtlasMarkup ~= nil and grp.HasAtlas(grp.style.crownAtlas) then
		return CreateAtlasMarkup(grp.style.crownAtlas, 14, 14) .. " "
	end
	return "|T" .. grp.style.crownTex .. ":12:12:0:0|t "
end

function grp.GetRaceAtlas(race, sex)
	if type(race) ~= "string" or race == "" then return nil end
	local r = strlower(race)
	local gender = sex == 3 and "female" or "male"
	local alias = grp.style.raceAliases[r]
	local candidates = alias ~= nil and {r, alias} or {r}
	for i = 1, #candidates do
		local suffix = candidates[i] .. "-" .. gender
		local a128 = "raceicon128-" .. suffix
		if grp.HasAtlas(a128) then return a128 end
		local a64 = "raceicon-" .. suffix
		if grp.HasAtlas(a64) then return a64 end
	end
	return nil
end

function grp.GetTaxiIcon(faction)
	if faction == "Horde" then return grp.style.taxiHorde end
	if faction == "Alliance" then return grp.style.taxiAlliance end
	if UnitFactionGroup ~= nil then
		local pf = UnitFactionGroup("player")
		if pf == "Horde" then return grp.style.taxiHorde end
		if pf == "Alliance" then return grp.style.taxiAlliance end
	end
	return nil
end

function grp.GetUnitMeta(unit, fallbackName, fallbackClass, fallbackRace, fallbackSex)
	local name = fallbackName
	local class = fallbackClass
	local race = fallbackRace
	local sex = fallbackSex
	local faction = nil
	local taxi = false
	local ghost = false
	local dead = false
	local leader = false
	local online = true
	if unit ~= nil then
		if UnitIsConnected ~= nil then
			local c = UnitIsConnected(unit)
			if not IsSecret(c) and c == false then online = false end
		end
		if UnitName ~= nil then
			local un = UnitName(unit)
			if not IsSecret(un) and type(un) == "string" and un ~= "" then name = un end
		end
		if UnitClass ~= nil then
			local _, uc = UnitClass(unit)
			if not IsSecret(uc) and type(uc) == "string" and uc ~= "" then class = uc end
		end
		if UnitRace ~= nil then
			local _, ur = UnitRace(unit)
			if not IsSecret(ur) and type(ur) == "string" and ur ~= "" then race = ur end
		end
		if UnitSex ~= nil then
			local us = UnitSex(unit)
			if not IsSecret(us) and type(us) == "number" then sex = us end
		end
		if UnitFactionGroup ~= nil then
			local uf = UnitFactionGroup(unit)
			if not IsSecret(uf) and type(uf) == "string" and uf ~= "" then faction = uf end
		end
		if UnitOnTaxi ~= nil then
			local ut = UnitOnTaxi(unit)
			if not IsSecret(ut) and (ut == true or ut == 1) then taxi = true end
		end
		if UnitIsGhost ~= nil then
			local ug = UnitIsGhost(unit)
			if not IsSecret(ug) and (ug == true or ug == 1) then ghost = true end
		end
		if UnitIsDeadOrGhost ~= nil then
			local d = UnitIsDeadOrGhost(unit)
			if not IsSecret(d) and d == true then dead = true end
		end
		if UnitIsGroupLeader ~= nil then
			local l = UnitIsGroupLeader(unit)
			if not IsSecret(l) and l == true then leader = true end
		end
	end
	return name, class, dead, leader, online, race, sex, faction, taxi, ghost
end

function grp.GetClassRGB(class, dead, ghost)
	if ghost then return 0.55, 0.55, 0.55 end
	if class == nil or class == "" then return 0.75, 0.85, 1 end
	if D4.GetClassColor ~= nil then
		local r, g, b = D4:GetClassColor(class)
		if r ~= nil and g ~= nil and b ~= nil then return r, g, b end
	end
	local tab = CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS
	local c = tab ~= nil and tab[class] or nil
	if c ~= nil then return c.r or 1, c.g or 1, c.b or 1 end
	return 0.75, 0.85, 1
end

function grp.StopSharing()
	GROUP.watchUntil = 0
	GROUP.forceSend = false
	impl.Release(GROUP_LEASE)
	if reg.groupTicker ~= nil then reg.groupTicker:Hide() end
end

function grp.ShareTick(now)
	if GROUP.shareEnabled == false or grp.GetChannel() == nil then
		grp.StopSharing()
		return
	end
	local curInst = GetCurrentInstanceID()
	if curInst == nil or now >= (GROUP.watchUntil or 0) then
		grp.StopSharing()
		return
	end
	local wx, wy, wz, facing, _, showArrow = impl.GetLive(GROUP_LEASE, curInst, true)
	if wx == nil or wy == nil then return end
	local isRaid = grp.IsRaidSize()
	local minGap = isRaid and 2.5 or 1.2
	local idleGap = isRaid and 10.0 or 6.0
	local dt = now - (GROUP.lastSendTime or 0)
	if dt < minGap then return end
	local moving = showArrow == true
	local shouldSend = GROUP.forceSend or GROUP.lastSendInst ~= curInst or dt >= idleGap or GROUP.lastSendMoving ~= moving
	if not shouldSend and GROUP.lastSendX ~= nil and GROUP.lastSendY ~= nil then
		local dx = wx - GROUP.lastSendX
		local dy = wy - GROUP.lastSendY
		if (dx * dx + dy * dy) >= 4 then
			shouldSend = true
		elseif moving and facing ~= nil and (GROUP.lastSendFacing == nil or math.abs(facing - GROUP.lastSendFacing) >= 0.35) then
			shouldSend = true
		end
	elseif not shouldSend then
		shouldSend = true
	end
	if not shouldSend then return end
	local classToken = ""
	if UnitClass ~= nil then
		local _, c = UnitClass("player")
		if not IsSecret(c) and type(c) == "string" then classToken = c end
	end
	local raceToken = ""
	if UnitRace ~= nil then
		local _, r = UnitRace("player")
		if not IsSecret(r) and type(r) == "string" then raceToken = r end
	end
	local sexNum = 2
	if UnitSex ~= nil then
		local s = UnitSex("player")
		if not IsSecret(s) and type(s) == "number" then sexNum = s end
	end
	local faceStr = (moving and facing ~= nil) and format("%.2f", facing) or ""
	local payload = format("P:%d:%.1f:%.1f:%.1f:%s:%d:%s:%s:%d", curInst, wx, wy, wz or 0, faceStr, moving and 1 or 0, classToken, raceToken, sexNum)
	if grp.Send(payload, now) then
		GROUP.lastSendTime = now
		GROUP.lastSendInst = curInst
		GROUP.lastSendX = wx
		GROUP.lastSendY = wy
		GROUP.lastSendZ = wz or 0
		GROUP.lastSendFacing = moving and facing or nil
		GROUP.lastSendMoving = moving
		GROUP.forceSend = false
	end
end

function grp.EnsureTicker()
	if reg.groupTicker == nil then
		if CreateFrame == nil then return nil end
		local t = CreateFrame("Frame")
		t:Hide()
		reg.groupTicker = t
	end
	reg.groupTicker:SetScript("OnUpdate", function(_, elapsed)
		GROUP.elapsed = (GROUP.elapsed or 0) + elapsed
		if GROUP.elapsed < 0.3 then return end
		GROUP.elapsed = 0
		grp.ShareTick(GetTime())
	end)
	return reg.groupTicker
end

function grp.NotifyWatch(instID)
	if instID == nil or grp.GetChannel() == nil then return end
	local curInst = GetCurrentInstanceID()
	if curInst == nil or curInst ~= instID then return end
	local now = GetTime()
	local watchGap = grp.IsRaidSize() and 12 or 8
	if (GROUP.lastWatchInst ~= instID or (now - (GROUP.lastWatchSent or 0)) >= watchGap) and grp.Send("W:" .. tostring(instID), now) then
		GROUP.lastWatchSent = now
		GROUP.lastWatchInst = instID
	end
end

function grp.OnAddonMessage(prefix, msg, dist, sender)
	if IsSecret(prefix) or IsSecret(msg) or IsSecret(dist) or IsSecret(sender) then return end
	if prefix ~= GROUP_PREFIX then return end
	if dist ~= "PARTY" and dist ~= "RAID" and dist ~= "INSTANCE_CHAT" then return end
	if type(msg) ~= "string" or type(sender) ~= "string" or msg == "" or #msg > 160 then return end
	if grp.IsSelfSender(sender) then return end
	local now = GetTime()
	local tag = strsub(msg, 1, 2)
	if tag == "W:" then
		if GROUP.shareEnabled == false then return end
		local reqInst = tonumber(strsub(msg, 3))
		local curInst = GetCurrentInstanceID()
		if reqInst == nil or curInst == nil or reqInst ~= curInst then return end
		local ttl = grp.IsRaidSize() and 22 or 15
		if (now + ttl) > (GROUP.watchUntil or 0) then GROUP.watchUntil = now + ttl end
		GROUP.forceSend = true
		local ticker = grp.EnsureTicker()
		if ticker ~= nil and not ticker:IsShown() then ticker:Show() end
		grp.ShareTick(now)
	elseif tag == "P:" then
		local _, instStr, xStr, yStr, zStr, faceStr, movStr, clsStr, raceStr, sexStr = strsplit(":", msg)
		local instID = tonumber(instStr)
		local x = tonumber(xStr)
		local y = tonumber(yStr)
		if instID == nil or x == nil or y == nil or x ~= x or y ~= y then return end
		local z = tonumber(zStr) or 0
		local facing = (faceStr ~= nil and faceStr ~= "") and tonumber(faceStr) or nil
		local moving = movStr == "1"
		local sex = tonumber(sexStr)
		local short = strmatch(sender, "^([^%-]+)") or sender
		local key = strlower(short)
		local peer = GROUP.peers[key]
		if peer == nil then
			peer = {
				["key"] = key,
				["sender"] = sender,
				["name"] = short,
				["class"] = clsStr or "",
				["race"] = raceStr or "",
				["sex"] = sex,
				["instID"] = instID,
				["prevX"] = x,
				["prevY"] = y,
				["targetX"] = x,
				["targetY"] = y,
				["z"] = z,
				["lerpStart"] = now,
				["lerpDur"] = 0,
				["facing"] = facing,
				["moving"] = moving,
				["time"] = now,
			}
			GROUP.peers[key] = peer
		else
			local curX = peer.targetX
			local curY = peer.targetY
			if peer.lerpDur > 0 then
				local f = math.min(1, math.max(0, (now - peer.lerpStart) / peer.lerpDur))
				curX = peer.prevX + (peer.targetX - peer.prevX) * f
				curY = peer.prevY + (peer.targetY - peer.prevY) * f
			end
			local dt = now - (peer.time or now)
			local dx = x - curX
			local dy = y - curY
			if peer.instID == instID and (dx * dx + dy * dy) < 1600 and dt > 0.05 and dt < 12 then
				peer.prevX = curX
				peer.prevY = curY
				peer.lerpStart = now
				peer.lerpDur = math.min(0.6, math.max(0.18, dt * 0.45))
			else
				peer.prevX = x
				peer.prevY = y
				peer.lerpStart = now
				peer.lerpDur = 0
			end
			peer.sender = sender
			peer.name = short
			if clsStr ~= nil and clsStr ~= "" then peer.class = clsStr end
			if raceStr ~= nil and raceStr ~= "" then peer.race = raceStr end
			if sex ~= nil then peer.sex = sex end
			peer.instID = instID
			peer.targetX = x
			peer.targetY = y
			peer.z = z
			peer.facing = facing
			peer.moving = moving
			peer.time = now
		end
	end
end

function grp.EnsureEventFrame()
	if C_ChatInfo ~= nil and C_ChatInfo.RegisterAddonMessagePrefix ~= nil then
		pcall(C_ChatInfo.RegisterAddonMessagePrefix, GROUP_PREFIX)
	end
	if reg.groupFrame == nil then
		if CreateFrame == nil then return nil end
		local gf = CreateFrame("Frame")
		pcall(gf.RegisterEvent, gf, "CHAT_MSG_ADDON")
		pcall(gf.RegisterEvent, gf, "GROUP_ROSTER_UPDATE")
		pcall(gf.RegisterEvent, gf, "PLAYER_ENTERING_WORLD")
		reg.groupFrame = gf
	end
	reg.groupFrame:SetScript("OnEvent", function(_, event, ...)
		if event == "CHAT_MSG_ADDON" then
			grp.OnAddonMessage(...)
		elseif event == "GROUP_ROSTER_UPDATE" then
			GROUP.rosterDirty = true
			if grp.GetChannel() == nil then
				wipe(GROUP.peers)
				grp.StopSharing()
			end
		elseif event == "PLAYER_ENTERING_WORLD" then
			GROUP.rosterDirty = true
			if GetCurrentInstanceID() == nil or grp.GetChannel() == nil then
				wipe(GROUP.peers)
				grp.StopSharing()
			end
		end
	end)
	return reg.groupFrame
end

local grpScratch = {}
local grpSeen = {}

function impl.SetGroupShareEnabled(enabled)
	GROUP.shareEnabled = enabled ~= false
	if GROUP.shareEnabled == false then
		grp.StopSharing()
	end
end

function grp.CollectDirect(instID, out)
	if UnitPosition == nil then return 0 end
	local isRaid = IsInRaid ~= nil and IsInRaid()
	local count = isRaid and (GetNumGroupMembers ~= nil and GetNumGroupMembers() or 0) or 4
	if IsSecret(count) or type(count) ~= "number" or count <= 0 then return 0 end
	local prefix = isRaid and "raid" or "party"
	local n = 0
	for i = 1, count do
		local unit = prefix .. i
		local validUnit = (UnitExists == nil or UnitExists(unit)) and (UnitIsUnit == nil or not UnitIsUnit(unit, "player"))
		if validUnit then
			local nx, ny, nz, uInst = UnitPosition(unit)
			local validPos = not IsSecret(nx) and not IsSecret(ny) and type(nx) == "number" and type(ny) == "number" and (uInst == nil or IsSecret(uInst) or uInst == instID)
			if validPos then
				local uName, uClass, uDead, uLeader, uOnline, uRace, uSex, uFaction, uTaxi, uGhost = grp.GetUnitMeta(unit, unit, "")
				if uOnline then
					local key = strlower(uName or unit)
					grpSeen[key] = true
					n = n + 1
					local row = out[n]
					if row == nil then
						row = {}
						out[n] = row
					end
					row.key = key
					row.name = uName
					row.class = uClass
					row.race = uRace
					row.sex = uSex
					row.faction = uFaction
					row.taxi = uTaxi
					row.ghost = uGhost
					row.x = nx
					row.y = ny
					row.z = (not IsSecret(nz) and type(nz) == "number") and nz or 0
					row.facing = nil
					row.moving = false
					row.dead = uDead
					row.leader = uLeader
				end
			end
		end
	end
	return n
end

function impl.CollectGroupMembers(instID, out)
	if instID == nil or grp.GetChannel() == nil then return 0 end
	local now = GetTime()
	wipe(grpSeen)
	local n = grp.CollectDirect(instID, out)
	local maxAge = grp.IsRaidSize() and 30 or 20
	for key, peer in pairs(GROUP.peers) do
		if (now - (peer.time or 0)) > maxAge then
			GROUP.peers[key] = nil
		elseif peer.instID == instID and not grpSeen[key] then
			local unit = grp.FindUnit(peer.sender) or grp.FindUnit(peer.name)
			local uName, uClass, uDead, uLeader, uOnline, uRace, uSex, uFaction, uTaxi, uGhost = grp.GetUnitMeta(unit, peer.name, peer.class, peer.race, peer.sex)
			if uOnline and not grpSeen[strlower(uName or key)] then
				local ix = peer.targetX
				local iy = peer.targetY
				if peer.lerpDur > 0 then
					local f = math.min(1, math.max(0, (now - peer.lerpStart) / peer.lerpDur))
					ix = peer.prevX + (peer.targetX - peer.prevX) * f
					iy = peer.prevY + (peer.targetY - peer.prevY) * f
				end
				n = n + 1
				local row = out[n]
				if row == nil then
					row = {}
					out[n] = row
				end
				row.key = key
				row.name = uName
				row.class = uClass
				row.race = uRace
				row.sex = uSex
				row.faction = uFaction
				row.taxi = uTaxi
				row.ghost = uGhost
				row.x = ix
				row.y = iy
				row.z = peer.z or 0
				row.facing = peer.facing
				row.moving = peer.moving == true
				row.dead = uDead
				row.leader = uLeader
			end
		end
	end
	return n
end

function impl.NotifyGroupWatch(instID)
	grp.EnsureEventFrame()
	grp.NotifyWatch(instID)
end

if reg.version < VERSION then
	reg.version = VERSION
	reg.impl = impl
	if POS.moveStart == nil then POS.moveStart = 0 end
	if POS.fix.headingTime == nil then POS.fix.headingTime = 0 end
	if reg.motionFrame ~= nil then
		BindMotionScript(reg.motionFrame)
	else
		EnsureMotionFrame()
	end
	grp.EnsureEventFrame()
	if reg.groupTicker ~= nil then grp.EnsureTicker() end
end

function D4:SetInstanceGroupPosEnabled(enabled)
	reg.impl.SetGroupShareEnabled(enabled)
end

function D4:RegisterInstancePosData(data)
	if type(data) == "table" then reg.data = data end
end

function D4:IsInstancePositionAvailable()
	return reg.impl.IsAvailable()
end

function D4:IsInstancePositionScanning()
	return POS.active == true
end

function D4:RequestInstancePosition(ownerKey, instID)
	return reg.impl.Request(ownerKey, instID)
end

function D4:ReleaseInstancePosition(ownerKey)
	reg.impl.Release(ownerKey)
end

function D4:GetInstancePosition()
	return reg.impl.Get()
end

function D4:GetInstanceArtBounds(artKey)
	return reg.impl.GetArtBounds(artKey)
end

function D4:GetLiveInstancePosition(ownerKey, instID, enabled)
	return reg.impl.GetLive(ownerKey, instID, enabled)
end

local playerRow = {}

local function BuildPortraitPin(parent, level, sz, enableMouse)
	local pin = CreateFrame("Frame", nil, parent)
	local ringInset = math.max(1, sz * 0.055)
	local innerInset = math.max(2.6, sz * 0.16)
	local iconPad = math.max(0.8, (sz - sz * 0.32) * 0.085)
	local markInset = math.max(1, sz * 0.05)
	local crownSize = sz * 0.58
	local crownOverlap = sz * 0.24
	local ptrSize = sz * 2.1
	pin:SetSize(sz, sz)
	pin:EnableMouse(enableMouse == true)
	if enableMouse == true and pin.SetMouseClickEnabled ~= nil then pcall(pin.SetMouseClickEnabled, pin, false) end
	if level ~= nil then pin:SetFrameLevel(level) end
	local pointer = pin:CreateTexture(nil, "BACKGROUND", nil, -1)
	pointer:SetSize(ptrSize, ptrSize)
	pointer:SetPoint("CENTER", pin, "CENTER", 0, 0)
	pointer:SetTexture(TEX_POINTER)
	pointer:Hide()
	local outer = pin:CreateTexture(nil, "BACKGROUND", nil, 0)
	outer:SetAllPoints(pin)
	outer:SetTexture(grp.style.mask)
	outer:SetVertexColor(0, 0, 0, 0.92)
	local ring = pin:CreateTexture(nil, "BACKGROUND", nil, 1)
	ring:SetPoint("TOPLEFT", pin, "TOPLEFT", ringInset, -ringInset)
	ring:SetPoint("BOTTOMRIGHT", pin, "BOTTOMRIGHT", -ringInset, ringInset)
	ring:SetTexture(grp.style.mask)
	local innerBg = pin:CreateTexture(nil, "BORDER", nil, 0)
	innerBg:SetPoint("TOPLEFT", pin, "TOPLEFT", innerInset, -innerInset)
	innerBg:SetPoint("BOTTOMRIGHT", pin, "BOTTOMRIGHT", -innerInset, innerInset)
	innerBg:SetTexture(grp.style.mask)
	innerBg:SetVertexColor(0.06, 0.06, 0.08, 1)
	local mask = pin:CreateMaskTexture()
	mask:SetTexture(grp.style.mask, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	mask:SetAllPoints(innerBg)
	local portrait = pin:CreateTexture(nil, "ARTWORK", nil, 0)
	portrait:SetAllPoints(innerBg)
	portrait:AddMaskTexture(mask)
	portrait:Hide()
	local icon = pin:CreateTexture(nil, "ARTWORK", nil, 0)
	icon:SetPoint("TOPLEFT", innerBg, "TOPLEFT", -iconPad, iconPad)
	icon:SetPoint("BOTTOMRIGHT", innerBg, "BOTTOMRIGHT", iconPad, -iconPad)
	icon:AddMaskTexture(mask)
	icon:Hide()
	local fallback = pin:CreateTexture(nil, "ARTWORK", nil, 0)
	fallback:SetAllPoints(innerBg)
	fallback:SetTexture(grp.style.mask)
	fallback:AddMaskTexture(mask)
	fallback:Hide()
	local deadMark = pin:CreateTexture(nil, "OVERLAY", nil, 1)
	deadMark:SetTexture(grp.style.deadMark)
	deadMark:SetPoint("TOPLEFT", innerBg, "TOPLEFT", markInset, -markInset)
	deadMark:SetPoint("BOTTOMRIGHT", innerBg, "BOTTOMRIGHT", -markInset, markInset)
	deadMark:Hide()
	local crown = pin:CreateTexture(nil, "OVERLAY", nil, 2)
	crown:SetSize(crownSize, crownSize)
	crown:SetPoint("BOTTOM", pin, "TOP", 0, -crownOverlap)
	if crown.SetAtlas ~= nil and grp.HasAtlas(grp.style.crownAtlas) then
		crown:SetAtlas(grp.style.crownAtlas)
	else
		crown:SetTexture(grp.style.crownTex)
	end
	crown:Hide()
	pin.pointer = pointer
	pin.outer = outer
	pin.ring = ring
	pin.innerBg = innerBg
	pin.mask = mask
	pin.portrait = portrait
	pin.icon = icon
	pin.fallback = fallback
	pin.deadMark = deadMark
	pin.crown = crown
	pin.circle = ring
	pin.tex = pointer
	pin:Hide()
	return pin
end

local function ApplyPortraitPin(pin, row)
	local isGhost = row.ghost == true
	local isDead = row.dead == true and not isGhost
	local r, g, b = grp.GetClassRGB(row.class, isDead, isGhost)
	if pin._d4R ~= r or pin._d4G ~= g or pin._d4B ~= b then
		pin._d4R = r
		pin._d4G = g
		pin._d4B = b
		pin.ring:SetVertexColor(r, g, b, 1)
		pin.pointer:SetVertexColor(r, g, b, 1)
	end
	local taxiIcon = row.taxi and grp.GetTaxiIcon(row.faction) or nil
	if taxiIcon ~= nil then
		if pin._d4Tex ~= taxiIcon then
			pin._d4Tex = taxiIcon
			pin.icon:SetTexture(taxiIcon)
		end
		if pin.icon.SetDesaturated ~= nil then pin.icon:SetDesaturated(false) end
		pin.icon:SetVertexColor(1, 1, 1, 1)
		pin.icon:Show()
		pin.portrait:Hide()
		pin.fallback:Hide()
		pin.deadMark:Hide()
	else
		local atlas = grp.GetRaceAtlas(row.race, row.sex)
		if atlas ~= nil and pin.portrait.SetAtlas ~= nil then
			if pin._d4Atlas ~= atlas then
				pin._d4Atlas = atlas
				pcall(pin.portrait.SetAtlas, pin.portrait, atlas)
			end
			if pin.portrait.SetDesaturated ~= nil then pin.portrait:SetDesaturated(isGhost or isDead) end
			if isGhost then
				pin.portrait:SetVertexColor(0.75, 0.75, 0.75, 1)
			elseif isDead then
				pin.portrait:SetVertexColor(0.65, 0.65, 0.65, 1)
			else
				pin.portrait:SetVertexColor(1, 1, 1, 1)
			end
			pin.portrait:Show()
			pin.icon:Hide()
			pin.fallback:Hide()
		else
			pin.fallback:SetVertexColor(r, g, b, isDead and 0.65 or 1)
			pin.fallback:Show()
			pin.portrait:Hide()
			pin.icon:Hide()
		end
		pin.deadMark:SetShown(isDead)
	end
	pin.crown:SetShown(row.leader == true)
	local wantPointer = row.moving == true and row.facing ~= nil and not isDead and not isGhost
	if wantPointer then
		if pin._d4Rot == nil or math.abs(row.facing - pin._d4Rot) > 0.005 then
			pin._d4Rot = row.facing
			pin.pointer:SetRotation(row.facing)
		end
		if not pin.pointer:IsShown() then pin.pointer:Show() end
	else
		if pin.pointer:IsShown() then pin.pointer:Hide() end
		pin._d4Rot = nil
	end
	pin._d4Name = row.name
	pin._d4Class = row.class
	pin._d4Dead = isDead
	pin._d4Ghost = isGhost
	pin._d4Leader = row.leader == true
end

function D4:CreateInstancePosArrow(parent, level, size)
	local a = BuildPortraitPin(parent, level, size or ARROW_SIZE, false)
	D4:SetInstancePosArrowState(a, nil, false)
	return a
end

function D4:SetInstancePosArrowState(arrow, facing, showArrow)
	if arrow == nil then return end
	local uName, uClass, uDead, uLeader, _, uRace, uSex, uFaction, uTaxi, uGhost = grp.GetUnitMeta("player", "", "")
	playerRow.name = uName
	playerRow.class = uClass
	playerRow.race = uRace
	playerRow.sex = uSex
	playerRow.faction = uFaction
	playerRow.taxi = uTaxi
	playerRow.ghost = uGhost
	playerRow.dead = uDead
	playerRow.leader = uLeader
	playerRow.facing = facing
	playerRow.moving = showArrow == true
	ApplyPortraitPin(arrow, playerRow)
end

function D4:HideInstancePosArrow(arrow, ownerKey)
	if arrow ~= nil then
		if arrow:IsShown() then arrow:Hide() end
		if arrow.pointer ~= nil and arrow.pointer:IsShown() then arrow.pointer:Hide() end
		arrow._d4X = nil
		arrow._d4Y = nil
		arrow._d4Rot = nil
	end
	if ownerKey ~= nil then reg.impl.Release(ownerKey) end
end

function D4:UpdateInstancePosArrow(arrow, artTex, artKey, ownerKey, enabled)
	if arrow == nil or artTex == nil or enabled == false then
		D4:HideInstancePosArrow(arrow, ownerKey)
		return false
	end
	local bounds = reg.impl.GetArtBounds(artKey)
	if bounds == nil then
		D4:HideInstancePosArrow(arrow, ownerKey)
		return false
	end
	local wx, wy, _, facing, _, showArrow = reg.impl.GetLive(ownerKey, bounds[1], enabled)
	if wx == nil then
		if arrow:IsShown() then arrow:Hide() end
		arrow._d4X = nil
		arrow._d4Y = nil
		arrow._d4Rot = nil
		return false
	end
	local dx = bounds[3] - bounds[2]
	local dy = bounds[5] - bounds[4]
	local aw = artTex:GetWidth() or 0
	local ah = artTex:GetHeight() or 0
	if dx <= 0 or dy <= 0 or aw <= 0 or ah <= 0 then
		if arrow:IsShown() then arrow:Hide() end
		return false
	end
	local u = (bounds[5] - wy) / dy
	local v = (bounds[3] - wx) / dx
	if u < -0.06 or u > 1.06 or v < -0.06 or v > 1.06 then
		if arrow:IsShown() then arrow:Hide() end
		arrow._d4X = nil
		arrow._d4Y = nil
		arrow._d4Rot = nil
		return false
	end
	local ax = u * aw
	local ay = -v * ah
	if arrow._d4X == nil or math.abs(ax - arrow._d4X) > 0.05 or math.abs(ay - arrow._d4Y) > 0.05 then
		arrow._d4X = ax
		arrow._d4Y = ay
		arrow:ClearAllPoints()
		arrow:SetPoint("CENTER", artTex, "TOPLEFT", ax, ay)
	end
	D4:SetInstancePosArrowState(arrow, facing, showArrow)
	if not arrow:IsShown() then arrow:Show() end
	return true
end

local function ShowGroupPinTooltip(pin)
	if GameTooltip == nil or pin == nil or pin._d4Layer == nil then return end
	local layer = pin._d4Layer
	GameTooltip:SetOwner(pin, "ANCHOR_RIGHT")
	local px = pin._d4X
	local py = pin._d4Y
	local shown = 0
	local function AddMemberLine(p)
		if p == nil or p._d4Name == nil or p._d4Name == "" then return end
		local r, g, b = grp.GetClassRGB(p._d4Class, p._d4Dead, p._d4Ghost)
		local text = p._d4Name
		if p._d4Leader then text = grp.GetCrownMarkup() .. text end
		if p._d4Ghost or p._d4Dead then text = text .. " (" .. (DEAD or "Dead") .. ")" end
		if shown == 0 then
			GameTooltip:SetText(text, r, g, b)
		else
			GameTooltip:AddLine(text, r, g, b)
		end
		shown = shown + 1
	end
	AddMemberLine(pin)
	if px ~= nil and py ~= nil then
		for i = 1, layer.activeCount or 0 do
			local other = layer.pins[i]
			if other ~= nil and other ~= pin and other:IsShown() and other._d4X ~= nil and other._d4Y ~= nil then
				local dx = other._d4X - px
				local dy = other._d4Y - py
				if (dx * dx + dy * dy) <= 256 then
					AddMemberLine(other)
				end
			end
		end
	end
	if shown > 0 then GameTooltip:Show() end
end

local function HideGroupPinTooltip(pin)
	if GameTooltip ~= nil and GameTooltip:IsOwned(pin) then GameTooltip:Hide() end
end

local function AcquireGroupPin(layer, index)
	local pin = layer.pins[index]
	if pin ~= nil then
		if layer.level ~= nil and pin:GetFrameLevel() ~= layer.level then pin:SetFrameLevel(layer.level) end
		return pin
	end
	pin = BuildPortraitPin(layer.parent, layer.level, layer.size or 22, true)
	pin._d4Layer = layer
	pin:SetScript("OnEnter", ShowGroupPinTooltip)
	pin:SetScript("OnLeave", HideGroupPinTooltip)
	layer.pins[index] = pin
	return pin
end

local function ApplyGroupPinVisual(pin, row)
	ApplyPortraitPin(pin, row)
end

function D4:CreateInstanceGroupLayer(parent, level, size)
	local sz = size ~= nil and math.max(18, math.floor(size * 0.92 + 0.5)) or 22
	return {
		["parent"] = parent,
		["level"] = level,
		["size"] = sz,
		["pins"] = {},
		["activeCount"] = 0,
	}
end

function D4:HideInstanceGroupPins(layer)
	if layer == nil then return end
	for i = 1, #layer.pins do
		local pin = layer.pins[i]
		if pin ~= nil then
			HideGroupPinTooltip(pin)
			if pin:IsShown() then pin:Hide() end
			pin._d4X = nil
			pin._d4Y = nil
			pin._d4Px = nil
			pin._d4Py = nil
			pin._d4Rot = nil
		end
	end
	layer.activeCount = 0
end

function D4:UpdateInstanceGroupPins(layer, artTex, artKey, enabled)
	if layer == nil or artTex == nil or enabled == false then
		D4:HideInstanceGroupPins(layer)
		return 0
	end
	local bounds = reg.impl.GetArtBounds(artKey)
	if bounds == nil then
		D4:HideInstanceGroupPins(layer)
		return 0
	end
	local instID = bounds[1]
	reg.impl.NotifyGroupWatch(instID)
	local count = reg.impl.CollectGroupMembers(instID, grpScratch)
	if count == 0 then
		D4:HideInstanceGroupPins(layer)
		return 0
	end
	local dx = bounds[3] - bounds[2]
	local dy = bounds[5] - bounds[4]
	local aw = artTex:GetWidth() or 0
	local ah = artTex:GetHeight() or 0
	if dx <= 0 or dy <= 0 or aw <= 0 or ah <= 0 then
		D4:HideInstanceGroupPins(layer)
		return 0
	end
	local shown = 0
	for i = 1, count do
		local row = grpScratch[i]
		local u = (bounds[5] - row.y) / dy
		local v = (bounds[3] - row.x) / dx
		if u >= -0.06 and u <= 1.06 and v >= -0.06 and v <= 1.06 then
			shown = shown + 1
			local pin = AcquireGroupPin(layer, shown)
			local ax = u * aw
			local ay = -v * ah
			if pin._d4X == nil or math.abs(ax - pin._d4X) > 0.05 or math.abs(ay - pin._d4Y) > 0.05 then
				pin._d4X = ax
				pin._d4Y = ay
				pin:ClearAllPoints()
				pin:SetPoint("CENTER", artTex, "TOPLEFT", ax, ay)
			end
			ApplyGroupPinVisual(pin, row)
			if not pin:IsShown() then pin:Show() end
		end
	end
	for i = shown + 1, #layer.pins do
		local pin = layer.pins[i]
		if pin ~= nil then
			HideGroupPinTooltip(pin)
			if pin:IsShown() then pin:Hide() end
			pin._d4X = nil
			pin._d4Y = nil
		end
	end
	layer.activeCount = shown
	return shown
end

function D4:LayoutInstanceGroupPlanPins(layer, canvas, tileScale)
	if layer == nil or canvas == nil or tileScale == nil or tileScale <= 0 then return end
	for i = 1, layer.activeCount or 0 do
		local pin = layer.pins[i]
		if pin ~= nil and pin:IsShown() and pin._d4Px ~= nil and pin._d4Py ~= nil then
			local ax = pin._d4Px * tileScale
			local ay = -pin._d4Py * tileScale
			if pin._d4X == nil or math.abs(ax - pin._d4X) > 0.05 or math.abs(ay - pin._d4Y) > 0.05 then
				pin._d4X = ax
				pin._d4Y = ay
				pin:ClearAllPoints()
				pin:SetPoint("CENTER", canvas, "TOPLEFT", ax, ay)
			end
		end
	end
end

function D4:UpdateInstanceGroupPlanPins(layer, canvas, mapData, instID, tileScale, enabled)
	if layer == nil or canvas == nil or mapData == nil or instID == nil or tileScale == nil or tileScale <= 0 or enabled == false then
		D4:HideInstanceGroupPins(layer)
		return 0
	end
	if mapData.wx == nil or mapData.wy == nil or mapData.ps == nil then
		D4:HideInstanceGroupPins(layer)
		return 0
	end
	reg.impl.NotifyGroupWatch(instID)
	local count = reg.impl.CollectGroupMembers(instID, grpScratch)
	if count == 0 then
		D4:HideInstanceGroupPins(layer)
		return 0
	end
	local shown = 0
	for i = 1, count do
		local row = grpScratch[i]
		local px = (mapData.wy - row.y) * mapData.ps
		local py = (mapData.wx - row.x) * mapData.ps
		if px >= -48 and px <= (mapData.w + 48) and py >= -48 and py <= (mapData.h + 48) then
			shown = shown + 1
			local pin = AcquireGroupPin(layer, shown)
			pin._d4Px = px
			pin._d4Py = py
			local ax = px * tileScale
			local ay = -py * tileScale
			if pin._d4X == nil or math.abs(ax - pin._d4X) > 0.05 or math.abs(ay - pin._d4Y) > 0.05 then
				pin._d4X = ax
				pin._d4Y = ay
				pin:ClearAllPoints()
				pin:SetPoint("CENTER", canvas, "TOPLEFT", ax, ay)
			end
			ApplyGroupPinVisual(pin, row)
			if not pin:IsShown() then pin:Show() end
		end
	end
	for i = shown + 1, #layer.pins do
		local pin = layer.pins[i]
		if pin ~= nil then
			HideGroupPinTooltip(pin)
			if pin:IsShown() then pin:Hide() end
			pin._d4X = nil
			pin._d4Y = nil
			pin._d4Px = nil
			pin._d4Py = nil
		end
	end
	layer.activeCount = shown
	return shown
end

function D4:PrintInstancePositionStatus()
	local avail = reg.impl.IsAvailable()
	local phaseNames = {[0] = "idle", [1] = "acquiring", [2] = "tracking", [3] = "sleeping"}
	local pName = phaseNames[POS.phase] or tostring(POS.phase)
	local leaseList = {}
	for k in pairs(reg.leases) do leaseList[#leaseList + 1] = k end
	local peerCount = 0
	for _ in pairs(GROUP.peers) do peerCount = peerCount + 1 end
	local watchLeft = math.max(0, (GROUP.watchUntil or 0) - GetTime())
	local f = POS.fix
	if f.valid then
		self:INFO(format("InstancePos: avail=%s active=%s phase=%s inst=%s leases=[%s] xyz=(%.1f, %.1f, %.1f) res=%.2f confirmed=%s groupShare=%s peers=%d watch=%.0fs", tostring(avail), tostring(POS.active), pName, tostring(POS.instID), table.concat(leaseList, ","), f.x, f.y, f.zMed, f.residual, tostring(f.confirmed), tostring(GROUP.shareEnabled ~= false), peerCount, watchLeft))
	else
		self:INFO(format("InstancePos: avail=%s active=%s phase=%s inst=%s leases=[%s] (no fix) groupShare=%s peers=%d watch=%.0fs", tostring(avail), tostring(POS.active), pName, tostring(POS.instID), table.concat(leaseList, ","), tostring(GROUP.shareEnabled ~= false), peerCount, watchLeft))
	end
end
