local YUI=_G.YUI
local B=YUI and YUI.YBags
if not B then return end
local A,S=YUI.API.Bags,YUI.API.Security
local Unit = YUI.API.Unit
local H={dirty={}}
B.Holdings=H
function H:Queue(kind)
    if not B.active then return end
    self.dirty[kind]=true;B:QueueFlush()
end
function H:Flush()
    for kind in pairs(self.dirty) do
        self.dirty[kind]=nil
        local entries,complete
        if kind=="equipped" then entries=A.ReadEquipment(false)
        elseif kind=="bankBags" and B.bankOpen then entries=A.ReadEquipment(true)
        elseif kind=="mail" and self.mailOpen then entries,complete=A.ReadMail(false)
        elseif kind=="auctions" and self.auctionOpen and self.auctionReady then entries,complete=A.ReadAuctions()
        elseif kind=="void" and self.voidOpen then entries=A.ReadVoid() end
        if kind=="equipped" then self.equipmentPending=entries==nil or nil end
        if entries then B.Cache:WriteLocation(kind,entries,complete) end
    end
end
local function NormalizeRealm(value)
    local realm = Unit.NormalizeCharacterRealm(value)
    return realm and realm:lower()
end

local function MailTarget(recipient)
    recipient = S.SafeString(recipient)
    if not recipient then return end
    local name, explicitRealm = recipient:match("^(.-)%-(.+)$")
    name = (name or recipient):match("^%s*(.-)%s*$"):lower()
    local realm = NormalizeRealm(explicitRealm or Unit.GetRealmName())
    local useFullName = B.client == "forever" and not explicitRealm and not realm
        and not name:find("-", 1, true) and Unit.SplitForeverName(name)
    if name == "" or (not realm and not useFullName) then return end

    -- A regional full name can match a single character in this local account cache.
    local target
    for key, character in pairs(B.Cache.db.characters) do
        if character.client == B.client and character.source == B.Cache.source
            and type(character.name) == "string" and character.name:lower() == name
            and (useFullName or NormalizeRealm(character.realm) == realm) then
            if target then return end
            target = key
        end
    end
    return target
end
local function CaptureMail(recipient)
    if not B.active or not H.mailOpen then return end
    H.pendingMail=nil
    local target=MailTarget(recipient);if not target then return end
    local entries=A.ReadMail(true)
    if entries and #entries>0 then H.pendingMail={target=target,entries=entries,event="MAIL_SEND_SUCCESS"} end
end
local function CaptureReturn(index)
    if not B.active or not H.mailOpen then return end
    H.pendingMail=nil
    local recipient,entries=A.ReadReturnedMail(index)
    local target=MailTarget(recipient)
    if target and entries and #entries>0 then H.pendingMail={target=target,entries=entries,event="MAIL_SUCCESS"} end
end
function H:InstallMailHook()
    if not self.mailHook then self.mailHook=A.RegisterMailSend(CaptureMail) end
    if not self.returnHook then self.returnHook=A.RegisterMailReturn(CaptureReturn) end
end
function H:RequestAuctions()
    if self.auctionOpen and self.auctionPending then self.auctionDirty=true;return end
    if self.auctionOpen and not self.auctionPending then
        self.auctionPending=true
        if not A.RequestOwnedAuctions() then self.auctionPending=nil end
    end
end
function H:Interaction(event,kind)
    kind=S.SafeNumber(kind)
    local types=Enum and Enum.PlayerInteractionType or {}
    local opening=event=="PLAYER_INTERACTION_MANAGER_FRAME_SHOW"
    if kind~=nil and kind==types.Auctioneer then
        if opening then
            if not self.auctionOpen then self.auctionOpen=true;self.auctionReady=nil;self:RequestAuctions() end
        else self.auctionOpen,self.auctionReady,self.auctionPending,self.auctionDirty=nil,nil,nil,nil end
    elseif kind~=nil and kind==types.VoidStorageBanker then self.voidOpen=opening or nil;if opening then self:Queue("void") end end
