local _, private = ...

local GetTime = GetTime
local tinsert, tsort = table.insert, table.sort
local UnitIsUnit, UnitExists, UnitIsVisible, SetRaidTarget, GetRaidTargetIndex =
	UnitIsUnit, UnitExists, UnitIsVisible, SetRaidTarget, GetRaidTargetIndex

local playerName = UnitName("player")

private.canSetIcons = {}
private.addsGUIDs = {}
private.enableIcons = true -- Set to false when a raid leader or a promoted player has a newer version of DBM

--Common variables
local eventsRegistered = false
--Mob Scanning Variables
local scanExpires = {}
local addsIcon = {}
local addsIconSet = {}
local iconVariables = {}
--Player setting variables
local iconSortTable = {}
local iconSet = {}

local module = private:NewModule("Icons")

function module:SetIcon(bossModPrototype, target, icon, timer)
	if not target then return end--Fix a rare bug where target becomes nil at last second (end combat fires and clears targets)
	if DBM.Options.DontSetIcons or not private.enableIcons or DBM:GetRaidRank(playerName) == 0 then
		return
	end
	bossModPrototype:UnscheduleMethod("SetIcon", target)
	if type(icon) ~= "number" or type(target) ~= "string" then--icon/target probably backwards.
		DBM:Debug("|cffff0000SetIcon is being used impropperly. Check icon/target order|r")
		return--Fail silently instead of spamming icon lua errors if we screw up
	end
	icon = icon and icon >= 0 and icon <= 8 and icon or 8
	local uId = DBM:GetRaidUnitId(target)
	if uId and UnitIsUnit(uId, "player") and DBM:GetNumRealGroupMembers() < 2 then return end--Solo raid, no reason to put icon on yourself.
	if uId or UnitExists(target) then--target accepts uid, unitname both.
		uId = uId or target
		--save previous icon into a table.
		local oldIcon = self:GetIcon(uId) or 0
		if not bossModPrototype.iconRestore[uId] then
			bossModPrototype.iconRestore[uId] = oldIcon
		end
		--set icon
		if oldIcon ~= icon then--Don't set icon if it's already set to what we're setting it to
			SetRaidTarget(uId, bossModPrototype.iconRestore[uId] and icon == 0 and bossModPrototype.iconRestore[uId] or icon)
		end
		--schedule restoring old icon if timer enabled.
		if timer then
			bossModPrototype:ScheduleMethod(timer, "SetIcon", target, 0)
		end
	end
end

local function SortByGroup(v1, v2)
	return DBM:GetRaidSubgroup(DBM:GetUnitFullName(v1)) < DBM:GetRaidSubgroup(DBM:GetUnitFullName(v2))
end

local function clearSortTable(scanId)
	iconSortTable[scanId] = nil
	iconSet[scanId] = nil
end

local function SetIconByAlphaTable(bossModPrototype, returnFunc, scanId)
	tsort(iconSortTable[scanId])--Sorted alphabetically
	for i = 1, #iconSortTable[scanId] do
		local target = iconSortTable[scanId][i]
		if i > 8 then
			DBM:Debug("|cffff0000Too many players to set icons, reconsider where using icons|r", 2)
			return
		end
		if not bossModPrototype.iconRestore[target] then
			bossModPrototype.iconRestore[target] = bossModPrototype:GetIcon(target) or 0
		end
		SetRaidTarget(target, i)--Icons match number in table in alpha sort
		if returnFunc then
			bossModPrototype[returnFunc](bossModPrototype, target, i)--Send icon and target to returnFunc. (Generally used by announce icon targets to raid chat feature)
		end
	end
	DBM:Schedule(1.5, clearSortTable, scanId)--Table wipe delay so if icons go out too early do to low fps or bad latency, when they get new target on table, resort and reapplying should auto correct teh icon within .2-.4 seconds at most.
end

