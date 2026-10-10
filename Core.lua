--[[
  Resource Cost Overlay — simple rage/energy/mana cost numbers on Cooldown
  Manager spell bars, buff bars, and optionally action bars.
]]

local ADDON_NAME, ns = ...

local issecretvalue = issecretvalue
local canaccessvalue = canaccessvalue
local issecrettable = issecrettable
local canaccesstable = canaccesstable

local POWER_MANA = Enum and Enum.PowerType and Enum.PowerType.Mana or 0
local POWER_RAGE = Enum and Enum.PowerType and Enum.PowerType.Rage or 1
local POWER_FOCUS = Enum and Enum.PowerType and Enum.PowerType.Focus or 2
local POWER_ENERGY = Enum and Enum.PowerType and Enum.PowerType.Energy or 3

local TRACKED_POWER = {
	[POWER_MANA] = true,
	[POWER_RAGE] = true,
	[POWER_FOCUS] = true,
	[POWER_ENERGY] = true,
}

local POWER_TINT = {
	[POWER_MANA] = { 0.25, 0.50, 1.00 },
	[POWER_RAGE] = { 0.90, 0.20, 0.20 },
	[POWER_FOCUS] = { 1.00, 0.55, 0.20 },
	[POWER_ENERGY] = { 1.00, 0.95, 0.20 },
}

local PERCENT_KEY = {
	[POWER_MANA] = "percentMana",
	[POWER_RAGE] = "percentRage",
	[POWER_FOCUS] = "percentFocus",
	[POWER_ENERGY] = "percentEnergy",
}

local FONT_PATH_FALLBACK = "Fonts\\FRIZQT__.TTF"
local REFRESH_THROTTLE = 0.08

local driver = CreateFrame("Frame")
local overlays = {} -- [button] = FontString
local trackedButtons = {}
local cooldownSpellCache = {} -- [cooldownID] = spellID
local pendingRefresh = false
local refreshAt = 0
local layoutDirty = true

local function Print(msg)
	print("|cffc4b5fdJoipov|r Resource Cost on Icons: " .. tostring(msg or ""))
end

ns.Print = Print

local function DB()
	return ns.db
end

--- Blizzard default font, or Ellesmere's configured UI font when EUI is loaded.
local function ResolveFont()
	if EllesmereUI and EllesmereUI.GetFontPath then
		local path = EllesmereUI.GetFontPath()
		if type(path) == "string" and path ~= "" then
			local flags = ""
			if EllesmereUI.GetFontOutlineFlag then
				flags = EllesmereUI.GetFontOutlineFlag() or ""
			end
			if flags == "" or flags == nil then
				flags = "OUTLINE"
			elseif not tostring(flags):find("OUTLINE", 1, true) then
				flags = tostring(flags) .. ",OUTLINE"
			end
			return path, flags
		end
	end
	local path = (STANDARD_TEXT_FONT and STANDARD_TEXT_FONT ~= "" and STANDARD_TEXT_FONT) or FONT_PATH_FALLBACK
	return path, "OUTLINE"
end

local function SecretBlocked(value)
	return issecretvalue and issecretvalue(value) and not (canaccessvalue and canaccessvalue(value))
end

local function CanIndex(value)
	if value == nil or SecretBlocked(value) then
		return false
	end
	if issecrettable and issecrettable(value) and not (canaccesstable and canaccesstable(value)) then
		return false
	end
	return true
end

local function ReadableNumber(value)
	if value == nil or SecretBlocked(value) or type(value) ~= "number" then
		return nil
	end
	return value
end

local function ReadableString(value)
	if type(value) ~= "string" or SecretBlocked(value) then
		return nil
	end
	return value
end

--- Spellbook name -> the rank the player actually has. Buff viewers often
--- store rank 1, which still has a (smaller) cost, so the low rank must not win.
local knownByName = {}
local knownRanksReady = false

local function SpellSubtext(spellID)
	if not (C_Spell and C_Spell.GetSpellSubtext) then
		return nil
	end
	local sub = C_Spell.GetSpellSubtext(spellID)
	if type(sub) ~= "string" or sub == "" or SecretBlocked(sub) then
		return nil
	end
	return sub