end
function H:OnEvent(event,...)
    if event=="UNIT_INVENTORY_CHANGED" or event=="GET_ITEM_INFO_RECEIVED" then
        if self.equipmentPending then self:Queue("equipped") end
    elseif event=="PLAYER_EQUIPMENT_CHANGED" or event=="PLAYER_ENTERING_WORLD" then self:Queue("equipped")
    elseif event=="BAG_CONTAINER_UPDATE" then self:Queue("equipped");if B.bankOpen then self:Queue("bankBags") end
    elseif event=="BANKFRAME_OPENED" then self:Queue("bankBags")
    elseif event=="MAIL_SHOW" then self.mailOpen=true;self:InstallMailHook();self:Queue("mail")
    elseif event=="MAIL_INBOX_UPDATE" then if self.mailOpen then self:Queue("mail") end
    elseif event=="MAIL_CLOSED" then self.mailOpen=nil
    elseif event=="MAIL_SEND_SUCCESS" or event=="MAIL_SUCCESS" then
        local pending=self.pendingMail
        if pending and pending.event==event then self.pendingMail=nil;B.Cache:AddMail(pending.target,pending.entries) end
    elseif event=="MAIL_FAILED" then self.pendingMail=nil
    elseif event=="AUCTION_HOUSE_SHOW" then
        if not self.auctionOpen then self.auctionOpen=true;self.auctionReady=nil;self:RequestAuctions() end
    elseif event=="AUCTION_HOUSE_CLOSED" then self.auctionOpen,self.auctionReady,self.auctionPending,self.auctionDirty=nil,nil,nil,nil
    elseif event=="OWNED_AUCTIONS_UPDATED" or event=="AUCTION_OWNED_LIST_UPDATE" then
        if self.auctionOpen then
            self.auctionPending=nil;self.auctionReady=true;self:Queue("auctions")
            if self.auctionDirty then self.auctionDirty=nil;self:RequestAuctions() end
        end
    elseif event=="AUCTION_HOUSE_AUCTION_CREATED" or event=="AUCTION_CANCELED" then self:RequestAuctions()
    elseif event=="PLAYER_INTERACTION_MANAGER_FRAME_SHOW" or event=="PLAYER_INTERACTION_MANAGER_FRAME_HIDE" then self:Interaction(event,...)
    elseif event=="VOID_TRANSFER_DONE" and self.voidOpen then self:Queue("void") end
end
local function OnEvent(event,...) if B.active then H:OnEvent(event,...) end end
function H:Enable()
    self:InstallMailHook();self:Queue("equipped")
    self.listeners=0
    local function Listen(event,options)
        YUI.Event:On(event,OnEvent,self,options);self.listeners=self.listeners+1;B.Stats.listeners=B.Stats.listeners+1
    end
    for _,event in ipairs({"PLAYER_EQUIPMENT_CHANGED","PLAYER_ENTERING_WORLD","BAG_CONTAINER_UPDATE","BANKFRAME_OPENED","MAIL_SHOW","MAIL_INBOX_UPDATE","MAIL_CLOSED",
        "MAIL_SEND_SUCCESS","MAIL_SUCCESS","MAIL_FAILED","AUCTION_HOUSE_SHOW","AUCTION_HOUSE_CLOSED","PLAYER_INTERACTION_MANAGER_FRAME_SHOW","PLAYER_INTERACTION_MANAGER_FRAME_HIDE"}) do
        Listen(event)
    end
    if A.LegacyAuctions() then Listen("AUCTION_OWNED_LIST_UPDATE")
    else for _,event in ipairs({"OWNED_AUCTIONS_UPDATED","AUCTION_HOUSE_AUCTION_CREATED","AUCTION_CANCELED"}) do Listen(event) end end
    if type(CanUseVoidStorage)=="function" then Listen("VOID_TRANSFER_DONE") end
    Listen("UNIT_INVENTORY_CHANGED",{unit="player"});Listen("GET_ITEM_INFO_RECEIVED")
    if A.StorageOpen("mail") then self:OnEvent("MAIL_SHOW") end
    if A.StorageOpen("auctions") then self:OnEvent("AUCTION_HOUSE_SHOW") end
    if A.StorageOpen("void") then self.voidOpen=true;self:Queue("void") end
end
function H:Disable()
    YUI.Event:OffOwner(self)
    B.Stats.listeners=math.max(0,B.Stats.listeners-(self.listeners or 0));self.listeners=0
    self.dirty={};self.equipmentPending=nil;self.pendingMail=nil;self.mailOpen=nil;self.auctionOpen=nil;self.auctionReady=nil;self.auctionPending=nil;self.auctionDirty=nil;self.voidOpen=nil
end
