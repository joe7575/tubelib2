--[[

	Tube Library 2
	==============

	Copyright (C) 2018 Joachim Stolberg

	LGPLv2.1+
	See LICENSE.txt for more information

	internal.lua

]]--

-- for lazy programmers
local P = minetest.pos_to_string
local S = minetest.string_to_pos
local M = minetest.get_meta


--
-- Tubelib2 specific 6D directions (1 = North, 2 = East, 3 = South, 4 = West, 5 = Down, 6 = Up)
--
-- All 6D dirs are the view from the node to the outer side
-- Tubes are based on two node types, "angled" and "straight" tubes.
--
--         +-------+          
--        /       /|               +-------+
--       +-------+ |              /       /|
--       |       | |             /       / |
--       |       | |            +-------+  |
--       |       | |            |       |  |
--       |       | |            |       |/ |
--       |       | +            +-------+| +
--       |       |/               |      |/
--       +-------+                +------+ 
--
-- All other nodes are build by means of axis/rotation variants based on param2
-- (paramtype2 == "facedir").


local Turn180Deg = {3,4,1,2,6,5}

-- To calculate param2 based on dir6d information
local DirToParam2 = {
 -- dir1 / dir2 ==> param2 / type (Angled/Straight)
	[12] = {11, "A"},
	[13] = {12, "S"},
	[14] = {14, "A"},
	[15] = { 8, "A"},
	[16] = {10, "A"},
	[23] = { 7, "A"},
	[24] = {21, "S"},
	[25] = { 3, "A"},
	[26] = {19, "A"},
	[34] = { 5, "A"},
	[35] = { 0, "A"},
	[36] = {20, "A"},
	[45] = {15, "A"},
	[46] = {13, "A"},
	[56] = { 4, "S"},
}

-- To retrieve dir6d values from the nodes param2
local Param2ToDir = {}
for k,item in pairs(DirToParam2) do
	Param2ToDir[item[1]] = k
end

-- For neighbour position calculation
local Dir6dToVector = {
	{x=0,  y=0,  z=1},
	{x=1,  y=0,  z=0},
	{x=0,  y=0, z=-1},
	{x=-1, y=0,  z=0},
	{x=0,  y=-1, z=0},
	{x=0,  y=1,  z=0},
}

local VectorToDir6d = {
	[{x=0,  y=0,  z=1}] = 1,
	[{x=1,  y=0,  z=0}] = 2,
	[{x=0,  y=0, z=-1}] = 3,
	[{x=-1, y=0,  z=0}] = 4,
	[{x=0,  y=-1, z=0}] = 5,
	[{x=0,  y=1,  z=0}] = 6,
}


--
-- Local Functions
--

local function Tbl(list)
	local tbl = {}
	for _,item in ipairs(list) do
		tbl[item] = true
	end
	return tbl
end

local function range(val, min, max)
	if val > max then return max end
	if val < min then return min end
	return val
end

local function get_node_lvm(pos)
	local node = minetest.get_node_or_nil(pos)
	if node then
		return node
	end
	local vm = minetest.get_voxel_manip()
	local MinEdge, MaxEdge = vm:read_from_map(pos, pos)
	local data = vm:get_data()
	local param2_data = vm:get_param2_data()
	local area = VoxelArea:new({MinEdge = MinEdge, MaxEdge = MaxEdge})
	local idx = area:index(pos.x, pos.y, pos.z)
	node = {
		name = minetest.get_name_from_content_id(data[idx]),
		param2 = param2_data[idx]
	}
	return node
end

-- Return node next to pos in direction 'dir'
local function get_next_node(pos, dir)
	if dir and Dir6dToVector[dir] then
		local npos = vector.add(pos, Dir6dToVector[dir])
		return npos, get_node_lvm(npos)
	end
	return pos, get_node_lvm(pos)
end

--
-- Tubelib2 Methods
--

local Tube = tubelib2.Tube

-- check if node has a connection on the given dir
function Tube:connected(pos, dir)
	local _, node = get_next_node(pos, dir)
	return self.primary_node_names[node.name] or self.secondary_node_names[node.name]
end

