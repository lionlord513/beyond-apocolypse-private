local P={prefix='BASKIN1',kind='BAModelSelector',marker='BA_PlayerSkin_v1_',catalog={
 {id=0,name='Default game appearance',description='Your original character and clothing.',portrait='default-face.png',preview='default-preview.png'},
 {id=1,name='SciFi Soldier',description='Armoured soldier. Original movement and weapon handling.',portrait='soldier-face.png',preview='soldier-preview.png'},
}}
function P.allowed(id)return type(id)=='number'and(id==0 or id==1)end
function P.parse(message,op)
 if type(message)~='string'or #message>64 then return end
 local nonce,id=message:match('^BASKIN1|'..op..'|([1-9]%d*)|([01])$');nonce=tonumber(nonce);id=tonumber(id)
 if not nonce or nonce>2147483647 or not P.allowed(id)then return end
 return nonce,id
end
function P.message(op,nonce,id)assert(P.allowed(id)and nonce>=1 and nonce<=2147483647 and nonce%1==0);return ('BASKIN1|%s|%d|%d'):format(op,nonce,id)end
function P.markerId(name)if type(name)~='string'then return end;return tonumber(name:match('^BA_PlayerSkin_v1_([01])$'))end
-- Client requests never contain a target player. The RPC's owning controller
-- supplies identity, and stale/replayed requests cannot replace newer choices.
function P.accept(state,nonce,id,now)
 if not P.allowed(id)or type(nonce)~='number'or nonce%1~=0 or nonce<1 or nonce>2147483647 then return false end
 if state.nonce and nonce<=state.nonce then return nonce==state.nonce and id==state.id end
 if state.at and now-state.at<.4 then return false end
 state.id=id;state.nonce=nonce;state.at=now;return true
end
return P