end

--- "Rank 3" / "Rang 3" style subtext. Other subtext (Solar, Lunar) is identity.
local function RankNumber(spellID)
	local sub = SpellSubtext(spellID)
	if not sub or not sub:match("^%a+%s+%d+$") then
		return nil
	end
	return tonumber(sub:match("(%d+)"))
end

local function NonRankSubtext(spellID)
	local sub = SpellSubtext(spellID)
	if not sub or sub:match("^%a+%s+%d+$") then
		return nil
	end
	return sub
end

local function SameRankFamily(a, b)
	if not (C_Spell and C_Spell.GetSpellName) then
		return false
	end
	local nameA = C_Spell.GetSpellName(a)
	local nameB = C_Spell.GetSpellName(b)
	if type(nameA) ~= "string" or nameA == "" or SecretBlocked(nameA) then
		return false
	end
	if nameA ~= nameB then
		return false
	end
	local subA = NonRankSubtext(a)
	local subB = NonRankSubtext(b)
	if subA and subB and subA ~= subB then
		return false
	end
	return true
end

local function PlayerKnowsSpell(spellID)
	spellID = ReadableNumber(spellID)
	if not spellID then
		return false
	end
	if C_SpellBook and C_SpellBook.IsSpellKnown then
		local ok, known = pcall(C_SpellBook.IsSpellKnown, spellID)
		if ok and known then
			return true
		end
	end
	if IsPlayerSpell then
		local ok, known = pcall(IsPlayerSpell, spellID)
		if ok and known then
			return true
		end
	end
	if IsSpellKnown then
		local ok, known = pcall(IsSpellKnown, spellID)
		if ok and known then
			return true
		end
	end
	return false
end

local function RebuildKnownRanks()
	wipe(knownByName)
	knownRanksReady = false
	if not (C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines and C_SpellBook.GetSpellBookSkillLineInfo and C_SpellBook.GetSpellBookItemInfo) then
		return
	end
	local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player
	if not bank or not (C_Spell and C_Spell.GetSpellName) then
		return
	end
	local futureType = Enum and Enum.SpellBookItemType and Enum.SpellBookItemType.FutureSpell
	local okLines, lines = pcall(C_SpellBook.GetNumSpellBookSkillLines)
	if not okLines or type(lines) ~= "number" or lines <= 0 then
		return
	end
	for index = 1, lines do
		local okLine, line = pcall(C_SpellBook.GetSpellBookSkillLineInfo, index)
		if okLine and line and type(line.itemIndexOffset) == "number" and type(line.numSpellBookItems) == "number" then
			local last = line.itemIndexOffset + line.numSpellBookItems
			for slot = line.itemIndexOffset + 1, last do
				local okItem, item = pcall(C_SpellBook.GetSpellBookItemInfo, slot, bank)
				local itemType = okItem and item and item.itemType
				local isFuture = false
				if itemType ~= nil and not SecretBlocked(itemType) then
					isFuture = itemType == futureType or itemType == "FUTURESPELL"
				end
				if okItem and type(item) == "table" and not isFuture then
					local actionID = ReadableNumber(item.actionID)
					local castID = ReadableNumber(item.spellID)
					if actionID and actionID <= 0 then
						actionID = nil
					end
					if castID and castID <= 0 then
						castID = nil
					end
					local id = actionID or castID
					if actionID and castID and actionID ~= castID then
						local actionRank = RankNumber(actionID)
						local castRank = RankNumber(castID)
						if actionRank and castRank and castRank > actionRank then
							id = castID
						end
					end
					if id then
						local name = C_Spell.GetSpellName(id)
						if type(name) == "string" and name ~= "" and not SecretBlocked(name) then
							knownByName[name] = id
						end
					end
				end
			end
		end
	end
	knownRanksReady = true
end

local function EnsureKnownRanks()
	if not knownRanksReady then
		RebuildKnownRanks()
	end
end

