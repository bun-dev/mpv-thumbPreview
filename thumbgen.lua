--[[
    Thumbnail Generator script for thumbs.lua.   	
--]]

local utils = require "mp.utils"
local ffi = require("ffi")

--	Get memory address from ffmpeg's stdout.
local function extract_address(s)
	local addr = tostring(ffi.cast("char*",s))
	local _, loc = string.find(addr, ": 0x")
	return tonumber(string.sub(addr,loc+1,-1),16)
end

--	Generate thumbnails in stdout.
local function generate(timespan, input, size,maxThumbs)
	local thumbs = {
	data = {},
	addr = {}
	}
	
	local command = {}

	command.args = {
		"ffmpeg",
		"-loglevel","quiet",
		"-ss", "",		
		"-i", input,
		"-frames:v","1",
		"-vf", size,
		"-vcodec", "rawvideo",
		"-pix_fmt", "bgra",
		"-f", "image2",
		"-threads", "4",
		"-"
	}

	local start = mp.get_time()
	for i=0, maxThumbs do
		curtime=(i*timespan)
		command.args[5] = curtime
	
--		mp.osd_message("Running: " .. table.concat(command.args,' '),3) --[debug]
			
		local process = utils.subprocess(command)
		
		--Check if process was successful.
		if process.status ~=0 then
			mp.msg.warn("ffmpeg failed. Check if ffmpeg is in your path environment variables.")
			return
		end
		
		thumbs.data[i] = process.stdout
		thumbs.addr[i] = extract_address(thumbs.data[i])
		
		--Send thumb table to thumbs.lua
		mp.commandv("script-message-to", "thumbs", "add_thumb", i, thumbs.addr[i])

		if curtime > (maxThumbs-timespan) then
			local stop = mp.get_time()
			mp.msg.debug("All thumbs created in " .. stop-start .. " seconds")
			mp.unregister_script_message("generate")
			thumbs = {}
			return
		end	
		
	end
	
end

--Generate thumbnails in cache folder.
local function generateLocal(...)
	local arg={...}
	local init = false
	local timespan = tonumber(arg[1])
	local input = arg[2]
	local size = arg[3]
	local maxThumbs = tonumber(arg[4])
	local output = arg[5]
	local regen = tonumber(arg[6])


	local command = {}
	local mkcmd = {}
	
	mkcmd.args = {"mkdir", "-p",output}
	
	command.args = {
		"ffmpeg",
		"-loglevel","quiet",
		"-ss", "",		
		"-i", input,
		"-frames:v","1",
		"-vf", size,
		"-vcodec", "rawvideo",
		"-pix_fmt", "bgra",
		"-f", "image2",
		"-threads", "4",
		"out"
	}	
	
	if regen == 0 then
		local folder_process = utils.subprocess(mkcmd)
		if folder_process.status == 0 then
			init = true
		end
	else
		init = true
	end

	if init then
		local start = mp.get_time()
		for i=0, maxThumbs do
			curtime=(i*timespan)
			command.args[5] = curtime
			command.args[20] = output.."\\\\thumb"..tostring(i)..".bgra"
--			mp.osd_message("Running: " .. table.concat(command.args,' '),3) --[debug]
			
			local process = utils.subprocess(command)
			--Check if process was successful.
			if process.status ~=0 then
				mp.msg.warn("ffmpeg failed. Check if ffmpeg is in your path environment variables.")
				return
			end
		
			
			
			if curtime > (maxThumbs-timespan) then
				local stop = mp.get_time()
				mp.msg.debug("All thumbs created in " .. stop-start .. " seconds")
				mp.unregister_script_message("generateLocal")
				return
			end	
			
		end
		
	end
	
end


mp.register_script_message("generate", generate)
mp.register_script_message("generateLocal", generateLocal)