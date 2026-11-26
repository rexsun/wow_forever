local YUI = _G.YUI
local B = YUI and YUI.YBags
if not B then return end
local A=YUI.API.Bags
local Runtime={dirty={},kind={},waiting={},leases={},readable={},chargeSlots={}}
B.Runtime=Runtime
local OnViewError
local gearRevision=0
local gearReview
local gearReviewsPerFlush=4
local sortSpace={dirty=true}
local sortSpaceQuietTime=.12
local sortSpaceSliceBudget=.0008
local sortSpaceRoundsPerSlice=3

local function CancelSortSpace()
    if sortSpace.timer then sortSpace.timer:Cancel();sortSpace.timer=nil end
    sortSpace.preview=nil
    B.Stats.sortSpacePending=false
end
local function SortSpaceBlocked()
    return not B.active or not sortSpace.visible or B.Actions.queue or B.Actions.nativeSort or Runtime.finalCarryBatch
        or A.InCombat() or A.CursorBusy() or B.Actions:DirectionalSort()
end
local StepSortSpace
local function ScheduleSortSpace(delay)
    if sortSpace.timer then return end
    sortSpace.timer=C_Timer.NewTimer(delay,StepSortSpace)
    B.Stats.sortSpacePending=true
end
function B:RefreshSortSpace()
    if not sortSpace.visible then return end
    if SortSpaceBlocked() then
        CancelSortSpace()
        self.View:SetSortSpace(nil)
    elseif sortSpace.dirty then
        self.View:SetSortSpace(nil)
        ScheduleSortSpace(math.max(0,(sortSpace.due or 0)-GetTime()))
    else
        self.View:SetSortSpace(sortSpace.count)
    end
end
function B:InvalidateSortSpace(settled)
    if not YUI.IsForever then return end
    sortSpace.dirty,sortSpace.count,sortSpace.preview=true,nil,nil
    if not sortSpace.visible then sortSpace.due=nil;return end
    if self.Actions.queue or self.Actions.nativeSort then
        self:RefreshSortSpace()
        return
    end
    sortSpace.due=not settled and GetTime()+sortSpaceQuietTime or nil
    self:RefreshSortSpace()
end
function B:SortSpaceVisibility(visible)
    if not YUI.IsForever then return end
    sortSpace.visible=visible
    if visible then self:RefreshSortSpace()
    else CancelSortSpace() end
end
StepSortSpace=function()
    sortSpace.timer=nil
    B.Stats.sortSpacePending=false
    if SortSpaceBlocked() then CancelSortSpace();return end
    local delay=(sortSpace.due or 0)-GetTime()
    if B.Stats.pendingRefresh or delay>0 then
        ScheduleSortSpace(math.max(0,delay))
        return
    end
    local clock=YUI.API.System.GetTimePreciseSec
    local started=clock and clock()
    local deadline=started and started+sortSpaceSliceBudget
    B.Stats.sortSpaceSlices=(B.Stats.sortSpaceSlices or 0)+1
    if not sortSpace.preview then sortSpace.preview=B.Actions:BeginSortSpace() end
    local done,count
    if sortSpace.preview then
        for _=1,sortSpaceRoundsPerSlice do
            done,count=B.Actions:AdvanceSortSpace(sortSpace.preview)
            if done or deadline and (clock() or deadline)>=deadline then break end
        end
    else
        -- A later inventory snapshot can make this estimate available.
        done=true
    end
    if done then
        sortSpace.preview,sortSpace.due,sortSpace.dirty,sortSpace.count=nil,nil,false,count
        B.View:SetSortSpace(count)
    else
        ScheduleSortSpace(0)
    end
end

local function BankBagsReady(personalOnly)
    if A.ActiveBankKind()=="shared" then return not personalOnly end
    local first=A.FirstPersonalBankBag()
    return first and Runtime.readable[first]==true and A.BankWindowReady()
end
local function PresentPendingBank(kind)
    Runtime.bankPresentation=nil
    local ok,shown=xpcall(B.BankView.Open,OnViewError,B.BankView,kind)
    if not ok or not shown then B.BankView:Close(kind) end
    if kind=="bank" and ok and shown and Runtime.bankPurchaseBlocked then
        Runtime.bankPurchaseBlocked=nil
        B.BankView:RefreshFirstBankActivation(false)
    end
    if kind=="guild" then B.View:RefreshGuildBagRoute() end
end
local OpenBankSession
local function FinishBankPanelClose()
    if Runtime.bankPanelClosePending and A.HideClosedPersonalBankPanel() then Runtime.bankPanelClosePending=nil end
end
local function RestoreNativeBankPanel()
    Runtime.bankPanelClosePending=nil
    A.RestorePersonalBankPanel()
end
local function FlushQueued()
    Runtime.timer=nil;B.Stats.timers=math.max(0,B.Stats.timers-1);B.Stats.pendingRefresh=false
    if not B.active then return end
    FinishBankPanelClose()
    if Runtime.bankOpenDeferred or (Runtime.bankPurchaseBlocked and not B.bankOpen) then
        Runtime.bankOpenDeferred=nil
        if A.BankWindowShown("bank") then OpenBankSession() end
    end
    B:Flush(nil,true)
    local opener=Runtime.bankBagOpenPending
    if opener and A.BankWindowShown("bank") and BankBagsReady() then Runtime:PresentBags(false,opener) end
    if Runtime.bankPurchaseBlocked then B.BankView:RefreshFirstBankActivation(true) end
end
function B:QueueFlush()
    if not self.active then return end
    if not Runtime.timer then
        Runtime.timer=C_Timer.NewTimer(0,FlushQueued);self.Stats.timers=self.Stats.timers+1;self.Stats.pendingRefresh=true
    end
end
function B:MarkBag(id)
    if not self.active or type(id)~="number" or not Runtime.kind[id] then return end
    Runtime.dirty[id]=true;self:QueueFlush()
end
function B:RefreshTimedGear()
    if not YUI.IsForever then return end
    gearReview=nil
    local transfer=self.Actions.transferResult
    if transfer then transfer.gearStates=nil end
    for id,kind in pairs(Runtime.kind) do
        local bag=kind=="bags" and self.Model.bags[id]
        if bag then
            for _,item in pairs(bag.slots) do
                if item.gearTrade or item.gearKnown==false then self:MarkBag(id);break end
            end
        end
    end
end
local function ReadGearState(bag,slot,item,old,states,setLocations)
    if item.classID~=2 and item.classID~=4 then return end
    local candidates=Runtime.gearSets[item.itemID]
    local checkTrade=item.bound==true or item.bound==nil and item.bindType==1
    local guid=item.guid
    local reliable=guid and guid~="" and item.link and item.link~="" and item.bound~=nil
    if states and not reliable and old and old.guid then states[old.guid]=nil end
    local cached=states and guid and states[guid]
    if cached and (not reliable or cached.itemID~=item.itemID or cached.link~=item.link or cached.bound~=item.bound) then
        states[guid]=nil
        cached=nil
    end
    if not candidates and not checkTrade then return end
    item.gearRevision=reliable and gearRevision or nil
    local same=reliable and old and old.gearRevision and item.itemID==old.itemID and item.link==old.link
        and guid==old.guid and item.bound==old.bound
    local review=gearReview and gearReview.byItem[old]
    if review then
        -- Late bag-wide events can overlap every cleanup slice. Only query a
        -- verified timed copy on its turn, even after its slot was reviewed.
        if not states and same and review.guid==guid and old.gearRevision==gearRevision and old.gearKnown and old.gearTrade then
            if not review.due then
                item.gearTrade,item.gearSet,item.gearKnown=true,old.gearSet,true
                return
            end
            review.due=nil
        else
            gearReview.byItem[old]=nil
        end
    end
    if cached then
        item.gearTrade,item.gearSet,item.gearKnown=cached.trade,cached.set,true
        return
    elseif same and old.gearRevision==gearRevision and old.gearKnown and not old.gearTrade then
        item.gearSet,item.gearKnown=old.gearSet,true
    else
        item.gearTrade,item.gearSet,item.gearKnown=A.ReadGearState(bag,slot,candidates,checkTrade,setLocations,item.itemID)
    end
    if states and reliable and item.gearKnown then
        states[guid]={itemID=item.itemID,link=item.link,bound=item.bound,trade=item.gearTrade,set=item.gearSet}
    elseif not item.gearKnown and same then
        item.gearTrade=old.gearTrade
        if not item.gearSet and old.gearRevision==gearRevision then item.gearSet=old.gearSet end
    end
