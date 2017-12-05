--[[
    MPV Thumbnail Preview
    Version: 0.3
	
	Changes:
	0.1 - Initial release
	0.2 - Mouse region improved.
	0.3 - Mouse region adjusted for no-keepaspect-window.
	
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
local options = require "mp.options"

--	variables which can be modified.
local _global = {
	thumbdir = "D:\\\\mpv\\\\cache\\\\", --The global thumbnail folder. [Only if cache is set to true]
	thumb_width = 150, --thumbnail width. aspect ratio automatically applied.
	offset_from_seekbar = 120, --The offset y from the seekbar.
	y_offset = 0, --Thumbnail y-pos offset.
	timespan = 20, --The amount of thumbs to be created. IE, every 30 seconds.
	minTime = 300, -- The minimum time needed in order to check for thumbs. We don't want thumbnails being created on files less than 5 minutes for example.
	auto = true, -- If true, will automatically create thumbs everytime a video is open. If false, a key will have to be pressed to start the generation.
	cache = false -- If true, thumbs will be saved inside the 'thumbdir' so that they do not need to be created again. If false, thumbs will only persist in mpv's memory.
}
options.read_options(_global)

local vid_w,vid_h = 0
local osd_w,osd_h = 0
local input,outpath = ""
local mpath = ""
local hash = ""
local init,init2 = false
local regen = 0
local oldSize= {}
local thumb_height
local duration = 0
local thumbaddr = {}
local offset_x_seekbar = (_global.thumb_width/2) --Center of thumbnail width.
local zoneY, zoneX = 0		
local zRect = {}
local sw,sh = 0

local function script_path()
   local str = debug.getinfo(2, "S").source:sub(2)
   return str:match("(.*/)")
end

function GetFileExtension(strFilename)
  return string.match(strFilename,"^.+(%..+)$")
end

local function escape(str)
    return str:gsub("\\", "\\\\"):gsub("'", "'\\''")
end

local function osd(str)
    return mp.osd_message(str, 2)
end

-- modified from https://github.com/occivink/mpv-scripts/blob/master/drag-to-pan.lua
local function compute_video_dimensions()
    local video_params = mp.get_property_native("video-out-params")
    local h = video_params["h"]
    local dw = video_params["dw"]
    local dh = video_params["dh"]

	local fwidth = osd_w
	local fheight = math.floor(osd_w / dw * dh)
			
	if fheight > osd_h or fheight < h then
		local tmpw = math.floor(osd_h / dh * dw)
		if tmpw <= osd_w then
			fheight = osd_h
			fwidth = tmpw
		end
	end
	
	if fheight < osd_h then
		fheight = osd_h
	end
	
	sw = fwidth + math.floor( fwidth / fheight)
	sh = fheight + math.floor( fwidth / fheight)
end

local function resized()
	oldSize.x,oldSize.y = osd_w,osd_h
	compute_video_dimensions()
	local osc = tostring(mp.get_property("osc"))
	
	--hard coded ranges based on bottombar layout and progressbar.lua
	if osc == "yes" then 
		zRect = {
			aY = ((sh * 94) / 100),
			aY2 = ((sh * 1) / 100),
			bX = ((sw * 19)/ 100),
			bX2 = ((sw * 32) / 100)
		}
	else
		zRect = {
			aY = ((osd_h * 94) / 100),
			aY2 = ((osd_h * 1)/ 100),
			bX = ((osd_w* 1) / 100),
			bX2 = ((osd_w * 1) / 100)
		}

	end
end

--	https://github.com/wiiaboo/mpv-scripts/blob/master/zones.lua
local function zone(p)
	local v = {0, 1, 2}
	local h = {0, 1, 2}
	
    local y = (p.y < zRect.aY) and v[1] or (p.y < (osd_h - zRect.aY2)) and v[2] or v[3]
	local x = (p.x < zRect.bX) and h[1] or (p.x < (osd_w - zRect.bX2)) and h[2] or h[3]

    return y, x
end

local function on_seek()
	--	init2 is set true when the thumbs creation has been started. we don't want these calculations being performed needlessly, unless caching is enabled.
	if init2 or _global.cache then 
		osd_w,osd_h = mp.get_osd_size()
		local point = {}
		point.x, point.y = mp.get_mouse_pos()
	
		--Setup video w/h once.
		if vid_w == 0 then
			vid_w,vid_h = mp.get_property("width"),mp.get_property("height")
			
			resized()
			
			--calculate thumb_height based on given width.				
			thumb_height = math.floor(_global.thumb_width/ (vid_w/vid_h))
		end
	
		--calculate new sizes when resized.
		if oldSize.x ~= osd_w or oldSize.y ~= osd_h then
			resized()
		end
		
		zoneY, zoneX = zone(point)
		
--		osd(tostring(zoneX).."-"..tostring(zoneY)) --[Debug] 
		
		local posx = (point.x-offset_x_seekbar)
		local posy = math.floor(zRect.aY-(thumb_height+_global.y_offset))
		
		local region = zoneX ==1 and zoneY == 1 --mouse zone(seekbar)
		local norm = math.floor(((point.x - zRect.bX)/ ((osd_w - zRect.bX2) - zRect.bX))*duration) --normalized range of mouse x(ssp)
		local index = math.floor(norm/_global.timespan) +1
		local thumbpath = nil
						
		if init then
			if _global.cache then
				local tmp = string.format("%s%s",outpath,"\\thumb")
				thumbpath = tmp..tostring(index)..".bgra"
				thumbaddr[index] = 0 --dummy value
			else
				thumbpath = "&"..tostring(thumbaddr[index])
			end
			
			if index > #thumbaddr+1 then
				index = #thumbaddr
				mp.commandv("overlay-add",1,posx,posy,mpath.."blank.bgra", 0, "bgra",_global.thumb_width, thumb_height, (4*_global.thumb_width))
			end
			
			if index < 0 then
				index = 0
			end
						
			if region then
				mp.commandv("overlay-add",1,posx,posy,thumbpath, 0, "bgra",_global.thumb_width, thumb_height, (4*_global.thumb_width))
			else
				mp.commandv("overlay-remove",1)
			end
		end
	end
end
 
 local function createThumbs()

	local size = "lavfi=[scale=$thumbwidth:-1]"
	size = size:gsub("$thumbwidth", _global.thumb_width)
	init2 = true
	
	if not _global.cache then
		mp.msg.debug("Generating thumbnails dynamically")
		mp.commandv("script-message-to", "thumbgen", "generate",_global.timespan, input, size,duration)
	else
		mp.msg.debug("Generating thumbnails locally")
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
	mp.msg.debug("mpv thumbs unregistered")
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
	local validlist = '.avi|.divx|flv|.mkv|.mov|.mp4|.mpeg|.mpg|.rm|.rmvb|.ts|.vob|.webm|.wmv|.m2ts'
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
		
	oldSize.x,oldSize.y = mp.get_osd_size()
	input = escape(utils.join_path(utils.getcwd(),mp.get_property("path")))
	
	--If we're using cache, grab md5 of video.
	if _global.cache then
		local cmd = {}

		cmd.args = {
			"mpv",
			"--msg-level","all=no",	
			input,
			"--frames","1",
			"--of", "md5",
			"--o=-"
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
	mp.msg.debug("mpv thumbs initial check performed")	
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
