-- Public gameplay keeps its shared HUD without installing developer controls.
-- The companion is local-only and never included in player/update packages.
return function(M,root,H,valid,enqueue,log)
 local path=root..'/../BeyondApocolypseDevMenu/Scripts/attach.lua'
 local file=io.open(path,'r')
 if file then
  file:close()
  local ok,result=pcall(function()return dofile(path)(M,root,H,valid,enqueue,log,M.dashboard.flight)end)
  if ok and result and type(result.ui)=='table' and type(result.tick)=='function' and type(result.reset)=='function' then return result end
  log('Optional private companion could not load: '..tostring(result))
 end
 return nil
end
