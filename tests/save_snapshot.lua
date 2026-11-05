local scripts,dir=assert(arg[1]),assert(arg[2])
local S=dofile(scripts..'/save_snapshot.lua')
local world=string.rep('a',32)
local function key(revision)return world..'-'..revision..'-1' end
local zero=key(string.rep('0',32));local rev=key(string.rep('1',32))
local path=dir..'/state/'..zero
S.commit(path,zero,'first');S.commit(path,zero,'second')
assert(S.read(path)=='second'and S.read(path..'.bak')=='first')
os.remove(path);assert(S.read(path)=='first')
S.commit(path,zero,'recovered');assert(S.read(path)=='recovered')
path=dir..'/state/'..rev
S.commit(path,rev,'immutable');S.commit(path,rev,'immutable')
assert(not pcall(S.commit,path,rev,'replacement')and S.read(path)=='immutable')
return 'Repeatable zero revision, backup recovery and immutable normal revision'
