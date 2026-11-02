-- Manual ZIP upgrades leave old local records beside the renamed mod. Copy an
-- absent record only when requested; every subsequent read/write uses this mod.
-- Never enumerate, execute, move or remove the legacy files.
return function(root)
 local S={};local checked={};local failure
 local parent=root:match('^(.*)/[^/]+$')
 local legacy=root:lower():match('/beyondapocalypse$')and parent..'/BasicM4'or nil
 local function open(path)
  local file,err,code=io.open(path,'rb')
  assert(file or code==2,'Cannot read mod data: '..path..': '..tostring(err))
  return file
 end
 local function resolve(relative)
  local target=root..'/'..relative
  if checked[target]then return target end
  local current=open(target)
  if current then current:close();checked[target]=true;return target end
  local old=legacy and open(legacy..'/'..relative)
  if old then
   local tmp=target..'.legacy-migrate.tmp';local output
   local ok,err=pcall(function()
    output=assert(io.open(tmp,'wb'),'Cannot migrate mod data: '..target)
    while true do
     local bytes,readError=old:read(65536)
     assert(not readError,readError)
     if not bytes or #bytes==0 then break end
     assert(output:write(bytes))
    end
    assert(output:close());output=nil;assert(old:close());old=nil
    -- A canonical file always wins, including one created while copying.
    local existing=open(target)
    if existing then existing:close();assert(os.remove(tmp))
    else assert(os.rename(tmp,target))end
   end)
   if old then old:close()end;if output then output:close()end
   if not ok then os.remove(tmp);error(err,0)end
  end
  checked[target]=true;return target
 end
 local function safe(relative)
  if failure then error(failure,0)end
  local ok,path=pcall(resolve,relative)
  if not ok then failure=tostring(path);error(failure,0)end
  return path
 end
 function S.state(name)
  assert(type(name)=='string'and name:match('^[%w_.%-]+$')and not name:find('..',1,true),'Invalid mod state filename')
  return safe('state/'..name)
 end
 function S.config()
  local path=safe('Scripts/config.lua');local file=open(path)
  if file then file:close();return path end
  return root..'/Scripts/default_config.lua'
 end
 return S
end
