--[[

	Tube Library 2
	==============

	Copyright (C) 2017-2018 Joachim Stolberg

	LGPLv2.1+
	See LICENSE.txt for more information

	tube_api.lua

]]--

-- Version for compatibility checks, see readme.md/history
tubelib2.version = 0.4

-- for lazy programmers
local M = minetest.get_meta
local S = minetest.pos_to_string

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

-- Tubelib2 Class
tubelib2.Tube = {}
local Tube = tubelib2.Tube

--
-- API Functions
--

function Tube:new(attr)
	local o = {
		dirs_to_check = attr.dirs_to_check or {1,2,3,4,5,6},
		max_tube_length = attr.max_tube_length or 1000, 
		primary_node_names = Tbl(attr.primary_node_names or {}), 
		secondary_node_names = Tbl(attr.secondary_node_names or {}),
		legacy_node_names = Tbl(attr.legacy_node_names or {}),
		show_infotext = attr.show_infotext or false,
		clbk_after_place_tube = attr.after_place_tube,
		pairingList = {}, -- teleporting nodes
	}
	o.allowed_6d_dirs = Tbl(o.dirs_to_check)
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

-- To be called after a secondary node is placed.
-- dirs is a list with valid dirs, like: {1,2,3,4}
function Tube:after_place_node(pos, dirs)
	-- [s][f]----[n] x
	-- s..secondary, f..far, n..near, x..node to be placed
	for _,dir in ipairs(self:update_after_place_node(pos, dirs)) do
		local fpos,fdir = self:get_meta(pos, dir)
		local npos, ndir = self:get_pos(pos, dir)
		self:update_secondary_node(fpos,fdir, npos,ndir)
		self:update_secondary_node(npos,ndir, fpos,fdir)
	end
end

-- To be called after a tube/primary node is placed.
function Tube:after_place_tube(pos, placer, pointed_thing)
	-- [s1][f1]----[n1] x [n2]-----[f2][s2]
	-- s..secondary, f..far, n..near, x..node to be placed
	local res,dir1,dir2 = self:update_after_place_tube(pos, placer, pointed_thing)
	if res then
		local fpos1,fdir1 = self:del_meta(pos, dir1)
		local fpos2,fdir2 = self:del_meta(pos, dir2)
		self:add_meta(fpos1, fpos2,fdir2)
		self:add_meta(fpos2, fpos1,fdir1)
		self:update_secondary_node(fpos1,fdir1, fpos2,fdir2)
		self:update_secondary_node(fpos2,fdir2, fpos1,fdir1)
	end
	return res
end

function Tube:after_dig_node(pos, dirs)
	-- [s][f]----[n] x
	-- s..secondary, f..far, n..near, x..node to be removed
	for _,dir in ipairs(self:update_after_dig_node(pos, dirs)) do
		local fpos,fdir = self:get_meta(pos, dir)
		local npos,ndir = self:get_pos(pos, dir)
		self:add_meta(npos, fpos,fdir)
		self:add_meta(fpos, npos,ndir)
		self:update_secondary_node(fpos,fdir, npos,ndir)
	end
end

function Tube:after_dig_tube(pos, oldnode, oldmetadata)
	-- [s1][f1]----[n1] x [n2]-----[f2][s2]
	-- s..secondary, f..far, n..near, x..node to be removed
	for _,dir in ipairs(self:update_after_dig_tube(pos, oldnode.param2)) do
		local fpos,fdir = self:get_oldmeta(pos, dir, oldmetadata)
		local npos,ndir = self:get_pos(pos, dir)
		self:add_meta(npos, fpos,fdir)
		self:add_meta(fpos, npos,ndir)
		self:update_secondary_node(fpos,fdir, npos,ndir)
	end
end


-- From source node to destination node via tubes.
-- pos is the source node position, dir the output dir
-- The returned pos is the destination position, dir
-- is the direction into the destination node.
function Tube:get_connected_node_pos(pos, dir)
	local fpos,fdir = self:get_meta(pos, dir)
	local npos,ndir = self:get_pos(fpos,fdir)
	return npos, dir
end


-- To be called from a repair tool in the case of a "WorldEdit" or with
-- legacy nodes corrupted tube line.
function Tube:tool_repair_tube(pos)
	local res,dir1,dir2 = self:determine_next_node(pos)
	if res then
		local fpos1,fdir1,cnt1 = self:repair_tube_line(pos, dir1)
		local fpos2,fdir2,cnt2 = self:repair_tube_line(pos, dir2)
		self:add_meta(fpos1, fpos2,fdir2)
		self:add_meta(fpos2, fpos1,fdir1)
		self:update_secondary_node(fpos1,fdir1, fpos2,fdir2)
		self:update_secondary_node(fpos2,fdir2, fpos1,fdir1)
		return dir1, dir2, fpos1, fpos2, fdir1, fdir2, cnt1 or 0, cnt2 or 0
	end
end


-- To be called from a repair tool in the case, tube nodes are "unbreakable".
function Tube:tool_remove_tube(pos, sound)
	local oldnode, oldmeta = self:remove_tube(pos, sound)
	if oldnode then
		self:after_dig_tube(pos, oldnode, oldmeta)
	end
end


function Tube:prepare_pairing(pos, tube_dir, sFormspec)
	local meta = M(pos)
	meta:set_int("tube_dir", tube_dir)

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

		--self:delete_tube_meta_data(pos, tube_dir1)
		--self:delete_tube_meta_data(peer_pos, tube_dir2)
		local fpos1,fdir1 = self:repair_tube_line(pos, tube_dir1)
		local fpos2,fdir2 = self:repair_tube_line(peer_pos, tube_dir2)
		self:add_meta(fpos1, fpos2,fdir2)
		self:add_meta(fpos2, fpos1,fdir1)
		self:update_secondary_node(fpos1,fdir1, fpos2,fdir2)
		self:update_secondary_node(fpos2,fdir2, fpos1,fdir1)

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
			self:after_place_node(tele_pos, {peer_meta:get_int("tube_dir")})

			peer_meta:set_string("channel", nil)
			peer_meta:set_string("tele_pos", nil)
			peer_meta:set_string("formspec", sFormspec)
			peer_meta:set_string("infotext", "Unconnected")
		end
	end
end
