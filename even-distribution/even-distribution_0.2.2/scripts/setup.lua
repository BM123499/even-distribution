-- Sets up the global table

local setup = {}
local util = scripts.util

local defaultTrash = require("default-trash")

local entityAsIndex = { -- metatable for using an entity as a table index
	__index = function (tbl, entity)
		if type(entity) == "table" and entity.valid then
			local id = entity.unit_number
			
			if id then
				local tblId = rawget(tbl, "id")
				if tblId then return tblId[id] end
			else
				local tblPos = rawget(tbl, "pos")
			
				if tblPos then 
					local surface, pos = entity.surface.name, entity.position
					local x, y = pos.x, pos.y
					local tbls = tblPos[surface]
					
					if tbls then
						local tblsx = tbls[x]
						if tblsx then return tblsx[y] end
					end
				end
			end
		end
    end,
	
	__newindex = function (tbl, entity, value)
		local id = entity.unit_number
		local count = rawget(tbl, "count") or 0
		
		if id then -- entities indexed by unit number
			local tblId = rawget(tbl, "id")
			
			if tblId then 
				local oldvalue = tblId[id]
				if value ~= oldvalue then
					if value == nil then
						rawset(tbl, "count", count - 1)
					else
						rawset(tbl, "count", count + 1)
					end
					
					tblId[id] = value
				end
			elseif value ~= nil then
				rawset(tbl, "id", { [entity.unit_number] = value })
				rawset(tbl, "count", count + 1)
			end
		else -- other entities that don't support unit number indexed by their surface and position
			local surface, pos = entity.surface.name, entity.position
			local x, y = pos.x, pos.y
			local tblPos = rawget(tbl, "pos")
			
			if tblPos then
				local tbls = tblPos[surface]
				
				if tbls then
					local tblsx = tbls[x]
					
					if tblsx then
						local oldvalue = tblsx[y]
						if value ~= oldvalue then
							if value == nil then
								rawset(tbl, "count", count - 1)
							else
								rawset(tbl, "count", count + 1)
							end
							
							tblsx[y] = value
						end
					elseif value ~= nil then
						tbls[x] = { [y] = value }
						rawset(tbl, "count", count + 1)
					end
				elseif value ~= nil then
					tblPos[surface] = { [x] = { [y] = value } }
					rawset(tbl, "count", count + 1)
				end
			elseif value ~= nil then
				rawset(tbl, "pos", { [surface] = { [x] = { [y] = value } } })
				rawset(tbl, "count", count + 1)
			end
		end
    end,
	
	__len = function (tbl)
		return rawget(tbl, "count") or 0
	end
}

function setup.on_init()
	global.cache = global.cache or {}
	global.distrEvents = global.distrEvents or {}
	global.settings = {}
	global.defaultTrash = setup.generateTrashItemList()
	global.furnaceRecipes = setup.parseFurnaceRecipes()
	
	for player_index,_ in pairs(game.players) do
		setup.createPlayerCache(player_index)
		setup.parsePlayerSettings(player_index)
	end
end

setup.on_configuration_changed = setup.on_init

function setup.on_player_created(event)
	setup.createPlayerCache(event.player_index)
	setup.parsePlayerSettings(event.player_index)
end

function setup.on_runtime_mod_setting_changed(event)
	if event.setting == "inventory-cleanup-custom-trash" then
		setup.parsePlayerSettings(event.player_index)
	end
end

function setup.createPlayerCache(index)
	global.cache[index] = global.cache[index] or {}
	global.cache[index].items = global.cache[index].items or {}
	global.cache[index].markers = global.cache[index].markers or {}
	setup.useEntityAsIndex(global.cache[index].markers)
	global.cache[index].entities = global.cache[index].entities or {}
	setup.useEntityAsIndex(global.cache[index].entities)
end

function setup.parsePlayerSettings(index)
	global.settings[index] = {
		customTrash = setup.parseCustomTrashSetting(index)
	}
end

function setup.parseCustomTrashSetting(index)
	local setting = game.players[index].mod_settings["inventory-cleanup-custom-trash"].value
	local result = {}
	
	for item,count in string.gmatch(setting, "%s*([^ :]+):(%d+)%s*") do
		result[item] = count
	end
	
	return result
end

function setup.on_load()
	for _,cache in pairs(global.cache) do
		setup.useEntityAsIndex(cache.markers)
		setup.useEntityAsIndex(cache.entities)
	end
end

function setup.useEntityAsIndex(tbl)
	if tbl then setmetatable(tbl, entityAsIndex) end
end

function setup.newEAITable() -- creates new table with entity as index
	local tbl = {}
	setup.useEntityAsIndex(tbl)
	return tbl
end

function setup.generateTrashItemList()
	local items = {}
	
	for name,item in pairs(game.item_prototypes) do
		if not (item.place_result or item.place_as_equipment_result or item.flags.hidden) then -- or item.place_as_tile_result
			local default = defaultTrash[name] or defaultTrash[item.subgroup.name] or defaultTrash[item.group.name]
			
			if default and default ~= "ignore" then
				if item.fuel_category and not defaultTrash[name] then -- fuels default to 2 stacks as desired amount
					items[name] = 2 * item.stack_size
				else
					items[name] = default
				end
			end
		end
	end
	
	return items
end

function setup.parseFurnaceRecipes()
	local list = {}
	for name,recipe in pairs(game.recipe_prototypes) do
		local category = recipe.category
		list[category] = list[category] or {}
		
		local ingredients, products = recipe.ingredients, recipe.products
		if #ingredients == 1 and #products == 1 then
			local ingredient, product = ingredients[1], products[1]
			if ingredient.type == "item" and product.type == "item" then
				list[category][product.name] = list[category][product.name] or {}
				list[category][product.name][ingredient.name] = true
			end
		end
	end
	return list
end

return setup