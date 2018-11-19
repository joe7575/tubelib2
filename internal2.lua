--[[

	Tube Library 2
	==============

	Copyright (C) 2018 Joachim Stolberg

	LGPLv2.1+
	See LICENSE.txt for more information

	internal.lua

]]--

-- for lazy programmers
local S = function(pos) if pos then return minetest.pos_to_string(pos) end end
local P = minetest.string_to_pos
local M = minetest.get_meta


local Turn180Deg = {[0]=0,3,4,1,2,6,5}
tubelib2.Turn180Deg = Turn180Deg

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
local Dir6dToVector = {[0] =
	{x=0,  y=0,  z=0},
	{x=0,  y=0,  z=1},
	{x=1,  y=0,  z=0},
	{x=0,  y=0, z=-1},
	{x=-1, y=0,  z=0},
	{x=0,  y=-1, z=0},
	{x=0,  y=1,  z=0},
}

tubelib2.Dir6dToVector = Dir6dToVector

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

-- Return val in the range of min and max
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


--
-- Tubelib2 Methods
--

local Tube = tubelib2.Tube

function Tube:fdir(player)
	local pitch = player:get_look_pitch()
	if pitch > 1.1 and self.valid_dirs[6] then -- up?
		return 6
	elseif pitch < -1.1 and self.valid_dirs[5] then -- down?
		return 5
	elseif not self.valid_dirs[1] then
		return 6
	else
		return minetest.dir_to_facedir(player:get_look_dir()) + 1
	end
end

function Tube:get_player_data(placer, pointed_thing)
	if placer and pointed_thing and pointed_thing.type == "node" then
		if placer:get_player_control().sneak then
			return pointed_thing.under, self:fdir(placer)
		else
			return nil, self:fdir(placer)
		end
	end
end

-- Return param2 and tube type ("A"/"S")
function Tube:encode_param2(dir1, dir2, num_conn)
	if dir1 > dir2 then
		dir1, dir2 = dir2, dir1
	end
	local param2, _type = unpack(DirToParam2[dir1 * 10 + dir2] or {0, "S"})
	return (num_conn * 32) + param2, _type
end

-- Check if node has a connection on the given dir
function Tube:connected(pos, dir)
	local npos = vector.add(pos, Dir6dToVector[dir or 0])
	local node = get_node_lvm(npos)
	return self.primary_node_names[node.name] 
		or self.secondary_node_names[node.name]
end

-- Determine dirs via surrounding nodes
function Tube:determine_dir1_dir2_and_num_conn(pos)
	local dirs = {}
	for dir = 1, 6 do
		if self:connected(pos, dir) then
			dirs[#dirs+1] = dir
		end
	end
	if #dirs == 1 then
		return dirs[1], nil, 1
	elseif #dirs == 2 then
		return dirs[1], dirs[2], 2
	end
end

-- Return dir1, dir2, num_conn
function Tube:decode_param2(pos, param2)
	local val = Param2ToDir[param2 % 32]
	if val then
		local dir1, dir2 = math.floor(val / 10), val % 10
		local num_conn = math.floor(param2 / 32)
		return dir1, dir2, num_conn
	end
	-- determine dirs via surrounding nodes
	return self:determine_dir1_dir2_and_num_conn(pos)

end

-- No connection to both sides
function Tube:first_placed_node(pos, param2)
	return math.floor(param2 / 32) == 0
end

-- Return node next to pos in direction 'dir'
function Tube:get_node(pos, dir)
	local npos = vector.add(pos, Dir6dToVector[dir or 0])
	return npos, get_node_lvm(npos)
end

-- Return pos for a primary_node and true if num_conn < 2, else false
function Tube:friendly_primary_node(pos, dir)
	local npos, node = self:get_node(pos, dir)
	if self.primary_node_names[node.name] then
		local _,_,num_conn = self:decode_param2(npos, node.param2)
		-- tube node with max one connection?
		return npos, (num_conn or 2) < 2
	end
end

-- Check all 6 possible positions for known nodes considering preferred_pos 
-- and the players fdir and return dir1, dir2 and the number of tubes to connect to (0..2).
function Tube:determine_tube_dirs(pos, preferred_pos, fdir)
	local tbl = {}
	local allowed = table.copy(self.valid_dirs)
	
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

function Tube:determine_next_node(pos, dir)
	local npos, node = self:get_node(pos, dir)
	if self.primary_node_names[node.name] then
		-- determine dirs on two ways
		local da1,da2,numa = self:decode_param2(npos, node.param2)
		local db1,db2,numb = self:determine_dir1_dir2_and_num_conn(npos)
		-- both identical?
		if da1 == db1 and da2 == db2 then
			return npos, da1, da2
		end
		-- test if stored dirs point to valid nodes
		if self:connected(npos, da1) and self:connected(npos, da2) then
			return npos, da1, da2
		end
		-- use and store the determined dirs
		if db1 and db2 then
			node.param2 = self:encode_param2(db1,db2,numb)
			minetest.set_node(npos, node)
			return npos, db1, db2
		end
		return npos, da1, da2
	end
end

-- format and return given data as table
function Tube:tube_data_to_table(pos, dir1, dir2, num_tubes)
	local param2, tube_type = self:encode_param2(dir1, dir2, num_tubes)
	return pos, param2, tube_type, num_tubes
end	

-- Determine a tube side without connection, increment the number of connections
-- and return the new data to be able to update the node: 
-- new_pos, dir1, dir2, num_connections (1, 2)
function Tube:add_tube_dir(pos, dir)
	local npos, node = self:get_node(pos, dir)
	if self.primary_node_names[node.name] then
		local d1, d2, num = self:decode_param2(npos, node.param2)
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

-- Decrement the number of tube connections
-- and return the new data to be able to update the node: 
-- new_pos, dir1, dir2, num_connections (0, 1)
function Tube:del_tube_dir(pos, dir)
	local npos, node = self:get_node(pos, dir)
	if self.primary_node_names[node.name] then
		local d1, d2, num = self:decode_param2(npos, node.param2)
		return npos, d1, d2, math.max(num - 1, 0)
	end
end
	
-- Pairing helper function
function Tube:store_teleport_data(pos, peer_pos)		
	local meta = M(pos)
	meta:set_string("tele_pos", S(peer_pos))
	meta:set_string("channel", nil)
	meta:set_string("formspec", nil)
	meta:set_string("infotext", "Connected with "..S(peer_pos))
	return meta:get_int("tube_dir")
end

-- Jump over the teleport nodes to the next tube node
function Tube:get_next_teleport_node(pos, dir)
	local npos = vector.add(pos, Dir6dToVector[dir or 0])
	local meta = M(npos)
	local s = meta:get_string("tele_pos")
	if s ~= "" then
		local tele_pos = P(s)
		local tube_dir = M(tele_pos):get_int("tube_dir")
		if tube_dir ~= 0 then
			return tele_pos, tube_dir
		end
	end
end

function Tube:remove_tube(pos, sound)
	local node = get_node_lvm(pos)
	if self.primary_node_names[node.name] then
		minetest.sound_play({
				name=sound},{
				gain=1,
				max_hear_distance=5,
				loop=false})
		minetest.remove_node(pos)
		return node, {}
	end
end