function module:SetAlphaIcon(bossModPrototype, delay, target, maxIcon, returnFunc, scanId)
	if not target then return end
	if DBM.Options.DontSetIcons or not private.enableIcons or DBM:GetRaidRank(playerName) == 0 then
		return
	end
	scanId = scanId or 1
	local uId = DBM:GetRaidUnitId(target)
	if uId or UnitExists(target) then--target accepts uid, unitname both.
		uId = uId or target
		if not iconSortTable[scanId] then iconSortTable[scanId] = {} end
		if not iconSet[scanId] then iconSet[scanId] = 0 end
		local foundDuplicate = false
		for i = #iconSortTable[scanId], 1, -1 do
			if iconSortTable[scanId][i] == uId then
				foundDuplicate = true
				break
			end
		end
		if not foundDuplicate then
			iconSet[scanId] = iconSet[scanId] + 1
			tinsert(iconSortTable[scanId], uId)
		end
		bossModPrototype:Unschedule(SetIconByAlphaTable)
		if maxIcon and iconSet[scanId] == maxIcon then
			SetIconByAlphaTable(bossModPrototype, returnFunc, scanId)
		elseif bossModPrototype:LatencyCheck() then--lag can fail the icons so we check it before allowing.
			bossModPrototype:Schedule(delay or 0.5, SetIconByAlphaTable, bossModPrototype, returnFunc, scanId)
		end
	end
end

local function SetIconBySortedTable(bossModPrototype, startIcon, reverseIcon, returnFunc, scanId)
	tsort(iconSortTable[scanId], SortByGroup)
	local icon, CustomIcons
	if startIcon and type(startIcon) == "table" then--Specific gapped icons
		CustomIcons = true
		icon = 1
	else
		icon = startIcon or 1
	end
	for _, v in ipairs(iconSortTable[scanId]) do
		if not bossModPrototype.iconRestore[v] then
			bossModPrototype.iconRestore[v] = module:GetIcon(v) or 0
		end
		if CustomIcons then
			SetRaidTarget(v, startIcon[icon])--do not use SetIcon function again. It already checked in SetSortedIcon function.
			icon = icon + 1
			if returnFunc then
				bossModPrototype[returnFunc](bossModPrototype, v, startIcon[icon])--Send icon and target to returnFunc. (Generally used by announce icon targets to raid chat feature)
			end
		else
			SetRaidTarget(v, icon)--do not use SetIcon function again. It already checked in SetSortedIcon function.
			if reverseIcon then
				icon = icon - 1
			else
				icon = icon + 1
			end
			if returnFunc then
				bossModPrototype[returnFunc](bossModPrototype, v, icon)--Send icon and target to returnFunc. (Generally used by announce icon targets to raid chat feature)
			end
		end
	end
	DBM:Schedule(1.5, clearSortTable, scanId)--Table wipe delay so if icons go out too early do to low fps or bad latency, when they get new target on table, resort and reapplying should auto correct teh icon within .2-.4 seconds at most.
end

function module:SetSortedIcon(bossModPrototype, delay, target, startIcon, maxIcon, reverseIcon, returnFunc, scanId)
	if not target then return end
	if DBM.Options.DontSetIcons or not private.enableIcons or DBM:GetRaidRank(playerName) == 0 then
		return
	end
	scanId = scanId or 1
	if not startIcon then startIcon = 1 end
	local uId = DBM:GetRaidUnitId(target)
	if uId or UnitExists(target) then--target accepts uid, unitname both.
		uId = uId or target
		if not iconSortTable[scanId] then iconSortTable[scanId] = {} end
		if not iconSet[scanId] then iconSet[scanId] = 0 end
		local foundDuplicate = false
		for i = #iconSortTable[scanId], 1, -1 do
			if iconSortTable[scanId][i] == uId then
				foundDuplicate = true
				break
			end
		end
		if not foundDuplicate then
			iconSet[scanId] = iconSet[scanId] + 1
			tinsert(iconSortTable[scanId], uId)
		end
		bossModPrototype:Unschedule(SetIconBySortedTable)
		if maxIcon and iconSet[scanId] == maxIcon then
			SetIconBySortedTable(bossModPrototype, startIcon, reverseIcon, returnFunc, scanId)
		elseif bossModPrototype:LatencyCheck() then--lag can fail the icons so we check it before allowing.
			bossModPrototype:Schedule(delay or 0.5, SetIconBySortedTable, bossModPrototype, startIcon, reverseIcon, returnFunc, scanId)
		end
	end
