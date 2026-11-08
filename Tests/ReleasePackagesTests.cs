using System;using System.IO;using System.Linq;using BeyondModManager;
class ReleasePackagesTests {
 static void Assert(bool ok,string what){if(!ok)throw new Exception(what);Console.WriteLine("PASS "+what);}
 static void Main(string[] args){
  var root=Path.GetFullPath(args[0]);if(Directory.Exists(root))throw new Exception("Fixture must be new");
  var game=Path.Combine(root,"Game");var bin=Path.Combine(game,GameInstallation.BinaryRoot.Replace('/',Path.DirectorySeparatorChar));Directory.CreateDirectory(bin);File.WriteAllText(Path.Combine(bin,"DriveBeyondHorizons-Win64-Shipping.exe"),"fixture");
  var store=new ModStore(game,Path.Combine(root,"Data"),()=>false);
  // First install must work without any other mod or preinstalled runtime.
  var tuning=store.Install(store.PreviewZip(args[1]));Assert(tuning.Id=="beyondtuning"&&RuntimeSupport.Compatible(game),"published Tuning-only package installs with matching runtime");
  Assert(!Directory.Exists(Path.Combine(game,GameInstallation.ModsRoot.Replace('/',Path.DirectorySeparatorChar),"BeyondApocalypse")),"Tuning does not install Apocalypse");
  for(int i=2;i<args.Length;i++){var r=store.Install(store.PreviewZip(args[i]));Assert(r.Managed&&r.Enabled,"published "+r.Name+" installs and enables");}
  var records=store.List().Where(r=>r.Managed).ToArray();Assert(records.Length==3,"all three public mods installed");
  File.WriteAllText(Path.Combine(bin,"ue4ss","UE4SS.dll"),"external incompatible replacement");
  store.Install(store.PreviewZip(args[1]));Assert(RuntimeSupport.Compatible(game),"reinstalling published Tuning repairs runtime changed outside BMM");
  foreach(var r in records){var folder=Path.Combine(game,r.LuaRoots.First().Replace('/',Path.DirectorySeparatorChar));File.WriteAllText(Path.Combine(folder,"user-generated-fixture.dat"),"runtime state");store.Uninstall(r.Id);Assert(!Directory.Exists(folder),"uninstall removes full "+r.Name+" folder including generated state");}
  Assert(RuntimeSupport.Compatible(game),"uninstall keeps shared runtime");
  foreach(var archive in args.Skip(1)){var r=store.Install(store.PreviewZip(archive));var folder=Path.Combine(game,r.LuaRoots.First().Replace('/',Path.DirectorySeparatorChar));Assert(!File.Exists(Path.Combine(folder,"user-generated-fixture.dat")),r.Name+" reinstalls without old generated state");foreach(var f in r.Files.Where(f=>!f.Shared)){var p=Path.Combine(game,f.Path.Replace('/',Path.DirectorySeparatorChar));if(ModStore.HashFile(p)!=f.Hash)throw new Exception("Installed payload mismatch: "+f.Path);}}
  Console.WriteLine("PASS all three clean reinstalls match their recorded payload hashes");Console.WriteLine("Fixture: "+root);
 }
}