function ns.InvalidateKnownRanks()
	knownRanksReady = false
end

--- Rank the player has trained, when `spellID` is an older rank of that spell.
local function CurrentRankSpellID(spellID)
	EnsureKnownRanks()
	if not (C_Spell and C_Spell.GetSpellName) then
		return nil
	end
	local name = C_Spell.GetSpellName(spellID)
	if type(name) ~= "string" or name == "" or SecretBlocked(name) then
		return nil
	end

	local function accept(id)
		id = ReadableNumber(id)
		if not id or id <= 0 or id == spellID or not SameRankFamily(spellID, id) then
			return nil
		end
		local passedRank = RankNumber(spellID)
		local nextRank = RankNumber(id)
		if passedRank and nextRank and nextRank > passedRank then
			return id
		end
		if not PlayerKnowsSpell(spellID) and PlayerKnowsSpell(id) then
			return id
		end
		return nil
	end

	local fromBook = accept(knownByName[name])
	if fromBook then
		return fromBook
	end
	if C_SpellBook and C_SpellBook.FindSpellOverrideByID then
		local upgraded = accept(C_SpellBook.FindSpellOverrideByID(spellID))
		if upgraded then
			return upgraded
		end
	end
	if C_Spell.GetOverrideSpell then
		local upgraded = accept(C_Spell.GetOverrideSpell(spellID))
		if upgraded then
			return upgraded
		end
	end
	if C_Spell.GetSpellIDForSpellIdentifier then
		local upgraded = accept(C_Spell.GetSpellIDForSpellIdentifier(name))
		if upgraded then
			return upgraded
		end
	end

	-- Talent replacement can change the name. Only use it when the stored id
	-- is not the spell the player currently knows.
	if PlayerKnowsSpell(spellID) then
		return nil
	end
	local function knownUpgrade(id)
		id = ReadableNumber(id)
		if id and id > 0 and id ~= spellID and PlayerKnowsSpell(id) then
			return id
		end
		return nil
	end
	if C_SpellBook and C_SpellBook.FindSpellOverrideByID then
		local upgraded = knownUpgrade(C_SpellBook.FindSpellOverrideByID(spellID))
		if upgraded then
			return upgraded
		end
	end
	if C_Spell.GetOverrideSpell then
		local upgraded = knownUpgrade(C_Spell.GetOverrideSpell(spellID))
		if upgraded then
			return upgraded
		end
	end
	return nil
end

local function ReadCostEntry(entry)
	if not CanIndex(entry) then
		return nil
	end
	local powerType = ReadableNumber(entry.type)
	if not powerType or not TRACKED_POWER[powerType] then
		return nil
	end

	local cost = ReadableNumber(entry.cost)
	local minCost = ReadableNumber(entry.minCost)
	-- Important: cost may be 0 while minCost is the real flat cost (0 is truthy in Lua).
	local amount = nil
	if cost and cost > 0 then
		amount = cost
	elseif minCost and minCost > 0 then
		amount = minCost
	end
	if not amount then
		return nil
	end

	local costPercent = ReadableNumber(entry.costPercent) or 0
	local costPerSec = ReadableNumber(entry.costPerSec) or 0
	if costPercent ~= 0 or costPerSec ~= 0 then
		return nil
	end

	return amount, powerType
end

local function DirectSpellCost(spellID)
	local getCosts = (C_Spell and C_Spell.GetSpellPowerCost) or GetSpellPowerCost
	if not getCosts then
		return nil
	end
	local costs = getCosts(spellID)
	if not CanIndex(costs) then
		return nil
	end
	-- Prefer an entry whose required aura is currently met; otherwise still
	-- use a flat cost so stance abilities (Shield Block, Disarm) show.
	local fallbackAmount, fallbackType
	for i = 1, #costs do
		local amount, powerType = ReadCostEntry(costs[i])
		if amount then
			local entry = costs[i]
			local requiredAuraID = ReadableNumber(entry.requiredAuraID)
			if requiredAuraID and requiredAuraID > 0 and entry.hasRequiredAura == false then
				fallbackAmount = fallbackAmount or amount
				fallbackType = fallbackType or powerType
			else
				return amount, powerType
			end
		end
	end
	if fallbackAmount then
		return fallbackAmount, fallbackType
	end
	return nil
