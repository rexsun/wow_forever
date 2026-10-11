-- Stable runtime facades. Only plain configuration tables are persisted.
local Context = {}
Context.__index = Context

function Context.New(model, getModel, id, configKey, getRoot, fields)
    local self = setmetatable({id=id, model=model, getModel=getModel,
        configKey=configKey, getRoot=getRoot, fields=fields or {}}, Context)
    self.config = setmetatable({}, {
        __index=function(_, key)
            local db = getModel()
            local instance = db.instances[self.id]
            if not instance then return nil end
            local common = self.fields[key]
            if common then
                local field = type(common) == "table" and common or nil
                local value = model.Resolve(db, self.id, field and field.key or common)
                if value ~= nil then
                    if field and field.fromCommon then return field.fromCommon(value) end
                    return value
                end
            end
            return instance.config[key]
        end,
        __newindex=function(_, key, value)
            local instance = getModel().instances[self.id]
            assert(instance, "missing-instance")
            local common = self.fields[key]
            if type(common) == "table" then
                local converted=common.toCommon(value)
                if converted~=model.Resolve(getModel(),self.id,common.key) then instance.appearance[common.key]=converted end
            elseif common then
                if value~=model.Resolve(getModel(),self.id,common) then instance.appearance[common]=value end
            else instance.config[key] = value end
        end,
    })
    self.root = setmetatable({}, {
        __index=function(_, key)
            if key == configKey then return self.config end
            if key == "fontFlags" then
                local value = model.Resolve(getModel(), self.id, "outline")
                if value == "NONE" or value == false then return "" end
                if value == true then return "OUTLINE" end
                return value
            elseif key == "fontOutline" then
                local value = model.Resolve(getModel(), self.id, "outline")
                if value ~= nil then return value ~= "NONE" and value ~= "" and value ~= false end
            elseif key == "fontShadow" then
                local value = model.Resolve(getModel(), self.id, "shadow")
                if value ~= nil then return value end
            end
            local root = getRoot()
            return root and root[key]
        end,
        __newindex=function(_, key, value)
            if key == configKey then
                if value == self.config then return end
                assert(type(value) == "table", "invalid-config")
                assert(model.IsSerializable(value), "invalid-config-values")
                getModel().instances[self.id].config = model.Copy(value)
            else
                error("instance-root-write:" .. tostring(key))
            end
        end,
    })
    return self
end

function Context:GetRoot() return self.root end
function Context:GetConfig() return self.config end
local owner=_G.YUI and _G.YUI.YBar
if owner then
    owner.LayoutLibraries=owner.LayoutLibraries or {}
    owner.LayoutLibraries.Context=Context
end
return Context
