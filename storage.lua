--[[

	Tube Library 2
	==============

	Copyright (C) 2017-2018 Joachim Stolberg

	LGPLv2.1+
	See LICENSE.txt for more information

	storage.lua

]]--

local MemStore = {}
local storage = minetest.get_mod_storage()

local function new_block(block_key)
	MemStore[block_key] = minetest.deserialize(storage:get(block_key) or "return {}")
	return MemStore[block_key]
end

local function new_node(block, node_key)
	block[node_key] = {used = true}
	return block[node_key]
end

local function update_mod_storage()
	local gametime = minetest.get_gametime()
	for k,v in pairs(MemStore) do
		if v.used then
			v.used = false
			v.best_before = gametime + 10
			storage:set_string(k, minetest.serialize(v))
		elseif v.best_before < gametime then
			storage:set_string(k, minetest.serialize(v))
			MemStore[k] = nil
		end
	end	
	-- run every minute
	minetest.after(60, update_mod_storage)
end

minetest.register_on_shutdown(function()
	for k,v in ipairs(MemStore) do
		storage:set_string(k, minetest.serialize(v))
	end	
end)

minetest.after(60, update_mod_storage)

-- API function for a node related and high efficient storage table
-- for all kind of node data.
function tubelib2.mem_load(pos)
	local block_key = math.floor((pos.z+32768)/16)*4096*4096 + 
		math.floor((pos.y+32768)/16)*4096 + math.floor((pos.x+32768)/16)
	local node_key = (pos.z%16)*16*16 + (pos.y%16)*16 + (pos.x%16)
	local block = MemStore[block_key] or new_block(block_key)
	block.used = true
	return block[node_key] or new_node(block, node_key)
end
