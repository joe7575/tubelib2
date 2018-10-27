--[[

	Tube Library 2
	==============

	Copyright (C) 2017-2018 Joachim Stolberg

	LGPLv2.1+
	See LICENSE.txt for more information

	tube_api.lua

]]--

-- Version for compatibility checks, see readme.md/history
tubelib2.version = 0.2

-- for lazy programmers
local M = minetest.get_meta

local Dir2Str = {"north", "east", "south", "west", "down", "up"}

function tubelib2.dir_to_string(dir)
	return Dir2Str[dir]
end

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
		clbk_after_place_tube = attr.after_place_tube,
		pairingList = {}, -- teleporting nodes
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

-- Check if node at given position is a tube node
-- If dir == nil then node_pos = pos 
-- Function returns the new pos or nil
function Tube:primary_node(pos, dir)
	local npos, node = self:get_next_node(pos, dir)
	local _,_,num_conn = self:decode_param2(node.param2)
	if self.primary_node_names[node.name] then
		return npos
	end
end

-- Check if node at given position is a secondary node
-- If dir == nil then node_pos = pos 
-- Function returns the new pos or nil
function Tube:secondary_node(pos, dir)
	local npos, node = self:get_next_node(pos, dir)
	if self.secondary_node_names[node.name] then
		return npos
	end
end

-- Used to determine the node side to the tube connection.
-- Function returns the first found dir value
-- to a primary node.
function Tube:get_primary_dir(pos)
	-- Check all valid positions
	for dir = 1,6 do
		if self:primary_node(pos, dir) then
			return dir
		end
	end
end

-- From source node to destination node via tubes.
-- pos is the source node position, dir the output dir
-- The returned pos is the destination position, dir
-- is the direction into the destination node.
function Tube:get_connected_node_pos(pos, dir)
	local node = {}
	if self:is_tube_head(pos, dir, node) then
		local npos, ndir = self:get_peer_tube_head(node)
		return vector.add(npos, tubelib2.Dir6dToVector[ndir or 0]), ndir
	end
	return vector.add(pos, tubelib2.Dir6dToVector[dir or 0]), dir
end

function Tube:beside(pos1, pos2)
	local pos = vector.subtract(pos1, pos2)
	local res = pos.x + pos.y + pos.z
	return res == 1 or res == -1
end

-- From tube head to tube head.
-- pos is the tube head position, dir is the direction into the head node.
-- The returned pos is the peer head position, dir
-- is the direction out of the peer head node.
function Tube:get_tube_end_pos(pos, dir)
	local node = {}
	if self:is_tube_head(pos, nil, node) then
		return self:get_peer_tube_head(node)
	end
	return pos, dir
end


-- To be called after a secondary node is placed.
function Tube:after_place_node(pos, dir1, dir2)
	self:delete_tube_meta_data(pos, dir1, dir2)
	
	if dir1 then
		local npos, d1, d2, num = self:add_tube_dir(pos, dir1)
		if npos then
			self.clbk_after_place_tube(self:tube_data_to_table(npos, d1, d2, num))
		end
	end
	
	if dir2 then
		local npos, d1, d2, num = self:add_tube_dir(pos, dir2)
		if npos then
			self.clbk_after_place_tube(self:tube_data_to_table(npos, d1, d2, num))
		end
	end
end

-- To be called after a crossing node is placed.
function Tube:after_place_crossing_node(pos)
	-- Check all valid positions
	for dir = 1,6 do
		if self.allowed_6d_dirs[dir] then
			self:delete_tube_meta_data(pos, dir)
			local npos, d1, d2, num = self:add_tube_dir(pos, dir)
			if npos then
				self.clbk_after_place_tube(self:tube_data_to_table(npos, d1, d2, num))
			end
		end
	end
end

-- To be called after a tube/primary node is placed.
function Tube:after_place_tube(pos, placer, pointed_thing)
	local preferred_pos, fdir = self:get_player_data(placer, pointed_thing)
	local dir1, dir2, num_tubes = self:determine_tube_dirs(pos, preferred_pos, fdir)
	if dir1 == nil then
		return false
	end
	
	self:delete_tube_meta_data(pos, dir1, dir2)
	
	self.clbk_after_place_tube(self:tube_data_to_table(pos, dir1, dir2, num_tubes))
	
	if num_tubes >= 1 then
		local npos, d1, d2, num = self:add_tube_dir(pos, dir1)
		if npos then
			self.clbk_after_place_tube(self:tube_data_to_table(npos, d1, d2, num))
		end
	end
	
	if num_tubes >= 2 then
		local npos, d1, d2, num = self:add_tube_dir(pos, dir2)
		if npos then
			self.clbk_after_place_tube(self:tube_data_to_table(npos, d1, d2, num))
		end
	end
	
	return true
end

