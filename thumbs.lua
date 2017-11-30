--[[
    MPV Thumbnail Preview
    Version: 0.1
	
	Generates preview thumbnails for mpv either locally or dynamically using overlay-add.
	
	[Requirements]
		-ffmpeg ( not included. Please make sure ffmpeg is included in your PATH environment vars. IE, D:\ffmpeg\bin)
		-thumbgen.lua (included)
		-blank.bgra (included)
		
	[Usage]
		Press 'k' to activate. Set 'auto' to true in _global for automatic activation. (thumbs will be generated every time a video is opened)
		
	[Cached Thumbnails]
		To enable cached thumbs, set 'cache' in _global to true.
		
	[Remove thumbs] (Cache only)
		TODO: If the video has been deleted, then the old thumbs will not work and thus deleted.
		
	Special thanks to various anons in https://boards.4chan.org/g/catalog#s=mpv
--]]

local msg = require 'mp.msg'
local utils = require "mp.utils"

--	variables which can be modified.
local _global = {
	thumbdir = "D:\\\\mpv\\\\cache\\\\", --The global thumbnail folder. [Only if cache is set to true]
	thumb_width = 150, --thumbnail width. aspect ratio automatically applied.
	offset_from_seekbar = 120, --The offset y from the seekbar.
	scale_offset = 20, --The window scale offset-y position of the thumb. 
	timespan = 20, --The amount of thumbs to be created. IE, every 30 seconds.
	minTime = 300, -- The minimum time needed in order to check for thumbs. We don't want thumbnails being created on files less than 5 minutes for example.
	auto = false, -- If true, will automatically create thumbs everytime a video is open. If false, a key will have to be pressed to start the generation.
	cache = true -- If true, thumbs will be saved inside the 'thumbdir' so that they do not need to be created again. If false, thumbs will only persist in mpv's memory.
}

local vid_w,vid_h = 0
local osd_w,osd_h = 0
local input,outpath,mpath = ""
local hash = ""
local init,init2 = false
local regen = 0
local oldSize,thumb_height = 0
local scale,vid_sh,offsety,posy = 0
local duration = 0
local thumbaddr = {}
local rect = { }
local offset_x_seekbar = (_global.thumb_width/2) --Center of thumbnail width.
		
local function script_path()
   local str = debug.getinfo(2, "S").source:sub(2)
   return str:match("(.*/)")
end

local function extract_address(s)
	local addr = tostring(ffi.cast("char*",s))
	local _, loc = string.find(addr, ": 0x")
	return tonumber(string.sub(addr,loc+1,-1),16)
end

function GetFileExtension(strFilename)
  return string.match(strFilename,"^.+(%..+)$")
end

local function escape(str)
    return str:gsub("\\", "\\\\"):gsub("'", "'\\''")
end

local function trim(str)
    return str:gsub("^%s+", ""):gsub("%s+$", "")
end

local function osd(str)
    return mp.osd_message(str, 3)
end

local function round(number)
    return math.floor(number + 0.5)
end

local clamp = function (val, min, max)
	assert(min <= max)
	if val < min then return min end
	if val > max then return max end
	return val
end


local function resized()
	oldSize = osd_w
	scale = math.min(osd_w/vid_w, osd_h/vid_h) -- Factor by which the video is scaled to fit the screen
	vid_sh,offsety = scale*vid_h,round((vid_h -osd_h)/_global.scale_offset)	--video scale-height and offset.
	posy = round((vid_sh+offsety)-_global.offset_from_seekbar)	
end

--	https://github.com/aidanholm/mpv-easycrop/blob/master/easycrop.lua
local video_space_from_screen_space = function (ssp)
	-- Factor by which the video is scaled to fit the screen
	local scale = math.min(osd_w/vid_w, osd_h/vid_h)

	-- Size video takes up in screen
	local vid_sw, vid_sh = scale*vid_w, scale*vid_h

	-- Video offset within screen
	local off_x = math.floor((osd_w - vid_sw)/2)
	local off_y = math.floor((osd_h - vid_sh)/2)

	local vsp = {}

	-- Move the point to within the video
	vsp.x = clamp(ssp.x, off_x, off_x + vid_sw)
	vsp.y = clamp(ssp.y, off_y, off_y + vid_sh)

	-- Convert screen-space to video-space
	vsp.x = math.floor((vsp.x - off_x) / scale)
	vsp.y = math.floor((vsp.y - off_y) / scale)

	return vsp
end