end

--- Spellbook cast of the same name, when `spellID` itself has no flat cost
--- (buff-slot aura ids are often "known" and still have no mana cost).
local function SpellbookCastID(spellID)
	EnsureKnownRanks()
	if not (C_Spell and C_Spell.GetSpellName) then
		return nil
	end
	local name = C_Spell.GetSpellName(spellID)
	if type(name) ~= "string" or name == "" or SecretBlocked(name) then
		return nil
	end
	local known = ReadableNumber(knownByName[name])
	if not known or known <= 0 or known == spellID or not SameRankFamily(spellID, known) then
		return nil
	end
	return known
end

--- Flat cost of the player's current rank. A lower rank's cost is not used
--- once a higher trained rank of the same spell is known.
function ns.GetSpellResourceCost(spellID)
	spellID = ReadableNumber(spellID)
	if not spellID or spellID <= 0 then
		return nil
	end

	local current = CurrentRankSpellID(spellID)
	if current then
		return DirectSpellCost(current)
	end
	local amount, powerType = DirectSpellCost(spellID)
	if amount then
		return amount, powerType
	end
	local book = SpellbookCastID(spellID)
	if book then
		return DirectSpellCost(book)
	end
	return nil
end

--- Full cost display only.
function ns.ComputeDisplay(spellID)
	local db = DB()
	if not db or not db.enabled then
		return nil
	end

	local cost, powerType = ns.GetSpellResourceCost(spellID)
	if not cost or not powerType then
		return nil
	end

	local percentKey = PERCENT_KEY[powerType]
	if percentKey and db[percentKey] then
		local maxPower = ReadableNumber(UnitPowerMax("player", powerType))
		if maxPower and maxPower > 0 then
			local pct = math.floor((cost / maxPower) * 100 + 0.5)
			return tostring(pct) .. "%", powerType
		end
	end

	return tostring(math.floor(cost + 0.5)), powerType
end

local function ApplyTextStyle(fs, powerType)
	local db = DB()
	if not db or not fs then
		return
	end

	local size = db.fontSize or 9
	local path, flags = ResolveFont()
	fs:SetFont(path, size, flags)

	if db.tintByResource and powerType and POWER_TINT[powerType] then
		local c = POWER_TINT[powerType]
		fs:SetTextColor(c[1], c[2], c[3], 1)
	else
		fs:SetTextColor(db.colorR or 1, db.colorG or 1, db.colorB or 1, 1)
	end
end

local function LayoutOverlay(fs)
	local db = DB()
	if not fs or not db then
		return
	end
	local anchor = db.anchor or "BOTTOMLEFT"
	fs:ClearAllPoints()
	fs:SetPoint(anchor, fs:GetParent(), anchor, db.offsetX or 1, db.offsetY or 1)
end

function ns.EnsureOverlay(button)
	if not button then
		return nil
	end
	local fs = overlays[button]
	if fs then
		local holder = fs:GetParent()
		if holder and holder ~= button and holder.SetFrameLevel and button.GetFrameLevel then
			holder:SetFrameLevel((button:GetFrameLevel() or 0) + 30)
		end
		return fs
	end

	local holder = CreateFrame("Frame", nil, button)
	holder:SetAllPoints(button)
	holder:EnableMouse(false)
	if holder.EnableMouseMotion then
		holder:EnableMouseMotion(false)
	end
	holder:SetFrameLevel((button:GetFrameLevel() or 0) + 30)

	fs = holder:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
	fs:SetJustifyH("CENTER")
	fs:SetJustifyV("MIDDLE")
	fs:Hide()
	overlays[button] = fs
	LayoutOverlay(fs)
	ApplyTextStyle(fs, nil)
	return fs
end

function ns.HideOverlay(button)
	local fs = overlays[button]
	if fs then
		fs:SetText("")
		fs:Hide()
	end
end

