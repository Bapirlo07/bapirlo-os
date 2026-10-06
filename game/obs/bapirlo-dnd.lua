-- Bapirlo OS — tell the desktop when OBS is live (recording, streaming or replay buffer saving).
-- OBS → Tools → Scripts → "+" → pick this file. Remove it there to turn it off.
-- It only creates/deletes ~/.local/state/bapirlo/obs-live; the bapirlo-game GNOME extension
-- reacts to that (Do Not Disturb + instant replay). Zero cost while idle.
obs = obslua

local flag = (os.getenv("XDG_STATE_HOME") or (os.getenv("HOME") .. "/.local/state")) .. "/bapirlo/obs-live"
local recording, streaming = false, false

local function sync()
  if recording or streaming then
    os.execute('mkdir -p "' .. flag:match("(.*)/") .. '"')
    local f = io.open(flag, "w")
    if f then f:write(recording and "recording" or "streaming"); f:close() end
  else
    os.remove(flag)
  end
end

local function on_event(ev)
  if ev == obs.OBS_FRONTEND_EVENT_RECORDING_STARTED then recording = true
  elseif ev == obs.OBS_FRONTEND_EVENT_RECORDING_STOPPED then recording = false
  elseif ev == obs.OBS_FRONTEND_EVENT_STREAMING_STARTED then streaming = true
  elseif ev == obs.OBS_FRONTEND_EVENT_STREAMING_STOPPED then streaming = false
  elseif ev == obs.OBS_FRONTEND_EVENT_EXIT then recording, streaming = false, false
  else return end
  sync()
end

function script_description()
  return "Bapirlo OS: Do Not Disturb + instant replay while recording or streaming."
end

function script_load(settings)
  recording = obs.obs_frontend_recording_active()
  streaming = obs.obs_frontend_streaming_active()
  sync()
  obs.obs_frontend_add_event_callback(on_event)
end

function script_unload()
  recording, streaming = false, false
  sync()
end
