-- Includes
local kb = libs.keyboard;
local script = libs.script;
local win = libs.win;
local server = require("server");

-- Variables
local cached_device_vol = nil; -- Stores the locally cached volume
local cached_device_name = ""; -- Stores the name of the default playback device
local sync_timer = nil; -- Timer for periodic sync with the system volume and device
local plex_exe   = "C:\\Program Files\\Plex\\Plex\\Plex.exe";
local plex_win   = "plex.exe";
local plex_title = "Plex";
local last_volume_update = libs.timer.time(); -- Current timestamp in millisecond
local update_delay = 10000; -- Time in milliseconds between default device name/vol updates

libs.server.update({ id = "plexDetails",  text = "Plex Path:  " .. plex_exe 
                                             .."\nPlex Title:  " .. plex_title
                                             .."\nPlex Win:   " .. plex_win 
                                            });

-- Constants
local VOLUME_STEP = 2; -- Step size for volume changes (2%)

----- Function to get system volume using PowerShell
-- local function get_system_volume()
--     local powershell_script_template = [[
--         Import-Module AudioDeviceCmdlets;
--         $defaultDevice = args[0];
--         $defaultDevice;
--         if ($defaultDevice -and $defaultDevice.Device) {
--             [Math]::Round($defaultDevice.Device.AudioEndpointVolume.MasterVolumeLevelScalar * 100);
--         } else {
--             -1; # Return -1 if no matching device is found
--         }
--     ]];
--     -- Insert the saved device ID into the script
--     local powershell_script = string.format(powershell_script_template, device_id);
--     local result, err, code = script.powershell(powershell_script);
--     print("\nRESULT: " .. result);
--     if result then
--         local volume = tonumber(result);
--         if volume and volume >= 0 then
--             print("VOLUME: " .. volume);
--             return volume;
--         end
--     end
--     return nil; -- Return nil if retrieval fails
-- end

-- Function to get the default playback device name using PowerShell
local function get_default_playback_device()
    local powershell_script = [[
        Import-Module AudioDeviceCmdlets;
        $defaultDevice = Get-AudioDevice -List | Where-Object { $_.Default -eq "True" -and $_.Type -eq "Playback" };
        if ($defaultDevice) {
            $volume = [Math]::Round($defaultDevice.Device.AudioEndpointVolume.MasterVolumeLevelScalar * 100);
            Write-Host "$($defaultDevice.Name),$($defaultDevice.id),$($volume)";
        } else {
            Write-Host "No default playback device found";
        }
    ]];
    local result, err, code = script.powershell(powershell_script);
    if result and result ~= "No default playback device found" then
        local device_name, device_id, device_vol = result:match("([^,]+),([^,]+),([^,]+)");
        return { name = device_name, id = device_id, vol = device_vol };
    end
    return nil; -- Return nil if retrieval fails
end

-- Sync the default playback device
local function sync_playback_device()
    local def_device = get_default_playback_device();
    if def_device then
        cached_device_name = def_device.name;
        cached_device_vol = tonumber(def_device.vol);
        print("\nDEVICE INFO " .. 
            "\nName: " .. def_device.name .. 
            "\nID:   " .. def_device.id ..
            "\nVol:  " .. def_device.vol .. "%");
        libs.server.update({ id = "vol_control_label", text = "Volume Control\nDevice: " .. def_device.name});
        libs.server.update({ id = "vol_slider", progress = cached_device_vol });
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
        sync_playback_device();
    end, update_delay); -- Sync every X seconds
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
    local now = libs.timer.time(); -- Current timestamp in milliseconds

    -- Rate limit volume updates to avoid queued/delayed updates
    if now - last_volume_update >= 70 then
        local volume_units = math.floor(vol * 655.35);
        kb.press("volumemute");
        kb.press("volumemute");
        script.default(string.format('nircmd.exe setsysvolume %d', volume_units));
        cached_device_vol = vol; -- Update cached volume
        last_volume_update = now; -- Update the timestamp
    end
end

--@help Lower Volume
actions.volume_down = function()
    kb.press("volumedown"); -- Lower system volume
    if cached_device_vol ~= nil then
        cached_device_vol = math.max(0, cached_device_vol - VOLUME_STEP);
        libs.server.update({ id = "vol_slider", progress = cached_device_vol });
    end
end

--@help Raise Volume
actions.volume_up = function()
    kb.press("volumeup"); -- Raise system volume
    if cached_device_vol ~= nil then
        cached_device_vol = math.min(100, cached_device_vol + VOLUME_STEP);
        libs.server.update({ id = "vol_slider", progress = cached_device_vol });
    end
end

--@help Mute/Unmute
actions.mute = function()
    kb.press("volumemute");
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

-- Remote Initialization (tab_update handles this just fine..)
--events.focus = function()
--    sync_playback_device();
--    os.sleep(3000);
--    start_periodic_sync(); -- Start periodic syncing
--end

events.blur = function()
    if sync_timer then
        libs.timer.cancel(sync_timer);
        sync_timer = nil;
    end
end

-- only run timer on first tab
actions.tab_update = function (index)
    print("/n/nTab #: " .. index);
    if index > 0 then
        libs.timer.cancel(sync_timer);
        sync_timer = nil;
    else
        start_periodic_sync(); -- Start periodic syncing
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
