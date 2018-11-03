--[[

	Tube Library 2
	==============

	Copyright (C) 2017-2018 Joachim Stolberg

	LGPLv2.1+
	See LICENSE.txt for more information

	convert.lua

    Optional module, only needed to convert legacy tubes into tubelib2 tubes.
    This is done by means of a callback function:
	    dir1, dir2, num = func(pos, name, param2)

]]--

-- for lazy programmers
local M = minetest.get_meta

local Tube = tubelib2.Tube

function Tube:on_convert_tube(convert_tube_clbk)
	self.convert_tube_clbk = convert_tube_clbk
end

-- Register legacy tube nodes.
function Tube:add_legacy_node_names(names)
	for _,name in ipairs(names) do
		self.legacy_node_names[name] = true
	end
end


function Tube:convert_tube_line(pos, dir)
	local convert_next_tube = function(self, pos, dir)
		local npos, node = self:get_next_node(pos, dir)
		if self.legacy_node_names[node.name]  then
			local dir1, dir2, num
			if self.convert_tube_clbk then
				dir1, dir2, num = self.convert_tube_clbk(npos, node.name, node.param2)
			else
				dir1, dir2, num = self:determine_dir1_dir2_and_num_conn(npos)
			end
			if dir1 then
				self.clbk_after_place_tube(self:tube_data_to_table(npos, dir1, 
					dir2 or tubelib2.Turn180Deg[dir1], num))
				if tubelib2.Turn180Deg[dir] == dir1 then
					return npos, dir2
				else
					return npos, dir1
				end
			end
		end
	end
	
	local cnt = 0
	if not dir then	return pos, cnt end	
	while cnt <= 100000 do
		local new_pos, new_dir = convert_next_tube(self, pos, dir)
		if not new_dir then	break end
		pos, dir = new_pos, new_dir
		cnt = cnt + 1
	end
	return pos, dir, cnt
end	

function Tube:set_pairing(pos, peer_pos)
	
	M(pos):set_int("tube_dir", self:get_primary_dir(pos))
	M(peer_pos):set_int("tube_dir", self:get_primary_dir(peer_pos))
	
	local tube_dir1 = self:store_teleport_data(pos, peer_pos)
	local tube_dir2 = self:store_teleport_data(peer_pos, pos)

	self:delete_tube_meta_data(pos, tube_dir1)
	self:delete_tube_meta_data(peer_pos, tube_dir2)
end
