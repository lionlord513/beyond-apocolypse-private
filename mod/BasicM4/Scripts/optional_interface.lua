-- Public gameplay keeps its shared HUD without installing developer controls.
-- The companion is local-only and never included in player/update packages.
return function(M,root,H,valid,enqueue,log)
 local dashboard=dofile(root..'/Scripts/dashboard.lua')(M,H,valid);M.dashboard=dashboard
 local hud=dashboard.flight;M.hudFrame=dashboard.frame
 local interface={ui={opened=false,hud=hud},tick=function()end,reset=function()hud(nil)end}
 local path=root..'/../BeyondApocolypseDevMenu/Scripts/attach.lua'
 local file=io.open(path,'r')
 if file then
  file:close()
  local ok,result=pcall(function()return dofile(path)(M,root,H,valid,enqueue,log,hud)end)
  if ok then return result end
  log('Optional private companion could not load: '..tostring(result))
 end
 return interface
end
