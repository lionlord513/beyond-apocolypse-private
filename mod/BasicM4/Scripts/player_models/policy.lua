local P={prefix='BASKIN1',kind='BAModelSelector',marker='BA_PlayerSkin_v1_',catalog={
 {id=0,name='Default game appearance',description='Your original character and clothing.',portrait='default-face.png',preview='default-preview.png'},
 {id=1,name='SciFi Soldier',description='Armoured soldier. Original movement and weapon handling.',portrait='soldier-face.png',preview='soldier-preview.png'},
 {id=2,name='Alien',description='Alien skin and glowing eyes.',portrait='alien-face.png',preview='alien-preview.png'},
}}
P.regions={
 [0]={{'Wristband','9C603C'}},
 [1]={{'Visor','3CDCEC'},{'Undersuit','343A42'},{'Armor','596875'},{'Armor trim','849097'}},
 [2]={{'Eyes','41FFE6'},{'Skin','829A8F'}}
}
function P.allowed(id)return type(id)=='number' and P.regions[id]~=nil end
function P.stock(id)return string.rep('------0',#P.regions[id])end
function P.validColors(id,s)
 if not P.allowed(id) or type(s)~='string' or #s~=#P.regions[id]*7 then return false end
 for i=1,#s,7 do
  local hex=s:sub(i,i+5);local finish=s:sub(i+6,i+6)
  if hex~='------' and not hex:match('^%x%x%x%x%x%x$') then return false end
  if not finish:match('^[012]$') or id~=1 and finish~='0' then return false end
 end
 return true
end
function P.parse(message,op)
 if type(message)~='string' or #message>96 then return end
 local nonce,id,colors=message:match('^BASKIN1|'..op..'|([1-9]%d*)|([012])|([%x%-]+)$')
 if not nonce then nonce,id=message:match('^BASKIN1|'..op..'|([1-9]%d*)|([012])$') end
 nonce,id=tonumber(nonce),tonumber(id)
 if not nonce or nonce>2147483647 or not P.allowed(id)then return end
 colors=(colors or P.stock(id)):upper()
 if P.validColors(id,colors)then return nonce,id,colors end
end
function P.message(op,nonce,id,colors)
 colors=colors or P.stock(id)
 assert(P.validColors(id,colors)and nonce>=1 and nonce<=2147483647 and nonce%1==0)
 return ('BASKIN1|%s|%d|%d|%s'):format(op,nonce,id,colors)
end
function P.markerId(name)
 if type(name)~='string'then return end
 local id,colors=name:match('^BA_PlayerSkin_v1_([012])_([%x%-]+)$')
 if not id then id=name:match('^BA_PlayerSkin_v1_([012])$')end
 id=tonumber(id);if not P.allowed(id)then return end;colors=(colors or P.stock(id)):upper()
 if P.validColors(id,colors)then return id,colors end
end
-- Client requests never contain a target player. The RPC's owning controller
-- supplies identity, and stale/replayed requests cannot replace newer choices.
function P.accept(state,nonce,id,now,colors)
 colors=colors or (P.allowed(id) and P.stock(id));if not P.validColors(id,colors)then return false end
 if not P.allowed(id)or type(nonce)~='number'or nonce%1~=0 or nonce<1 or nonce>2147483647 then return false end
 if state.nonce and nonce<=state.nonce then return nonce==state.nonce and id==state.id and colors==state.colors end
 if state.at and now-state.at<.4 then return false end
 state.colors=colors;state.id=id;state.nonce=nonce;state.at=now;return true
end
return P