-- To be called after a secondary node is removed.
function Tube:after_dig_node(pos, dir1, dir2)
	self:delete_tube_meta_data(pos, dir1, dir2)
	
	local npos, d1, d2, num = self:del_tube_dir(pos, dir1)
	if npos then
		self.clbk_after_place_tube(self:tube_data_to_table(npos, d1, d2, num))
	end
	
	npos, d1, d2, num = self:del_tube_dir(pos, dir2)
	if npos then
		self.clbk_after_place_tube(self:tube_data_to_table(npos, d1, d2, num))
	end
end

-- To be called after a crossing node is removed.
function Tube:after_dig_crossing_node(pos)
	-- Check all valid positions
	for dir = 1,6 do
		if self.allowed_6d_dirs[dir] then
			self:delete_tube_meta_data(pos, dir)
			
			local npos, d1, d2, num = self:del_tube_dir(pos, dir)
			if npos then
				self.clbk_after_place_tube(self:tube_data_to_table(npos, d1, d2, num))
			end
		end
	end
end

-- To be called after a tube node is removed.
function Tube:after_dig_tube(pos, oldnode, oldmetadata)
	local dir1, dir2, num_tubes = self:decode_param2(oldnode.param2)
	
	self:delete_tube_meta_data(pos, dir1, dir2, oldmetadata)
	
	local npos, d1, d2, num = self:del_tube_dir(pos, dir1)
	if npos then
		self.clbk_after_place_tube(self:tube_data_to_table(npos, d1, d2, num))
	end
	
	npos, d1, d2, num = self:del_tube_dir(pos, dir2)
	if npos then
		self.clbk_after_place_tube(self:tube_data_to_table(npos, d1, d2, num))
	end
end


-- To be called from a repair tool in the case of a "WorldEdit" corrupted tube line.
function Tube:tool_repair_tubes(pos)
	local d1, d2 = self:get_tube_dirs(pos)
	if d1 ~= 0 then
		self:set_2_conn_tube(pos)
		local npos1, dir1, cnt1 = self:repair_tube_line(pos, d1)
		local npos2, dir2, cnt2 = self:repair_tube_line(pos, d2)
		self:add_meta_data(npos1, npos2, dir1, dir2, cnt1+cnt2+1)
		return npos1, npos2, dir1, dir2, cnt1, cnt2
	end
end


-- To be called from a repair tool in the case, tube nodes are "unbreakable".
function Tube:tool_remove_tube(pos, sound)
	local dir1, dir2 = self:get_tube_dirs(pos)
	if dir1 ~= 0 then
		minetest.sound_play({
            name=sound},{
            gain=1,
            max_hear_distance=5,
            loop=false})
		minetest.remove_node(pos)
	
		self:delete_tube_meta_data(pos, dir1, dir2)
		
		local npos, d1, d2, num = self:del_tube_dir(pos, dir1)
		if npos then
			self.clbk_after_place_tube(self:tube_data_to_table(npos, d1, d2, num))
		end
		
		npos, d1, d2, num = self:del_tube_dir(pos, dir2)
		if npos then
			self.clbk_after_place_tube(self:tube_data_to_table(npos, d1, d2, num))
		end
	end
end

function Tube:prepare_pairing(pos, tube_dir, sFormspec)
	local meta = M(pos)
	meta:set_int("tube_dir", tube_dir)
	
	-- break the connection
	self:delete_tube_meta_data(pos, tube_dir)
	
	meta:set_string("channel", nil)
	meta:set_string("infotext", "Unconnected")
	meta:set_string("formspec", sFormspec)
end

function Tube:pairing(pos, channel)
	if self.pairingList[channel] and pos ~= self.pairingList[channel] then
		-- store peer position on both nodes
		local peer_pos = self.pairingList[channel]
		
		local tube_dir1 = self:store_teleport_data(pos, peer_pos)
		local tube_dir2 = self:store_teleport_data(peer_pos, pos)
		
		self:delete_tube_meta_data(pos, tube_dir1)
		self:delete_tube_meta_data(peer_pos, tube_dir2)
		
		self.pairingList[channel] = nil
		return true
	else
		self.pairingList[channel] = pos
		local meta = M(pos)
		meta:set_string("channel", channel)
		meta:set_string("infotext", "Unconnected ("..channel..")")
		return false
	end
end

function Tube:stop_pairing(pos, oldmetadata, sFormspec)
	-- unpair peer node
	if oldmetadata and oldmetadata.fields and oldmetadata.fields.tele_pos then
		local tele_pos = minetest.string_to_pos(oldmetadata.fields.tele_pos)
		local peer_meta = M(tele_pos)
		if peer_meta then
			self:delete_tube_meta_data(tele_pos, peer_meta:get_int("tube_dir"))
			
			peer_meta:set_string("channel", nil)
			peer_meta:set_string("tele_pos", nil)
			peer_meta:set_string("formspec", sFormspec)
			peer_meta:set_string("infotext", "Unconnected")
		end
	end
	
	if oldmetadata and oldmetadata.fields then
		self:delete_tube_meta_data(pos, tonumber(oldmetadata.fields.tube_dir or 0), nil, oldmetadata)
	end
end