local function on_seek()	

	--	init2 is set true when the thumbs creation has been started. we don't want these calculations being performed needlessly, unless caching is enabled.
	if init2 or _global.cache then 
		osd_w,osd_h = mp.get_property("osd-width"),mp.get_property("osd-height")
		
		--Setup video w/h once.
		if vid_w == 0 then
			vid_w,vid_h = mp.get_property("width"),mp.get_property("height")
			
			local osc = tostring(mp.get_property("osc"))
			
			--harded mouse region based. Probably needs to be redone the 'proper' way
			if osc == "yes" then 
				rect = { 
					x1 = 234,
					y1 = 690,
					x2 = 875,
					y2 =716
					}
			else
				rect = { 
					x1 = 0,
					y1 = 680,
					x2 = tonumber(vid_w),
					y2 = 718
					}
			end
		
			--calculate thumb_height based on given width.	
			thumb_height = math.floor(_global.thumb_width/ (vid_w/vid_h))
			resized()
		end
	
		local point = {}
		point.x, point.y = mp.get_mouse_pos()
		local ssp = video_space_from_screen_space(point)
		
		--calculate new sizes when resized.
		if oldSize ~= osd_w then
			resized()	
		end

			
		local posx =(point.x-offset_x_seekbar)
		local region = ssp.x > rect.x1 and ssp.x <  rect.x2 and ssp.y > rect.y1 and ssp.y < rect.y2 --mouse zone(seekbar)
		local norm = math.floor(((ssp.x - rect.x1)/ (rect.x2 - rect.x1))*duration) --normalized range of mouse x(ssp)
		local index = math.floor(norm/_global.timespan) 
		local thumbpath = nil
		
		if init then
			if _global.cache then
				local tmp = string.format("%s%s",outpath,"\\thumb")
				thumbpath = tmp..tostring(index)..".bgra"
				thumbaddr[index] = 0 --dummy value
			else
				thumbpath = "&"..tostring(thumbaddr[index])
			end

			if region then
				if norm % _global.timespan < (_global.timespan-1) then
					if thumbaddr[index] ~= nil then					
						mp.commandv("overlay-add",1,posx,posy,thumbpath, 0, "bgra",_global.thumb_width, thumb_height, (4*_global.thumb_width))
					else
						--not loaded yet.
						mp.commandv("overlay-add",1,posx,posy,mpath.."blank.bgra", 0, "bgra",_global.thumb_width, thumb_height, (4*_global.thumb_width))
					end
				end	
			else
				mp.commandv("overlay-remove",1)
			end
		end
	end
end
 
 local function createThumbs()

	local size = "scale=$thumbwidth:-1"
	size = size:gsub("$thumbwidth", _global.thumb_width)	


	if not _global.cache then
--		osd("Generating thumbnails dynamically") --[debug]
		init2 = true
		mp.commandv("script-message-to", "thumbgen", "generate",_global.timespan, input, size,duration)
	else
--		osd("Generating thumbnails locally") --[debug]
		init2 = true			
		mp.commandv("script-message-to", "thumbgen", "generateLocal",_global.timespan, input, size,duration,outpath,regen)
	end

end

local function checkThumbs()	

	if duration < _global.minTime then
		if not _global.auto then
			osd("Video duration less than ".. tostring(_global.minTime) .. " seconds. Cancelled")
		end
	return end
	
	--Check if a local folder exists or not if caching, else use regular streaming method.
	if _global.cache then
		local command = {}
		command.args = {
			"cd",outpath
		}
		local response = utils.subprocess(command)
		
		if response.status ~= 0 then
			createThumbs()
		else
			osd("Thumbnails exist. Recreate? Y/N",25)
			addBinding()
		end	
	else
		if not init2 then
			createThumbs()
		end
	end
end

--	Gets data from generate function from thumbgen.lua
local function add_thumb(index, addr)
	local i = tonumber(index)
	thumbaddr[i] = tonumber(addr)
end

local function unsave()
	osd("Cancelled.",1)
	removeBinding()
end

local function regenThumb()
	regen = 1
	createThumbs()
	removeBinding()
end

--	Temporarily force y as a keybinding for confirmation.
local function addBinding()
	mp.add_forced_key_binding("y", "save", regenThumb)
	mp.add_forced_key_binding("Y", "save2", regenThumb)
	mp.add_forced_key_binding("n", "unsave", unsave)
	mp.add_forced_key_binding("N", "unsave2", unsave)	
end

--	Temporarily force n as a keybinding for confirmation.
local function removeBinding()
	mp.remove_key_binding("unsave")
	mp.remove_key_binding("unsave2")
	mp.remove_key_binding("save")
	mp.remove_key_binding("save2")
end

local function unregister()
	init = false
	init2 = false
	mp.remove_key_binding("checkThumbs")
	mp.unregister_script_message("add_thumb")
	timer:kill()
	return
end

local check
check = function()
	mp.unregister_event(check)
	
	
	--check if valid format for making previews
	local validlist = '.avi|.divx|flv|.mkv|.mov|.mp4;.mpeg|.mpg|.rm|.rmvb|.ts|.vob|.webm|.wmv'
	local ext = GetFileExtension(mp.get_property("filename"))
	
	mpath = script_path() 
	mpath=mpath:gsub([[/]],[[\\]])
	
	--if the video isn't in the valid list, then it's ignored.
	if not string.match(validlist, ext) then
		unregister()
	return end
	
	--check if video length is sane
	if duration == 0 then
		duration = math.floor(mp.get_property_number("duration"))
		
		--if the video length is too small, don't create thumbs.
		if duration < _global.minTime then
			unregister()
		return end
	end
		
	oldSize = mp.get_property("osd-width")
	input = escape(utils.join_path(utils.getcwd(),mp.get_property("path")))
	--If we're using cache, grab md5 of video.
	if _global.cache then
		local cmd = {}

		cmd.args = {
			"ffmpeg",
			"-loglevel","quiet",	
			"-i", input,
			"-frames:v","1",
			"-t", "0.1",
			"-f", "md5",
			"-"
		}

		local process = utils.subprocess(cmd)
		local tmp = process.stdout
		hash = tostring(tmp:gsub("MD5=", ""))
		hash = tostring(hash:gsub("\n", ""))
		outpath = _global.thumbdir .. hash
		init = true
	end
	
	if _global.auto then
		checkThumbs()
	end
		
	init = true
end

--keybindings
mp.add_key_binding("k", "checkThumbs", checkThumbs)

--registers
mp.register_script_message("add_thumb", add_thumb)
local timer = mp.add_periodic_timer(0.03, on_seek)

local fileLoaded
fileLoaded = function()
  return mp.register_event('playback-restart', check)
end
return mp.register_event('file-loaded', fileLoaded)