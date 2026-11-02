-- Local preferences only. Never execute configuration text or send it to a peer.
return function(M,root,H,valid)
 local C={values={},saved={},borrowed={}}
 C.rows={{'pitchForward','Pitch forward','W','Up'},{'pitchBack','Pitch back','S','Down'},
  {'rollLeft','Bank left','A','Left'},{'rollRight','Bank right','D','Right'},
  {'yawLeft','Turn left','Q','None'},{'yawRight','Turn right','E','None'},
  {'collectiveUp','Raise collective','LeftShift','RightShift'},{'collectiveDown','Lower collective','LeftControl','RightControl'},
  {'transport','Dock / release / blade rack',(M.config.Gyrocopter or{}).TransportKey or 'J','None'},
  {'ignition','Engine ignition','I','None','Ignition','Vehicule'},
  {'brake','Parking brake','SpaceBar','None','Handbrake','Vehicule'},
  {'camera','Change camera','C','None','CameraSwitch','Universal'},
  {'melee','Melee mode','CapsLock','None'}}
 C.keys={};C.codes={}
 local special={SPACE='SpaceBar',RETURN='Enter',INS='Insert',DEL='Delete',UP_ARROW='Up',DOWN_ARROW='Down',LEFT_ARROW='Left',RIGHT_ARROW='Right',OEM_PLUS='Equals',OEM_MINUS='Hyphen',OEM_COMMA='Comma',OEM_PERIOD='Period',OEM_ONE='Semicolon',OEM_TWO='Slash',OEM_THREE='Tilde',OEM_FOUR='LeftBracket',OEM_FIVE='Backslash',OEM_SIX='RightBracket',OEM_SEVEN='Apostrophe',XBUTTON_ONE='ThumbMouseButton',XBUTTON_TWO='ThumbMouseButton2',ADD='Add',SUBTRACT='Subtract',MULTIPLY='Multiply',DIVIDE='Divide',DECIMAL='Decimal',LEFT_SHIFT='LeftShift',RIGHT_SHIFT='RightShift',LEFT_CONTROL='LeftControl',RIGHT_CONTROL='RightControl',LEFT_ALT='LeftAlt',RIGHT_ALT='RightAlt',UP='Up',DOWN='Down',LEFT='Left',RIGHT='Right',ENTER='Enter',BACKSPACE='BackSpace',DELETE='Delete',INSERT='Insert',HOME='Home',END='End',PAGE_UP='PageUp',PAGE_DOWN='PageDown',TAB='Tab',CAPS_LOCK='CapsLock',LEFT_MOUSE_BUTTON='LeftMouseButton',RIGHT_MOUSE_BUTTON='RightMouseButton',MIDDLE_MOUSE_BUTTON='MiddleMouseButton',NUM_ZERO='NumPadZero',NUM_ONE='NumPadOne',NUM_TWO='NumPadTwo',NUM_THREE='NumPadThree',NUM_FOUR='NumPadFour',NUM_FIVE='NumPadFive',NUM_SIX='NumPadSix',NUM_SEVEN='NumPadSeven',NUM_EIGHT='NumPadEight',NUM_NINE='NumPadNine'}
 local digits={'Zero','One','Two','Three','Four','Five','Six','Seven','Eight','Nine'}
 for symbol,code in pairs(Key)do
  local name=special[symbol]or(symbol:match('^[A-Z]$')and symbol)or(symbol:match('^F%d+$')and symbol)
  local n=symbol:match('^NUM_(%d)$')or symbol:match('^(%d)$');if n then name=digits[tonumber(n)+1]end
  if name and name~='F8'and name~='F7'then C.keys[name]=true;C.codes[code]=name end
 end
 for i,name in ipairs({'Zero','One','Two','Three','Four','Five','Six','Seven','Eight','Nine'})do local code=Key[name:upper()];if code then C.codes[code]=name;C.keys[name]=true end end
 for code,name in pairs({[160]='LeftShift',[161]='RightShift',[162]='LeftControl',[163]='RightControl',[164]='LeftAlt',[165]='RightAlt'})do C.codes[code]=name;C.keys[name]=true end
 C.keys.None=true
 for _,r in ipairs(C.rows)do C.values[r[1]]={r[3],r[4]};C.keys[r[3]]=true;C.keys[r[4]]=true end
 local file=root..'/state/controls.txt'
 local gameplayFile=root..'/state/gameplay.txt'
 C.simpleFlight=false
 do local f=io.open(gameplayFile,'r');if f then C.simpleFlight=f:read('*a'):match('^simpleFlight=1%s*$')~=nil;f:close()end end
 function C.setSimpleFlight(enabled)
  local f=assert(io.open(gameplayFile..'.tmp','w'),'Cannot save gameplay settings')
  assert(f:write(enabled and 'simpleFlight=1\n'or 'simpleFlight=0\n'));assert(f:close())
  os.remove(gameplayFile..'.bak');local old=io.open(gameplayFile,'r');if old then old:close();assert(os.rename(gameplayFile,gameplayFile..'.bak'))end
  local ok,err=os.rename(gameplayFile..'.tmp',gameplayFile);if not ok then os.rename(gameplayFile..'.bak',gameplayFile);error(err)end
  C.simpleFlight=enabled==true
 end
 local f=io.open(file,'r');if f then for line in f:lines()do local id,a,b=line:match('^(%w+) ([%w]+) ([%w]+)$');if C.values[id]and C.keys[a]and C.keys[b]then C.values[id]={a,b};C.saved[id]=true end end;f:close()end
 function C.down(pc,id)
  local v=C.values[id];return v and((v[1]~='None'and pc:IsInputKeyDown({KeyName=FName(v[1])}))or(v[2]~='None'and pc:IsInputKeyDown({KeyName=FName(v[2])})))or false
 end
 function C.readNative()
  for _,r in ipairs(C.rows)do if r[5]and not C.saved[r[1]]then
   local ctx=StaticFindObject('/Game/Inputs/PIE/IMC_'..r[6]..'.IMC_'..r[6]);local keys={}
   if valid(ctx)then ctx.Mappings:ForEach(function(_,v)local m=v:get();local key=m.Key.KeyName:ToString();if m.Action:GetFullName():match('/'..r[5]..'%.'..r[5]..'$')and C.keys[key]and key~='None'and #m.Modifiers==0 and #m.Triggers==0 then keys[#keys+1]=key end end)end
   if #keys>0 then C.values[r[1]]={keys[1],keys[2]or 'None'}end
  end end
 end
 function C.copy()local t={};for id,v in pairs(C.values)do t[id]={v[1],v[2]}end;return t end
 local function rebuild(ctx)StaticFindObject('/Script/EnhancedInput.Default__EnhancedInputLibrary'):RequestRebuildControlMappingsUsingContext(ctx,true)end
 function C.restore()
  local contexts={}
  for _,r in ipairs(C.borrowed)do if valid(r.ctx)and valid(r.action)then
   for _,k in ipairs(r.added)do r.ctx:UnmapKey(r.action,{KeyName=FName(k)})end
   for _,k in ipairs(r.old)do r.ctx:MapKey(r.action,{KeyName=FName(k)})end
   contexts[r.ctx:GetAddress()]=r.ctx
  end end
  for _,ctx in pairs(contexts)do rebuild(ctx)end;C.borrowed={};C.vehicle=nil
 end
 function C.meleeKeyAllowed(key)
  if key=='None'then return true end
  if key=='Tab'or key=='B'or key=='L'or key=='MiddleMouseButton'then return false end
  local fist=StaticFindObject('/Game/Inputs/ActionsPlayer/FistMode.FistMode')
  for _,name in ipairs({'Player','Universal'})do
   local ctx=StaticFindObject('/Game/Inputs/PIE/IMC_'..name..'.IMC_'..name);local occupied=false
   if valid(ctx)then ctx.Mappings:ForEach(function(_,v)local m=v:get()
    if m.Key.KeyName:ToString()==key and(not valid(fist)or m.Action:GetAddress()~=fist:GetAddress()or #m.Modifiers>0 or #m.Triggers>0)then occupied=true end
   end)end
   if occupied then return false end
  end
  return true
 end
 function C.apply(values)
  local used={}
  for _,r in ipairs(C.rows)do local v=assert(values[r[1]],'Missing binding');for _,key in ipairs(v)do
   assert(C.keys[key]and key~='F8'and key~='F7','Unsupported or reserved key')
   if r[1]=='melee'then assert(C.meleeKeyAllowed(key),'Key used by another control: '..key)end
   if key~='None'then assert(not used[key],'Key already used: '..key);used[key]=true end
  end;assert(v[1]~='None'or v[2]~='None','Each action needs a key')end
  local f=assert(io.open(file..'.tmp','w'),'Cannot save controls')
  for _,r in ipairs(C.rows)do local v=values[r[1]];assert(f:write(r[1]..' '..v[1]..' '..v[2]..'\n'))end;assert(f:close())
  -- Keep the previous valid preferences if replacement fails.
  os.remove(file..'.bak');local old=io.open(file,'r');if old then old:close();assert(os.rename(file,file..'.bak'))end
  local ok,err=os.rename(file..'.tmp',file);if not ok then os.rename(file..'.bak',file);error(err)end
  C.restore();for _,r in ipairs(C.rows)do local id=r[1];C.values[id]={values[id][1],values[id][2]};C.saved[id]=true end
 end
 function C.tick()
  local pc=H.GetPlayerController();local a=valid(pc)and pc.Vehicle
  local active=M.features~=false and valid(a)and M.gyrocopter and M.gyrocopter.tracked[a:GetFullName()]
  if not active then if C.vehicle then C.restore()end;return end
  if C.vehicle==a:GetAddress()then return end;C.restore();C.vehicle=a:GetAddress()
  for _,r in ipairs(C.rows)do if r[5]then
   local ctx=StaticFindObject('/Game/Inputs/PIE/IMC_'..r[6]..'.IMC_'..r[6]);local action=StaticFindObject('/Game/Inputs/ActionCar/'..r[5]..'.'..r[5])
   if valid(ctx)and valid(action)then
    local old={};ctx.Mappings:ForEach(function(_,v)local m=v:get();local k=m.Key.KeyName:ToString();if m.Action:GetAddress()==action:GetAddress()and C.keys[k]and k~='None'and #m.Modifiers==0 and #m.Triggers==0 then old[#old+1]=k end end)
    if not C.saved[r[1]]and #old>0 then C.values[r[1]]={old[1],old[2]or'None'}end
    if C.saved[r[1]]then
     for _,k in ipairs(old)do ctx:UnmapKey(action,{KeyName=FName(k)})end
     local added={};for _,k in ipairs(C.values[r[1]])do if k~='None'then ctx:MapKey(action,{KeyName=FName(k)});added[#added+1]=k end end
     C.borrowed[#C.borrowed+1]={ctx=ctx,action=action,old=old,added=added};rebuild(ctx)
    end
   end
  end end
 end
 return C
end
