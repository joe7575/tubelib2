--[[

	Tube Library 2
	==============

	Copyright (C) 2018 Joachim Stolberg

	LGPLv2.1+
	See LICENSE.txt for more information

	internal1.lua
	
	First level functions behind the API

]]--

-- for lazy programmers
local S = function(pos) if pos then return minetest.pos_to_string(pos) end end
local P = minetest.string_to_pos
local M = minetest.get_meta

local Tube = tubelib2.Tube
local Turn180Deg = tubelib2.Turn180Deg
local Dir6dToVector = tubelib2.Dir6dToVector
local tValidNum = {[0] = true, true, true}  -- 0..2 are valid

--------------------------------------------------------------------------------------
-- node get/test functions
--------------------------------------------------------------------------------------

-- Check if node at given position is a tube node
-- If dir == nil then node_pos = pos 
-- Function returns the new pos or nil
function Tube:primary_node(pos, dir)
	local npos, node = self:get_node(pos, dir)
	if self.primary_node_names[node.name] then
		return npos
	end
end

-- Check if node at given position is a secondary node
-- If dir == nil then node_pos = pos 
-- Function returns the new pos or nil
function Tube:secondary_node(pos, dir)
	local npos, node = self:get_node(pos, dir)
	if self.secondary_node_names[node.name] then
		return npos
	end
end

-- Used to determine the node side to the tube connection.
-- Function returns the first found dir value
-- to a primary node.
-- Only used by convert.set_pairing()
function Tube:get_primary_dir(pos)
	-- Check all valid positions
	for dir = 1,6 do
		if self:primary_node(pos, dir) then
			return dir
		end
	end
end

-- Return the new pos behind pos/dir and the dir our of the node.
function Tube:get_pos(pos, dir)
	return vector.add(pos, Dir6dToVector[dir or 0]), Turn180Deg[dir]
end


--------------------------------------------------------------------------------------
-- get/del/add meta data functions
--------------------------------------------------------------------------------------

function Tube:del_meta(pos, dir)
	local npos, node = self:get_node(pos, dir)
	if self.primary_node_names[node.name] then
		local meta = M(npos)
		local peer_pos = meta:get_string("peer_pos")
		local peer_dir = meta:get_int("peer_dir")
		meta:from_table(nil)
		if peer_pos ~= "" then
			return P(peer_pos), peer_dir
		end
	end
	return self:repair_tube_line(pos, dir)
end

function Tube:get_meta(pos, dir)
	local npos = vector.add(pos, Dir6dToVector[dir or 0])
	local meta = M(npos)
	local peer_pos = meta:get_string("peer_pos")
	local peer_dir = meta:get_int("peer_dir")
	if peer_pos ~= "" then
		return P(peer_pos), peer_dir
	end
	return self:repair_tube_line(pos, dir)
end

function Tube:get_oldmeta(pos, dir, oldmetadata)
	if oldmetadata.fields and oldmetadata.fields.peer_pos then
		return P(oldmetadata.fields.peer_pos), tonumber(oldmetadata.fields.peer_dir)
	end
	return self:repair_tube_line(pos, dir)
end

-- Add meta data from the other tube head node
function Tube:add_meta(pos, peer_pos, peer_dir)
	local _, node = self:get_node(pos)
	if self.primary_node_names[node.name] then
		if self.show_infotext then
			M(pos):set_string("infotext", S(peer_pos))
		end
		M(pos):set_string("peer_pos", S(peer_pos))
		M(pos):set_int("peer_dir", peer_dir)
	end
end

--------------------------------------------------------------------------------------
-- Further helper functions
--------------------------------------------------------------------------------------

-- Do a correction of param2, delete meta data of all 2-conn-tubes,
-- and return peer_pos, peer_dir, and number of tube nodes.
function Tube:repair_tube_line(pos, dir)
	local repair_next_tube = function(self, pos, dir)
		local npos, dir1, dir2 = self:determine_next_node(pos, dir)
		if dir1 then
			M(npos):from_table(nil)
			if Turn180Deg[dir] == dir1 then
				return npos, dir2
			else
				return npos, dir1
			end
		end
		return self:get_next_teleport_node(pos, dir)
	end
	
	local cnt = 0
	if not dir then	return pos, dir, cnt end	
	while cnt <= self.max_tube_length do
		--if cnt > 1 then M(pos):from_table(nil) end
		local new_pos, new_dir = repair_next_tube(self, pos, dir)
		if not new_dir then	break end
		pos, dir = new_pos, new_dir
		cnt = cnt + 1
	end
	return pos, dir, cnt
end	

