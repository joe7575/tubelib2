--[[

	Tube Library 2
	==============

	Copyright (C) 2017-2018 Joachim Stolberg

	LGPLv2.1+
	See LICENSE.txt for more information

	tube_test.lua
	
	THIS FILE IS ONLY FOR TESTING PURPOSES

]]--

-- for lazy programmers
local S = minetest.pos_to_string
local P = minetest.string_to_pos
local M = minetest.get_meta

-- Test tubes

local Tube = tubelib2.Tube:new({
	max_tube_length = 1000, 
	show_infotext = true,
	primary_node_names = {"tubelib2:tubeS", "tubelib2:tubeA"}, 
	secondary_node_names = {"default:chest", "default:chest_open", 
			"tubelib2:source", "tubelib2:teleporter"},
	after_place_tube = function(pos, param2, tube_type, num_tubes)
		print("after_place_tube", S(pos), param2, tube_type, num_tubes)
		minetest.set_node(pos, {name = "tubelib2:tube"..tube_type, param2 = param2})
	end,
})

minetest.register_node("tubelib2:tubeS", {
	description = "Tubelib2 Test tube",
	tiles = { -- Top, base, right, left, front, back
		"tubelib2_tube.png",
		"tubelib2_tube.png",
		"tubelib2_tube.png",
		"tubelib2_tube.png",
		"tubelib2_hole.png",
		"tubelib2_hole.png",
	},
	
	after_place_node = function(pos, placer, itemstack, pointed_thing)
		if not Tube:after_place_tube(pos, placer, pointed_thing) then
			minetest.remove_node(pos)
			return true
		end
		return false
	end,
	
	after_dig_node = function(pos, oldnode, oldmetadata, digger)
		Tube:after_dig_tube(pos, oldnode, oldmetadata)
	end,
	
	paramtype2 = "facedir", -- important!
	drawtype = "nodebox",
	node_box = {
		type = "fixed",
		fixed = {
			{-2/8, -2/8, -4/8,  2/8, 2/8, 4/8},
		},
	},
	node_placement_prediction = "", -- important!
	on_rotate = screwdriver.disallow, -- important!
	paramtype = "light",
	sunlight_propagates = true,
	is_ground_content = false,
	groups = {crumbly = 3, cracky = 3, snappy = 3},
	sounds = default.node_sound_glass_defaults(),
})

minetest.register_node("tubelib2:tubeA", {
	description = "Tubelib2 Test tube",
	tiles = { -- Top, base, right, left, front, back
		"tubelib2_tube.png",
		"tubelib2_hole.png",
		"tubelib2_tube.png",
		"tubelib2_tube.png",
		"tubelib2_tube.png",
		"tubelib2_hole.png",
	},
	
	after_dig_node = function(pos, oldnode, oldmetadata, digger)
		Tube:after_dig_tube(pos, oldnode, oldmetadata)
	end,
	
	paramtype2 = "facedir", -- important!
	drawtype = "nodebox",
	node_box = {
		type = "fixed",
		fixed = {
			{-2/8, -4/8, -2/8,  2/8, 2/8,  2/8},
			{-2/8, -2/8, -4/8,  2/8, 2/8, -2/8},
		},
	},
	--on_rotate = screwdriver.disallow, -- important!
	paramtype = "light",
	sunlight_propagates = true,
	is_ground_content = false,
	groups = {crumbly = 3, cracky = 3, snappy = 3}, --not_in_creative_inventory=1},
	sounds = default.node_sound_glass_defaults(),
	drop = "tubelib2:tubeS",
})

local sFormspec = "size[7.5,3]"..
	"field[0.5,1;7,1;channel;Enter channel string;]" ..
	"button_exit[2,2;3,1;exit;Save]"


minetest.register_node("tubelib2:source", {
	description = "Tubelib2 Item Source",
	tiles = {
		-- up, down, right, left, back, front
		'tubelib2_source.png',
		'tubelib2_source.png',
		'tubelib2_source.png',
		'tubelib2_source.png',
		'tubelib2_source.png',
		'tubelib2_conn.png',
	},

	after_place_node = function(pos, placer)
		local tube_dir = ((minetest.dir_to_facedir(placer:get_look_dir()) + 2) % 4) + 1
		M(pos):set_int("tube_dir", tube_dir)
		Tube:after_place_node(pos, tube_dir)		
		minetest.get_node_timer(pos):start(2)
	end,

	after_dig_node = function(pos, oldnode, oldmetadata, digger)
		local tube_dir = tonumber(oldmetadata.fields.tube_dir or 0)
		Tube:after_dig_node(pos, tube_dir)
	end,
	
	on_timer = function(pos, elapsed)
		local tube_dir = M(pos):get_int("tube_dir")
		local dest_pos = Tube:get_connected_node_pos(pos, tube_dir)
		local inv = minetest.get_inventory({type="node", pos=dest_pos})
		local stack = ItemStack("default:dirt")
		if inv then
			local leftover = inv:add_item("main", stack)
			if leftover:get_count() == 0 then
				return true
			end
		end
		local node = minetest.get_node(dest_pos)
		if node.name == "air" then
			minetest.add_item(dest_pos, stack)
		else
			print("add_item error")
		end
		return true
	end,
	
	paramtype2 = "facedir", -- important!
	on_rotate = screwdriver.disallow, -- important!
	paramtype = "light",
	sunlight_propagates = true,
	is_ground_content = false,
	groups = {crumbly = 3, cracky = 3, snappy = 3},
	sounds = default.node_sound_glass_defaults(),
})

