# mpv-thumbPreview
mpv thumbnail generator script [windows]

Generates thumbnail previews for mpv.

![Alt text](https://i.imgur.com/SGxtLps.png "Screenshot")

Tested with shinchiro's compiled mpv only.[mpv!]https://sourceforge.net/projects/mpv-player-windows/files/64bit/

If compiling mpv, requires luajit module.

# [Installation]
Drag n' Drop blank.bgra, thumbgen.lua and thumbs.lua into your mpv\scripts folder.

# [Requirements]
Updated MPV + ffmpeg.
Please make sure the path to ffmpeg exists inside your PATH environment variables.IE, C:\ffmpeg\bin

# [Info]
Blank.bgra - placeholder 'loading' thumbnail.

thumbgen.lua - ffmpeg generator script. It uses mp.commandv("script-message-to") to pipe the stdout to thumbs.lua in a non-blocking manner.

thumbs.lua - main viewer script which handles the input and general behaviour.

# [Usage]

By default the thumbnails should be generated anytime a video is shown. However this behaviour can be changed by editing the global variable inside thumbs.lua.

	[thumbdir]  --The global thumbnail folder. [Only if cache is set to true]
	[thumb_width]  --thumbnail width. Aspect ratio automatically applied.
	[offset_from_seekbar] --The offset y from the seekbar.
	[y_offset] --Thumbnail y-pos offset.
	[timespan] --The amount of thumbs to be created. IE, every 20 seconds.
	[minTime] --The minimum time needed in order to check for thumbs. We don't want thumbnails being created on files less than 5 minutes for example.
	[auto] --If true, will automatically create thumbs everytime a video is open. If false, a key will have to be pressed to start the generation. True by default.
	[cache] --If true, thumbs will be saved inside the 'thumbdir' so that they do not need to be created again. If false, thumbs will only persist in mpv's memory. If you set this to true, then you must change the default placeholder thumbdir var. False by default.
  

# [Known-Bugs]
- no-keepaspect-window works but has issues at extreme scales.
- cache=true is still wip
- Some videos with odd native resolutions break the mouse region. will be fixed next update

# [ChangeLog]
	0.1 - Initial release
	0.2 - Mouse region improved.
	0.3 - Mouse region adjusted for no-keepaspect-window.
 

