using System;
using System.Collections.Generic;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Reflection;
using System.Security.Cryptography;
using System.Text;

namespace BeyondModManager {
 public static class RuntimeSupport {
  public const string Profile="ue4ss-8f7b2ca3";
  public const string LoaderHash="e14657eec1c3fb08d1d0e4d5b24f69a9343cd06359e1af27ae6c9c84c5f010cf";
  public const string ProxyHash="0c407a52fd6666a0cea61035878a4f637ea19882b44634e33f4a9a4a45a98ebe";
  public const string BundleHash="622d59fcf5e42ac041c99610f61f066350420ec5605742014413597faef0626a";
  public static bool Compatible(string game) {
   var bin=Path.Combine(game,GameInstallation.BinaryRoot.Replace('/',Path.DirectorySeparatorChar));
   return Matches(Path.Combine(bin,"ue4ss","UE4SS.dll"),LoaderHash)&&Matches(Path.Combine(bin,"dwmapi.dll"),ProxyHash)&&!File.Exists(Path.Combine(bin,"UE4SS.dll"));
  }
  static bool Matches(string path,string hash){return File.Exists(path)&&String.Equals(ModStore.HashFile(path),hash,StringComparison.OrdinalIgnoreCase);}
  public static void ValidateProfile(string profile){if(profile!=null&&!String.Equals(profile,Profile,StringComparison.OrdinalIgnoreCase))throw new InvalidDataException("This mod requires a runtime profile this BMM version does not support: "+profile+". Update BMM before installing it.");}
  internal static Dictionary<string,byte[]> Payload() {
   // Runtime files only come from BMM's pinned embedded bundle, never an arbitrary mod ZIP.
   using(var input=Assembly.GetExecutingAssembly().GetManifestResourceStream("dependency-runtime.zip"))using(var memory=new MemoryStream()){
    if(input==null)throw new InvalidDataException("BMM's runtime support bundle is missing.");input.CopyTo(memory);
    using(var h=SHA256.Create())if(BitConverter.ToString(h.ComputeHash(memory.ToArray())).Replace("-","").ToLowerInvariant()!=BundleHash)throw new InvalidDataException("BMM's runtime support bundle failed verification.");
    memory.Position=0;var files=new Dictionary<string,byte[]>(StringComparer.OrdinalIgnoreCase);
    using(var zip=new ZipArchive(memory,ZipArchiveMode.Read))foreach(var e in zip.Entries)if(e.FullName.StartsWith("runtime/",StringComparison.Ordinal))using(var s=e.Open())using(var bytes=new MemoryStream()){s.CopyTo(bytes);files.Add(GameInstallation.BinaryRoot+"/"+e.FullName.Substring(8),bytes.ToArray());}
    return files;
   }
  }
 }
 public sealed partial class ModStore {
  static bool NeedsRuntime(InstallPlan plan){return plan.RuntimeProfile!=null||plan.LuaRoots.Count>0||plan.Dependencies.Any(x=>Compare.Equals(x,"ue4ss")||Compare.Equals(x,"bpmodloadermod"))||plan.Files.Any(x=>x.Shared||Prefix(x.Path,GameInstallation.PaksRoot+"/LogicMods"));}
  static bool NeedsBlueprint(InstallPlan plan){return plan.Dependencies.Any(x=>Compare.Equals(x,"bpmodloadermod"))||plan.Files.Any(x=>Prefix(x.Path,GameInstallation.PaksRoot+"/LogicMods"));}
  void ValidateRuntimeProfiles(InstallPlan plan) {
   RuntimeSupport.ValidateProfile(plan.RuntimeProfile);
   foreach(var record in Records().Where(x=>x.Enabled&&!SameMod(x.Id,plan.Id)))RuntimeSupport.ValidateProfile(record.RuntimeProfile);
   // Also honor explicit requirements of enabled packages installed outside BMM.
   var mods=Destination(GameInstallation.ModsRoot);if(!Directory.Exists(mods))return;
   foreach(var dir in Directory.EnumerateDirectories(mods)){
    var name=System.IO.Path.GetFileName(dir);if(plan.LuaRoots.Any(x=>Compare.Equals(x.Split('/').Last(),name))||!IsLuaEnabled(name,dir))continue;
    var file=System.IO.Path.Combine(dir,"bmm.json");NoLinks(file);if(!File.Exists(file))continue;
    if(new FileInfo(file).Length>65536)throw new InvalidDataException("Installed mod metadata is too large: "+name);
    var metadata=Json.Deserialize<PackageMetadata>(File.ReadAllText(file));if(metadata!=null)RuntimeSupport.ValidateProfile(metadata.RuntimeProfile);
   }
  }
  void EnsureRuntime(Transaction tx,bool blueprint) {
   var payload=RuntimeSupport.Payload();var records=Records();var support=records.FirstOrDefault(x=>Compare.Equals(x.Id,"bmm-runtime"));
   bool changed=support==null;
   if(support==null)support=new ModRecord{Id="bmm-runtime",Name="UE4SS mod support",Managed=true,Enabled=true,Version=RuntimeSupport.Profile};
   foreach(var pair in payload){
    bool bp=Prefix(pair.Key,GameInstallation.ModsRoot+"/BPModLoaderMod");if(bp&&!blueprint)continue;
    var target=Destination(pair.Key);bool force=Compare.Equals(pair.Key,GameInstallation.BinaryRoot+"/dwmapi.dll")||Compare.Equals(pair.Key,GameInstallation.BinaryRoot+"/ue4ss/UE4SS.dll");
    var hash=HashBytes(pair.Value);
    if(!File.Exists(target)||(force&&!Compare.Equals(HashFile(target),hash))){tx.Write(target,new MemoryStream(pair.Value,false),pair.Value.Length,hash);changed=true;}
    // Existing settings, shared Lua helpers and BP loader configuration stay intact.
    if(!support.Files.Any(f=>Compare.Equals(f.Path,pair.Key))&&(RuntimePath(pair.Key)||bp)){
     support.Files.Add(new ModFile{Path=pair.Key,Hash=HashFile(target),Bytes=new FileInfo(target).Length,Shared=!bp,Preserve=!force});changed=true;
    }else if(force){var f=support.Files.FirstOrDefault(x=>Compare.Equals(x.Path,pair.Key));if(f!=null&&(f.Hash!=hash||f.Bytes!=pair.Value.Length)){f.Hash=hash;f.Bytes=pair.Value.Length;changed=true;}}
   }
   // A legacy root-level DLL can shadow the standard nested loader. Journal its removal.
   var legacy=Destination(GameInstallation.BinaryRoot+"/UE4SS.dll");if(File.Exists(legacy)){tx.Delete(legacy);changed=true;}
   if(blueprint){
    var root=GameInstallation.ModsRoot+"/BPModLoaderMod";
    if(records.Any(r=>!Compare.Equals(r.Id,"bmm-runtime")&&r.LuaRoots.Contains(root,Compare)&&!r.Enabled))throw new InvalidOperationException("Enable BPModLoaderMod before installing this package.");
    if(!support.LuaRoots.Contains(root,Compare)&&!records.Any(r=>!Compare.Equals(r.Id,"bmm-runtime")&&r.LuaRoots.Contains(root,Compare))){support.LuaRoots.Add(root);changed=true;}
    var marker=Destination(root+"/enabled.txt");if(!File.Exists(marker)){tx.Write(marker,new byte[0]);changed=true;}
   }
   if(changed){support.RuntimeProfile=RuntimeSupport.Profile;support.Version=RuntimeSupport.Profile;tx.Write(ManifestPath("bmm-runtime"),Encoding.UTF8.GetBytes(Json.Serialize(support)));}
   if(!RuntimeSupport.Compatible(GamePath))throw new IOException("UE4SS runtime verification failed; installation was rolled back.");
  }
  static string HashBytes(byte[] bytes){using(var h=SHA256.Create())return Hex(h.ComputeHash(bytes));}
  public void RepairRuntime(bool blueprint=false) {
   Ready();using(var gate=Lock()){RecoverPending();ValidateRuntimeProfiles(new InstallPlan());using(var tx=new Transaction(DataPath,GamePath))try{EnsureRuntime(tx,blueprint);tx.Commit();}catch{tx.Rollback();throw;}}
  }
 }
}