minetest.register_node("tubelib2:teleporter", {
	description = "Tubelib2 Teleporter",
	tiles = {
		-- up, down, right, left, back, front
		'tubelib2_tele.png',
		'tubelib2_tele.png',
		'tubelib2_tele.png',
		'tubelib2_tele.png',
		'tubelib2_tele.png',
		'tubelib2_conn.png',
	},

	after_place_node = function(pos, placer)
		-- the tube_dir calculation depends on the player look-dir and the hole side of the node
		local tube_dir = ((minetest.dir_to_facedir(placer:get_look_dir()) + 2) % 4) + 1
		Tube:prepare_pairing(pos, tube_dir, sFormspec)
		Tube:after_place_node(pos, tube_dir)
	end,

	on_receive_fields = function(pos, formname, fields, player)
		if fields.channel ~= nil then
			Tube:pairing(pos, fields.channel)
		end
	end,
	
	after_dig_node = function(pos, oldnode, oldmetadata, digger)
		Tube:stop_pairing(pos, oldmetadata, sFormspec)
		local tube_dir = tonumber(oldmetadata.fields.tube_dir or 0)
		Tube:after_dig_node(pos, tube_dir)
	end,
	
	paramtype2 = "facedir", -- important!
	on_rotate = screwdriver.disallow, -- important!
	paramtype = "light",
	sunlight_propagates = true,
	is_ground_content = false,
	groups = {crumbly = 3, cracky = 3, snappy = 3},
	sounds = default.node_sound_glass_defaults(),
})

--local function read_test_type(itemstack, placer, pointed_thing)
--	local param2
--	if pointed_thing.type == "node" then
--		local node = minetest.get_node(pointed_thing.under)	
--		param2 = node.param2
--	else
--		param2 = 0
--	end
--	local num = math.floor(param2/32)
--	local axis = math.floor(param2/4) % 8
--	local rot = param2 % 4	
--	minetest.chat_send_player(placer:get_player_name(), "[Tubelib2] param2 = "..param2.."/"..num.."/"..axis.."/"..rot)
	
--	return itemstack
--end

--local function TEST_determine_tube_dirs(itemstack, placer, pointed_thing)
--	if pointed_thing.type == "node" then
--		local pos = pointed_thing.above
--		local preferred_pos = pointed_thing.under
--		local fdir = Tube:fdir(placer)
--		local dir1, dir2, num_tubes = Tube:determine_tube_dirs(pos, preferred_pos, fdir)
--		print("num_tubes="..num_tubes.." dir1="..(dir1 or "nil").." dir2="..(dir2 or "nil"))
--	end
--end

--local function TEST_update_tubes_after_place_node(itemstack, placer, pointed_thing)
--	if pointed_thing.type == "node" then
--		local pos = pointed_thing.above
--		local nodes = Tube:update_tubes_after_place_node(pos, placer, pointed_thing)
--		print("nodes"..dump(nodes))
--	end
--end

--local function TEST_add_tube_dir(itemstack, placer, pointed_thing)
--	read_test_type(itemstack, placer, pointed_thing)
--	if pointed_thing.type == "node" then
--		local pos = pointed_thing.above
--		local fdir = Tube:fdir(placer)
--		local npos, d1, d2, num = Tube:add_tube_dir(pos, fdir)
--		print("npos, d1, d2, num", npos and S(npos), d1, d2, num)
--	end
--end

--local function TEST_del_tube_dir(itemstack, placer, pointed_thing)
--	read_test_type(itemstack, placer, pointed_thing)
--	if pointed_thing.type == "node" then
--		local pos = pointed_thing.above
--		local fdir = Tube:fdir(placer)
--		local npos, d1, d2, num = Tube:del_tube_dir(pos, fdir)
--		print("npos, d1, d2, num", npos and S(npos), d1, d2, num)
--	end
--end

local function read_param2(pos, player)
	local node = minetest.get_node(pos)	
	local num = math.floor(node.param2/32)
	local axis = math.floor(node.param2/4) % 8
	local rot = node.param2 % 4	
	minetest.chat_send_player(player:get_player_name(), "[Tubelib2] param2 = "..node.param2.."/"..num.."/"..axis.."/"..rot)
end

local function repair_tubes(itemstack, placer, pointed_thing)
	if pointed_thing.type == "node" then
		local pos = pointed_thing.under
		if placer:get_player_control().sneak then
			local end_pos, dir = Tube:get_tube_end_pos(pos, 0)
			if end_pos and dir then
				minetest.chat_send_player(placer:get_player_name(), "[Tubelib2] end_pos = "..S(end_pos)..", dir = "..dir)
			end
		else
			local t = minetest.get_us_time()
			local pos1, pos2, dir1, dir2, cnt1, cnt2 = Tube:tool_repair_tubes(pos)
			t = minetest.get_us_time() - t
			print("time", t)
			if pos1 and pos2 then
				minetest.chat_send_player(placer:get_player_name(), "[Tubelib2] 1: "..S(pos1)..", dir = "..dir1..", "..cnt1.." tubes")
				minetest.chat_send_player(placer:get_player_name(), "[Tubelib2] 2: "..S(pos2)..", dir = "..dir2..", "..cnt2.." tubes")
			end
		end
	end
end

local function remove_tube(itemstack, placer, pointed_thing)
	if pointed_thing.type == "node" then
		local pos = pointed_thing.under
		if placer:get_player_control().sneak then
			read_param2(pos, placer)
		else
			Tube:tool_remove_tube(pos, "default_break_glass")
		end
	end
end

-- Tool for tube workers to crack a tube line
minetest.register_node("tubelib2:tool", {
	description = "Tubelib2 Tool",
	inventory_image = "tubelib2_tool.png",
	wield_image = "tubelib2_tool.png",
	use_texture_alpha = true,
	groups = {cracky=1, book=1},
	on_use = remove_tube,
	on_place = repair_tubes,
	node_placement_prediction = "",
	stack_max = 1,
})

