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

local Tube = tubelib2.Tube

function Tube:on_convert_tube(convert_tube_clbk)
	self.convert_tube_clbk = convert_tube_clbk
end

function Tube:convert_to_tubelib2(pos1, dir1)
	local pos2, dir2, cnt = self:convert_tube_line(pos1, dir1)
	self:add_meta_data(pos1, pos2, dir1, dir2, cnt)
end


function Tube:convert_tube_line(pos, dir)
	local convert_next_tube = function(self, pos, dir)
		local npos, node = self:get_next_node(pos, dir)
		local dir1, dir2, num = self.convert_tube_clbk(npos, node.name, node.param2)
		if dir1 then
			self.clbk_after_place_tube(self:tube_data_to_table(npos, dir1, dir2 or tubelib2.Turn180Deg[dir1], num))
			
			if tubelib2.Turn180Deg[dir] == dir1 then
				return npos, dir2
			else
				return npos, dir1
			end
		end
	end
	
	local cnt = 0
	if not dir then	return pos, cnt end	
	while cnt <= self.max_tube_length do
		local new_pos, new_dir = convert_next_tube(self, pos, dir)
		if not new_dir then	break end
		pos, dir = new_pos, new_dir
		cnt = cnt + 1
	end
	return pos, dir, cnt
end	
