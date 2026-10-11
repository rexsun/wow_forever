local addonName, namespace = ...
local YUI = _G.YUI or namespace
local S, Assets = YUI and YUI.Sound, YUI and YUI.Assets
if not (S and S.RegisterSystemSounds and Assets) then return end
if S.systemSounds["sfx-gunshot-dry"] then return end
local product = YUI.GetAddonProductId and YUI:GetAddonProductId(addonName, "suite") or YUI.ProductId
local root = "Interface\\AddOns\\" .. addonName
if product ~= "suite" then root = root .. "\\CoreEmbed" end
Assets:RegisterBundleRoot("sfx-default", root .. "\\Media\\Bundles\\sfx-default")
S:RegisterSystemSounds("yui.sfx.default", {
    ["sfx-gunshot-dry"] = { label = "Gunshot - Dry", labelKey = "sound.effect.gunshot-dry", file = Assets:Bundle("sfx-default", "gunshot-dry.ogg") },
    ["sfx-gunshot-deep"] = { label = "Gunshot - Deep", labelKey = "sound.effect.gunshot-deep", file = Assets:Bundle("sfx-default", "gunshot-deep.ogg") },
    ["sfx-bell-metal"] = { label = "Bell - Metal", labelKey = "sound.effect.bell-metal", file = Assets:Bundle("sfx-default", "bell-metal.ogg") },
    ["sfx-bell-bright"] = { label = "Bell - Bright", labelKey = "sound.effect.bell-bright", file = Assets:Bundle("sfx-default", "bell-bright.ogg") },
    ["sfx-sonar-single"] = { label = "Sonar - Single", labelKey = "sound.effect.sonar-single", file = Assets:Bundle("sfx-default", "sonar-single.ogg") },
    ["sfx-sonar-double"] = { label = "Sonar - Double", labelKey = "sound.effect.sonar-double", file = Assets:Bundle("sfx-default", "sonar-double.ogg") },
    ["sfx-metal-light"] = { label = "Metal - Light", labelKey = "sound.effect.metal-light", file = Assets:Bundle("sfx-default", "metal-light.ogg") },
    ["sfx-metal-heavy"] = { label = "Metal - Heavy", labelKey = "sound.effect.metal-heavy", file = Assets:Bundle("sfx-default", "metal-heavy.ogg") },
    ["sfx-arc-sharp"] = { label = "Electric Arc - Sharp", labelKey = "sound.effect.arc-sharp", file = Assets:Bundle("sfx-default", "arc-sharp.ogg") },
    ["sfx-alarm-double"] = { label = "Alarm - Double Pulse", labelKey = "sound.effect.alarm-double", file = Assets:Bundle("sfx-default", "alarm-double.ogg") },
    ["sfx-alarm-siren"] = { label = "Alarm - Siren", labelKey = "sound.effect.alarm-siren", file = Assets:Bundle("sfx-default", "alarm-siren.ogg") },
    ["sfx-squeak-a"] = { label = "Squeaky Toy - A", labelKey = "sound.effect.squeak-a", file = Assets:Bundle("sfx-default", "squeak-a.ogg") },
    ["sfx-squeak-b"] = { label = "Squeaky Toy - B", labelKey = "sound.effect.squeak-b", file = Assets:Bundle("sfx-default", "squeak-b.ogg") },
    ["sfx-k98-bolt"] = { label = "K98 - Bolt Action", labelKey = "sound.effect.k98-bolt", file = Assets:Bundle("sfx-default", "k98-bolt.ogg") },
    ["sfx-shotgun-pump"] = { label = "Shotgun - Pump Action", labelKey = "sound.effect.shotgun-pump", file = Assets:Bundle("sfx-default", "shotgun-pump.ogg") },
    ["sfx-akm-burst"] = { label = "AKM - Burst", labelKey = "sound.effect.akm-burst", file = Assets:Bundle("sfx-default", "akm-burst.ogg") },
    ["sfx-shotgun-shot"] = { label = "20 Gauge Shotgun", labelKey = "sound.effect.shotgun-shot", file = Assets:Bundle("sfx-default", "shotgun-shot.ogg") },
    ["sfx-fire-burst"] = { label = "Fire - Burst", labelKey = "sound.effect.fire-burst", file = Assets:Bundle("sfx-default", "fire-burst.ogg") },
    ["sfx-guitar-short"] = { label = "Acoustic Guitar - Short", labelKey = "sound.effect.guitar-short", file = Assets:Bundle("sfx-default", "guitar-short.ogg") },
    ["sfx-glass-short"] = { label = "Glass - Short", labelKey = "sound.effect.glass-short", file = Assets:Bundle("sfx-default", "glass-short.ogg") },
})