end
function B:FinishTransferGear(transfer)
    local states=transfer.gearStates
    transfer.gearStates=nil
    if not self.active then return end
    if states then
        for id,kind in pairs(Runtime.kind) do
            local bag=kind=="bags" and self.Model.bags[id]
            if bag then
                for _,item in pairs(bag.slots) do
                    local cached=item.gearTrade and states[item.guid]
                    if cached and cached.trade and item.gearKnown and item.gearRevision==gearRevision then
                        gearReview=gearReview or {byItem={}}
                        if not gearReview.byItem[item] then
                            cached.item,cached.guid=item,item.guid
                            gearReview[#gearReview+1]=cached
                            gearReview.byItem[item]=cached
                        end
                    end
                end
            end
        end
    end
    if gearReview then self:QueueFlush() end
end
local function WaitForItem(itemID,bagID)
    local bags=Runtime.waiting[itemID]
    local first=not bags
    if first then bags={};Runtime.waiting[itemID]=bags end
    bags[bagID]=true
    return first
end
function B:ReadAll(initial)
    if Runtime.timer and not Runtime.bankBagOpenPending and Runtime.bankPresentation~="bank" then
        Runtime.timer:Cancel();Runtime.timer=nil;self.Stats.timers=math.max(0,self.Stats.timers-1);self.Stats.pendingRefresh=false
    end
    Runtime.kind={}
    Runtime.readable={}
    for _,id in ipairs(A.GetCarryBags(true)) do Runtime.kind[id]="bags";Runtime.dirty[id]=true end
    if self.bankOpen then
        for _,kind in ipairs({"bank","shared"}) do for _,id in ipairs(A.BankBags(kind)) do Runtime.kind[id]=kind;Runtime.dirty[id]=true end end
    end
    self:Flush(initial)
end
-- Never narrow a bag-wide invalidation to the slots of our own move.
local function DirtySlot(id,slot)
    if not Runtime.kind[id] or Runtime.dirty[id]==true then return end
    local bag=B.Model.bags[id]
    if not bag or not slot or slot<1 or slot>bag.capacity or slot~=math.floor(slot) then
        Runtime.dirty[id]=true
        return
    end
    local pending=Runtime.dirty[id] or {}
    Runtime.dirty[id]=pending
    pending[slot]=true
end
function B:MarkMoveReceipt(op)
    DirtySlot(op.source.bag,op.source.slot)
    DirtySlot(op.target.bag,op.target.slot)
    self:QueueFlush()
end

local function IsDirtySlot(bag,slot)
    local pending=Runtime.dirty[bag]
    return pending==true or pending and pending[slot]
end

function B:MarkCarrySortRecovery(bag,slot,immediate)
    local recovery=self.Actions.carrySortRecovery
    if not recovery then return end
    for _,receipt in ipairs(recovery.receipts) do
        local from,to=receipt.source,receipt.to
        local sourceMatches=bag==from.bag and (not slot or slot==from.slot)
        local targetMatches=bag==to.bag and (not slot or slot==to.slot)
        if not bag or sourceMatches or targetMatches then
            DirtySlot(from.bag,from.slot)
            DirtySlot(to.bag,to.slot)
            recovery.verify=true
        end
    end
    if recovery.verify and not immediate then self:QueueFlush() end
end

function B:MarkPendingPlacementReads(round,allPending)
    local marked=false
    for _,receipt in ipairs(round.receipts) do
        if allPending or receipt.missedRead or receipt.retryRead then
            receipt.missedRead=nil
            if receipt.retryRead and not allPending then
                receipt.retryRead,receipt.readRetried=nil,true
            end
            DirtySlot(receipt.source.bag,receipt.source.slot)
            DirtySlot(receipt.to.bag,receipt.to.slot)
            marked=true
        end
    end
    return marked
end

local placementReceiptCheckDelay=.12
function B:SchedulePlacementReceiptCheck(round)
    local placement=round.placement
    if placement.receiptCheckTimer or placement.checkingDeadline then return end
    placement.receiptCheckTimer=C_Timer.NewTimer(placementReceiptCheckDelay,function()
        placement.receiptCheckTimer=nil
        B.Stats.timers=B.Stats.timers-1
        if B.Actions.sortRound~=round then return end
        local marked=B:MarkPendingPlacementReads(round)
        local retry=placement.dispatchRetry
        if retry and not placement.dispatchRetryReady then
            DirtySlot(retry.source.bag,retry.source.slot)
            DirtySlot(retry.target.bag,retry.target.slot)
            placement.dispatchRetryReady,placement.needsSteps=true,true
            marked=true
        end
        if marked then B:QueueFlush() end
    end)
    B.Stats.timers=B.Stats.timers+1
end
-- Bag-wide notifications from our own moves are reconciled once at the end.
-- Explicit invalidations such as a container change still take the full-read path.
function B:FinishCarryBatch(batch,sortRound)
    batch.sortRound=sortRound
    Runtime.finalCarryBatch=batch
    local kind=batch.kind or "bags"
    for id in pairs(batch.bags) do
        if Runtime.kind[id]==kind and (kind~="bank" or self.bankOpen) then Runtime.dirty[id]=true end
    end
    self:QueueFlush()
end
local function ReviewTimedSlots()
    for i=1,gearReviewsPerFlush do
        local review=table.remove(gearReview)
        if not review then return end
        local item=review.item
        local id,slot=item.bag,item.slot
        local bag=Runtime.kind[id]=="bags" and B.Model.bags[id]
        if Runtime.readable[id] and bag and bag.slots[slot]==item and item.guid==review.guid
            and gearReview.byItem[item]==review and item.gearTrade then
            review.due=true
            DirtySlot(id,slot)
        end
    end
    if #gearReview>0 then B:QueueFlush() end
end
local function ReadDirtyBag(id,kind,pending)
    if pending==true or not Runtime.readable[id] then return A.ReadBag(id,false,kind) end
    local bag=B.Model.bags[id]
    local items,selected={},{}
    for slot in pairs(pending) do
        local item,err=A.Slot(id,slot)
        if err then return nil,err end
        items[slot]=item
        selected[#selected+1]=slot
    end
    return items,bag.capacity,bag.family,bag.space,selected
end
local function TransferSlotReadable(batch,kind,position)
    local id=position.bag
    if Runtime.kind[id]==kind and Runtime.readable[id] and position.slot<=B.Model.bags[id].capacity then return true end
    B.Cache:RequireTransferRead(batch,kind,id)
    return false
end
function B:Flush(initial,canPresentBank)
    if not self.active then return end
    if self.Actions.splitBatch then self.Actions:AdvanceSplitBatch() end
    self.BankView:FlushBagDragRelease()
    self.Holdings:Flush()
    local started=self.Diagnostics:Begin()
    local structural,changed=false,false
    local bankChanged,carryReadinessChanged=false,false
    local sortSpaceChanged=false
    local recentChanges={}
    local player=self.View.windows.player
    local loot=player and player.effectiveLayout=="category" and player.combatLoot
    local trackCombatLoot=not initial and loot and #loot.prepared>0 and A.InCombat()
    -- Sorting and personal transfer receipts can observe a move before both
    -- BAG_UPDATE events arrive. Read both ends before confirming this step.
    local actions=self.Actions
    if actions.bankSortRecovery then actions:CheckBankSortRecovery() end
    local bankRecovery=actions.bankSortRecovery
    local splitDisplay=Runtime.splitDisplay
    Runtime.splitDisplay=nil
    local transferWindows=actions:IsPersonalBatch() and {}
    local transfer=transferWindows and actions.transferResult
    local sortRound=actions.sortRound
    local placement=sortRound and sortRound.placement
    local carryBatch,finalCarryBatch=actions.carryBatch,Runtime.finalCarryBatch
    local renderSort=sortRound or finalCarryBatch and finalCarryBatch.sortRound
    Runtime.finalCarryBatch=nil
    if carryBatch then
        local receipts=sortRound and sortRound.receipts or actions.roundWaiting
        local coarse=placement and placement.dirtyBags
        local fallback=placement and placement.dirtyAll
        local missedRead=false
        if placement then
            -- Keep track of bag-wide notifications suppressed by slot events.
            -- They may also cover other pending moves in the same bag.
            for id in pairs(carryBatch.bags) do
                if Runtime.dirty[id] then
                    if coarse[id] then coarse[id]=false end
                    fallback=false
                elseif coarse[id] then fallback=false end
            end
        end
        for _,receipt in ipairs(receipts or {}) do
            if not receipt.confirmed then
                local from,to=receipt.source,receipt.to or receipt.target
                if not placement or fallback or coarse[from.bag] or coarse[to.bag]
                    or IsDirtySlot(from.bag,from.slot) or IsDirtySlot(to.bag,to.slot) then
                    receipt.missedRead=nil
                    DirtySlot(from.bag,from.slot)
                    DirtySlot(to.bag,to.slot)
                elseif placement.dirtyAll or coarse[from.bag]==false or coarse[to.bag]==false then
                    receipt.missedRead=true
                    missedRead=true
                end
            end
        end
        if placement then
            for id in pairs(coarse) do coarse[id]=nil end
            placement.dirtyAll=nil
            if missedRead then self:SchedulePlacementReceiptCheck(sortRound) end
        end
    elseif sortRound and sortRound.bags then
        for id in pairs(sortRound.bags) do
            if Runtime.kind[id] then Runtime.dirty[id]=true end
        end
    end
    local waiting=actions.waiting
    local pending=waiting and waiting.operation
    local batch=actions.transferResult and actions.transferResult.snapshots
    local equipment=actions.equipmentTransfer
    if equipment and not equipment.sending then
        local all=equipment.finalRead or not next(Runtime.dirty)
        for _,receipt in pairs(equipment.targets) do
            local op=receipt.operation
            local from,to=op.source,op.target
            local a,b=Runtime.dirty[from.bag],Runtime.dirty[to.bag]
            if all or a==true or b==true or a and a[from.slot] or b and b[to.slot] then
                DirtySlot(from.bag,from.slot)
                DirtySlot(to.bag,to.slot)
            end
        end
    elseif transferWindows and pending and pending.personalTransfer then
        DirtySlot(pending.source.bag,pending.source.slot)
        DirtySlot(pending.target.bag,pending.target.slot)
    elseif pending and (actions.kind=="sort" or actions.kind=="restack" or actions:IsSortingBank()) then
        local source,target=pending.source.bag,pending.target.bag
        if Runtime.kind[source] then Runtime.dirty[source]=true end
        if Runtime.kind[target] then Runtime.dirty[target]=true end
    end
    if Runtime.questRefresh then
        Runtime.questRefresh=nil
        for id,kind in pairs(Runtime.kind) do
            local pending=Runtime.dirty[id]
            if Runtime.readable[id] and pending~=true and (kind=="bags" or kind=="bank") then
                for slot,item in pairs(self.Model.bags[id].slots) do
                    if not pending or not pending[slot] then
                        local quest,visual=A.SlotQuestState(id,slot)
                        if quest~=item.quest or visual~=item.questVisual then DirtySlot(id,slot) end
                    end
                end
            end
        end
    end
    local refreshSets=YUI.IsForever and not Runtime.gearSets
    if refreshSets then
        gearRevision=gearRevision+1
        Runtime.gearSets=A.EquipmentSetCandidates()
    end
    -- Locations move with items. Reuse a scheme's positions within this flush.
    local setLocations=Runtime.gearSets and next(Runtime.gearSets) and {}
    local gearStates
    if Runtime.gearSets and transfer then
        if refreshSets or not transfer.gearStates then transfer.gearStates={} end
        gearStates=transfer.gearStates
    elseif gearReview then
        ReviewTimedSlots()
    end
    for id,read in pairs(Runtime.dirty) do
        Runtime.dirty[id]=nil
        local kind=Runtime.kind[id]
        local due=self.Cache.player and self.Cache.player.pendingBagReads
        local retry=due and due[kind] and due[kind][id]
        -- The bank snapshot is incomplete until the final read. While sorting,
        -- individual move receipts only need their selected slots.
        if kind=="bank" and carryBatch and carryBatch.bags[id] and finalCarryBatch~=carryBatch then retry=nil end
        local slots,capacity,family,space,selected=ReadDirtyBag(id,kind,retry and true or read)
        local wasReadable=Runtime.readable[id]
        if slots and (kind=="bags" or capacity>0) then
            Runtime.readable[id]=true
            self.Stats.reads=self.Stats.reads+(selected and #selected or capacity)
            if Runtime.gearSets and kind=="bags" then
                local old=self.Model.bags[id]
                for slot,item in pairs(slots) do ReadGearState(id,slot,item,old and old.slots[slot],gearStates,setLocations) end
            end
            local oldBag=self.Model.bags[id]
            local topology=transferWindows and (not wasReadable or not oldBag or oldBag.capacity~=capacity
                or oldBag.family~=family or space and oldBag.space~=space)
            local changedSlots=transferWindows and {}
            local layout,patch,occupiedDelta,chargeSlotsChanged,sortChanged=self.Model:ApplyBag(
                id,slots,capacity,family,initial,kind,not initial and recentChanges or nil,space,selected,changedSlots,trackCombatLoot)
            if YUI.IsForever and kind=="bags" and not selected and capacity>0 then
                self.View:RecheckNativeSlotLocks(id,capacity)
            end
            if YUI.IsForever and kind=="bags" and self.Model.bags[id].space~="keyring" and (sortChanged or not wasReadable) then
                sortSpaceChanged=true
            end
            if transferWindows and (layout or patch or topology) then
                self.View:MarkTransferWindow(transferWindows,self.Model.bags[id],occupiedDelta,topology,layout,changedSlots)
            end
            if YUI.IsForever and kind=="bags" and (not wasReadable or chargeSlotsChanged) then
                local charged
                for slot,item in pairs(self.Model.bags[id].slots) do
                    local spellID=item.chargeSpellID
                    if spellID then
                        charged=charged or {}
                        local list=charged[spellID] or {}
                        charged[spellID]=list
                        list[#list+1]=slot
                    end
                end
                Runtime.chargeSlots[id]=charged
            end
            structural,changed=structural or layout,changed or patch
            if kind=="bank" and (layout or patch or not wasReadable) then bankChanged=true end
            local modelBag=self.Model.bags[id]
            if renderSort and (layout or patch) and (kind~=(renderSort.bank and "bank" or "bags") or modelBag.space=="keyring") then
                renderSort.otherChanged=true
            end
            if (layout or patch or retry or finalCarryBatch and finalCarryBatch.bags[id])
                and not (kind=="bank" and bankRecovery and bankRecovery.bags[id])
                and not (retry=="sort" and (A.ActiveBankKind()~="bank" or not A.CanUsePersonalBank() or A.BankPurchasePending()))
                and (not carryBatch or not carryBatch.bags[id] or finalCarryBatch==carryBatch) then
                self.Cache:WriteModelBag(kind,id,modelBag)
            end
            for _,item in pairs(slots) do
                if not item.loaded then WaitForItem(item.itemID,id) end
            end
        else
            local oldBag=self.Model.bags[id]
            if YUI.IsForever and kind=="bags" and Runtime.readable[id] and oldBag and oldBag.space~="keyring" then
                sortSpaceChanged=true
            end
            if transferWindows and Runtime.readable[id] and self.Model.bags[id] then
                self.View:MarkTransferWindow(transferWindows,self.Model.bags[id],0,true)
            end
            if kind=="bank" and Runtime.readable[id] then bankChanged=true end
            Runtime.readable[id]=false
            if placement and carryBatch and kind==(carryBatch.kind or "bags") and not placement.checkingDeadline then
                for _,receipt in ipairs(sortRound.receipts) do
                    if not receipt.readRetried and (receipt.source.bag==id or receipt.to.bag==id) then
                        receipt.retryRead=true
                        self:SchedulePlacementReceiptCheck(sortRound)
                    end
                end
            end
            if not slots and capacity=="pending" and family and WaitForItem(family,id) then
                pcall(YUI.API.Item.RequestLoadDataByID,family)
            end
            if not slots then self.Stats.errors=self.Stats.errors+1 end
        end
        if kind=="bags" and wasReadable~=Runtime.readable[id] then carryReadinessChanged=true end
    end
    if gearReview and #gearReview==0 then gearReview=nil end
    local snapshots=actions.transferResult and actions.transferResult.snapshots
    local receiptReadable=true
    if snapshots and snapshots==batch and pending and pending.personalTransfer then
        local targetKind=pending.target.kind
        local sourceOK=TransferSlotReadable(batch,targetKind=="bank" and "bags" or "bank",pending.source)
        local targetOK=TransferSlotReadable(batch,targetKind,pending.target)
        receiptReadable=sourceOK and targetOK
    end
    for _,kind in ipairs({"bags","bank","shared"}) do
        local expected,complete=0,true
        for id,bagKind in pairs(Runtime.kind) do if bagKind==kind then expected=expected+1;if Runtime.readable[id]~=true then complete=false end end end
        if snapshots then snapshots.complete[kind]=expected>0 and complete end
        local container=self.Cache.player and self.Cache:GetContainer(self.Cache.playerKey,kind)
        local due=self.Cache.player and self.Cache.player.pendingBagReads
        if container and expected>0 then container.complete=complete and not (due and due[kind]) end
    end
    local allowRecent=not initial and not splitDisplay and not finalCarryBatch and not self.bankOpen and not self.guildOpen and not self.Actions.nativeSort and not self.Actions.queue and not A.CursorBusy() and A.Context()~="bank"
    if actions.carrySortRecovery and not sortRound then actions:ReconcileCarrySortRecovery() end
    if self.Model:UpdateRecent(recentChanges,allowRecent,trackCombatLoot) then changed=true;structural=true end
    self.Stats.flushes=self.Stats.flushes+1
    local armed=self.Actions.deleteItem
    if armed then
        local current=A.Slot(armed.bag,armed.slot)
        if not current or current.itemID~=armed.itemID or current.link~=armed.link or current.count~=armed.count or current.locked then self.Actions:CancelDelete() end
    end
    local recipeRefresh=Runtime.recipeRefresh
    if recipeRefresh then Runtime.recipeRefresh=nil;self.View:ResetRecipeStates() end
    -- Item buttons are disabled during a sort. Render the settled arrangement
    -- once on completion or cancellation, including changes to other open views.
    local personalBatch=actions:IsPersonalBatch()
    if finalCarryBatch and sortRound and finalCarryBatch.sortRound==sortRound and placement and placement.verifying then
        if actions:ConfirmPlacementLayout(sortRound) then finalCarryBatch=nil end
        sortRound=nil
    end
    if finalCarryBatch then
        if finalCarryBatch.sortRound then self.View:FinishSortLayout(finalCarryBatch.sortRound)
        else self:RefreshVisible(true,true) end
        self.View:RefreshItemInputs()
        local finished=finalCarryBatch.sortRound
        if finished and finished.bank then
            local reason=finished.bankFinishReason
            if not self.bankOpen then reason="interrupted" end
            if reason=="complete" then
                for id in pairs(finalCarryBatch.bags) do
                    if not Runtime.readable[id] then reason="unreadable";break end
                end
            end
            actions:FinishBankSortObservation(finished,reason)
        end
    elseif carryBatch then
        local player=self.View.windows.player
        if splitDisplay and not sortRound and player and player.open then self.View:Layout(player,false) end
    elseif not sortRound and not (transferWindows and personalBatch) and (changed or structural or splitDisplay) then
        self:RefreshVisible(structural,splitDisplay)
    end
    if recipeRefresh then self.View:RefreshRecipeTints() end
    if bankChanged then
        if sortRound and not sortRound.bank then sortRound.otherChanged=true
        elseif not sortRound and not (finalCarryBatch and finalCarryBatch.kind=="bank") and not personalBatch and not structural then
            self.BankView:Refresh("bank")
        end
    end
    if Runtime.bankSockets then
        Runtime.bankSockets=nil
        if self.bankOpen and not bankChanged and not structural then self.BankView:RefreshSockets() end
    end
    if self.Deposit.withdrawal and self.Deposit:CheckGuildWithdrawal() then
        Runtime.guildRefresh="metadata"
    end
    local guildRefresh=Runtime.guildRefresh
    if guildRefresh then
        Runtime.guildRefresh=nil
        if self.guildOpen then
            local updated=self.Deposit.slotEvents and self.Deposit:FlushGuildSlots()
            local w=self.View.windows["live-guild"]
            if guildRefresh=="metadata" or updated or not w or w.page or w.guildMode~="items" then
                self.BankView:Refresh("guild")
            end
            if self.Deposit.bagDeposit then self.Deposit:TryBagDeposit() end
        end
    end
    -- Personal bank presentation is allowed after native show or on the queued read.
    local kind=Runtime.bankPresentation
    if kind and not A.InCombat() and A.BankWindowShown(kind)
        and (kind~="bank" or canPresentBank and BankBagsReady(true)) then
        PresentPendingBank(kind)
    end
    if finalCarryBatch then self:InvalidateSortSpace(true)
    elseif sortSpaceChanged then self:InvalidateSortSpace(initial) end
    if equipment then actions:ConfirmEquipmentTransfer(equipment,transferWindows)
    elseif sortRound then actions:ConfirmSortRound()
    elseif not carryBatch and receiptReadable then actions:Confirm() end
    if transferWindows and transfer and transfer==actions.transferResult and actions:IsPersonalBatch() then
        if waiting and waiting.displayPending and actions.waiting~=waiting then
            local w=self.View.windows[pending.target.kind=="bank" and "live-bank" or "player"]
            if w and w.open and w.effectiveLayout=="category" and transferWindows[w]~="layout" then
                self.View:MarkTransferSlot(w,pending.target.bag,pending.target.slot)
                transferWindows[w]="category"
            end
        end
        self.View:PatchTransferWindows(transferWindows)
    end
    local hover=self.BankView.presetHover
    if hover and (hover.pending or changed or structural or bankChanged or guildRefresh or carryReadinessChanged) then
        self.BankView:RefreshPresetPreview()
    end
    self.Diagnostics:Finish("inventory",started)
end
function B:RefreshVisible(structural,splitDisplay)
    if self.View then self.View:Refresh(structural~=false,splitDisplay) end
end
local function OnBag(event,id,slot)
    if B.Actions.carrySortRecovery then
        local bag=YUI.API.Security.SafeNumber(id)
        if bag and Runtime.kind[bag]=="bags" then
            B:MarkCarrySortRecovery(bag,YUI.API.Security.SafeNumber(slot))
        end
    end
    local carryBatch=B.Actions.carryBatch
    if carryBatch then
        local bag=YUI.API.Security.SafeNumber(id)
        if bag and Runtime.kind[bag]==(carryBatch.kind or "bags") then
            if event=="BAG_UPDATE" and carryBatch.bags[bag] then
                local round=B.Actions.sortRound
                if round and round.placement then round.placement.dirtyBags[bag]=true end
                B:QueueFlush()
                return
            elseif event~="BAG_UPDATE" then
                local position=YUI.API.Security.SafeNumber(slot)
                if position then
                    DirtySlot(bag,position)
                    B:QueueFlush()
                end
                return
            end
        end
    end
    if event~="BAG_UPDATE" and B.Actions:IsPersonalBatch() and Runtime.kind[id] then
        DirtySlot(id,YUI.API.Security.SafeNumber(slot))
        B:QueueFlush()
        return
    end
    if event=="BAG_UPDATE" and B.bankOpen and type(id)=="number" then
        if A.IsBankBagSocketContainer and A.IsBankBagSocketContainer(id) then
            local round=B.Actions.sortRound
            if round and round.bank then round.cancelled=true end
            for bag,kind in pairs(Runtime.kind) do if kind=="bank" then B:MarkBag(bag) end end
            return
        end
        if not Runtime.kind[id] then
            for _,kind in ipairs({"bank","shared"}) do
                for _,bag in ipairs(A.BankBags(kind)) do
                    if bag==id then Runtime.kind[id]=kind;break end
                end
            end
        end
    end
    B:MarkBag(id)
end
local function OnRecipeKnowledge()
    if next(B.View.recipeStates) or next(B.View.bankRecipeStates) then Runtime.recipeRefresh=true;B:QueueFlush() end
end
local function OnInfo(_,id,success)
    if not success or type(id)~="number" then return end
    A.InvalidateItem(id)
    local bags=Runtime.waiting[id]
    Runtime.waiting[id]=nil
    if bags then for bag in pairs(bags) do B:MarkBag(bag) end end
    if B.View.waitingEquipment[id] then B.View:InvalidateEquipmentBadges() end
    if B.View.recipePending[id] then OnRecipeKnowledge() end
    if B.bankOpen and B.BankView:SocketNeedsItemInfo(id) then Runtime.bankSockets=true;B:QueueFlush() end
end
local function OnEquipment(event)
    B.View:InvalidateEquipmentBadges()
    if event=="PLAYER_LEVEL_UP" or event=="SKILL_LINES_CHANGED" then OnRecipeKnowledge() end
end
local function OnEquipmentSets()
    gearReview=nil
    Runtime.gearSets=nil
    for id,kind in pairs(Runtime.kind) do
        if kind=="bags" then B:MarkBag(id) end
    end
end
local function PrepareBankPresentation(kind)
    if not YUI.IsForever then return end
    Runtime.bankPresentation=kind
    if kind=="guild" then A.ParkBankWindow(kind) end
    B:QueueFlush()
end
OpenBankSession=function()
    Runtime.bankOpenDeferred=nil
    if not B.active or B.bankOpen then return end
    B.bankOpen=true;B:ReadAll(false)
    if YUI.IsForever then
        Runtime.bankBagOpenPending=Runtime.bankBagOpenPending or BankFrame
        PrepareBankPresentation("bank")
    else
        B.View:ShowPlayer(BankFrame or "bank")
    end
    B.View:UpdateGrouping();B.View:RefreshItemInputs()
end
local function OnBankOpen()
    if not B.active then return end
    -- Restore our child panel before the native OnShow reads the active bank type.
    RestoreNativeBankPanel()
    if B.bankOpen then return end
    if YUI.IsForever and A.IsOpeningFirstPersonalBank(true) then
        -- This event can arrive before the native default tab and its free purchase.
        Runtime.bankOpenDeferred=true
        B:QueueFlush()
        return
    end
    OpenBankSession()
end
local function OnBankClose()
    local first=A.FirstPersonalBankBag()
    local bankWasReady=B.bankOpen and first and Runtime.kind[first]=="bank" and Runtime.readable[first]==true
    if bankWasReady then Runtime.bankPanelClosePending=true end
    Runtime.bankOpenDeferred,Runtime.bankPurchaseBlocked=nil,nil
    Runtime.bankBagOpenPending=nil
    if Runtime.bankPresentation=="bank" then Runtime.bankPresentation=nil end
    B.bankOpen=false;B.Actions:Stop();B.Actions:CancelDelete()
    for id,kind in pairs(Runtime.kind) do if kind~="bags" then Runtime.kind[id]=nil;Runtime.dirty[id]=nil;Runtime.readable[id]=nil end end
    B.BankView:Close("bank")
    FinishBankPanelClose()
    if Runtime.bankPanelClosePending and not A.InCombat() then B:QueueFlush() end
    if B.View then
        B.View:HidePlayer(BankFrame or "bank")
        B.View:BankClosed();B.View:UpdateGrouping();B.View:RefreshItemInputs()
    end
end
local function OnNativePersonalBankHidden()
    -- This callback can run inside native OnHide. Only the queued flush may hide the child.
    if B.active and Runtime.bankPanelClosePending and not A.InCombat() then B:QueueFlush() end
end
local function CheckGuildTransferAccess()
    local actions=B.Actions
    local op=actions.queue and actions.queue[actions.index]
    if op and op.guildOwner and not B.Deposit:GuildReceiptAllowed(op) then actions:Stop() end
end
local function OnGuildSelectionChanged()
    if B.active and B.guildOpen then
        CheckGuildTransferAccess()
        B.View:RefreshGuildBagRoute()
    end
end
local function OnGuildOpen()
    if not B.active or B.guildOpen then return end
    B.guildOpen=true;PrepareBankPresentation("guild")
    if YUI.IsForever and not Runtime.guildSelectionHook and type(SetCurrentGuildBankTab)=="function" then
        Runtime.guildSelectionHook=YUI.API.Security.SafeHook("YBags.GuildTab",_G,"SetCurrentGuildBankTab",OnGuildSelectionChanged)
    end
    B.View:RefreshGuildBagRoute()
    B.Cache:UpdateGuild();B.Deposit:BeginGuild();Runtime.guildRefresh=nil
    B.View:ShowPlayer(GuildBankFrame or "guild");B.View:UpdateGrouping();B.View:RefreshItemInputs()
end
local function PresentPersonalBankAfterShow(first,readBeforeShow)
    if not first or A.ActiveBankKind()~="bank" or not A.BankWindowShown("bank") or not A.BankWindowReady() then return false end
    if Runtime.readable[first] and not Runtime.dirty[first] then
        PresentPendingBank("bank")
        return true
    end
    if not readBeforeShow then return false end
    -- A bank-open event may have scanned the tabs before the native OnShow finished.
    if Runtime.kind[first]~="bank" then
        for _,id in ipairs(A.BankBags("bank")) do
            if Runtime.kind[id]~="bank" then Runtime.kind[id]="bank";Runtime.dirty[id]=true end
        end
        if Runtime.kind[first]~="bank" then return false end
    end
    Runtime.dirty[first]=true
    B:Flush(nil,true)
    return Runtime.bankPresentation~="bank"
end
local function OnNativeBankShown(kind)
    if not B.active or A.InCombat() then return end
    if kind=="bank" then
        if not A.BankWindowShown("bank") then return end
        local readBeforeShow=B.bankOpen
        OpenBankSession()
        if Runtime.bankPresentation=="bank" then
            local first=A.FirstPersonalBankBag()
            if PresentPersonalBankAfterShow(first,readBeforeShow) then return end
            if first and not Runtime.readable[first] then OnBag("BAG_UPDATE",first) end
            B:QueueFlush()
        end
        return
    end
    -- Repeated ShowUIPanel calls must respect an explicit switch back to Blizzard.
    if B.guildOpen and Runtime.bankPresentation~=kind or not A.ParkBankWindow(kind) then return end
    if B.guildOpen then B:QueueFlush() else OnGuildOpen() end
end
local function OnGuildChanged(_,unit)
    if unit and unit~="player" then return end
    local previous=B.Cache.guildKey
    if B.Cache:UpdateGuild()~=previous then
        B.Deposit:ResetGuild();Runtime.guildRefresh=nil;B.BankView:Close("guild")
        if B.Actions.kind=="deposit" then B.Actions:Stop() end
    elseif B.guildOpen then
        B.Deposit:UpdateGuildAccess()
        CheckGuildTransferAccess()
        Runtime.guildRefresh="metadata";B:QueueFlush()
    end
    B.View:RefreshGuildBagRoute()
end
local function OnGuildClose()
    if not B.guildOpen then return end
    if Runtime.bankPresentation=="guild" then Runtime.bankPresentation=nil end
    B.guildOpen=false;B.Deposit:ResetGuild();Runtime.guildRefresh=nil;B.BankView:Close("guild")
    B.View:RefreshGuildBagRoute()
    B.Actions:Stop();B.Actions:CancelDelete()
    B.View:HidePlayer(GuildBankFrame or "guild")
    B.View:BankClosed();B.View:UpdateGrouping();B.View:RefreshItemInputs()
end
local function OnGuildSlots(event)
    if not B.guildOpen then return end
    if event=="GUILDBANKBAGSLOTS_CHANGED" or event=="GUILDBANK_ITEM_LOCK_CHANGED" then
        B.Deposit:MarkGuildSlots(event=="GUILDBANK_ITEM_LOCK_CHANGED")
        Runtime.guildRefresh=Runtime.guildRefresh or "slots"
    else
        B.Deposit:UpdateGuildAccess()
        CheckGuildTransferAccess()
        B.View:RefreshGuildBagRoute(true)
        Runtime.guildRefresh="metadata"
    end
    B:QueueFlush()
end
local function OnGuildViewport()
    local w=B.View.windows["live-guild"]
    if not B.guildOpen or not w or not w.open or A.InCombat() then return end
    Runtime.guildRefresh="metadata"
    B:QueueFlush()
end
local function OnBankTabs(_,bankType)
    if not B.bankOpen then return end
    local round=B.Actions.sortRound
    local characterBank=bankType==nil or YUI.API.Security.SafeNumber(bankType)==Enum.BankType.Character
    if round and round.bank and characterBank then round.cancelled=true end
    if Runtime.bankPurchaseBlocked then
        B.BankView:RefreshFirstBankActivation(false)
        B:QueueFlush()
    end
    B:ReadAll(false);B.BankView:Refresh("bank",true)
    if Runtime.bankPresentation=="bank" and characterBank then
        -- Native tab data can arrive after the first bank presentation attempt.
        B:QueueFlush()
    end
end
local function OnBankPurchaseBlocked(_,_,action)
    action=YUI.API.Security.SafeString(action)
    if (action~="PurchaseBankTab()" and action~="C_Bank.PurchaseBankTab()")
        or not A.BankWindowShown("bank") then return end
    Runtime.bankPurchaseBlocked=true
    B:QueueFlush()
end
local function OnContainers()
    if not B.active then return end
    local round=B.Actions.sortRound
    if round and (round.carryLayout or round.bank) then round.cancelled=true end
    B:ReadAll(false)
    if B.View.windows.player then B.View:RenderBagBar(B.View.windows.player) end
    if B.bankOpen then B.BankView:RefreshSockets() end
end
local function OnCurrency(event)
    if B.active and B.View then
        if event=="PLAYER_MONEY" then
            YUI.CharacterMoney:Record(B.HOST_ID)
            if B.bankOpen then Runtime.bankSockets=true;B:QueueFlush() end
        end
        B.View:UpdateCurrencies()
    end
end
local function MarkWaitingTransfer()
    local waiting=B.Actions.waiting
    local operation=waiting and waiting.operation
    if B.Actions.equipmentTransfer or operation and operation.personalTransfer and B.Actions:IsPersonalBatch() then
        B:QueueFlush()
    elseif operation and (operation.personalTransfer or B.Actions:IsSortingBank()) then
        B:MarkBag(operation.source.bag);B:MarkBag(operation.target.bag)
    elseif waiting and waiting.guildReceipt then
        B:MarkBag(operation.source.bag)
    elseif operation and operation.guildWithdraw then
        B:QueueFlush()
    end
end
local function OnBankSlots()
    if not B.bankOpen then return end
    if Runtime.bankPresentation=="bank" then OnBag("BAG_UPDATE",A.FirstPersonalBankBag()) end
    Runtime.bankSockets=true;B:QueueFlush();MarkWaitingTransfer()
end
local function OnBagsSettled()
    if B.active then B.Actions:FinishNativeSort();MarkWaitingTransfer() end
    local carryBatch=B.Actions.carryBatch
    local round=B.Actions.sortRound
    if round and round.placement then round.placement.dirtyAll=true end
    if round or carryBatch then B:QueueFlush() end
    if B.Actions.carrySortRecovery then B:MarkCarrySortRecovery() end
    if B.Deposit.withdrawal then B:QueueFlush() end
end
local function OnCooldown()
    if not B.active then return end
    B.View:RefreshCooldowns()
end
local function OnChargeSpell(_,unit,castGUID,spellID)
    spellID=YUI.API.Security.SafeNumber(spellID)
    if not spellID then return end
    for id,spells in pairs(Runtime.chargeSlots) do
        local slots=spells[spellID]
        if slots and Runtime.kind[id]=="bags" and Runtime.dirty[id]~=true then
            local pending=Runtime.dirty[id] or {}
            Runtime.dirty[id]=pending
            for _,slot in ipairs(slots) do pending[slot]=true end
            B:QueueFlush()
        end
    end
end
local function OnUnlocked(event,bag,slot)
    OnBag(event,bag,slot)
    if B.Actions.carryBatch then return end
    if B.Actions.kind=="split-groups" and slot then B.Actions:ConfirmGroupSlot(bag,slot)
    elseif B.Actions.kind=="split" or B.Actions.kind=="split-groups" then B.Actions:Confirm() end
end
local function OnRegen()
    if B.pendingDisable then B.pendingDisable=nil;Runtime:Restore();if B.View.pendingProfile then B.View:LoadProfile() end;return end
    if B.pendingEnable then
        local open=B.openBagsOnEnable
        B.pendingEnable,B.openBagsOnEnable=nil,nil
        YUI.Event:OffOwner(B)
        if B:IsEnabled() and B:OnLifecycleEnable() and B.active and open then B.View:ShowPlayer() end
        return
    end
    if B.pendingNativeBags and B.active and not A.InCombat() then B:RequestNativeBags();return end
    if B.active then
        FinishBankPanelClose()
        Runtime.combatEndedAt=A.Now()
        B.Model.combatArrivals=nil
        if Runtime.bankPresentation~="bank" or BankBagsReady() then Runtime:CloseNativeBags() end
        B.Appearance:RefreshIconStyle();B.View:Invalidate(true);B:RefreshVisible(true)
        B.View:QueueNativeSlotLockReads()
        if B.guildOpen then B.Deposit:UpdateGuildAccess();B.View:RefreshGuildBagRoute() end
        if Runtime.bankPresentation or Runtime.bankPurchaseBlocked then B:QueueFlush() end
        B:RefreshSortSpace()
    end
end
local function OnInputChanged(event)
    if B.active then
        if B.Actions.carryBatch and event=="CURSOR_CHANGED" then
            local round=B.Actions.sortRound
            if not B.Actions.sendingRound and not (round and round.sending) and A.CursorBusy() then B:QueueFlush() end
            return
        end
        if event=="PLAYER_REGEN_DISABLED" then
            local player=B.View.windows.player
            if player and player.recentSweep then B.Appearance:SetRecentSweep(player) end
        end
        if event=="CURSOR_CHANGED" or event=="PLAYER_REGEN_DISABLED" then B:RefreshSortSpace() end
        if B.Actions.sortRound and event=="CURSOR_CHANGED" then
            if not B.Actions.sortRound.sending and A.CursorBusy() then B:QueueFlush() end
            return
        end
        if B.Deposit.bagDeposit then B.Deposit:CheckBagDeposit() end
        if B.guildOpen and event=="CURSOR_CHANGED" then
            B.Deposit:GuildCursorChanged()
            -- Observe a foreign item even inside the native call. Advance only
            -- in the coalesced flush, outside that callback.
            B.Actions:ObserveGuildCursor()
            local waiting=B.Actions.waiting
            if waiting and (waiting.guildReceipt or waiting.operation and waiting.operation.guildWithdraw) then B:QueueFlush() end
        end
        if A.InCombat() then
            B.BankView:Close("bank");B.BankView:Close("guild")
            if B.Actions.sortRound or B.Actions.carryBatch or B.Actions.kind=="extract" or B.Actions.kind=="bag-remove" or B.Actions.kind=="deposit" then B.Actions:Stop() end
        end
        B.BankView:RefreshBagDrag()
        B.View:UpdateGrouping();B.View:RefreshItemInputs(event=="CURSOR_CHANGED");B.BankView:UpdateBankControls()
    end
end
local function TryView(method,opener)
    local ok,result=xpcall(method,OnViewError,B.View,opener)
    if not ok then
        local w=B.View.windows.player;if w then w.prepared=false end
        B.View:HidePlayer();return false
    end
    return result~=false
end
local interactionStarts={MERCHANT_SHOW="merchantOpen",TRADE_SHOW="tradeOpen",
    MAIL_SHOW="mailOpen",AUCTION_HOUSE_SHOW="auctionOpen"}
local interactionEnds={MERCHANT_CLOSED="merchantOpen",TRADE_CLOSED="tradeOpen",
    MAIL_CLOSED="mailOpen",AUCTION_HOUSE_CLOSED="auctionOpen"}
local managedInteractions={
    MailInfo={flag="mailOpen",storage="mail"},
    Auctioneer={flag="auctionOpen",storage="auctions"},
}
local function OnInteraction(event,interactionType)
    if event=="MERCHANT_CLOSED" and MerchantFrame then B.View:HidePlayer(MerchantFrame) end
    local flag=interactionStarts[event] or interactionEnds[event]
    local open=interactionStarts[event]~=nil
    if not flag then
        local kinds=Enum and Enum.PlayerInteractionType
        local id=YUI.API.Security.SafeNumber(interactionType)
        if not kinds or id==nil then return OnInputChanged() end
        if YUI.IsForever and id==kinds.GuildBanker then
            if event=="PLAYER_INTERACTION_MANAGER_FRAME_HIDE" then
                OnGuildClose()
            elseif A.BankWindowShown("guild") then
                OnNativeBankShown("guild")
            end
            return
        end
        local interaction=id==kinds.MailInfo and managedInteractions.MailInfo
            or id==kinds.Auctioneer and managedInteractions.Auctioneer
        if not interaction then return OnInputChanged() end
        flag=interaction.flag
        open=event=="PLAYER_INTERACTION_MANAGER_FRAME_SHOW"
        if open and not A.StorageOpen(interaction.storage) and A.NpcInteractionState(id)~=true then
            -- Native presentation may run later in this dispatch. Allow the frame fallback on its bag-open call.
            if Runtime[flag]==false then Runtime[flag]=nil end
            return OnInputChanged()
        end
    end
    if Runtime[flag]~=open then
        Runtime[flag]=open
        B.Actions:CancelDelete()
        if B.Actions.nativeSort or B.Actions.queue and (B.Actions.kind~="extract" or not open) then B.Actions:Stop() end
        if flag=="tradeOpen" then
            if not open then
                B.View:HidePlayer("trade")
            else
                local w=B.View.windows.player
                -- An unparked native window can still be in use after a view error.
                local nativeFallback=Runtime.nativeParking and not Runtime.parkedFrames
                if not nativeFallback and not (w and w.open) and B:GetConfig().autoOpenTrade==true then
                    TryView(B.View.ShowPlayer,"trade")
                end
            end
        end
    end
    OnInputChanged()
end
local function OnSocket(event)
    local open=event=="SOCKET_INFO_UPDATE"
    if Runtime.socketOpen==open then return end
    Runtime.socketOpen=open
    OnInputChanged()
end
local function OnExternal()
    if B:IsEnabled() and A.Conflict()~=B.conflict then B:OnLifecycleDisable();B:OnLifecycleEnable() end
end
local function OnLogout()
    local transfer=B.Actions.transferResult
    if transfer and transfer.snapshots then B.Cache:FinishTransferSnapshots(transfer) end
end
local function OnQuestChanged()
    Runtime.questRefresh=true
    B:QueueFlush()
end
local events={BAG_UPDATE=OnBag,BAG_UPDATE_DELAYED=OnBagsSettled,BAG_UPDATE_COOLDOWN=OnCooldown,ITEM_LOCK_CHANGED=OnBag,ITEM_LOCKED=OnBag,ITEM_UNLOCKED=OnUnlocked,GET_ITEM_INFO_RECEIVED=OnInfo,
    YUI_YBAGS_ITEM_USE_BLOCKED=function(_,confirmed) B.View:SignalItemUseHelp(confirmed) end,
    YUI_YBAGS_ITEM_USE_CLEARED=function() B.View:ClearItemUseHelp() end,
    QUEST_ACCEPTED=OnQuestChanged,QUEST_REMOVED=OnQuestChanged,QUEST_TURNED_IN=OnQuestChanged,
    BANKFRAME_OPENED=OnBankOpen,BANKFRAME_CLOSED=OnBankClose,PLAYER_MONEY=OnCurrency,CURRENCY_DISPLAY_UPDATE=OnCurrency,
    PLAYER_REGEN_ENABLED=OnRegen,MERCHANT_SHOW=OnInteraction,MERCHANT_CLOSED=OnInteraction,
    TRADE_SHOW=OnInteraction,TRADE_CLOSED=OnInteraction,MAIL_SHOW=OnInteraction,MAIL_CLOSED=OnInteraction,
    AUCTION_HOUSE_SHOW=OnInteraction,AUCTION_HOUSE_CLOSED=OnInteraction}
events.GUILDBANKFRAME_OPENED=OnGuildOpen;events.GUILDBANKFRAME_CLOSED=OnGuildClose
events.GUILDBANKBAGSLOTS_CHANGED=OnGuildSlots;events.BAG_CONTAINER_UPDATE=OnContainers
events.GUILDBANK_ITEM_LOCK_CHANGED=OnGuildSlots;events.GUILDBANK_UPDATE_TABS=OnGuildSlots
events.BANK_TABS_CHANGED=OnBankTabs
events.PLAYERBANKSLOTS_CHANGED=OnBankSlots
events.PLAYER_GUILD_UPDATE=OnGuildChanged
events.PLAYER_EQUIPMENT_CHANGED=OnEquipment;events.PLAYER_LEVEL_UP=OnEquipment
events.NEW_RECIPE_LEARNED=OnRecipeKnowledge;events.SKILL_LINES_CHANGED=OnEquipment
events.SPELLS_CHANGED=OnRecipeKnowledge
events.MODIFIER_STATE_CHANGED=OnInputChanged;events.CURSOR_CHANGED=OnInputChanged
events.SOCKET_INFO_UPDATE=OnSocket;events.SOCKET_INFO_CLOSE=OnSocket
events.PLAYER_REGEN_DISABLED=OnInputChanged
events.PLAYER_INTERACTION_MANAGER_FRAME_SHOW=OnInteraction;events.PLAYER_INTERACTION_MANAGER_FRAME_HIDE=OnInteraction

OnViewError=function(message)
    Runtime.lastViewError=tostring(message)
    B.Stats.errors=B.Stats.errors+1
    local handler=type(geterrorhandler)=="function" and geterrorhandler()
    if type(handler)=="function" then handler(message) end
    return message
end
local function NativeResult(previous,ok,...)
    Runtime.nativeDepth=previous
    if not ok then error((...),0) end
    return ...
end
function Runtime:CallNative(callback,...)
    local previous=self.nativeDepth or 0;self.nativeDepth=previous+1
    return NativeResult(previous,pcall(callback,...))
end
function Runtime:CloseNativeBags(only)
    local closed=false
    for id,kind in pairs(self.kind) do
        if kind=="bags" and (only==nil or only==id) and A.IsBagOpen(id) then
            local lease=self.leases[id==0 and "CloseBackpack" or "CloseBag"]
            if lease then self:CallNative(lease.native,id);closed=true end
        end
    end
    return closed
end
function Runtime:ParkNativeBags(park)
    if A.InCombat() then return end
    if not park then
        for frame,state in pairs(self.parkedFrames or {}) do
            if frame:GetParent()==self.nativeParking then frame:SetParent(state.parent);frame:SetFrameLevel(state.level) end
        end
        self.parkedFrames=nil;return
    end
    local function Park(frame)
        if not frame or self.parkedFrames and self.parkedFrames[frame] and frame:GetParent()==self.nativeParking then return end
        if not self.nativeParking then
            local home=ContainerFrameContainer or UIParent
            self.nativeParking=YUI.GUI2:CreateFrame(UIParent,{hidden=true,width=1,height=1})
            self.nativeParking:SetAllPoints(UIParent);self.nativeParking:SetFrameStrata(home:GetFrameStrata())
            self.nativeParking:SetFrameLevel(home:GetFrameLevel())
        end
        self.parkedFrames=self.parkedFrames or setmetatable({}, {__mode="k"})
        local state={parent=frame:GetParent(),level=frame:GetFrameLevel()};self.parkedFrames[frame]=state
        frame:SetParent(self.nativeParking);frame:SetFrameLevel(state.level)
    end
    local count=YUI.API.Security.SafeNumber(NUM_CONTAINER_FRAMES) or 13
    for n=1,count do Park(_G["ContainerFrame"..n]) end
    Park(ContainerFrameCombinedBags)
end
local nestedBagCalls={
    OpenBackpack={"OpenAllBags","ToggleBackpack","ToggleBag"},
    ToggleBackpack={"OpenAllBags","CloseAllBags","OpenBackpack"},
    ToggleBag={"OpenAllBags","CloseAllBags","OpenBackpack","ToggleBackpack"},
    OpenBag={"OpenAllBags","OpenBackpack","ToggleBackpack","ToggleBag"},
}
local function NestedBagCall(name)
    local parents=nestedBagCalls[name]
    if not parents or type(debugstack)~="function" then return false end
    local stack=YUI.API.Security.SafeString(debugstack(3,16,0))
    if not stack then return false end
    for _,parent in ipairs(parents) do if stack:find(parent,1,true) then return true end end
    return false
end
function Runtime:PresentBags(toggle,opener)
    self.bankBagOpenPending=nil
    if not A.InCombat() then self:CloseNativeBags();self:ParkNativeBags(true) end
    if TryView(toggle and B.View.Toggle or B.View.ShowPlayer,opener) or A.InCombat() then return true end
    self:ParkNativeBags(false)
    local lease=self.leases.OpenAllBags
    if lease then self:CallNative(lease.native) end
    return false
end
function Runtime:NativeBagAction(name,id)
    if not B.active or not self.leases[name] or (self.nativeDepth or 0)>0 then return end
    -- The native bank opens its bags before selecting a tab. The stack can omit the outer call.
    if (nestedBagCalls[name] and A.IsOpeningFirstPersonalBank()) or NestedBagCall(name) then return end
    if name=="CloseAllBags" then
        -- No caller frame on ESC. Leave the visible bag for UISpecialFrames to close and count.
        if YUI.API.Security.IsSecretValue(id) or not id then return end
        if self.bankBagOpenPending==id then self.bankBagOpenPending=nil end
        B.View:HidePlayer(id)
        return
    end
    if name=="OpenBag" or name=="ToggleBag" then
        id=YUI.API.Security.SafeNumber(id)
        if not id or self.kind[id]~="bags" then return end
    end
    local opener=name=="OpenAllBags" and not YUI.API.Security.IsSecretValue(id) and id or nil
    -- Trade events own the custom bag even when the native gamepad UI also requests an open.
    if opener and opener==TradeFrame then return end
    if YUI.IsForever and opener and opener==BankFrame then
        -- The native bank selects its default tab and may buy the free first slot after this hook.
        RestoreNativeBankPanel()
        self.bankBagOpenPending=opener
        B:QueueFlush()
        return
    end
    self:PresentBags(name=="ToggleBackpack" or name=="ToggleBag",opener)
end
function Runtime:Lease()
    if next(self.leases) then return true end
    self.nativeHooks=self.nativeHooks or {}
    -- Automatic panel entry points must remain secure for subsequent native bank actions.
    for _,name in ipairs({"OpenAllBags","OpenBackpack","OpenBag","ToggleBackpack","ToggleBag","CloseAllBags","CloseBackpack","CloseBag"}) do
        local native=_G[name]
        if type(native)=="function" then
            self.leases[name]={native=native}
            if name~="CloseBackpack" and name~="CloseBag" and self.nativeHooks[name]~=native then
                local hooked=YUI.API.Security.SafeHook("YBags."..name,_G,name,function(...) self:NativeBagAction(name,...) end)
                if not hooked then return false end
                self.nativeHooks[name]=_G[name]
            end
        end
    end
    local native=_G.ToggleAllBags
    if type(native)=="function" then
        local lease={native=native}
        lease.callback=function(...)
            if (self.nativeDepth or 0)>0 or not B.active then return self:CallNative(native,...) end
            return self:PresentBags(true)
        end
        self.leases.ToggleAllBags=lease;_G.ToggleAllBags=lease.callback
    end
    self:ParkNativeBags(true)
    return true
end
function Runtime:Restore()
    RestoreNativeBankPanel()
    if not next(self.leases) then YUI.Event:OffOwner(self);return end
    if A.InCombat() then
        B.pendingDisable=true
        YUI.Event:On("PLAYER_REGEN_ENABLED",OnRegen,self)
        return
    end
    self:CloseNativeBags();self:ParkNativeBags(false)
    local lease=self.leases.ToggleAllBags
    if lease and _G.ToggleAllBags==lease.callback then _G.ToggleAllBags=lease.native end
    self.leases={}
    YUI.Event:OffOwner(self)
end
function B:Initialize()
    self:GetConfig()
    return true
end
function B:OnLifecycleEnable()
    if self.active then return true end
    self.conflict=A.Conflict()
    YUI.Event:On("YUI_EXTERNAL_STATE_CHANGED",OnExternal,self)
    if self.conflict then return true end
    if A.InCombat() then self.pendingEnable=true;YUI.Event:On("PLAYER_REGEN_ENABLED",OnRegen,self);return true end
    if not self.Cache:Initialize() then return false end
    YUI.CharacterMoney:Record(self.HOST_ID)
    if self.View.pendingProfile then self.View:LoadProfile() end
    local kinds=Enum and Enum.PlayerInteractionType
    if kinds then
        for name,interaction in pairs(managedInteractions) do
            Runtime[interaction.flag]=A.NpcInteractionState(kinds[name]) or nil
        end
    end
    self.active=true;self.Stats.enabled=true
    self.Cache:InstallTooltip()
    self.Model:Reset()
    self.View:InvalidateEquipmentBadges()
    self.Holdings:Enable()
    self:ReadAll(true)
    for event,handler in pairs(events) do YUI.Event:On(event,handler,self);self.Stats.listeners=self.Stats.listeners+1 end
    if YUI.IsForever then
        YUI.Event:On("ADDON_ACTION_FORBIDDEN",OnBankPurchaseBlocked,self)
        self.Stats.listeners=self.Stats.listeners+1
        YUI.Event:On("PLAYER_LOGOUT",OnLogout,self)
        self.Stats.listeners=self.Stats.listeners+1
        YUI.Event:On("UNIT_SPELLCAST_SUCCEEDED",OnChargeSpell,self,{unit="player"})
        self.Stats.listeners=self.Stats.listeners+1
        YUI.Event:On("GUILD_ROSTER_UPDATE",OnGuildSlots,self)
        YUI.Event:On("GUILD_RANKS_UPDATE",OnGuildSlots,self)
        YUI.Event:On("DISPLAY_SIZE_CHANGED",OnGuildViewport,self)
        YUI.Event:On("UI_SCALE_CHANGED",OnGuildViewport,self)
        self.Stats.listeners=self.Stats.listeners+4
        YUI.Event:On("EQUIPMENT_SETS_CHANGED",OnEquipmentSets,self)
        self.Stats.listeners=self.Stats.listeners+1
        if not Runtime.bankWindowHook then
            Runtime.bankWindowHook=A.HookBankWindowShown(OnNativeBankShown,OnNativePersonalBankHidden)
        end
    end
    self.View:EnsurePlayer()
    if not Runtime:Lease() then self:OnLifecycleDisable();return false end
    Runtime:CloseNativeBags()
    TryView(self.View.PreparePlayer)
    if self.Sync then self.Sync:Enable() end
    return true
end
function B:OnLifecycleDisable()
    self.pendingNativeBags=nil
    self.pendingEnable=nil
    self.openBagsOnEnable=nil
    Runtime.combatEndedAt=nil
    Runtime.bankBagOpenPending=nil
    Runtime.bankOpenDeferred,Runtime.bankPurchaseBlocked=nil,nil
    Runtime.splitDisplay=nil
    Runtime.finalCarryBatch=nil
    self:SortSpaceVisibility(false)
    sortSpace.dirty,sortSpace.due,sortSpace.count=true,nil,nil
    self.active=false;self.Stats.enabled=false
    self.View:RefreshGuildBagRoute()
    YUI.Event:OffOwner(self);self.Stats.listeners=0
    self.Holdings:Disable()
    if Runtime.timer then Runtime.timer:Cancel();Runtime.timer=nil;self.Stats.timers=math.max(0,self.Stats.timers-1) end
    self.Stats.pendingRefresh=false
    self.Actions:CancelDelete();self.Actions:Stop()
    if self.Sync then self.Sync:Disable() end
    self.BankView:Close("bank");self.BankView:Close("guild")
    if self.View then self.View:HideAll() end
    Runtime:Restore()
    Runtime.dirty,Runtime.kind,Runtime.waiting,Runtime.readable={},{},{},{}
    Runtime.questRefresh=nil
    Runtime.chargeSlots={}
    gearReview=nil
    Runtime.gearSets,Runtime.merchantOpen,Runtime.bankPresentation,Runtime.recipeRefresh=nil,nil,nil,nil
    Runtime.tradeOpen,Runtime.mailOpen,Runtime.auctionOpen,Runtime.socketOpen=nil,nil,nil,nil
    Runtime.bankSockets=nil
    self.View:ResetRecipeStates()
    self.Model:Reset();A.Reset()
    self.bankOpen=false
    self.guildOpen=false;self.Deposit:ResetGuild();Runtime.guildRefresh=nil
    return true
end
function B:RequestNativeBags()
    if not self.active then return end
    if A.InCombat() then
        self.pendingNativeBags=true
        self:Notify("help.switch_pending")
        return
    end
    self.pendingNativeBags=nil
    if self:SetEnabled(false) then self:Notify("help.switched") end
end
function B:OpenBagsFromSettings()
    if not self.active and not self:SetEnabled(true) then return false end
    if self.pendingEnable then self.openBagsOnEnable=true;return true end
    return self.View:ShowPlayer()
end
function B:OnProfileChanged()
    local cancelNativeSwitch=self.pendingNativeBags
    self:OnLifecycleDisable();self.config=nil;self:GetConfig()
    if cancelNativeSwitch then self:Notify("help.switch_profile_cancelled") end
    self.Diagnostics:NoteConfig("profile-change")
    self.View:LoadProfile()
    if self:IsEnabled() then self:OnLifecycleEnable() end
end
function B:OpenSettings(tab,subtab)
    if self.client=="forever" or tab then self:SetSettingsRoute(tab,subtab) end
    local settings=YUI.Settings
    local module=settings.modulesById and settings.modulesById[self.SETTINGS_ENTRY]
    local frame=module and module.frame
    if frame and (self.SettingsTab~=frame.ybagsSettingsTab or self.SettingsSubtab~=frame.ybagsSettingsSubtab) then
        return YUI:OpenSettings(self.SETTINGS_ENTRY,self.PRODUCT_ID,{afterOpen=function(opened,host)
            if opened==module then host:RefreshSelectedModule() end
        end})
    end
    return YUI:OpenSettings(self.SETTINGS_ENTRY,self.PRODUCT_ID)
end

YUI:RegisterProduct({id=B.PRODUCT_ID,title="YBags",titleKey="product.title",titleNamespace="YBags",
    shortTitle="YBags",shortTitleKey="product.nav",shortTitleNamespace="YBags",addonName=B.ADDON_NAME,
    author="Ayan",profileExportPrefix="!YUI-YBags-1:",settingsScope=B.PRODUCT_ID,
    settings={enabled=true,entry=B.SETTINGS_ENTRY,commonPages={"core.profiles","core.about"},minimapIcon=false},
    db={enabled=false,savedVariable="YUI_DB",storageKey=B.STORAGE_KEY},commands={}})
YUI.Module:Register({id=B.PRODUCT_ID,name="YBags",product=B.HOST_ID,scope=B.PRODUCT_ID,owner=B,defaultEnabled=false,
    dependencies={"core.db","core.event","core.locale","core.api","gui","settings"},
    getEnabled=function(owner) return owner:IsEnabled() end,setEnabled=function(owner,value) return owner:SetEnabled(value,true) end,
    OnInitialize="Initialize",OnEnable="OnLifecycleEnable",OnDisable="OnLifecycleDisable",OnProfileChanged="OnProfileChanged",OnConfigChanged="ConfigChanged"})
YUI.Components:Register({id=B.PRODUCT_ID,kind="product",displayName="YBags",localeNamespace="YBags",
    nameKey="product.nav",descriptionKey="product.description",settingsMode="external",standalone=false,
    order=916,storageKey=B.STORAGE_KEY,sourceRoot="Products\\YBags",versions={"mainline","forever"},
    getEnabled=function() return B:IsEnabled() end,setEnabled=function(_,enabled) return B:SetEnabled(enabled) end,
    getEffectiveState=function() if B.conflict then return {effective=false,kind="yield",controller=B.conflict,status="active",tone="warning"} end end,
    OpenSettings=function() return B:OpenSettings() end})
if YUI.Commands then
    YUI.Commands:Register({id="ybags",productId=B.HOST_ID,aliases={"/ybags"},handler=function() B:OpenSettings() end})
end