end

function module:GetIcon(uIdOrTarget)
	local uId = DBM:GetRaidUnitId(uIdOrTarget) or uIdOrTarget
	return UnitExists(uId) and GetRaidTargetIndex(uId)
end

function module:RemoveIcon(bossModPrototype, target)
	return self:SetIcon(bossModPrototype, target, 0)
end

function module:ClearIcons()
	if IsInRaid() then
		for i = 1, GetNumGroupMembers() do
			if UnitExists("raid" .. i) and GetRaidTargetIndex("raid" .. i) then
				SetRaidTarget("raid" .. i, 0)
			end
		end
	else
		for i = 1, GetNumSubgroupMembers() do
			if UnitExists("party" .. i) and GetRaidTargetIndex("party" .. i) then
				SetRaidTarget("party" .. i, 0)
			end
		end
	end
end

function module:CanSetIcon(optionName)
	return private.canSetIcons[optionName] or false
end

local function executeMarking(self, scanId, unitId)
	local guid = UnitGUID(unitId)
	local cid = DBM:GetCIDFromGUID(guid)
	local isFriend = UnitIsFriend("player", unitId)
	local isFiltered = false
	local success = 0--Success 1, found valid mob, Success 2, succeeded in marking it
	if (not iconVariables[scanId].allowFriendly and isFriend) or (iconVariables[scanId].skipMarked and GetRaidTargetIndex(unitId)) then
		isFiltered = true
		DBM:Debug(unitId.." was skipped because it's a filtered mob. Friend Flag: "..(isFriend and "true" or "false"), 2)
	end
	if not isFiltered then
		--Table based scanning, used if applying to multiple creature Ids in a single scan
		--Can be used in both ascending/descending icon assignment or even specific icons per Id
		if guid and iconVariables[scanId].scanTable and type(iconVariables[scanId].scanTable) == "table" and iconVariables[scanId].scanTable[cid] and not private.addsGUIDs[guid] then
			DBM:Debug("Match found in mobUids, SHOULD be setting table icon on "..unitId, 1)
			success = 1
			if type(iconVariables[scanId].scanTable[cid]) == "number" then--CID in table is assigned a specific icon number
				SetRaidTarget(unitId, iconVariables[scanId].scanTable[cid])
				DBM:Debug("DBM called SetRaidTarget on "..unitId.." with icon value of "..iconVariables[scanId].scanTable[cid], 2)
				if GetRaidTargetIndex(unitId) then
					success = 2
				end
			else--Incremental Icon method (ie the table value for the cid was true not a number)
				SetRaidTarget(unitId, addsIcon[scanId])
				DBM:Debug("DBM called SetRaidTarget on "..unitId.." with icon value of "..addsIcon[scanId], 2)
				if GetRaidTargetIndex(unitId) then
					success = 2
					if iconVariables[scanId].iconSetMethod == 1 then
						addsIcon[scanId] = addsIcon[scanId] + 1
					else
						addsIcon[scanId] = addsIcon[scanId] - 1
					end
				end
			end
		elseif guid and (guid == scanId or cid == scanId) and not private.addsGUIDs[guid] then
			DBM:Debug("Match found in mobUids, SHOULD be setting icon on "..unitId, 1)
			success = 1
			if iconVariables[scanId].iconSetMethod == 2 then--Fixed Icon
				SetRaidTarget(unitId, addsIcon[scanId])
				DBM:Debug("DBM called SetRaidTarget on "..unitId.." with icon value of "..addsIcon[scanId], 2)
				if GetRaidTargetIndex(unitId) then
					success = 2
				end
			else--Incremental Icon method
				SetRaidTarget(unitId, addsIcon[scanId])
				DBM:Debug("DBM called SetRaidTarget on "..unitId.." with icon value of "..addsIcon[scanId], 2)
				if GetRaidTargetIndex(unitId) then
					success = 2
					if iconVariables[scanId].iconSetMethod == 1 then--Asscending
						addsIcon[scanId] = addsIcon[scanId] + 1
					else--Descending
						addsIcon[scanId] = addsIcon[scanId] - 1
					end
				end
			end
		end
		if success == 2 then
			DBM:Debug("SetRaidTarget was successful", 2)
			private.addsGUIDs[guid] = true
			addsIconSet[scanId] = addsIconSet[scanId] + 1
			if addsIconSet[scanId] >= iconVariables[scanId].maxIcon then--stop scan immediately to save cpu
				--clear variables
				scanExpires[scanId] = nil
				addsIcon[scanId] = nil
				addsIconSet[scanId] = nil
				iconVariables[scanId] = nil
				if eventsRegistered and #scanExpires == 0 then--No remaining icon scans
					eventsRegistered = false
					self:UnregisterShortTermEvents()
					DBM:Debug("Target events Unregistered", 2)
				end
				return
			end
		elseif success == 1 then--Found right mob but never  marked it
			DBM:Debug("SetRaidTarget failed", 2)
		end
	end
	if GetTime() > scanExpires[scanId] then--scan for limited time.
		DBM:Debug("Stopping ScanForMobs for: "..(scanId or "nil"), 2)
		--clear variables
		scanExpires[scanId] = nil
		addsIcon[scanId] = nil
		addsIconSet[scanId] = nil
		iconVariables[scanId] = nil
		--Do not wipe adds GUID table here, it's wiped by :Stop() which is called by EndCombat
		if eventsRegistered and #scanExpires == 0 then--No remaining icon scans
			eventsRegistered = false
			self:UnregisterShortTermEvents()
			DBM:Debug("Target events Unregistered", 2)
		end
	end
