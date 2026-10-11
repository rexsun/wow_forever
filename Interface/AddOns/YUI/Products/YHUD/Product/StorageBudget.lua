local YUI = _G.YUI
local YHUD = YUI and YUI.YHUD
if not YHUD then return end

local StorageBudget = YHUD.StorageBudget or {}
YHUD.StorageBudget = StorageBudget

StorageBudget.NORMAL_TARGET_NODES = 16384
StorageBudget.SOFT_WARNING_NODES = 32768
StorageBudget.HARD_NODE_LIMIT = 131072
StorageBudget.NORMAL_PRINTABLE_EXPORT_BYTES = 256 * 1024
StorageBudget.HARD_PRINTABLE_EXPORT_BYTES = 512 * 1024

local function CountValueNodes(value, active)
    if type(value) ~= "table" then return 0 end
    if active[value] then return nil, "cyclic-profile" end
    active[value] = true

    local count = 0
    for _, item in pairs(value) do
        count = count + 1
        local childCount, code = CountValueNodes(item, active)
        if childCount == nil then
            active[value] = nil
            return nil, code
        end
        count = count + childCount
    end

    active[value] = nil
    return count
end

function StorageBudget:CountNodes(profile)
    return CountValueNodes(profile, {})
end

local function NormalizePrintableBytes(value)
    if value == nil then return nil end
    value = tonumber(value)
    if not value or value < 0 or value >= math.huge
        or value ~= math.floor(value) then
        return nil, "invalid-printable-bytes"
    end
    return value
end

function StorageBudget:Evaluate(profile, printableBytes)
    local nodeCount, code = self:CountNodes(profile)
    if nodeCount == nil then return nil, code end

    printableBytes, code = NormalizePrintableBytes(printableBytes)
    if code then return nil, code end

    local status = "normal"
    if nodeCount > self.HARD_NODE_LIMIT
        or printableBytes and printableBytes > self.HARD_PRINTABLE_EXPORT_BYTES then
        status = "hard"
    elseif nodeCount > self.SOFT_WARNING_NODES
        or printableBytes and printableBytes > self.NORMAL_PRINTABLE_EXPORT_BYTES then
        status = "soft"
    end

    local withinNodeTarget = nodeCount <= self.NORMAL_TARGET_NODES
    local withinPrintableTarget = printableBytes == nil
        or printableBytes <= self.NORMAL_PRINTABLE_EXPORT_BYTES

    return {
        status = status,
        nodeCount = nodeCount,
        printableBytes = printableBytes,
        normalTargetNodes = self.NORMAL_TARGET_NODES,
        softWarningNodes = self.SOFT_WARNING_NODES,
        hardNodeLimit = self.HARD_NODE_LIMIT,
        normalPrintableExportBytes = self.NORMAL_PRINTABLE_EXPORT_BYTES,
        hardPrintableExportBytes = self.HARD_PRINTABLE_EXPORT_BYTES,
        withinNormalNodeTarget = withinNodeTarget,
        withinPrintableTarget = withinPrintableTarget,
        withinNormalTarget = withinNodeTarget and withinPrintableTarget,
        softWarning = status == "soft",
        hardLimitExceeded = status == "hard",
        canPersist = status ~= "hard",
    }
end
