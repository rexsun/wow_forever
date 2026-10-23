local _, baseline = ...
local defaults = {
	["chat"] = {
		["height"] = 265.0,
		["width"] = 475.0,
		["x"] = 0.005375,
		["y"] = 0.028333,
	},
	["chatFontSize"] = 18.0,
	["cvars"] = {
		["cameraSavedDistance"] = "50.000000",
		["cameraSavedPitch"] = "30.576227",
		["cooldownViewerEnabled"] = "1",
		["enableMultiActionBars"] = "15",
		["mapFade"] = "0",
		["nameplateMaxAlpha"] = "1",
		["nameplateMaxAlphaDistance"] = "40",
		["nameplateMaxDistance"] = "41",
		["nameplateMaxScale"] = "1",
		["nameplateMinAlpha"] = "0.6",
		["nameplateMinAlphaDistance"] = "-100000",
		["nameplateMinScale"] = "1",
		["nameplateSelectedScale"] = "1",
		["nameplateTargetBehindMaxDistance"] = "30",
		["showQuestLevel"] = "1",
	},
	["euiPositions"] = {
		["partyUnlockPos"] = {
			["point"] = "CENTER",
			["relPoint"] = "CENTER",
			["x"] = -502.7777890157371,
			["y"] = -365,
		},
		["unlockPos"] = {
			["point"] = "CENTER",
			["relPoint"] = "CENTER",
			["x"] = -688.8889042867559,
			["y"] = -69.44444599664877,
		},
	},
	["layoutName"] = "YUI v3",
	["revision"] = 2,
}
for key, value in pairs(defaults) do baseline[key] = value end