function ns.ClearAllOverlays()
	for _, fs in pairs(overlays) do
		fs:SetText("")
		fs:Hide()
	end
end

function ns.CacheCooldownSpell(cooldownID, spellID)
	cooldownID = ReadableNumber(cooldownID)
	spellID = ReadableNumber(spellID)
	if cooldownID and spellID and spellID > 0 then
		cooldownSpellCache[cooldownID] = spellID
	end
end

function ns.GetCachedCooldownSpell(cooldownID)
	cooldownID = ReadableNumber(cooldownID)
	if not cooldownID then
		return nil
	end
	return cooldownSpellCache[cooldownID]
end

local function GetEcmeModule()
	if not EllesmereUI or not EllesmereUI._ModuleNS then
		return nil
	end
	return EllesmereUI._ModuleNS["EllesmereUICooldownManager"]
end

local function AddSpellCandidate(list, seen, spellID)
	spellID = ReadableNumber(spellID)
	if spellID and spellID > 0 and not seen[spellID] then
		seen[spellID] = true
		list[#list + 1] = spellID
	end
end

local function AddSpellCandidateList(list, seen, spellIDs)
	if type(spellIDs) ~= "table" or not CanIndex(spellIDs) then
		return
	end
	for i = 1, #spellIDs do
		AddSpellCandidate(list, seen, spellIDs[i])
	end
end

local function AddCooldownInfoCandidates(list, seen, info)
	if not CanIndex(info) then
		return
	end
	AddSpellCandidate(list, seen, info.overrideSpellID)
	AddSpellCandidateList(list, seen, info.linkedSpellIDs)
	AddSpellCandidate(list, seen, info.spellID)
end

--- First id in list that has a flat tracked resource cost.
function ns.PickCostSpellID(spellIDs)
	if type(spellIDs) ~= "table" then
		return nil
	end
	for i = 1, #spellIDs do
		local spellID = ReadableNumber(spellIDs[i])
		if spellID and spellID > 0 and ns.GetSpellResourceCost(spellID) then
			return spellID
		end
	end
	return nil
end

local function ReadCooldownID(child, fc)
	local cdID = ReadableNumber(child.cooldownID)
	if not cdID and CanIndex(child.cooldownInfo) then
		cdID = ReadableNumber(child.cooldownInfo.cooldownID)
	end
	if not cdID and CanIndex(fc) then
		cdID = ReadableNumber(fc.cachedCdID)
	end
	return cdID
end

--- Spell bars already carry a cast id with a cost. Buff viewers often expose a
--- spec aura (no cost) or a secret id while the aura is up, so walk aura,
--- canonical, and linked ids and keep the first one that has a flat cost.
function ns.ResolveCdmSpellID(child)
	if not child then
		return nil
	end

	local list = {}
	local seen = {}
	local eui = GetEcmeModule()
	local fc
	if eui and eui._ecmeFC then
		fc = eui._ecmeFC[child]
	end

	-- Missing-buff placeholders are Ellesmere's own frames. Their live spell
	-- getters and cooldown links are secret or shared while any other aura is
	-- up. The icon's spell is the plain id Ellesmere stored on the frame.
	if child._isPlaceholderFrame then
		AddSpellCandidate(list, seen, child._phSpellID)
		if CanIndex(fc) then
			AddSpellCandidate(list, seen, fc.spellID)
		end
		return ns.PickCostSpellID(list)
	end

	if eui and type(eui.GetCanonicalSpellIDForFrame) == "function" then
		local ok, sid = pcall(eui.GetCanonicalSpellIDForFrame, child)
		if ok then
			AddSpellCandidate(list, seen, sid)
		end
	end

	if CanIndex(fc) then
		AddSpellCandidate(list, seen, fc.resolvedSid)
		AddSpellCandidate(list, seen, fc.spellID)
		AddSpellCandidate(list, seen, fc.baseSpellID)
		AddSpellCandidateList(list, seen, fc.linkedSpellIDs)
	end

	local cdID = ReadCooldownID(child, fc)
	if cdID and eui and type(eui._cdmCleanSidByCDID) == "table" then
		AddSpellCandidate(list, seen, eui._cdmCleanSidByCDID[cdID])
	end

	if type(child.GetAuraSpellID) == "function" then
		local ok, sid = pcall(child.GetAuraSpellID, child)
		if ok then
			AddSpellCandidate(list, seen, sid)
		end
	end
	if type(child.GetSpellID) == "function" then
		local ok, sid = pcall(child.GetSpellID, child)
		if ok then
			AddSpellCandidate(list, seen, sid)
		end
	end

	if cdID then
		AddSpellCandidate(list, seen, ns.GetCachedCooldownSpell(cdID))
		if C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo then
			local info = C_CooldownViewer.GetCooldownViewerCooldownInfo(cdID)
			AddCooldownInfoCandidates(list, seen, info)
		end
	end
	AddCooldownInfoCandidates(list, seen, child.cooldownInfo)

	local picked = ns.PickCostSpellID(list)
	if picked and cdID then
		ns.CacheCooldownSpell(cdID, picked)
	end
	return picked
end

function ns.ResolveActionSpellID(button)
	if not button then
		return nil
	end

	local action
	if button.GetAttribute then
		local ok, value = pcall(button.GetAttribute, button, "action")
		if ok then
			action = ReadableNumber(value)
		end
	end
	if not action or action <= 0 then
		action = ReadableNumber(button.action)
	end
	if not action or action <= 0 then
		return nil
	end

	local actionType, id = GetActionInfo(action)
	actionType = ReadableString(actionType)
	id = ReadableNumber(id)
	if not actionType or not id then
		return nil
	end

	if actionType == "spell" then
		return id
	end
	if actionType == "macro" then
		if GetMacroSpell then
			local sid = ReadableNumber(GetMacroSpell(id))
			if sid and sid > 0 then
				return sid
			end
		end
		-- Named macros sometimes only resolve through the action slot helper.
		if GetActionText then
			local name = GetActionText(action)
			if type(name) == "string" and name ~= "" and C_Spell and C_Spell.GetSpellIDForSpellIdentifier then
				local sid = ReadableNumber(C_Spell.GetSpellIDForSpellIdentifier(name))
				if sid and sid > 0 then
					return sid
				end
			end
		end
	end
	-- Some Forever slots report an unusual type/subtype but still map to a spell.
	if C_Spell and C_Spell.GetSpellInfo then
		local info = C_Spell.GetSpellInfo(id)
		if CanIndex(info) then
			local sid = ReadableNumber(info.spellID) or id
			if sid and sid > 0 and C_Spell.DoesSpellExist and C_Spell.DoesSpellExist(sid) then
				-- Only accept if it actually has a resource cost candidate.
				if ns.GetSpellResourceCost(sid) then
					return sid
				end
			end
		end
	end
	return nil
end

function ns.UpdateButtonOverlay(button, spellID)
	if not button then
		return
	end

	local db = DB()
	if not db or not db.enabled then
		ns.HideOverlay(button)
		return
	end

	if not spellID then
		ns.HideOverlay(button)
		return
	end

	local text, powerType = ns.ComputeDisplay(spellID)
	if not text then
		ns.HideOverlay(button)
		return
	end

	local fs = ns.EnsureOverlay(button)
	if layoutDirty then
		LayoutOverlay(fs)
	end
	ApplyTextStyle(fs, powerType)
	fs:SetText(text)
	fs:Show()
end

function ns.MarkLayoutDirty()
	layoutDirty = true
end

function ns.SetTrackedButtons(list)
	trackedButtons = list or {}
end

function ns.GetTrackedButtons()
	return trackedButtons
end

function ns.RefreshAll()
	local db = DB()
	if not db or not db.enabled then
		ns.ClearAllOverlays()
		pendingRefresh = false
		return
	end

	if ns.CollectTargets then
		ns.CollectTargets()
	end

	ns.ClearAllOverlays()

	for i = 1, #trackedButtons do
		local entry = trackedButtons[i]
		local button = entry and entry.button
		if button then
			local spellID
			if entry.kind == "cdm" then
				spellID = entry.spellID or ns.ResolveCdmSpellID(button)
			else
				-- Always re-resolve: page/bonus remaps change action without new collect cache.
				spellID = ns.ResolveActionSpellID(button)
			end
			ns.UpdateButtonOverlay(button, spellID)
		end
	end

	layoutDirty = false
	pendingRefresh = false
end

function ns.RequestRefresh(immediate)
	if immediate then
		ns.RefreshAll()
		return
	end
	pendingRefresh = true
	refreshAt = GetTime() + REFRESH_THROTTLE
end

local function OnUpdate()
	if not pendingRefresh then
		return
	end
	if GetTime() >= refreshAt then
		ns.RefreshAll()
	end
end

local function OnEvent(_, event, arg1)
	if event == "ADDON_LOADED" then
		if arg1 ~= ADDON_NAME then
			return
		end
		ns.db = ns.LoadDB(_G.ResourceCostOverlayDB)
		_G.ResourceCostOverlayDB = ns.db
		return
	end

	if event == "PLAYER_LOGIN" then
		Print("Type |cffffffff/rco|r to open settings.")
		ns.InvalidateKnownRanks()
		if ns.InitOptions then
			ns.InitOptions()
		end
		if ns.CreateMinimapButton then
			ns.CreateMinimapButton()
		end
		if ns.HookTargets then
			ns.HookTargets()
		end
		ns.RequestRefresh(true)
		return
	end

	if event == "PLAYER_ENTERING_WORLD" then
		ns.InvalidateKnownRanks()
		if ns.InitOptions then
			ns.InitOptions()
		end
		if ns.CreateMinimapButton then
			ns.CreateMinimapButton()
		end
		if ns.HookTargets then
			ns.HookTargets()
		end
		ns.RequestRefresh(true)
		return
	end

	if event == "UNIT_AURA" then
		if arg1 ~= "player" then
			return
		end
		-- Ellesmere repaints missing-buff placeholders shortly after the aura
		-- event. Wait so _phSpellID is set before we draw.
		if C_Timer and C_Timer.After then
			C_Timer.After(0.3, function()
				ns.RequestRefresh(false)
			end)
		else
			ns.RequestRefresh(false)
		end
		return
	end

	if event == "UNIT_MAXPOWER" and arg1 ~= "player" then
		return
	end

	if event == "SPELLS_CHANGED" or event == "PLAYER_SPECIALIZATION_CHANGED" or event == "TRAIT_CONFIG_UPDATED" then
		ns.InvalidateKnownRanks()
	end

	ns.MarkLayoutDirty()
	ns.RequestRefresh(true)
end

driver:RegisterEvent("ADDON_LOADED")
driver:RegisterEvent("PLAYER_LOGIN")
driver:RegisterEvent("PLAYER_ENTERING_WORLD")
driver:RegisterEvent("SPELLS_CHANGED")
driver:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
driver:RegisterEvent("ACTIONBAR_PAGE_CHANGED")
driver:RegisterEvent("UPDATE_BONUS_ACTIONBAR")
driver:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
driver:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
driver:RegisterEvent("UNIT_MAXPOWER")
if driver.RegisterUnitEvent then
	driver:RegisterUnitEvent("UNIT_AURA", "player")
else
	driver:RegisterEvent("UNIT_AURA")
end
pcall(driver.RegisterEvent, driver, "ACTIONBAR_UPDATE_STATE_CHANGED")
pcall(driver.RegisterEvent, driver, "PLAYER_SPECIALIZATION_CHANGED")
pcall(driver.RegisterEvent, driver, "TRAIT_CONFIG_UPDATED")

driver:SetScript("OnEvent", OnEvent)
driver:SetScript("OnUpdate", OnUpdate)

function ns.SetEnabled(enabled)
	local db = DB()
	if not db then
		return
	end
	db.enabled = enabled and true or false
	ns.RequestRefresh(true)
end

function ns.ApplySettings()
	ns.MarkLayoutDirty()
	ns.RequestRefresh(true)
end