-- fpos,fdir points to the secondary node to be updated.
-- npos,ndir are used to calculate the connection data to be written.
function Tube:update_secondary_node(fpos,fdir, npos,ndir)
	-- [s]<-[n]----[f]->[s]
	local fpos2, node = self:get_node(fpos, fdir)
	if minetest.registered_nodes[node.name].tubelib2_on_update then
		local npos2 = self:get_pos(npos, ndir)
		if vector.equals(npos2, fpos2) then  -- last tube removed?
			npos2,ndir = nil,nil  -- used to delete the data base
		end
		minetest.registered_nodes[node.name].tubelib2_on_update(fpos2, Turn180Deg[fdir], npos2, ndir)
	end
end


--------------------------------------------------------------------------------------
-- pairing functions
--------------------------------------------------------------------------------------

-- Pairing helper function
function Tube:store_teleport_data(pos, peer_pos)		
	local meta = M(pos)
	meta:set_string("tele_pos", S(peer_pos))
	meta:set_string("channel", nil)
	meta:set_string("formspec", nil)
	meta:set_string("infotext", "Connected with "..S(peer_pos))
	return meta:get_int("tube_dir")
end

-------------------------------------------------------------------------------
-- update-after/get-dir functions
-------------------------------------------------------------------------------

function Tube:update_after_place_node(pos, dirs)
	-- Check all valid positions
	local lRes= {}
	dirs = dirs or self.dirs_to_check
	for _,dir in ipairs(dirs) do
		local npos, d1, d2, num = self:add_tube_dir(pos, dir)
		if npos and self.valid_dirs[d1] and self.valid_dirs[d2] and tValidNum[num]then
			self.clbk_after_place_tube(self:tube_data_to_table(npos, d1, d2, num))
			lRes[#lRes+1] = dir
		end
	end
	return lRes
end

function Tube:update_after_dig_node(pos, dirs)
	-- Check all valid positions
	local lRes= {}
	dirs = dirs or self.dirs_to_check
	for _,dir in ipairs(dirs) do
		local npos, d1, d2, num = self:del_tube_dir(pos, dir)
		if npos and self.valid_dirs[d1] and self.valid_dirs[d2] and tValidNum[num]then
			self.clbk_after_place_tube(self:tube_data_to_table(npos, d1, d2, num))
			lRes[#lRes+1] = dir
		end
	end
	return lRes
end

function Tube:update_after_place_tube(pos, placer, pointed_thing)
	local preferred_pos, fdir = self:get_player_data(placer, pointed_thing)
	local dir1, dir2, num_tubes = self:determine_tube_dirs(pos, preferred_pos, fdir)
	if dir1 == nil then
		return false
	end
	if self.valid_dirs[dir1] and self.valid_dirs[dir2] and tValidNum[num_tubes]then
		self.clbk_after_place_tube(self:tube_data_to_table(pos, dir1, dir2, num_tubes))
	end
	
	if num_tubes >= 1 then
		local npos, d1, d2, num = self:add_tube_dir(pos, dir1)
		if npos and self.valid_dirs[d1] and self.valid_dirs[d2] and tValidNum[num]then
			self.clbk_after_place_tube(self:tube_data_to_table(npos, d1, d2, num))
		end
	end
	
	if num_tubes >= 2 then
		local npos, d1, d2, num = self:add_tube_dir(pos, dir2)
		if npos and self.valid_dirs[d1] and self.valid_dirs[d2] and tValidNum[num]then
			self.clbk_after_place_tube(self:tube_data_to_table(npos, d1, d2, num))
		end
	end
	return true, dir1, dir2
end	
	
function Tube:update_after_dig_tube(pos, param2)
	local dir1, dir2, num_tubes = self:decode_param2(pos, param2)
	
	local lRes = {}
	local npos, d1, d2, num = self:del_tube_dir(pos, dir1)
	if npos and self.valid_dirs[d1] and self.valid_dirs[d2] and tValidNum[num]then
		self.clbk_after_place_tube(self:tube_data_to_table(npos, d1, d2, num))
		lRes[#lRes+1] = dir1
	end
	
	npos, d1, d2, num = self:del_tube_dir(pos, dir2)
	if npos and self.valid_dirs[d1] and self.valid_dirs[d2] and tValidNum[num]then
		self.clbk_after_place_tube(self:tube_data_to_table(npos, d1, d2, num))
		lRes[#lRes+1] = dir2
	end
	return lRes
end

function Tube:update_secondary_nodes_after_dig_tube(pos)
	local d1, d2 = self:determine_dir1_dir2_and_num_conn(pos)
	if d1 then
		self:update_secondary_node(pos,d1, pos,d1)
	end
	if d2 then
		self:update_secondary_node(pos,d2, pos,d2)
	end
end
