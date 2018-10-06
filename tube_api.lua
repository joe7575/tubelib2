--[[

	Tube Library 2
	==============

	Copyright (C) 2017-2018 Joachim Stolberg

	LGPLv2.1+
	See LICENSE.txt for more information

	tube_api.lua

]]--

-- for lazy programmers
local P = minetest.pos_to_string
local S = minetest.string_to_pos
local M = minetest.get_meta


local function Tbl(list)
	local tbl = {}
	for _,item in ipairs(list) do
		tbl[item] = true
	end
	return tbl
end

--
-- API Functions
--

-- Tubelib2 Class
tubelib2.Tube = {}
local Tube = tubelib2.Tube

function Tube:new(attr)
	local o = {
		allowed_6d_dirs = attr.allowed_6d_dirs or {true, true, true, true, true, true}, 
		max_tube_length = attr.max_tube_length or 1000, 
		primary_node_names = Tbl(attr.primary_node_names or {}), 
		secondary_node_names = Tbl(attr.secondary_node_names or {}),
		show_infotext = attr.show_infotext or false,
	}
	setmetatable(o, self)
	self.__index = self
	return o
end

-- Register (foreign) tubelib compatible nodes.
function Tube:add_secondary_node_names(names)
	for _,name in ipairs(names) do
		self.secondary_node_names[name] = true
	end
end

-- From node to node via tube
-- Used for item transportation via tubes
function Tube:get_connected_node_pos(pos, dir)
	pos, _ = self:get_next_node(pos, dir)
	pos, dir = self:get_tube_end_pos(pos)
	pos, _ = self:get_next_node(pos, dir)
	return pos, dir
end	

-- From tube head to tube head.
-- Return pos and dir to the connected/next node.
function Tube:get_tube_end_pos(pos)
	local spos = M(pos):get_string("peer_pos")
	if spos ~= "" then
		return S(spos), M(pos):get_int("peer_dir")
	end
	local npos, dir, num = self:find_tube_head(pos)
	self:update_head_tube(pos, npos, dir, num)
	return npos, dir
end


-- To be called after a tube node is placed.
function Tube:update_tubes_after_place_node(pos, placer, pointed_thing)
	local preferred_pos, fdir = self:get_player_data(placer, pointed_thing)
	local dir1, dir2, num_tubes = self:determine_tube_dirs(pos, preferred_pos, fdir)
	if dir1 == nil then
		return {}
	end
	
	local tbl = {self:tube_data_to_table(pos, dir1, dir2, num_tubes)}
	
	if num_tubes >= 1 then
		local npos, d1, d2, num = self:add_tube_dir(pos, dir1)
		if npos then
			--print("update_tubes_after_place_node: d1, d2, num", d1, d2, num)
			tbl[#tbl+1] = self:tube_data_to_table(npos, d1, d2, num)
		end
	end
	
	if num_tubes >= 2 then
		local npos, d1, d2, num = self:add_tube_dir(pos, dir2)
		if npos then
			--print("update_tubes_after_place_node: d1, d2, num", d1, d2, num)
			tbl[#tbl+1] = self:tube_data_to_table(npos, d1, d2, num)
		end
	end
	
	return tbl
end


-- To be called after a tube node is removed.
function Tube:update_tubes_after_dig_node(pos, oldnode)
	local dir1, dir2, num_tubes = self:decode_param2(oldnode.param2)
	local tbl = {}
	
	local npos, d1, d2, num = self:del_tube_dir(pos, dir1)
	if npos then
		tbl[#tbl+1] = self:tube_data_to_table(npos, d1, d2, num)
	end
	
	npos, d1, d2, num = self:del_tube_dir(pos, dir2)
	if npos then
		tbl[#tbl+1] = self:tube_data_to_table(npos, d1, d2, num)
	end
	
	return tbl
end


-- To be called from a repair tool in the case of a "WorldEdit" corrupted tube line.
function Tube:repair_tubes(pos)
	local d1, d2 = self:get_tube_dirs(pos)
	self:set_2_conn_tube(pos)
	local npos1, dir1, cnt1 = self:repair_tube_line(pos, d1)
	local npos2, dir2, cnt2 = self:repair_tube_line(pos, d2)
	self:add_meta_data(npos1, npos2, dir1, dir2, cnt1+cnt2+1)
	return npos1, npos2, dir1, dir2, cnt1, cnt2
end


-- To be called from a repair tool in the case, tube nodes are "unbreakable".
function Tube:remove_tube(pos, sound)
	local dir1, dir2 = self:get_tube_dirs(pos)
	if dir1 and dir2 then
		minetest.sound_play({
            name=sound},{
            gain=1,
            max_hear_distance=5,
            loop=false})
		local npos1 = self:friendly_primary_node(pos, dir1)
		local npos2 = self:friendly_primary_node(pos, dir2)
		minetest.remove_node(pos)
		if npos1 then self:repair_tubes(npos1) end
		if npos2 then self:repair_tubes(npos2) end
	end
end