end

function module:UPDATE_MOUSEOVER_UNIT()
	for _, scanId in ipairs(scanExpires) do
		executeMarking(self, scanId, "mouseover")
		--executeMarking(self, scanId, "mouseovertarget")
		DBM:Debug("executeMarking called by UPDATE_MOUSEOVER_UNIT", 2)
	end
end

function module:NAME_PLATE_UNIT_ADDED(unitId)
	for _, scanId in ipairs(scanExpires) do
		executeMarking(self, scanId, unitId)
		DBM:Debug("executeMarking called by NAME_PLATE_UNIT_ADDED", 2)
	end
end

function module:FORBIDDEN_NAME_PLATE_UNIT_ADDED(unitId)
	for _, scanId in ipairs(scanExpires) do
		executeMarking(self, scanId, unitId)
		DBM:Debug("executeMarking called by FORBIDDEN_NAME_PLATE_UNIT_ADDED", 2)
	end
end

function module:UNIT_TARGET(unitId)
	for _, scanId in ipairs(scanExpires) do
		executeMarking(self, scanId, unitId.."target")
		DBM:Debug("executeMarking called by UNIT_TARGET", 2)
	end
end

--If this continues to throw errors because SetRaidTarget fails even after IEEU has fired for a unit, then this will be scrapped
function module:INSTANCE_ENCOUNTER_ENGAGE_UNIT()
	for i = 1, 5 do
		local unitId = "boss"..i
		if UnitExists(unitId) and UnitIsVisible(unitId) then--Hopefully enough failsafe against icons failing
			for _, scanId in ipairs(scanExpires) do
				executeMarking(self, scanId, unitId)
			end
		end
	end
end

