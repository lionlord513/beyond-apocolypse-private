-- Single-cell inventory protocol. Slots are zero-based to match native hotbar slots.
local P={prefix='BAINV2|',tiers={BackpackBase_C={hotbar=2,cells=6,name='Small backpack'},BackpackMedium_C={hotbar=4,cells=12,name='Medium backpack'},BackpackLarge_C={hotbar=6,cells=18,name='Large backpack'}}}
function P.identity(g)
 if not g or(g.A==0 and g.B==0 and g.C==0 and g.D==0)then return '-'end
 return ('%08x:%08x:%08x:%08x'):format(g.A&0xffffffff,g.B&0xffffffff,g.C&0xffffffff,g.D&0xffffffff)
end
function P.slot(n,capacity)return type(n)=='number'and n%1==0 and n>=0 and n<capacity end
function P.token(s)return s=='-'or(type(s)=='string'and #s==35 and s:match('^%x%x%x%x%x%x%x%x:%x%x%x%x%x%x%x%x:%x%x%x%x%x%x%x%x:%x%x%x%x%x%x%x%x$')~=nil)end
function P.actor(s)
 local n=type(s)=='string'and s:match('^n:(%d+)$');n=n and tonumber(n)
 return n~=nil and n>0 and n<=2147483647
end
function P.bag(s)return P.actor(s)or(type(s)=='string'and P.tiers[s:match('^w:(%w+_C)$')]~=nil)end
function P.encode(r)return P.prefix..table.concat({r.seq,r.bag,r.op,r.from,r.to,r.source,r.target},'|')end
function P.decode(s)
 if type(s)~='string'or #s>200 then return end
 local seq,bag,op,a,b,source,target=s:match('^BAINV2|(%d+)|([^|]+)|(%a+)|(%-?%d+)|(%-?%d+)|([^|]+)|([^|]+)$')
 seq=tonumber(seq);if not seq or seq<1 or seq>2147483647 or not P.bag(bag)or not P.token(target)then return end
 if op~='move'and op~='put'and op~='take'and op~='unequip'and op~='store'and op~='drop'and op~='drophand'and op~='attach'and op~='detach'then return end
 if op=='put'or op=='store'or op=='drophand'then if not P.actor(source)then return end elseif not P.token(source)then return end
 return {seq=seq,bag=bag,op=op,from=tonumber(a),to=tonumber(b),source=source,target=target}
end
function P.validate(r,capacity,at,held)
 if r.op=='unequip'then return held=='-', 'Empty your hands first' end
 if r.op=='attach'then
  return P.slot(r.from,capacity)and P.slot(r.to,capacity)and r.from~=r.to and r.source~='-'and r.target~='-'and at(r.from)==r.source and at(r.to)==r.target,'Inventory changed; try again'
 elseif r.op=='move'then
  if not P.slot(r.from,capacity)or not P.slot(r.to,capacity)or r.from==r.to then return false,'Invalid slot' end
  return r.source~='-'and at(r.from)==r.source and at(r.to)==r.target,'Inventory changed; try again'
 elseif r.op=='store'then
  return r.from==-1 and P.slot(r.to,capacity)and r.source~='-'and at(r.to)=='-'and r.target=='-','Storage cell changed or full'
 elseif r.op=='put'then
  return P.slot(r.to,capacity)and held~='-'and held==r.source and at(r.to)=='-'and r.target=='-','Use an empty cell and hold an item'
 elseif r.op=='drophand'then
  return r.from==-1 and r.to==-1 and held~='-'and held==r.source,'Held item changed'
 elseif r.op=='drop'or r.op=='detach'then
  return P.slot(r.from,capacity)and r.to==-1 and r.source~='-'and at(r.from)==r.source,'Storage cell changed'
 elseif r.op=='take'then
  return P.slot(r.from,capacity)and r.source~='-'and at(r.from)==r.source and held=='-','Empty your hands first'
 end
 return false,'Invalid operation'
end
return P
