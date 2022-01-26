local original_props_by_player = {}
local original_speed_by_player = {}
local released_by_player = {}
local sneak_scale = tonumber(minetest.settings:get("visible_sneak.scale")) or 0.88
local sneak_speed = tonumber(minetest.settings:get("visible_sneak.speed")) or 1/3
local sneak_animation = false
local ANIMATION_SPEED_SNEAK

if minetest.global_exists('playeranim') and playeranim.register_animation then
	sneak_animation = true
	ANIMATION_SPEED_SNEAK = tonumber(minetest.settings:get("playeranim.animation_speed_sneak")) or 0.8
	local bones = playeranim.bones
	playeranim.set_rotate_on_sneak(false)
	playeranim.register_animation('sneak', nil, function (player, _time, anim)
		anim.positions[bones.BODY].y = anim.positions[bones.BODY].y-2

		anim.positions[bones.RLEG].y = anim.positions[bones.RLEG].y+1.5
		anim.positions[bones.LLEG].y = anim.positions[bones.LLEG].y+1.5
		anim.positions[bones.RLEG].z = anim.positions[bones.RLEG].z+0.4
		anim.positions[bones.LLEG].z = anim.positions[bones.LLEG].z+0.4

		anim.rotations[bones.BODY].x = anim.rotations[bones.BODY].x+30
		anim.rotations[bones.HEAD].x = anim.rotations[bones.HEAD].x+30
		anim.rotations[bones.RLEG].x = anim.rotations[bones.RLEG].x+50
		anim.rotations[bones.LLEG].x = anim.rotations[bones.LLEG].x+50
		anim.rotations[bones.RARM].x = anim.rotations[bones.RARM].x+20
		anim.rotations[bones.LARM].x = anim.rotations[bones.LARM].x+20
	end)
end

local function psuedo_sneak(player)
	local player_name = player:get_player_name()
	released_by_player[player_name] = true
	local original_speed = player:get_physics_override().speed
	original_speed_by_player[player_name] = original_speed
	player:set_physics_override({ speed=original_speed*sneak_speed })
end
local function psuedo_unsneak(player)
	local player_name = player:get_player_name()
	released_by_player[player_name] = nil
	player:set_physics_override({ speed=original_speed_by_player[player_name] })
	original_speed_by_player[player_name] = nil
end

local function record_original_props(player)
	local player_name = player:get_player_name()
	local current_props = player:get_properties()
	local original_props = {
		collisionbox = current_props.collisionbox,
		stepheight = current_props.stepheight,
		eye_height = current_props.eye_height
	}
	if not sneak_animation then
		original_props.visual_size = current_props.visual_size
	end
	original_props_by_player[player_name] = original_props

	return original_props
end

local function sneak(player)
	local original_props = record_original_props(player)
	if sneak_animation then
		playeranim.set_animation_speed(player, ANIMATION_SPEED_SNEAK)
		playeranim.assign_animation(player, 'sneak')
	else
		local new_visual_size = table.copy(original_props.visual_size)
		new_visual_size.y = sneak_scale
		player:set_properties({
			visual_size = new_visual_size
		})
	end
	local new_collisionbox = table.copy(original_props.collisionbox)
	new_collisionbox[5] = sneak_scale*new_collisionbox[5]
	player:set_properties({
		collisionbox = new_collisionbox,
		stepheight = sneak_scale*original_props.stepheight,
		eye_height = sneak_scale*original_props.eye_height,
	})
end
local function unsneak(player)
	local player_name = player:get_player_name()
	player:set_properties(original_props_by_player[player_name])
	original_props_by_player[player_name] = nil
	if sneak_animation then
		playeranim.set_animation_speed(player, nil)
		playeranim.unassign_animation(player, 'sneak')
	end
	psuedo_unsneak(player)
end

controls.register_on_press(function(player, key)
	if key ~= "sneak" then return end

	local player_name = player:get_player_name()

	-- Stop psuedo-sneaking as now we are really sneaking
	if released_by_player[player_name] then
		psuedo_unsneak(player)
	end
	-- If already sneaking, don't compound
	if original_props_by_player[player_name] then
		return
	end

	sneak(player)
end)

local function check_can_unsneak(player)
	local pos = player:get_pos()
	local original_props = original_props_by_player[player:get_player_name()] or player:get_properties()

	local central_ray = minetest.raycast(
		vector.add(pos, {
			x=0, y=original_props.collisionbox[5]-0.1, z=0
		}),
		vector.add(pos, {
			x=0, y=original_props.collisionbox[5], z=0
		}),
		false, false)
	for collision in central_ray do
		return false
	end
	local corner_ray1 = minetest.raycast(
		vector.add(pos, {
			x=original_props.collisionbox[4],
			y=original_props.collisionbox[5],
			z=original_props.collisionbox[6]
		}),
		vector.add(pos, {
			x=original_props.collisionbox[1],
			y=original_props.collisionbox[5],
			z=original_props.collisionbox[3]
		}),
		false, false)
	for collision in corner_ray1 do
		return false
	end
	local corner_ray2 = minetest.raycast(
		vector.add(pos, {
			x=original_props.collisionbox[1],
			y=original_props.collisionbox[5],
			z=original_props.collisionbox[6]
		}),
		vector.add(pos, {
			x=original_props.collisionbox[4],
			y=original_props.collisionbox[5],
			z=original_props.collisionbox[3]
		}),
		false, false)
	for collision in corner_ray2 do
		return false
	end
	return true
end

controls.register_on_release(function(player, key)
	if key ~= "sneak" then return end

	if check_can_unsneak(player) then
		unsneak(player)
	else
		psuedo_sneak(player)
	end
end)

local on_load = {}

local check_interval = 10
local check_counter = 0
minetest.register_globalstep(function()
	check_counter = check_counter+1
	if check_counter ~= check_interval then return end
	check_counter = 0

	-- Make sure the player is crouched when they join if they have collisions
	local new_on_load = {}
	for _, player in ipairs(on_load) do
		local pos = vector.round(player:get_pos())
		local node = minetest.get_node_or_nil(pos)
		if node then
			if not check_can_unsneak(player) then
				sneak(player)
				psuedo_sneak(player)
			end
		else
			table.insert(new_on_load, player)
		end
	end
	on_load = new_on_load

	-- Un-crouch the player when they stop colliding
	for _, player in pairs(minetest.get_connected_players()) do
		local player_name = player:get_player_name()
		if released_by_player[player_name] then
			if check_can_unsneak(player) then
				unsneak(player)
			end
		end
	end
end)

minetest.register_on_joinplayer(function(player)
	table.insert(on_load, player)
end)
