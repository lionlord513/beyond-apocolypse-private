-- Pinned UE4SS provides a persistent game-thread timer. Keep scheduling and
-- gameplay Lua on that thread, away from concurrent network userdata/GC.
return function(active,tick,log)
 local handle,running
 handle=LoopInGameThreadWithDelay(50,function()
  if not active()then if handle then CancelDelayedAction(handle)end;return end
  if running then return end
  running=true
  local ok,e=pcall(tick)
  running=false
  if not ok then log(tostring(e))end
 end)
 return handle
end
