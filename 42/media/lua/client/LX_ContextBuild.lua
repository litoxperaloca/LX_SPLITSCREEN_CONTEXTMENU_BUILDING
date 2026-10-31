--[[
    LX_SPLITSCREEN_CONTEXTMENU_BUILDING
    "Quick build" in the world context menu (right click / controller button), the way B41
    did it: walls, frames, doors, floors, fences and stairs in wood, metal and brick/stone,
    plus furniture and outdoors, WITHOUT opening B42's build window (which is very wide and
    in split-screen falls outside the player's viewport).

    It uses exactly the same system as the vanilla window:
      BuildLogic (Java)  -> buildable recipes, validity (skill / recipe known)
                            and availability (materials and tools)
      ISBuildIsoEntity   -> placement cursor (mouse or controller: d-pad moves, LB/RB rotate,
                            A builds, B cancels), consumes materials and starts the action.
    After each build the cursor stays active so you can keep building (like B41).

    v1.1.0 - every label is translatable (EN/ES), menu can be switched off in the options.
]]

LXContextBuild = LXContextBuild or {}
local M = LXContextBuild

-- Build categories, in menu order. 'key' is BuildLogic's own category name.
M.CATEGORIES = {
    { key = "Carpentry", text = "UI_LXCB_cat_carpentry" },
    { key = "Welding", text = "UI_LXCB_cat_welding" },
    { key = "Masonry", text = "UI_LXCB_cat_masonry" },
    { key = "Furniture", text = "UI_LXCB_cat_furniture" },
    { key = "Outdoors", text = "UI_LXCB_cat_outdoors" },
}

-- Grouped by the recipe's internal name (order matters: first match wins).
M.GROUPS = {
    { key = "stairs", text = "UI_LXCB_grp_stairs", match = { "stairs" } },
    { key = "doorframe", text = "UI_LXCB_grp_doorframes", match = { "doorframe" } },
    { key = "windowframe", text = "UI_LXCB_grp_windowframes", match = { "windowframe" } },
    { key = "wall", text = "UI_LXCB_grp_walls", match = { "wall" } },
    { key = "door", text = "UI_LXCB_grp_doors", match = { "door", "gate" } },
    { key = "floor", text = "UI_LXCB_grp_floors", match = { "floor" } },
    { key = "fence", text = "UI_LXCB_grp_fences", match = { "fence" } },
    { key = "table", text = "UI_LXCB_grp_tables", match = { "table" } },
    { key = "seating", text = "UI_LXCB_grp_seating", match = { "chair", "stool", "bench" } },
    { key = "shelves", text = "UI_LXCB_grp_shelves", match = { "shelves", "bookcase" } },
    { key = "storage", text = "UI_LXCB_grp_storage", match = { "crate", "locker", "cabinet" } },
    { key = "counters", text = "UI_LXCB_grp_counters", match = { "barelement", "counter" } },
    { key = "shelter", text = "UI_LXCB_grp_shelters", match = { "shelter" } },
    { key = "water", text = "UI_LXCB_grp_water", match = { "raincollector" } },
}
M.OTHERS = { key = "others", text = "UI_LXCB_grp_others" }
M.MAX_FLAT = 9 -- categories with few recipes are listed without subgroups

local opt = { enabled = true, counts = true }

local function log(msg) print("[LX_ContextBuild] " .. tostring(msg)) end

-- Label plus "available/total", if that option is on.
local function withCount(label, available, total)
    if not opt.counts then return label end
    return label .. " (" .. available .. "/" .. total .. ")"
end

-- ---------------------------------------------------------------- catalogue (once)
local catalog = nil -- [categoryKey] = { {recipe, name, display, group}, ... }

local function groupKeyFor(name)
    local low = string.lower(name or "")
    for _, g in ipairs(M.GROUPS) do
        for _, k in ipairs(g.match) do
            if string.find(low, k, 1, true) then return g.key end
        end
    end
    return M.OTHERS.key
end