-- The 3 free bits or param2 are used to store the number of connections.
-- return param2 and tube type
function Tube:encode_param2(dir1, dir2, num_conn)
	if dir1 > dir2 then
		dir1, dir2 = dir2, dir1
	end
	local param2, _type = unpack(DirToParam2[dir1 * 10 + dir2] or {0, "S"})
	return (num_conn * 32) + param2, _type
end

-- return dir1, dir2, num_conn
function Tube:decode_param2(param2)
	local val = Param2ToDir[param2 % 32]
	if val then
		local dir1, dir2 = math.floor(val / 10), val % 10
		local num_conn = math.floor(param2 / 32)
		return dir1, dir2, num_conn
	end
	return nil
end

-- return pos for a primary_node and true if num_conn < 2, else false
function Tube:friendly_primary_node(pos, dir)
	-- read node
	local npos, node = get_next_node(pos, dir)
	-- tube node with max one connection?
	local _,_,num_conn = self:decode_param2(node.param2)
	if self.primary_node_names[node.name] then
		return npos, num_conn < 2
	end
	return nil
end

function Tube:secondary_node(pos, dir)
	-- read node
	local npos, node = get_next_node(pos, dir)
	if self.secondary_node_names[node.name] then
		return npos
	end
	return nil
end

function Tube:fdir(player)
	local pitch = player:get_look_pitch()
	if pitch > 1.1 then -- up?
		return 6
	elseif pitch < -1.1 then -- down?
		return 5
	else
		return minetest.dir_to_facedir(player:get_look_dir()) + 1
	end
end

function Tube:get_player_data(placer, pointed_thing)
	if placer and pointed_thing and pointed_thing.type == "node" then
		if placer:get_player_control().sneak then
			return pointed_thing.under, Tube:fdir(placer)
		else
			return nil, Tube:fdir(placer)
		end
	end
end


-- Check all 6 possible positions for known nodes considering preferred_pos 
-- and the players fdir and return dir1, dir2 and the number of tubes to connect to (0..2).
function Tube:determine_tube_dirs(pos, preferred_pos, fdir)
	local tbl = {}
	local allowed = table.copy(self.allowed_6d_dirs)
	
	-- Check for primary nodes (tubes)
	for dir = 1,6 do
		if allowed[dir] then
			local npos, friendly = self:friendly_primary_node(pos, dir)
			if npos then
				if not friendly then
					allowed[dir] = false
				else
					if preferred_pos and vector.equals(npos, preferred_pos) then
						preferred_pos = nil
						table.insert(tbl, 1, dir)
					else
						table.insert(tbl, dir)
					end
				end
			end
		end
	end

	-- If no tube around the pointed pos and player prefers a position,
	-- then the new tube shall point to the player.
	if #tbl == 0 and preferred_pos and fdir and allowed[Turn180Deg[fdir]] then
		tbl[1] = Turn180Deg[fdir]
	-- Already 2 dirs found?
	elseif #tbl >= 2 then
		return tbl[1], tbl[2], 2
	end
	
	-- Check for secondary nodes (chests and so on)
	for dir = 1,6 do
		if allowed[dir] then
			local npos = self:secondary_node(pos, dir)
			if npos then 
				if preferred_pos and vector.equals(npos, preferred_pos) then
					preferred_pos = nil
					table.insert(tbl, 2, dir)
				else
					table.insert(tbl, dir)
				end
			end
		end
	end
	
	-- player pointed to an unknown node to force the tube orientation? 
	if preferred_pos and fdir then
		if tbl[1] == Turn180Deg[fdir] and allowed[fdir] then
			tbl[2] = fdir
		elseif allowed[Turn180Deg[fdir]] then
			tbl[2] = Turn180Deg[fdir]
		end
	end
	
	-- dir1, dir2 still unknown?
	if fdir then
		if #tbl == 0 and allowed[Turn180Deg[fdir]] then
			tbl[1] = Turn180Deg[fdir]
		end
		if #tbl == 1 and allowed[Turn180Deg[tbl[1]]] then
			tbl[2] = Turn180Deg[tbl[1]]
		elseif #tbl == 1 and tbl[1] ~= Turn180Deg[fdir] and allowed[Turn180Deg[fdir]] then
			tbl[2] = Turn180Deg[fdir]
		end
	end

	if #tbl >= 2 and tbl[1] ~= tbl[2] then
		local num_tubes = (self:connected(pos, tbl[1]) and 1 or 0) + 
				(self:connected(pos, tbl[2]) and 1 or 0)
		return tbl[1], tbl[2], math.min(2, num_tubes)
	end
