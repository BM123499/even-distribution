-- Common functions for handling items

local item_lib = {}
local util = scripts.util

function item_lib.getPlayerItemCount(player, item, includeCar)
	local cursor_stack = player.cursor_stack
	local count = player.get_inventory(defines.inventory.player_main).get_item_count(item) +
				  player.get_inventory(defines.inventory.player_quickbar).get_item_count(item)
	
	if cursor_stack.valid_for_read and cursor_stack.name == item then
		count = count + cursor_stack.count
	end
	
	if includeCar and player.driving and util.isValid(player.vehicle) then
		local vehicle = player.vehicle.get_inventory(defines.inventory.car_trunk)
		if util.isValid(vehicle) then count = count + vehicle.get_item_count(item) end
	end
		   
	return count
end

function item_lib.getPlayerContents(player)
	local contents = player.get_inventory(defines.inventory.player_main).get_contents()
	
	for item,count in pairs(player.get_quickbar().get_contents()) do
		contents[item] = (contents[item] or 0) + count
	end
	
	local cursor_stack = player.cursor_stack
	if cursor_stack.valid_for_read then
		local item = cursor_stack.name
		contents[item] = (contents[item] or 0) + cursor_stack.count
	end
		   
	return contents
end

function item_lib.getPlayerRequests(player)
	local requests = {}
	local character = player.character
	
	if character.request_slot_count > 0 then -- fetch requests
		for i = 1, character.request_slot_count do
			local request = character.get_request_slot(i)
			if request then
				local item, amount = request.name, request.count
				requests[item] = (requests[item] or 0) + amount
			end
		end
	end
	
	return requests
end

function item_lib.getBuildingItemCount(entity, item) -- counts the items and also includes items that are being consumed (fuel in burners, ingredients in assemblers, etc.)
	local count = entity.get_item_count(item)
	local type = entity.prototype.type
	
	if type == "assembling-machine" or type == "furnace" then
		if entity.recipe and entity.crafting_progress > 0 then
			count = count + item_lib.getRecipeIngredientCount(entity.recipe, item)
		end
	else
		count = count + item_lib.getOutputEntityItemCount(entity, item, "inserter")
		count = count + item_lib.getOutputEntityItemCount(entity, item, "loader")
	end
	if entity.burner then
		local burning = entity.burner.currently_burning
		if burning and burning.name == item then count = count + 1 end
	end
	
	return count
end

function item_lib.getOutputEntityItemCount(origin, item, outputType) -- get count of a specific item in any output inserters/loaders
	local count = 0
	for _,entity in pairs(origin.surface.find_entities_filtered{
		type = outputType, area = util.offsetBox(util.extendBox(origin.prototype.collision_box, 3), origin.position)
	}) do
		if outputType == "inserter" then
			if entity.pickup_target == origin then
				local held = entity.held_stack
				if held.valid_for_read and held.name == item then count = count + held.count end
			end
		elseif outputType == "loader" then
			if entity.loader_type == "output" then count = count + entity.get_item_count(item) end
		end
	end
	return count
end

function item_lib.getRecipeIngredientCount(recipe, item) -- get count of a specific item in recipe ingredients
	for _,ingredient in pairs(recipe.ingredients) do
		if ingredient.name == item then return ingredient.amount end
	end
	return 0
end

function item_lib.isIngredient(item, recipe)
	if not recipe then return false end
	for _,ingredient in ipairs(recipe.ingredients) do
		if ingredient.type == "item" and ingredient.name == item then return true end
	end
end

function item_lib.isTurretAmmo(item, turret)
	local attackParameters = turret.prototype.attack_parameters
	local ammoType = item.get_ammo_type("turret") or item.get_ammo_type()
	return attackParameters and (attackParameters.ammo_category == ammoType.category)
end

function item_lib.getRequestAmount(item, requester)
	local count = 0
	if requester.request_slot_count > 0 then
		for i = 1, requester.request_slot_count do
			local request = requester.get_request_slot(i)
			if request and request.name == item then count = count + request.count end
		end
	end
	return count
end

function item_lib.getRemainingRequest(item, requester)
	return item_lib.getRequestAmount(item, requester) - item_lib.getBuildingItemCount(requester, item)
end

function item_lib.getInputInventory(entity)
	return entity.get_inventory(defines.inventory.furnace_source) or
		   entity.get_inventory(defines.inventory.assembling_machine_input) or
		   entity.get_inventory(defines.inventory.lab_input) or
		   entity.get_inventory(defines.inventory.rocket_silo_rocket)
end

function item_lib.isInputItem(item, entity) -- is item already in one of the input slots?
	local inventory = item_lib.getInputInventory(entity)
	if inventory then return inventory.get_item_count(item) > 0 end
	return false
end

function item_lib.removePlayerItems(player, item, amount, takeFromCar, takeFromTrash)
	local removed = 0
	if takeFromTrash then
		local trash = player.get_inventory(defines.inventory.player_trash)
		if util.isValid(trash) then
			removed = trash.remove{ name = item, count = amount }
			if amount <= removed then return removed end
		end
	end	
	
	removed = removed + player.get_inventory(defines.inventory.player_main).remove{ name = item, count = amount - removed }
	if amount <= removed then return removed end
	
	removed = removed + player.get_inventory(defines.inventory.player_quickbar).remove{ name = item, count = amount - removed }
	if amount <= removed then return removed end
	
	local cursor_stack = player.cursor_stack
	if cursor_stack.valid_for_read and cursor_stack.name == item then
		local result = math.min(cursor_stack.count, amount - removed)
		removed = removed + result
		cursor_stack.count = cursor_stack.count - result
		if amount <= removed then return removed end
	end
	
	if takeFromCar and player.driving and util.isValid(player.vehicle) then
		local vehicle = player.vehicle.get_inventory(defines.inventory.car_trunk)
		if util.isValid(vehicle) then removed = removed + vehicle.remove{ name = item, count = amount - removed } end
	end
	
	return removed
end

function item_lib.entityInsert(entity, item, amount, safemode)
	if safemode then
		if entity.type == "furnace" and not (entity.recipe or item_lib.isInputItem(item, entity)) then -- furnace recipe fix
			local inventory = entity.get_fuel_inventory()
			if inventory then return inventory.insert{ name = item, count = amount } else return 0 end
		elseif entity.prototype.logistic_mode == "requester" then
			local requested = item_lib.getRemainingRequest(item, entity)
			if requested > 0 then return entity.insert{ name = item, count = math.min(amount, requested) } else return 0 end
		elseif game.item_prototypes[item].type == "module" and entity.get_module_inventory() then -- module slot fix
			local inventory = item_lib.getInputInventory(entity)  
			if inventory then return inventory.insert{ name = item, count = amount } else return 0 end
		end
	end
	
	return entity.insert{ name = item, count = amount }
end

function item_lib.returnToPlayer(player, item, amount, takenFromCar, takenFromTrash)
	local remaining = amount - player.insert{ name = item, count = amount }
	
	if remaining > 0 and takenFromCar and player.driving and util.isValid(player.vehicle) then
		local vehicle = player.vehicle.get_inventory(defines.inventory.car_trunk)
		if util.isValid(vehicle) then remaining = remaining - vehicle.insert{ name = item, count = remaining } end
	end
	
	if remaining > 0 and takenFromTrash then
		local trash = player.get_inventory(defines.inventory.player_trash)
		if util.isValid(trash) then remaining = remaining - trash.insert{ name = item, count = remaining } end
	end
	
	if remaining > 0 then
		player.surface.spill_item_stack(player.position, { name = item, count = remaining }, false)
	end
end

return item_lib