local function buildCatalog(player)
    local logic = BuildLogic.new(player, nil, nil)
    local all = logic:getAllBuildableRecipes()
    local wanted = {}
    for _, c in ipairs(M.CATEGORIES) do wanted[c.key] = true end
    local cat = {}
    for i = 0, all:size() - 1 do
        local recipe = all:get(i)
        local key = recipe:getCategory()
        local placeable = false
        if key and wanted[key] then
            -- drop recipes with no placeable object (e.g. vanilla's Wooden_Windows is broken)
            local ok, obj = pcall(function()
                logic:setRecipe(recipe)
                return logic:getSelectedBuildObject()
            end)
            placeable = ok and obj ~= nil
            if not placeable then log("recipe skipped (no placeable object): " .. tostring(recipe:getName())) end
        end
        if placeable then
            local name = recipe:getName()
            local display = recipe:getTranslationName()
            if not display or display == "" then display = name end
            cat[key] = cat[key] or {}
            table.insert(cat[key], { recipe = recipe, name = name, display = display, group = groupKeyFor(name) })
        end
    end
    for _, list in pairs(cat) do
        table.sort(list, function(a, b) return a.display < b.display end)
    end
    return cat
end

-- ---------------------------------------------------------------- available inventory
-- Counts items (and drainable uses) across every reachable container, once per menu.
local function countItems(containers)
    local counts, uses = {}, {}
    for c = 0, containers:size() - 1 do
        local items = containers:get(c):getItems()
        for i = 0, items:size() - 1 do
            local it = items:get(i)
            local t = it:getFullType()
            counts[t] = (counts[t] or 0) + 1
            if it.getCurrentUses then
                local ok, u = pcall(it.getCurrentUses, it)
                if ok and u then uses[t] = (uses[t] or 0) + u end
            end
        end
    end
    return counts, uses
end

local function perkName(perk)
    local ok, n = pcall(perk.getName, perk)
    if ok and n then return n end
    return tostring(perk)
end

-- ---------------------------------------------------------------- tooltip
local function buildTooltip(player, entry, info, counts, uses)
    local recipe = entry.recipe
    local tip = ISWorldObjectContextMenu.addToolTip()
    tip:setName(entry.display)
    local d = ""

    -- requirements (skill / recipe known)
    local n = recipe:getRequiredSkillCount()
    for i = 0, n - 1 do
        local rs = recipe:getRequiredSkill(i)
        local have = player:getPerkLevel(rs:getPerk())
        local ok = have >= rs:getLevel()
        d = d .. (ok and " <RGB:0.6,1,0.6> " or " <RGB:1,0.4,0.4> ") .. perkName(rs:getPerk()) .. " " .. rs:getLevel()
            .. " (" .. getText("UI_LXCB_you_have") .. " " .. have .. ") <LINE>"
    end
    if recipe:needToBeLearn() and not player:isRecipeKnown(recipe) then
        d = d .. " <RGB:1,0.4,0.4> " .. getText("UI_LXCB_not_learned") .. " <LINE>"
    end

    -- materials and tools
    local inputs = recipe:getInputs()
    if inputs and inputs:size() > 0 then
        d = d .. " <RGB:1,1,1> " .. getText("UI_LXCB_needs") .. " <LINE>"
        for i = 0, inputs:size() - 1 do
            local input = inputs:get(i)
            local possible = input:getPossibleInputItems()
            if possible and possible:size() > 0 then
                local byUses = not input:isItemCount()
                local required = byUses and input:getAmount() or input:getIntAmount()
                local available = 0
                for m = 0, possible:size() - 1 do
                    local ft = possible:get(m):getFullName()
                    available = available + (byUses and (uses[ft] or 0) or (counts[ft] or 0))
                end
                local nameTxt = getItemNameFromFullType(possible:get(0):getFullName())
                if possible:size() > 1 then nameTxt = nameTxt .. " " .. getText("UI_LXCB_or_similar") end
                local isTool = input:isKeep() or input:isTool()
                local color = (available >= required) and " <RGB:0.6,1,0.6> " or " <RGB:1,0.4,0.4> "
                if isTool then
                    d = d .. color .. getText("UI_LXCB_tool") .. " " .. nameTxt .. " <LINE>"
                else
                    d = d .. color .. nameTxt .. " " .. math.min(available, required) .. "/" .. required .. " <LINE>"
                end
            end
        end
    end

    if info and info:isValid() and not info:isCanPerform() then
        d = d .. " <RGB:1,0.8,0.3> " .. getText("UI_LXCB_missing") .. " <LINE>"
    end
    tip.description = d
    local ok, tex = pcall(recipe.getIconTexture, recipe)
    if ok and tex then tip.texture = tex end
    return tip
end

-- ---------------------------------------------------------------- build (cursor)
local function getTool(inputScript, inventory)
    if not inputScript then return nil end
    local entryItems = inputScript:getPossibleInputItems()
    for m = 0, entryItems:size() - 1 do
        local itemType = entryItems:get(m):getFullName()
        local result = inventory:getAllTypeEvalRecurse(itemType, ISBuildIsoEntity.predicateMaterial)
        if result:size() > 0 then return result:get(0):getFullType() end
    end
    return nil
end

function M.onStopCraft(ctx)
    -- a build finished (or was cancelled): re-arm the cursor for the next one
    local ok, err = pcall(function()
        local n = ctx.player:getPlayerNum()
        if getCell():getDrag(n) ~= ctx.cursor then return end
        ctx.logic:setContainers(ISInventoryPaneContextMenu.getContainers(ctx.player))
        ctx.logic:autoPopulateInputs()
        local can = ctx.logic:canPerformCurrentRecipe() or ctx.player:isBuildCheat()
        ctx.cursor.blockBuild = not can
    end)
    if not ok then log("onStopCraft: " .. tostring(err)) end
end

function M.onBuild(player, entry, logic)
    local ok, err = pcall(function()
        local n = player:getPlayerNum()
        local containers = ISInventoryPaneContextMenu.getContainers(player)
        logic:setContainers(containers)
        logic:setRecipe(entry.recipe)
        logic:autoPopulateInputs()
        local info = logic:getSelectedBuildObject()
        if not info then
            log("recipe " .. tostring(entry.name) .. " has no placeable object")
            return
        end
        local cursor = ISBuildIsoEntity:new(player, info, 1, containers, logic)
        cursor.dragNilAfterPlace = false -- stays active to build another piece
        cursor.blockAfterPlace = true    -- blocked while the action runs
        local inventory = player:getInventory()
        cursor.equipBothHandItem = getTool(entry.recipe:getToolBoth(), inventory)
        cursor.firstItem = getTool(entry.recipe:getToolRight(), inventory)
        cursor.secondItem = getTool(entry.recipe:getToolLeft(), inventory)
        cursor.blockBuild = not (logic:canPerformCurrentRecipe() or player:isBuildCheat())
        logic:addEventListener("onStopCraft", M.onStopCraft, { player = player, cursor = cursor, logic = logic })
        getCell():setDrag(cursor, n)
    end)
    if not ok then log("onBuild: " .. tostring(err)) end
end

-- ---------------------------------------------------------------- menu
local function addEntry(menu, player, entry, logic, counts, uses)
    local info = logic:getCachedRecipeInfo(entry.recipe)
    local option = menu:addOption(entry.display, player, M.onBuild, entry, logic)
    if not info:isAvailable() then option.notAvailable = true end
    option.toolTip = buildTooltip(player, entry, info, counts, uses)
end

local function countAvailable(list, logic)
    local n = 0
    for _, e in ipairs(list) do
        if logic:getCachedRecipeInfo(e.recipe):isAvailable() then n = n + 1 end
    end
    return n
end

local function fillMenu(player, context, worldobjects)
    if not catalog then catalog = buildCatalog(player) end

    local logic = BuildLogic.new(player, nil, nil)
    logic:getAllBuildableRecipes() -- registers the recipes for getSelectedBuildObject()
    local containers = ISInventoryPaneContextMenu.getContainers(player)
    logic:setContainers(containers)
    local counts, uses = countItems(containers)

    local rootOption = context:addOption(getText("UI_LXCB_root"), worldobjects, nil)
    local rootMenu = ISContextMenu:getNew(context)
    context:addSubMenu(rootOption, rootMenu)

    for _, c in ipairs(M.CATEGORIES) do
        local entries = catalog[c.key]
        if entries and #entries > 0 then
            local label = withCount(getText(c.text), countAvailable(entries, logic), #entries)
            local catOption = rootMenu:addOption(label, worldobjects, nil)
            local catMenu = rootMenu:getNew(rootMenu)
            context:addSubMenu(catOption, catMenu)

            if #entries <= M.MAX_FLAT then
                for _, e in ipairs(entries) do addEntry(catMenu, player, e, logic, counts, uses) end
            else
                -- subgroups in M.GROUPS order, "Others" last
                local byGroup, order = {}, {}
                for _, e in ipairs(entries) do
                    if not byGroup[e.group] then byGroup[e.group] = {} end
                    table.insert(byGroup[e.group], e)
                end
                for _, g in ipairs(M.GROUPS) do
                    if byGroup[g.key] then table.insert(order, g) end
                end
                if byGroup[M.OTHERS.key] then table.insert(order, M.OTHERS) end
                for _, g in ipairs(order) do
                    local list = byGroup[g.key]
                    local gText = withCount(getText(g.text), countAvailable(list, logic), #list)
                    local gOption = catMenu:addOption(gText, worldobjects, nil)
                    local gMenu = catMenu:getNew(catMenu)
                    context:addSubMenu(gOption, gMenu)
                    for _, e in ipairs(list) do addEntry(gMenu, player, e, logic, counts, uses) end
                end
            end
        end
    end
end

local function onFillWorldObjectContextMenu(playerNum, context, worldobjects, test)
    if not opt.enabled then return end
    local player = getSpecificPlayer(playerNum)
    if not player or player:isDead() or player:getVehicle() then return end
    if test then return ISWorldObjectContextMenu.setTest() end
    local ok, err = pcall(fillMenu, player, context, worldobjects)
    if not ok then log("error building the menu: " .. tostring(err)) end
end

Events.OnFillWorldObjectContextMenu.Add(onFillWorldObjectContextMenu)

-- ---------------------------------------------------------------- options
if PZAPI and PZAPI.ModOptions then
    local o = PZAPI.ModOptions:create("LXContextBuild", getText("UI_LXCB_name"))
    o:addDescription(getText("UI_LXCB_desc"))
    o:addSeparator()
    local tEnabled = o:addTickBox("ENABLED", getText("UI_LXCB_enable"), true, getText("UI_LXCB_enable_tip"))
    local tCounts = o:addTickBox("COUNTS", getText("UI_LXCB_counts"), true, getText("UI_LXCB_counts_tip"))

    o.apply = function(self)
        opt.enabled = tEnabled:getValue() == true
        opt.counts = tCounts:getValue() == true
        if tCounts and tCounts.setEnabled then pcall(tCounts.setEnabled, tCounts, opt.enabled) end
    end
    tEnabled.onChange = function(self, value) o:apply() end

    -- PZAPI does not call apply() on load: force it on menu entry and on game start.
    Events.OnMainMenuEnter.Add(function() o:apply() end)
    Events.OnGameStart.Add(function() o:apply() end)
end
