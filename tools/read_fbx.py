from pathlib import Path
import struct,zlib,json
class Reader:
 def __init__(self,p):self.b=Path(p).read_bytes();self.i=23;self.version=self.unpack('I');self.wide=self.version>=7500
 def unpack(self,f):n=struct.calcsize('<'+f);v=struct.unpack_from('<'+f,self.b,self.i);self.i+=n;return v[0]if len(v)==1 else v
 def prop(self):
  t=chr(self.unpack('B'))
  if t in 'YCI FDL'.replace(' ',''):return self.unpack({'Y':'h','C':'?','I':'i','F':'f','D':'d','L':'q'}[t])
  if t in 'SR':
   n=self.unpack('I');v=self.b[self.i:self.i+n];self.i+=n;return v.decode('utf-8',errors='replace')if t=='S'else v
  if t in 'fdilbc':
   n,encoding,size=self.unpack('III');v=self.b[self.i:self.i+size];self.i+=size
   if encoding:v=zlib.decompress(v)
   return list(struct.unpack('<'+str(n)+{'f':'f','d':'d','i':'i','l':'q','b':'b','c':'b'}[t],v))
  raise ValueError(t)
 def node(self):
  end,n,length=self.unpack('QQQ'if self.wide else 'III');count=self.unpack('B')
  if end==0:return None
  name=self.b[self.i:self.i+count].decode();self.i+=count;props=[self.prop()for _ in range(n)];children=[]
  while self.i<end:
   c=self.node()
   if c is None:break
   children.append(c)
  assert self.i==end,(name,self.i,end)
  return {'name':name,'p':props,'c':children}
 def read(self):
  out=[]
  while True:
   n=self.node()
   if n is None:return out
   out.append(n)
def child(n,name):return next((v for v in n['c']if v['name']==name),None)