--Initial scan Ids. These exclude boss unit Ids because them existing doessn't mean they are valid yet. They are not valid until they are added to boss health frame
--Attempting to SetRaidTarget on a non visible valid boss id actually just silently fails
local mobUids = {
	"nameplate1", "nameplate2", "nameplate3", "nameplate4", "nameplate5", "nameplate6", "nameplate7", "nameplate8", "nameplate9", "nameplate10",
	"nameplate11", "nameplate12", "nameplate13", "nameplate14", "nameplate15", "nameplate16", "nameplate17", "nameplate18", "nameplate19", "nameplate20",
	"nameplate21", "nameplate22", "nameplate23", "nameplate24", "nameplate25", "nameplate26", "nameplate27", "nameplate28", "nameplate29", "nameplate30",
	"nameplate31", "nameplate32", "nameplate33", "nameplate34", "nameplate35", "nameplate36", "nameplate37", "nameplate38", "nameplate39", "nameplate40",
	"raid1target", "raid2target", "raid3target", "raid4target", "raid5target", "raid6target", "raid7target", "raid8target", "raid9target", "raid10target",
	"raid11target", "raid12target", "raid13target", "raid14target", "raid15target", "raid16target", "raid17target", "raid18target", "raid19target", "raid20target",
	"raid21target", "raid22target", "raid23target", "raid24target", "raid25target", "raid26target", "raid27target", "raid28target", "raid29target", "raid30target",
	"raid31target", "raid32target", "raid33target", "raid34target", "raid35target", "raid36target", "raid37target", "raid38target", "raid39target", "raid40target",
	"party1target", "party2target", "party3target", "party4target",
	"mouseover", "target", "focus", "targettarget", "mouseovertarget"
}

function module:ScanForMobs(bossModPrototype, scanId, iconSetMethod, mobIcon, maxIcon, scanTable, scanningTime, optionName, allowFriendly, skipMarked, allAllowed)
	if not optionName then optionName = bossModPrototype.findFastestComputer[1] end
	if private.canSetIcons[optionName] or (allAllowed and not DBM.Options.DontSetIcons) then
		--Declare variables.
		DBM:Debug("canSetIcons or allAllowed true for "..(optionName or "nil"), 2)
		if not scanId then--Accepts cid and guid
			error("DBM:ScanForMobs calld without scanId")
			return
		end
		--Initialize icon method variables for event handlers
		if not addsIcon[scanId] then addsIcon[scanId] = mobIcon or 8 end
		if not addsIconSet[scanId] then addsIconSet[scanId] = 0 end
		if not scanExpires[scanId] then scanExpires[scanId] = GetTime() + (scanningTime or 8) end
		if not iconVariables[scanId] then iconVariables[scanId] = {} end
		iconVariables[scanId].iconSetMethod = iconSetMethod or 0--Set IconSetMethod -- 0: Descending / 1:Ascending / 2: Force Set / 9:Force Stop
		iconVariables[scanId].maxIcon = maxIcon or 8 --We only have 8 icons.
		iconVariables[scanId].allowFriendly = allowFriendly and true or false
		iconVariables[scanId].skipMarked = skipMarked and true or false
		if scanTable then
			if type(scanTable) == "table" then
				iconVariables[scanId].scanTable = scanTable
			else
				DBM:Debug("ScanForMobs is using obsolete parameter for scanTable on "..optionName..". This should be a CID definition table or nil")
			end
		end
		if iconSetMethod == 9 then--Force stop scanning
			--clear variables
			scanExpires[scanId] = nil
			addsIcon[scanId] = nil
			addsIconSet[scanId] = nil
			iconVariables[scanId] = nil
			return
		end
		--Do initial scan now to see if unit we're scaning for already exists (ie they wouldn't fire nameplate added or IEEU for example.
		--Caveat, if all expected units are found before it finishes going over mobUids table, it'll still finish goingg through table
		for _, unitId in ipairs(mobUids) do
			executeMarking(self, scanId, unitId)
		end
		--Hopefully we found all units with initial scan and scanExpires has already been emptied in the executeMarking calls
		--But if not, we Register listeners to watch for the units we seek to appear
		if not eventsRegistered and #scanExpires > 0 then
			eventsRegistered = true
			self:RegisterShortTermEvents("UPDATE_MOUSEOVER_UNIT", "UNIT_TARGET", "NAME_PLATE_UNIT_ADDED", "FORBIDDEN_NAME_PLATE_UNIT_ADDED", "INSTANCE_ENCOUNTER_ENGAGE_UNIT")
			DBM:Debug("Target events Registered", 2)
		end
	else
		DBM:Debug("Not elected to set icons for "..(optionName or "nil"), 2)
	end
end
