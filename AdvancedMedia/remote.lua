-- Includes
local kb = libs.keyboard;
local script = libs.script;
local win = libs.win;
local server = require("server");

-- Variables
local cached_volume = nil; -- Stores the locally cached volume
local cached_device_name = nil; -- Stores the name of the default playback device
local sync_timer = nil; -- Timer for periodic sync with the system volume and device
local plex_exe   = "C:\\Program Files\\Plex\\Plex\\Plex.exe";
local plex_win   = "plex.exe";
local plex_title = "Plex";

libs.server.update({ id = "plexDetails",  text = "Plex Path:  " .. plex_exe 
                                             .."\nPlex Title:  " .. plex_title
                                             .."\nPlex Win:   " .. plex_win 
                                            });

-- Constants
local VOLUME_STEP = 2; -- Step size for volume changes (2%)

-- Function to get system volume using PowerShell
local function get_system_volume()
    local powershell_script = [[
        Import-Module AudioDeviceCmdlets;
        $defaultDevice = Get-AudioDevice -List | Where-Object { $_.Default -eq "True" -and $_.Type -eq "Playback" };
        if ($defaultDevice -and $defaultDevice.Device) {
            [Math]::Round($defaultDevice.Device.AudioEndpointVolume.MasterVolumeLevelScalar * 100);
        } else {
            -1; # Return -1 if no device is found
        }
    ]];
    local result, err, code = script.powershell(powershell_script);
    if result then
        local volume = tonumber(result);
        if volume and volume >= 0 then
            return volume;
        end
    end
    return nil; -- Return nil if retrieval fails
end

-- Function to get the default playback device name using PowerShell
local function get_default_playback_device()
    local powershell_script = [[
        Import-Module AudioDeviceCmdlets;
        $defaultDevice = Get-AudioDevice -List | Where-Object { $_.Default -eq "True" -and $_.Type -eq "Playback" };
        if ($defaultDevice) {
            Write-Host $defaultDevice.Name;
        } else {
            Write-Host "No default playback device found";
        }
    ]];
    local result, err, code = script.powershell(powershell_script);
    if result and result ~= "" and result ~= "No default playback device found" then
        return result:match("^%s*(.-)%s*$"); -- Trim whitespace
    end
    return nil; -- Return nil if retrieval fails
end

-- Sync the slider with the current system volume
local function sync_slider_with_system_volume()
    local vol = get_system_volume();
    if vol ~= nil then
        cached_volume = vol;
        libs.server.update({ id = "vol_slider", progress = vol });
    end
end

-- Sync the default playback device
local function sync_playback_device()
    local device_name = get_default_playback_device();
    if device_name then
        cached_device_name = device_name;
        libs.server.update({ id = "vol_control_label", text = "Volume Control\nDevice: " .. device_name });
    else
        libs.server.update({ id = "vol_control_label", text = "Volume Control\nDevice: Unknown" });
        print("Failed to sync default playback device.");
    end
end

-- Periodically sync the system volume and playback device
local function start_periodic_sync()
    if sync_timer then
        libs.timer.cancel(sync_timer);
    end
    sync_timer = libs.timer.interval(function()
        sync_slider_with_system_volume();
        sync_playback_device();
    end, 5000); -- Sync every 5 seconds
end

-- Stop periodic syncing
local function stop_periodic_sync()
    if sync_timer then
        libs.timer.cancel(sync_timer);
        sync_timer = nil;
    end
end
-- Volume Section Actions
--@help Set Volume from Slider
--@param vol:number Volume (0-100) percent
actions.volume = function(vol)
    local volume_units = math.floor(vol * 655.35);
    kb.press("volumemute");
    kb.press("volumemute");
    script.default(string.format('nircmd.exe setsysvolume %d', volume_units));
    cached_volume = vol; -- Update cached volume
end

--@help Lower Volume
actions.volume_down = function()
    kb.press("volumedown"); -- Lower system volume
    if cached_volume ~= nil then
        cached_volume = math.max(0, cached_volume - VOLUME_STEP);
        libs.server.update({ id = "vol_slider", progress = cached_volume });
    end
end

--@help Raise Volume
actions.volume_up = function()
    kb.press("volumeup"); -- Raise system volume
    if cached_volume ~= nil then
        cached_volume = math.min(100, cached_volume + VOLUME_STEP);
        libs.server.update({ id = "vol_slider", progress = cached_volume });
    end
end

--@help Mute/Unmute
actions.mute = function()
    kb.press("volumemute");
    sync_slider_with_system_volume(); -- Sync slider with muted state
end

-- Navigation Buttons
--@help Back/Return
actions.back = function()
    kb.stroke("back");
end

--@help Move Up
actions.up = function()
    kb.stroke("up");
end

--@help Play/Pause Media
actions.play_pause = function()
    kb.stroke("space");
end

--@help Play/Pause Media
actions.stop = function()
    kb.stroke("x");
end

--@help Play/Pause Media
actions.escape = function()
    kb.stroke("esc");
end

--@help Move Left
actions.left = function()
    kb.stroke("left");
end

--@help Press Enter
actions.enter = function()
    kb.stroke("enter");
end

--@help Move Right
actions.right = function()
    kb.stroke("right");
end

--@help Skip Back
actions.skip_back = function()
    kb.stroke("left", "oem_comma");
end

--@help Move Down
actions.down = function()
    kb.stroke("down");
end

--@help Skip Forward
actions.skip_forward = function()
    kb.stroke("right", "oem_period");
end

-- Remote Initialization
events.focus = function()
    sync_slider_with_system_volume(); -- Sync slider on remote load
    start_periodic_sync(); -- Start periodic syncing
end

events.blur = function()
    if sync_timer then
        libs.timer.cancel(sync_timer);
        sync_timer = nil;
    end
end


-----------------------------------------------
-- Plex Tab commands
-----------------------------------------------

actions.launch_plex = function()
    os.start(plex_exe);
end

actions.focus_plex = function()
	win.switchtowait(plex_win);
end

actions.kill_plex = function()
	win.kill(plex_win);
end

actions.find_plex = function()
    findplex = win.find(plex_title, plex_title);
    libs.server.update({ id = "findPlex",  text = "Find Plex:\n"  .. findplex});
end

actions.launchFocusPlex = function()
    findplex = win.find(plex_win, plex_win);
    if findplex == 0 then
        os.start(plex_exe);
    else
        win.switchtowait(plex_win);
    end
end

--@help Skip Forward
actions.get_cur_window = function()
    hwnd  = win.active();		
    title = win.title(win.active());
    cls   = win.class(win.active());
    pid   = win.process(win.active());
    
    libs.server.update({ id = "winHWND",  text = "HWND:\n"  .. hwnd});
    libs.server.update({ id = "winTitle", text = "Title:\n" .. title});
    libs.server.update({ id = "winClass", text = "Class:\n" .. cls});
    libs.server.update({ id = "winPID",   text = "PID:\n"   .. pid});
end

actions.dashboard = function()
    win.switchtowait(plex_win);
    kb.stroke("g", "d");
end

actions.home = function()
    win.switchtowait(plex_win);
    kb.stroke("g", "h");
end
actions.settings = function()
    win.switchtowait(plex_win);
    kb.stroke("g", "s");
end

actions.context = function()
    win.switchtowait(plex_win);
    kb.stroke("c");
end

actions.fullscreen = function()
    kb.stroke("menu", "enter");
end

actions.prevScreen = function()
    kb.stroke("win", "shift", "left");
end
actions.nextScreen = function()
    kb.stroke("win", "shift", "right");
end