end


function Tube:tube_data_to_table(pos, dir1, dir2, num_tubes)
	local param2, ttype = self:encode_param2(dir1, dir2, num_tubes)
	return {pos = pos, param2 = param2, type = ttype, num_tubes = num_tubes}
end	


function Tube:add_tube_dir(pos, dir)
	local npos, node = get_next_node(pos, dir)
	if self.primary_node_names[node.name] then
		local d1, d2, num = self:decode_param2(node.param2)
		-- not already connected to the new tube?
		dir = Turn180Deg[dir]
		if d1 ~= dir and dir ~= d2 then
			if num == 0 then
				d1 = dir
			elseif num == 1 then
				-- determine, which of d1, d2 has already a connection
				if self:connected(npos, d1) then
					d2 = dir
				else
					d1 = dir
				end
			end
		end
		return npos, d1, d2, math.min(num + 1, 2)
	end
end


function Tube:del_tube_dir(pos, dir)
	local npos, node = get_next_node(pos, dir)
	if self.primary_node_names[node.name] then
		local d1, d2, num = self:decode_param2(node.param2)
		return npos, d1, d2, math.max(num - 1, 0)
	end
end
	
function Tube:get_tube_dirs(pos)
	local node = minetest.get_node(pos)
	if self.primary_node_names[node.name] then
		local d1, d2 = self:decode_param2(node.param2)
		return d1, d2
	end
end

function Tube:get_next_tube(pos, dir)
	local npos, node = get_next_node(pos, dir)
	local dir1, dir2, num = self:decode_param2(node.param2)
	if self.primary_node_names[node.name] then
		if Turn180Deg[dir] == dir1 then
			return npos, dir2
		else
			return npos, dir1
		end
	end
end

function Tube:find_tube_head(pos)
	local cnt = 0
	local dir = nil
	while cnt <= self.max_tube_length do
		local new_pos, new_dir = self:get_next_tube(pos, dir)
		if not new_dir then	break end
		pos, dir = new_pos, new_dir
		cnt = cnt + 1
	end
	return pos, dir
end	


-- Do a correction of param2, delete meta data and
-- return the new pos, dir
function Tube:repair_next_tube(pos, dir)
	local npos, node = get_next_node(pos, dir)
	if self.primary_node_names[node.name] then
		local dir1, dir2, num = self:decode_param2(node.param2)
		if num ~= 2 then
			node.param2 = self:encode_param2(dir1, dir2, 2)
			minetest.set_node(npos, node)
		end
		M(npos):from_table(nil)
		if Turn180Deg[dir] == dir1 then
			return npos, dir2
		else
			return npos, dir1
		end
	end
end

function Tube:repair_tube_line(pos, dir)
	local cnt = 0
	if not dir then	return pos, cnt end	
	while cnt <= self.max_tube_length do
		local new_pos, new_dir = self:repair_next_tube(pos, dir)
		if not new_dir then	break end
		pos, dir = new_pos, new_dir
		cnt = cnt + 1
	end
	return pos, cnt
end	

-- update meta data and set number of connections to 1 or 0
function Tube:update_head_tube(pos1, pos2, num_tubes)
	local _, node = get_next_node(pos1)
	local dir1, dir2, num = self:decode_param2(node.param2)
	num = (self:connected(pos1, dir1) and 1 or 0) + (self:connected(pos1, dir2) and 1 or 0)
	node.param2 = self:encode_param2(dir1, dir2, num)
	minetest.set_node(pos1, node)	
	if self.show_infotext then
		M(pos1):set_string("infotext", P(pos2).." / "..num_tubes.." tubes")
	end
	M(pos1):set_string("peer_pos", P(pos2))
end	

function Tube:add_meta(pos1, pos2, num_tubes)
	self:update_head_tube(pos1, pos2, num_tubes)
	self:update_head_tube(pos2, pos1, num_tubes)
end
