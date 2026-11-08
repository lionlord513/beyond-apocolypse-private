using System;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Text;
using BeyondModManager;

static class RuntimeTests {
 static int count;static string root;
 static void Check(bool condition,string label){count++;if(!condition)throw new Exception(label);}
 static void Write(string file,string value){Directory.CreateDirectory(Path.GetDirectoryName(file));File.WriteAllText(file,value);}
 static void Reject(Action action,string label){try{action();}catch(IOException){count++;return;}catch(InvalidDataException){count++;return;}catch(InvalidOperationException){count++;return;}throw new Exception("Accepted "+label);}
 static string Zip(string name,string metadata=null){var path=Path.Combine(root,name+".zip");using(var z=ZipFile.Open(path,ZipArchiveMode.Create)){
  using(var s=new StreamWriter(z.CreateEntry("BeyondTuning/Scripts/main.lua").Open()))s.Write("fixture "+name);
  using(var s=new StreamWriter(z.CreateEntry("BeyondTuning/Scripts/config.lua").Open()))s.Write("default");
  using(var s=new StreamWriter(z.CreateEntry("bmm.json").Open()))s.Write(metadata??"{\"id\":\"beyondtuning\",\"version\":\"1.2.7\",\"dependencies\":[\"UE4SS\"]}");
 }return path;}
 public static int Run(){root=Path.Combine(Path.GetTempPath(),"BMM-Runtime-"+Guid.NewGuid().ToString("N"));Directory.CreateDirectory(root);
  try{
   var game=Path.Combine(root,"Steam library with spaces","Game");var bin=Path.Combine(game,GameInstallation.BinaryRoot.Replace('/',Path.DirectorySeparatorChar));var mods=Path.Combine(bin,"ue4ss","Mods");
   Write(Path.Combine(bin,"DriveBeyondHorizons-Win64-Shipping.exe"),"fixture");var store=new ModStore(game,Path.Combine(root,"Data"),()=>false);
   var first=Zip("tuning-v1");var second=Zip("tuning-v2");
   store.Install(store.PreviewZip(first));Check(RuntimeSupport.Compatible(game),"Tuning-only clean installation missing compatible runtime");
   Check(!Directory.Exists(Path.Combine(mods,"BeyondApocalypse")),"Tuning installed Apocalypse");
   var loader=Path.Combine(bin,"ue4ss","UE4SS.dll");var proxy=Path.Combine(bin,"dwmapi.dll");var settings=Path.Combine(bin,"ue4ss","UE4SS-settings.ini");var module=Path.Combine(mods,"BeyondTuning");
   Write(settings,"user engine preferences");Write(Path.Combine(module,"Scripts/config.lua"),"my tuning");Write(Path.Combine(module,"state/generated.json"),"generated state");
   Write(loader,"incompatible UE4SS with the same 3.0.1 label");Write(proxy,"mismatched proxy");
   var preview=store.PreviewZip(second);Check(preview.MissingDependencies.Contains("UE4SS"),"Presence accepted as compatibility");store.Install(preview);
   Check(RuntimeSupport.Compatible(game),"Update did not repair incompatible pair");Check(File.ReadAllText(settings)=="user engine preferences"&&File.ReadAllText(Path.Combine(module,"Scripts/config.lua"))=="my tuning","Update overwrote settings");
   Check(Directory.GetFiles(store.DataPath,"*.bak",SearchOption.AllDirectories).Any(p=>new FileInfo(p).Length<100&&File.ReadAllText(p)=="incompatible UE4SS with the same 3.0.1 label"),"Runtime backup missing");
   var stamp=File.GetLastWriteTimeUtc(loader);store.Install(store.PreviewZip(second));Check(stamp==File.GetLastWriteTimeUtc(loader),"Correct runtime rewritten unnecessarily");
   // Changes made after preview must still be detected at commit time.
   preview=store.PreviewZip(second);File.Delete(proxy);store.Install(preview);Check(RuntimeSupport.Compatible(game),"Deleted proxy after preview not repaired");
   preview=store.PreviewZip(second);Write(loader,"changed after preview");store.Install(preview);Check(RuntimeSupport.Compatible(game),"Changed loader after preview not repaired");
   Write(Path.Combine(bin,"UE4SS.dll"),"legacy shadow DLL");store.Install(store.PreviewZip(second));Check(!File.Exists(Path.Combine(bin,"UE4SS.dll"))&&RuntimeSupport.Compatible(game),"Legacy shadow DLL retained");
   // A late failure must undo both runtime replacement and the mod update.
   Write(loader,"old loader before rollback");Write(proxy,"old proxy before rollback");var list=Path.Combine(mods,"mods.txt");
   using(var held=new FileStream(list,FileMode.Open,FileAccess.Read,FileShare.Read))Reject(()=>store.Install(store.PreviewZip(first)),"locked load order");
   Check(File.ReadAllText(loader)=="old loader before rollback"&&File.ReadAllText(proxy)=="old proxy before rollback","Runtime rollback incomplete");Check(File.ReadAllText(Path.Combine(module,"Scripts/main.lua"))=="fixture tuning-v2","Payload rollback incomplete");
   using(var held=new FileStream(loader,FileMode.Open,FileAccess.Read,FileShare.Read))Reject(()=>store.Install(store.PreviewZip(first)),"locked loader");
   Check(File.ReadAllText(proxy)=="old proxy before rollback","Locked loader did not roll back proxy");store.Install(store.PreviewZip(first));
   // Known unsupported requirements are refused before mutating the installed pair.
   var conflict=Zip("future", "{\"id\":\"beyondtuning\",\"runtimeProfile\":\"future-runtime\"}");Reject(()=>store.PreviewZip(conflict),"unsupported runtime profile");
   Write(Path.Combine(mods,"Other","bmm.json"),"{\"runtimeProfile\":\"different-runtime\"}");Write(Path.Combine(mods,"Other","enabled.txt"),"");
   Write(loader,"leave this conflict alone");Reject(()=>store.Install(store.PreviewZip(first)),"installed runtime conflict");Check(File.ReadAllText(loader)=="leave this conflict alone","Conflict changed runtime");
   File.Delete(Path.Combine(mods,"Other","enabled.txt"));store.Install(store.PreviewZip(first));
   var running=new ModStore(game,Path.Combine(root,"Data"),()=>true);Reject(()=>running.Install(store.PreviewZip(first)),"running game");
   // Complete uninstall, recovery, and fresh reinstall, including generated DLLs.
   Write(Path.Combine(module,"generated/extra.dll"),"generated plugin");Write(Path.Combine(module,"empty/keep"),"");File.Delete(Path.Combine(module,"empty/keep"));
   Write(Path.Combine(mods,"BeyondApocolypseDevMenu/Scripts/attach.lua"),"private companion");Write(Path.Combine(game,"Saved/SaveGames/world.sav"),"game world");
   using(var held=new FileStream(list,FileMode.Open,FileAccess.Read,FileShare.Read))Reject(()=>store.Uninstall("beyondtuning"),"late uninstall failure");Check(File.Exists(Path.Combine(module,"generated/extra.dll")),"Failed uninstall did not restore complete folder");
   var result=store.Uninstall("beyondtuning");Check(!Directory.Exists(module),"Uninstall left complete mod folder behind");
   Check(Directory.GetFiles(result.BackupPath,"extra.dll",SearchOption.AllDirectories).Length==1,"Recovery lacks generated file");
   Check(RuntimeSupport.Compatible(game)&&File.Exists(Path.Combine(mods,"BeyondApocolypseDevMenu/Scripts/attach.lua"))&&File.Exists(Path.Combine(game,"Saved/SaveGames/world.sav")),"Uninstall touched unrelated files");
   store.Install(store.PreviewZip(first));Check(File.ReadAllText(Path.Combine(module,"Scripts/config.lua"))=="default"&&!File.Exists(Path.Combine(module,"state/generated.json")),"Reinstall restored old data");
   store.SetEnabled("beyondtuning",false);result=store.Uninstall("beyondtuning");store.Install(store.PreviewZip(first));Check(!File.Exists(Path.Combine(module,"generated/extra.dll")),"Disabled uninstall resurrected generated files");
   // Upgrade from old BMM uninstall records without resurrecting their retained state.
   var old=store.List().First(r=>r.Id=="beyondtuning");Write(Path.Combine(module,"state/old-manager.json"),"old retained data");Write(Path.Combine(module,"Scripts/config.lua"),"old retained config");
   File.Delete(Path.Combine(module,"Scripts/main.lua"));File.Delete(Path.Combine(module,"enabled.txt"));
   Write(Path.Combine(store.DataPath,"removed/beyondtuning.json"),new System.Web.Script.Serialization.JavaScriptSerializer().Serialize(old));File.Delete(Path.Combine(store.DataPath,"manifests/beyondtuning.json"));
   store.Install(store.PreviewZip(first));Check(File.ReadAllText(Path.Combine(module,"Scripts/config.lua"))=="default"&&!File.Exists(Path.Combine(module,"state/old-manager.json")),"Old manager uninstall tombstone restored stale settings");
   Reject(()=>store.Uninstall("bmm-runtime"),"shared runtime uninstall");
   Console.WriteLine("PASS "+count+" runtime repair, conflict, rollback, clean uninstall and reinstall checks.");return count;
  }finally{if(root.StartsWith(Path.GetTempPath(),StringComparison.OrdinalIgnoreCase)&&Path.GetFileName(root).StartsWith("BMM-Runtime-",StringComparison.Ordinal))Directory.Delete(root,true);}
 }
}
