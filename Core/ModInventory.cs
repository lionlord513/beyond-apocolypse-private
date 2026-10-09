using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using System.Web.Script.Serialization;
using Microsoft.Win32;

namespace BeyondModManager {
 public sealed class GameStatus {
  public string Path {get;set;} public bool HasUE4SS {get;set;} public bool HasBPModLoader {get;set;} public bool GameRunning {get;set;}
 }
 public static class GameInstallation {
  public const string BinaryRoot="DriveBeyondHorizons/Binaries/Win64";
  public const string ModsRoot=BinaryRoot+"/ue4ss/Mods";
  public const string PaksRoot="DriveBeyondHorizons/Content/Paks";
  public static bool IsGame(string path) {return !String.IsNullOrWhiteSpace(path)&&File.Exists(System.IO.Path.Combine(path,BinaryRoot.Replace('/',System.IO.Path.DirectorySeparatorChar),"DriveBeyondHorizons-Win64-Shipping.exe"));}
  public static bool Running() {return Process.GetProcessesByName("DriveBeyondHorizons-Win64-Shipping").Length!=0;}
  public static string Find() {
   var roots=new List<string>();
   using(var key=Registry.CurrentUser.OpenSubKey(@"Software\Valve\Steam")){if(key!=null){var value=key.GetValue("SteamPath") as string;if(!String.IsNullOrWhiteSpace(value))roots.Add(value);}}
   roots.Add(System.IO.Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86),"Steam"));
   foreach(var root in roots.ToArray())try {var file=System.IO.Path.Combine(root,"steamapps","libraryfolders.vdf");if(File.Exists(file))foreach(Match m in Regex.Matches(File.ReadAllText(file),"\"path\"\\s+\"([^\"]+)\""))roots.Add(m.Groups[1].Value.Replace("\\\\","\\"));}catch(IOException){}catch(UnauthorizedAccessException){}
   return roots.Distinct(StringComparer.OrdinalIgnoreCase).Select(x=>System.IO.Path.Combine(x,"steamapps","common","Drive Beyond Horizons")).FirstOrDefault(IsGame);
  }
  public static GameStatus Inspect(string path) {
   if(!IsGame(path))throw new DirectoryNotFoundException("Choose the main Drive Beyond Horizons game folder.");
   var bin=System.IO.Path.Combine(path,BinaryRoot.Replace('/',System.IO.Path.DirectorySeparatorChar));
   var loader=File.Exists(System.IO.Path.Combine(bin,"ue4ss","UE4SS.dll"))||File.Exists(System.IO.Path.Combine(bin,"UE4SS.dll"));
   var bp=System.IO.Path.Combine(bin,"ue4ss","Mods","BPModLoaderMod");
   var enabled=File.Exists(System.IO.Path.Combine(bp,"enabled.txt"));
   var list=System.IO.Path.Combine(bin,"ue4ss","Mods","mods.txt");
   if(!enabled&&File.Exists(list))enabled=Regex.IsMatch(File.ReadAllText(list),@"(?im)^\s*BPModLoaderMod\s*:\s*1\s*(?:;.*)?$");
   return new GameStatus{Path=System.IO.Path.GetFullPath(path),HasUE4SS=loader,HasBPModLoader=File.Exists(System.IO.Path.Combine(bp,"Scripts","main.lua"))&&enabled,GameRunning=Running()};
  }
 }
 public sealed class PackageMetadata {
  public string Id {get;set;} public string Name {get;set;} public string Version {get;set;} public string Channel {get;set;}
  public string Description {get;set;} public string Changelog {get;set;}
  public string[] Dependencies {get;set;} public string[] LoadAfter {get;set;} public string[] Preserve {get;set;} public UpdateSource Update {get;set;}
 }
 public sealed class ModFile {
  public string Path {get;set;} public string Hash {get;set;} public long Bytes {get;set;} public bool Preserve {get;set;} public bool Shared {get;set;}
  [ScriptIgnore] public string Source {get;set;}
 }
 public sealed class InstallPlan {
  public string Id {get;set;} public string Name {get;set;} public string Version {get;set;} public string Channel {get;set;} public string Kind {get;set;}
  public string Description {get;set;} public string Changelog {get;set;} public string Readme {get;set;}
  public int FileCount {get{return Files.Count;}} public long TotalBytes {get{return Files.Sum(x=>x.Bytes);}}
  public List<string> Warnings {get;set;} public List<string> MissingDependencies {get;set;}
  public List<ModFile> Files {get;set;} public List<string> LuaRoots {get;set;}
  public string[] Dependencies {get;set;} public string[] LoadAfter {get;set;} public UpdateSource Update {get;set;}
  public string SourceZip {get;set;} public string ArchiveHash {get;set;}
  public bool ExistingUnmanaged {get;set;} public bool CanAdoptWithoutChanges {get;set;}
  public InstallPlan(){Warnings=new List<string>();MissingDependencies=new List<string>();Files=new List<ModFile>();LuaRoots=new List<string>();Dependencies=new string[0];LoadAfter=new string[0];}
 }
 public sealed class ModRecord {
  public int Schema {get;set;} public string Id {get;set;} public string Name {get;set;} public string Version {get;set;} public string Channel {get;set;} public string Kind {get;set;}
  public string Description {get;set;} public string Changelog {get;set;} public string Readme {get;set;}
  public bool Enabled {get;set;} public bool Managed {get;set;} public string InstalledUtc {get;set;} public string ArchiveHash {get;set;}
  public List<ModFile> Files {get;set;} public List<string> LuaRoots {get;set;} public string[] Dependencies {get;set;} public string[] LoadAfter {get;set;}
  public UpdateSource Update {get;set;}
  public ModRecord(){Schema=1;Files=new List<ModFile>();LuaRoots=new List<string>();Dependencies=new string[0];LoadAfter=new string[0];}
 }
 public sealed class OperationResult {
  public string BackupPath {get;set;} public List<string> PreservedFiles {get;set;}
  public OperationResult(){PreservedFiles=new List<string>();}
 }
 public sealed class ModStore {
  const string BeyondRoot=GameInstallation.ModsRoot+"/BeyondApocalypse", LegacyRoot=GameInstallation.ModsRoot+"/BasicM4";
  const string LegacyShimMarker="-- BeyondApocalypse legacy migration shim v1";
  const long MaxBytes=2L*1024*1024*1024; const long MaxEntry=512L*1024*1024; const int MaxEntries=20000;
  static readonly StringComparer Compare=StringComparer.OrdinalIgnoreCase;
  static readonly JavaScriptSerializer Json=new JavaScriptSerializer{MaxJsonLength=32*1024*1024,RecursionLimit=50};
  public readonly string GamePath; public readonly string DataPath;
  readonly Func<bool> running;
  public ModStore(string gamePath,string dataRoot):this(gamePath,dataRoot,GameInstallation.Running){}
  public ModStore(string gamePath,string dataRoot,Func<bool> isRunning) {
   if(!GameInstallation.IsGame(gamePath))throw new DirectoryNotFoundException("Choose the main Drive Beyond Horizons game folder.");
   GamePath=System.IO.Path.GetFullPath(gamePath).TrimEnd('\\','/');
   var root=String.IsNullOrEmpty(dataRoot)?System.IO.Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"BeyondModManager"):dataRoot;
   DataPath=System.IO.Path.Combine(System.IO.Path.GetFullPath(root),"Installations",HashText(GamePath.ToLowerInvariant()).Substring(0,24));running=isRunning;
   NoLinks(GamePath);NoLinks(DataPath);
  }
  public static string HashFile(string path){using(var h=SHA256.Create())using(var f=File.OpenRead(path))return Hex(h.ComputeHash(f));}
  static string HashText(string text){using(var h=SHA256.Create())return Hex(h.ComputeHash(Encoding.UTF8.GetBytes(text)));}
  static string Hex(byte[] bytes){return BitConverter.ToString(bytes).Replace("-","").ToLowerInvariant();}
  public static bool IsBeyondIdentity(string value){return Compare.Equals(value,"beyondapocalypse")||Compare.Equals(value,"basicm4");}
  static bool SameMod(string a,string b){return Compare.Equals(a,b)||(IsBeyondIdentity(a)&&IsBeyondIdentity(b));}
  static string RenamedPath(string path){return Compare.Equals(path,LegacyRoot)?BeyondRoot:Prefix(path,LegacyRoot)?BeyondRoot+path.Substring(LegacyRoot.Length):path;}
  static bool IsLegacyShim(string file){if(!File.Exists(file)||new FileInfo(file).Length>16384)return false;using(var reader=new StreamReader(file))return (reader.ReadLine()??"").Trim()==LegacyShimMarker;}
  void CheckBeyondRoots(){var old=Destination(LegacyRoot+"/Scripts/main.lua");if(File.Exists(old)&&File.Exists(Destination(BeyondRoot+"/Scripts/main.lua"))&&!IsLegacyShim(old))throw new IOException("Two complete Beyond Apocalypse installations exist. Back up and remove the duplicate before importing; BMM will not choose between them.");}
  static string Id(string value){if(value==null||!Regex.IsMatch(value,@"^[A-Za-z0-9][A-Za-z0-9._-]{0,79}$"))throw new InvalidDataException("The mod identifier is invalid.");return value.ToLowerInvariant();}
  static string DerivedId(string name){var slug=Regex.Replace(name,@"[^A-Za-z0-9._-]+","-").Trim('-','.','_');if(slug.Length==0)slug="mod";if(slug.Length>60)slug=slug.Substring(0,60);if(!Compare.Equals(slug,name))slug+="-"+HashText(name.ToLowerInvariant()).Substring(0,8);return Id(slug);}
  static string Canonical(string value) {
   if(String.IsNullOrWhiteSpace(value))throw new InvalidDataException("The archive contains an empty path.");
   value=value.Replace('\\','/');if(value.StartsWith("/")||value.Contains(":"))throw new InvalidDataException("Absolute archive paths are not supported.");
   var parts=value.Split('/');
   foreach(var p in parts)if(p.Length==0||p=="."||p==".."||p.EndsWith(".")||p.EndsWith(" ")||p.IndexOfAny(new[]{'<','>','"','|','?','*','\0'})>=0||p.Any(c=>c<32)||Regex.IsMatch(p,@"^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)",RegexOptions.IgnoreCase))throw new InvalidDataException("The archive contains an unsafe path.");
   return String.Join("/",parts);
  }
  static string Under(string root,string relative) {
   relative=Canonical(relative);var path=System.IO.Path.GetFullPath(System.IO.Path.Combine(root,relative.Replace('/',System.IO.Path.DirectorySeparatorChar)));
   if(!path.StartsWith(root.TrimEnd('\\','/')+System.IO.Path.DirectorySeparatorChar,StringComparison.OrdinalIgnoreCase))throw new InvalidDataException("A file would leave its destination folder.");
   NoLinks(path);return path;
  }
  static void NoLinks(string path) {
   for(var p=System.IO.Path.GetFullPath(path);!String.IsNullOrEmpty(p);p=System.IO.Path.GetDirectoryName(p))
    if((File.Exists(p)||Directory.Exists(p))&&(File.GetAttributes(p)&FileAttributes.ReparsePoint)!=0)throw new IOException("Linked folders/files are not supported: "+p);
  }
  static void NoTreeLinks(string root){NoLinks(root);if(!Directory.Exists(root))return;foreach(var p in Directory.EnumerateFileSystemEntries(root)){NoLinks(p);if(Directory.Exists(p))NoTreeLinks(p);}}
  string Destination(string relative){return Under(GamePath,relative);}
  string ManifestPath(string id){return Under(DataPath,"manifests/"+Id(id)+".json");}
  string RemovedPath(string id){return Under(DataPath,"removed/"+Id(id)+".json");}
  // Beside the game, outside every loader path, so folder moves remain atomic
  // even when Steam and LocalAppData are on different drives.
  string DisabledPath(string id,string relative){return Under(GamePath,".bmm-disabled/"+Id(id)+"/"+Canonical(relative));}
  static bool Prefix(string value,string prefix){return value.StartsWith(prefix.TrimEnd('/')+"/",StringComparison.OrdinalIgnoreCase);}
  static bool RuntimePath(string path){return Compare.Equals(path,GameInstallation.BinaryRoot+"/dwmapi.dll")||Compare.Equals(path,GameInstallation.BinaryRoot+"/ue4ss/UE4SS.dll")||Compare.Equals(path,GameInstallation.BinaryRoot+"/ue4ss/UE4SS-settings.ini")||Prefix(path,GameInstallation.ModsRoot+"/shared");}
  static bool ManagedPath(string path){return Prefix(path,GameInstallation.ModsRoot)&&!Compare.Equals(path,GameInstallation.ModsRoot+"/mods.txt")||Prefix(path,GameInstallation.PaksRoot+"/LogicMods")||Prefix(path,GameInstallation.PaksRoot+"/~mods")||RuntimePath(path);}
  static bool UserData(string path) {
   var parts=path.Split('/');var file=parts.Last().ToLowerInvariant();
   return parts.Any(p=>Regex.IsMatch(p,@"^(state|saves?|userdata|user-settings|profiles?|logs?|backups?)$",RegexOptions.IgnoreCase))||Regex.IsMatch(file,@"^(user.*\.(ini|json|cfg)|config(?:\..+)?|settings\.(ini|json|cfg))$",RegexOptions.IgnoreCase);
  }
  static bool Executable(string path){return new[]{".exe",".com",".bat",".cmd",".ps1",".vbs",".wsf",".msi",".lnk"}.Contains(System.IO.Path.GetExtension(path),Compare);}
  static string MapRuntime(string source) {
   var x=source.Replace('\\','/');var marker=GameInstallation.BinaryRoot+"/";
   var at=x.IndexOf(marker,StringComparison.OrdinalIgnoreCase);if(at>=0){var p=x.Substring(at);if(RuntimePath(p))return p;}
   at=x.IndexOf("runtime/",StringComparison.OrdinalIgnoreCase);if(at>=0){var p=GameInstallation.BinaryRoot+"/"+x.Substring(at+8);if(RuntimePath(p))return p;}
   return null;
  }
  public InstallPlan PreviewZip(string zipPath) {
   if(!File.Exists(zipPath))throw new FileNotFoundException("Choose a ZIP mod package.",zipPath);
   var plan=new InstallPlan{SourceZip=System.IO.Path.GetFullPath(zipPath),ArchiveHash=HashFile(zipPath)};
   var files=new Dictionary<string,ZipArchiveEntry>(Compare);var destinations=new HashSet<string>(Compare);long bytes=0;
   using(var archive=ZipFile.OpenRead(zipPath)) {
    if(archive.Entries.Count>MaxEntries)throw new InvalidDataException("The archive contains too many entries.");
    foreach(var entry in archive.Entries){var raw=entry.FullName.Replace('\\','/');var unix=(entry.ExternalAttributes>>16)&0xF000;
     if(unix==0xA000||(entry.ExternalAttributes&0x400)!=0)throw new InvalidDataException("Archive links are not supported.");
     if(raw.EndsWith("/")){Canonical(raw.TrimEnd('/'));continue;}var source=Canonical(raw);
     if(files.ContainsKey(source))throw new InvalidDataException("Duplicate archive paths are not supported.");
     if(entry.Length<0||entry.Length>MaxEntry||(bytes+=entry.Length)>MaxBytes||entry.Length>1024*1024&&entry.CompressedLength>0&&entry.Length/entry.CompressedLength>1000)throw new InvalidDataException("The archive exceeds safe extraction limits.");
     files.Add(source,entry);
    }
    var metadataFiles=files.Keys.Where(x=>Compare.Equals(x,"bmm.json")||x.EndsWith("/bmm.json",StringComparison.OrdinalIgnoreCase)).ToArray();
    if(metadataFiles.Length>1)throw new InvalidDataException("Only one bmm.json package manifest is supported.");
    var meta=new PackageMetadata();
    if(metadataFiles.Length==1){var entry=files[metadataFiles[0]];if(entry.Length>64*1024)throw new InvalidDataException("Package metadata is too large.");using(var r=new StreamReader(entry.Open()))meta=Json.Deserialize<PackageMetadata>(r.ReadToEnd())??new PackageMetadata();}
    var lua=new Dictionary<string,string>(Compare);
    foreach(var name in files.Keys.Where(x=>x.EndsWith("/Scripts/main.lua",StringComparison.OrdinalIgnoreCase))) {
     var source=name.Substring(0,name.Length-"/Scripts/main.lua".Length);var folder=source.Split('/').Last();
     if(Compare.Equals(folder,"shared"))continue;Canonical(folder);
     if(lua.Values.Contains(folder,Compare))throw new InvalidDataException("The package repeats a Lua mod folder.");lua.Add(source,folder);plan.LuaRoots.Add(GameInstallation.ModsRoot+"/"+folder);
    }
    if(files.ContainsKey("Scripts/main.lua"))throw new InvalidDataException("Place Scripts inside a named mod folder before importing.");
    if(lua.Keys.Any(a=>lua.Keys.Any(b=>!Compare.Equals(a,b)&&Prefix(a,b))))throw new InvalidDataException("Nested Lua mod folders are ambiguous. Import their separate mod folders instead.");
    if(IsBeyondIdentity(meta.Id)||lua.Values.Any(IsBeyondIdentity)){
     var beyondSources=lua.Where(x=>IsBeyondIdentity(meta.Id)||IsBeyondIdentity(x.Value)).Select(x=>x.Key).ToArray();
     foreach(var source in files.Keys){var parts=source.Split('/');bool companion=parts.Any(part=>Compare.Equals(part,"BeyondApocolypseDevMenu")||Compare.Equals(part,"BeyondApocalypseDevMenu"));bool embedded=beyondSources.Any(folder=>Prefix(source,folder+"/Scripts/devmenu")||Compare.Equals(source,folder+"/Scripts/devmenu")||Compare.Equals(source,folder+"/Scripts/attach.lua"));
      if(companion||embedded)throw new InvalidDataException("This Beyond Apocalypse package contains private companion files. Use the public gameplay package; BMM will not install or restore a personal dev menu from it.");
     }
    }
    if(lua.Values.Contains("BeyondApocalypse",Compare)&&lua.Values.Contains("BasicM4",Compare)){
     var legacy=lua.First(x=>Compare.Equals(x.Value,"BasicM4")).Key;var entry=files[legacy+"/Scripts/main.lua"];string first;
     using(var reader=new StreamReader(entry.Open()))first=reader.ReadLine();
     if(entry.Length>16384||(first??"").Trim()!=LegacyShimMarker||files.Keys.Where(x=>Prefix(x,legacy)).Any(x=>!Compare.Equals(x,legacy+"/Scripts/main.lua")&&!Compare.Equals(x,legacy+"/Scripts/release.lua")))throw new InvalidDataException("The archive contains two complete Beyond Apocalypse installations.");
     lua.Remove(legacy);plan.LuaRoots.RemoveAll(x=>Compare.Equals(x,LegacyRoot));plan.Warnings.Add("Legacy migration stubs are omitted; BMM manages one Beyond Apocalypse installation.");
    }
    var pakNames=new List<string>();int skipped=0;
    foreach(var pair in files) {
     string target=null;bool shared=false;var source=pair.Key;
     foreach(var module in lua)if(Prefix(source,module.Key)){target=GameInstallation.ModsRoot+"/"+module.Value+source.Substring(module.Key.Length);break;}
     if(target==null){target=MapRuntime(source);shared=target!=null;}
     if(target==null){
      var i=source.IndexOf(GameInstallation.PaksRoot+"/",StringComparison.OrdinalIgnoreCase);
      if(i>=0){var p=source.Substring(i);if(Prefix(p,GameInstallation.PaksRoot+"/LogicMods")||Prefix(p,GameInstallation.PaksRoot+"/~mods"))target=p;}
      if(target==null&&Prefix(source,"LogicMods"))target=GameInstallation.PaksRoot+"/"+source;
      if(target==null&&Prefix(source,"~mods"))target=GameInstallation.PaksRoot+"/"+source;
      if(target==null)foreach(var folder in new[]{"LogicMods","~mods"}){var marker="/"+folder+"/";var found=source.IndexOf(marker,StringComparison.OrdinalIgnoreCase);if(found>=0){target=GameInstallation.PaksRoot+source.Substring(found);break;}}
      if(target==null&&source.IndexOf('/')<0&&Regex.IsMatch(source,@"^ZodMenu\.(pak|utoc|ucas|sig)$",RegexOptions.IgnoreCase))target=GameInstallation.PaksRoot+"/LogicMods/"+source;
     }
     if(target==null){skipped++;continue;}target=Canonical(target);
     if(!ManagedPath(target)||Executable(target))throw new InvalidDataException("Unsupported executable or destination in package: "+source);
     if(Prefix(target,GameInstallation.PaksRoot)){
      if(!new[]{".pak",".utoc",".ucas",".sig"}.Contains(System.IO.Path.GetExtension(target),Compare))throw new InvalidDataException("Only Unreal package files belong in the mod package directory.");
      if(target.EndsWith(".pak",StringComparison.OrdinalIgnoreCase))pakNames.Add(System.IO.Path.GetFileNameWithoutExtension(target));
     }
     if(!destinations.Add(target))throw new InvalidDataException("Multiple files map to the same game path.");
     string hash;using(var h=SHA256.Create())using(var s=pair.Value.Open())hash=Hex(h.ComputeHash(s));
     var preserve=!Prefix(target,GameInstallation.PaksRoot)&&(UserData(target)||(meta.Preserve??new string[0]).Any(p=>Compare.Equals(target,Canonical(p))||Prefix(target,Canonical(p))));
     plan.Files.Add(new ModFile{Path=target,Source=source,Hash=hash,Bytes=pair.Value.Length,Preserve=preserve,Shared=shared});
    }
    if(plan.LuaRoots.Count==0&&pakNames.Count==0&&!plan.Files.Any(x=>Compare.Equals(x.Path,GameInstallation.BinaryRoot+"/ue4ss/UE4SS.dll")))throw new InvalidDataException("No supported mod was found. Lua mods need a named folder containing Scripts/main.lua; package mods need Content/Paks/LogicMods or Content/Paks/~mods folders.");
    foreach(var f in plan.Files.Where(x=>Prefix(x.Path,GameInstallation.PaksRoot))){var ext=System.IO.Path.GetExtension(f.Path);var stem=f.Path.Substring(0,f.Path.Length-ext.Length);if(!destinations.Contains(stem+".pak"))throw new InvalidDataException("A package companion is missing its .pak file.");if((ext.Equals(".utoc",StringComparison.OrdinalIgnoreCase)||ext.Equals(".ucas",StringComparison.OrdinalIgnoreCase))&&(!destinations.Contains(stem+".utoc")||!destinations.Contains(stem+".ucas")))throw new InvalidDataException("The .utoc and .ucas files must be installed together.");}
    var primary=plan.LuaRoots.Select(x=>x.Split('/').Last()).FirstOrDefault()??pakNames.FirstOrDefault()??"bmm-runtime";
    if(plan.LuaRoots.Any(x=>IsBeyondIdentity(x.Split('/').Last())))primary=plan.LuaRoots.Any(x=>Compare.Equals(x,BeyondRoot))?"BeyondApocalypse":"BasicM4";
    plan.Id=IsBeyondIdentity(primary)?"beyondapocalypse":meta.Id==null?DerivedId(primary):Id(meta.Id);plan.Name=IsBeyondIdentity(primary)?"Beyond Apocalypse":meta.Name??primary;plan.Version=meta.Version??"Imported";
    // Gameplay journals need this directory before the first custom purchase.
    // Historical launcher archives omitted it because their installer made it.
    if(IsBeyondIdentity(primary))foreach(var modRoot in plan.LuaRoots.Where(x=>IsBeyondIdentity(x.Split('/').Last()))){var keeper=modRoot+"/state/KEEP THIS FOLDER.txt";if(!plan.Files.Any(x=>Compare.Equals(x.Path,keeper)))plan.Files.Add(new ModFile{Path=keeper,Hash=HashText(""),Bytes=0,Preserve=true});}
    plan.Channel=meta.Channel;
    if(IsBeyondIdentity(primary)){var suffix=primary+"/Scripts/release.lua";var release=files.FirstOrDefault(x=>x.Key.EndsWith("/"+suffix,StringComparison.OrdinalIgnoreCase)||Compare.Equals(x.Key,suffix));if(release.Value!=null&&release.Value.Length<16384)using(var r=new StreamReader(release.Value.Open())){var text=r.ReadToEnd();var v=Regex.Match(text,"Version\\s*=\\s*['\"]([0-9]+\\.[0-9]+\\.[0-9]+)['\"]");if(v.Success&&meta.Version==null)plan.Version=v.Groups[1].Value;var c=Regex.Match(text,"Channel\\s*=\\s*['\"]([A-Za-z0-9._-]{1,40})['\"]");if(c.Success)plan.Channel=c.Groups[1].Value;}}
    if(plan.Channel!=null&&!Regex.IsMatch(plan.Channel,@"^[A-Za-z0-9._-]{1,40}$"))throw new InvalidDataException("The package channel is invalid.");
    if(plan.Name.Length>120||plan.Version.Length>80)throw new InvalidDataException("Package name or version is too long.");
    if((meta.Description??"").Length>8192||(meta.Changelog??"").Length>32768)throw new InvalidDataException("Package details are too long.");plan.Description=meta.Description;plan.Changelog=meta.Changelog;
    var readme=files.Where(x=>System.IO.Path.GetFileName(x.Key).StartsWith("README",StringComparison.OrdinalIgnoreCase)&&new[]{".txt",".md"}.Contains(System.IO.Path.GetExtension(x.Key),Compare)).OrderBy(x=>x.Key.Length).FirstOrDefault();
    if(readme.Value!=null)using(var reader=new StreamReader(readme.Value.Open())){var buffer=new char[65536];var count=reader.ReadBlock(buffer,0,buffer.Length);plan.Readme=new string(buffer,0,count).Replace("\0","");if(!reader.EndOfStream)plan.Readme+="\n[Additional text omitted]";}
    plan.Kind=plan.LuaRoots.Count>0?(pakNames.Count>0?"Lua + packages":"Lua"):"Packages";
    plan.Dependencies=meta.Dependencies??new string[0];plan.LoadAfter=meta.LoadAfter??new string[0];plan.Update=meta.Update;
    if(plan.Dependencies.Length>64||plan.LoadAfter.Length>64||(meta.Preserve??new string[0]).Length>128)throw new InvalidDataException("Too many package dependency or preservation rules.");
    if(plan.Update!=null)Updates.ValidateSource(plan.Update);
    foreach(var d in plan.Dependencies.Concat(plan.LoadAfter))Id(d);
    if(skipped>0)plan.Warnings.Add(skipped+" documentation, installer, or unsupported files will remain outside the game. No installer scripts are run.");
    if(pakNames.Any(x=>Compare.Equals(x,"ZodMenu")))plan.Warnings.Add("ZodMenu uses F8, which can overlap another mod's menu key. Its original package names are preserved.");
    if(plan.Files.Any(x=>x.Shared))plan.Warnings.Add("Bundled loader files are used only when absent. An existing UE4SS runtime is never replaced.");
   }
   var managed=Records();var previous=managed.FirstOrDefault(x=>SameMod(x.Id,plan.Id));
   if(IsBeyondIdentity(plan.Id))CheckBeyondRoots();
   var owned=new HashSet<string>(managed.SelectMany(x=>x.Files.Where(f=>!f.Shared)).Select(x=>x.Path),Compare);
   var removed=File.Exists(RemovedPath(plan.Id));
   plan.ExistingUnmanaged=!removed&&(plan.LuaRoots.Any(x=>Directory.Exists(Destination(x))&&Directory.EnumerateFileSystemEntries(Destination(x)).Any()&&(previous==null||!previous.LuaRoots.Contains(x,Compare)))||plan.Files.Any(x=>!x.Shared&&File.Exists(Destination(x.Path))&&!owned.Contains(x.Path)));
   if(plan.LuaRoots.Contains(BeyondRoot,Compare)&&Directory.Exists(Destination(LegacyRoot))){if(previous==null&&!removed)plan.ExistingUnmanaged=true;plan.Warnings.Add("The legacy Beyond Apocalypse folder will migrate with its settings and unknown files preserved. Conflicting files remain in a recovery copy outside the mod loader.");}
   plan.CanAdoptWithoutChanges=plan.ExistingUnmanaged&&plan.Files.Where(x=>!x.Shared).All(x=>File.Exists(Destination(x.Path))&&Compare.Equals(HashFile(Destination(x.Path)),x.Hash));
   if(plan.ExistingUnmanaged)plan.Warnings.Add(plan.CanAdoptWithoutChanges?"Matching files already exist. BMM can record ownership without rewriting them; unknown files and settings remain untouched.":"An existing installation is present. Explicit adoption backs up changed payload files before updating them; unknown files, configuration and saved settings remain untouched.");
   Dependencies(plan);return plan;
  }
  void Dependencies(InstallPlan plan) {
   plan.MissingDependencies.Clear();var status=GameInstallation.Inspect(GamePath);var records=Records();
   var bundledLoader=plan.Files.Any(x=>Compare.Equals(x.Path,GameInstallation.BinaryRoot+"/ue4ss/UE4SS.dll"));
   if((plan.LuaRoots.Count>0||plan.Files.Any(x=>Prefix(x.Path,GameInstallation.PaksRoot+"/LogicMods")))&&!status.HasUE4SS&&!bundledLoader)plan.MissingDependencies.Add("UE4SS");
   if(plan.Files.Any(x=>Prefix(x.Path,GameInstallation.PaksRoot+"/LogicMods"))&&!status.HasBPModLoader&&!plan.LuaRoots.Any(x=>Compare.Equals(x.Split('/').Last(),"BPModLoaderMod")))plan.MissingDependencies.Add("BPModLoaderMod");
   foreach(var dep in plan.Dependencies){if(Compare.Equals(dep,"ue4ss")){if(!status.HasUE4SS&&!bundledLoader&&!plan.MissingDependencies.Contains("UE4SS"))plan.MissingDependencies.Add("UE4SS");continue;}if(Compare.Equals(dep,"bpmodloadermod")){if(!status.HasBPModLoader&&!plan.LuaRoots.Any(x=>Compare.Equals(x.Split('/').Last(),dep))&&!plan.MissingDependencies.Contains("BPModLoaderMod"))plan.MissingDependencies.Add("BPModLoaderMod");continue;}var folder=Destination(GameInstallation.ModsRoot+"/"+dep);var managed=records.FirstOrDefault(x=>SameMod(x.Id,dep)||x.LuaRoots.Any(p=>SameMod(p.Split('/').Last(),dep)));if(managed==null&&IsBeyondIdentity(dep)){var current=Destination(BeyondRoot);if(File.Exists(System.IO.Path.Combine(current,"Scripts","main.lua")))folder=current;}var available=managed!=null?DependencyPresent(managed):File.Exists(System.IO.Path.Combine(folder,"Scripts","main.lua"))&&IsLuaEnabled(System.IO.Path.GetFileName(folder),folder);if(!available&&!plan.LuaRoots.Any(x=>SameMod(x.Split('/').Last(),dep)))plan.MissingDependencies.Add(dep);}
  }
  bool DependencyPresent(ModRecord record){return record.Enabled&&record.LuaRoots.All(root=>File.Exists(Destination(root+"/Scripts/main.lua"))&&IsLuaEnabled(root.Split('/').Last(),Destination(root)))&&record.Files.Where(f=>!f.Preserve&&!f.Shared&&!f.Path.EndsWith("/enabled.txt",StringComparison.OrdinalIgnoreCase)).All(f=>File.Exists(Destination(f.Path)));}
  List<ModRecord> Records() {
   var result=new List<ModRecord>();var path=Under(DataPath,"manifests");if(!Directory.Exists(path))return result;
   foreach(var f in Directory.EnumerateFiles(path,"*.json")){NoLinks(f);if(new FileInfo(f).Length>32*1024*1024)throw new InvalidDataException("An installed-mod manifest is too large.");var r=Json.Deserialize<ModRecord>(File.ReadAllText(f));ValidateRecord(r);if(!Compare.Equals(System.IO.Path.GetFileNameWithoutExtension(f),r.Id))throw new InvalidDataException("An installed-mod manifest has the wrong identifier.");result.Add(r);}if(result.Count(x=>IsBeyondIdentity(x.Id))>1)throw new IOException("Duplicate Beyond Apocalypse ownership records need review before changing mods.");return result;
  }
  static void ValidateRecord(ModRecord r) {
   if(r==null||r.Schema!=1||!r.Managed)throw new InvalidDataException("An installed-mod manifest is invalid.");Id(r.Id);
   var paths=new HashSet<string>(Compare);foreach(var f in r.Files){if(Canonical(f.Path)!=f.Path||!ManagedPath(f.Path)||!paths.Add(f.Path)||!Regex.IsMatch(f.Hash??"",@"^[a-f0-9]{64}$"))throw new InvalidDataException("An installed-mod manifest contains an unsafe file.");if(f.Shared&&!RuntimePath(f.Path))throw new InvalidDataException("Invalid shared dependency path.");}
   foreach(var root in r.LuaRoots)if(!Prefix(root,GameInstallation.ModsRoot)||root.Substring(GameInstallation.ModsRoot.Length+1).Contains("/"))throw new InvalidDataException("Invalid mod folder in installed manifest.");
  }
  public List<ModRecord> List() {
   var records=Records();var claimed=new HashSet<string>(records.SelectMany(x=>x.LuaRoots),Compare);var mods=Destination(GameInstallation.ModsRoot);
   if(Directory.Exists(mods))foreach(var folder in Directory.EnumerateDirectories(mods)){NoLinks(folder);var name=System.IO.Path.GetFileName(folder);var rel=GameInstallation.ModsRoot+"/"+name;var main=System.IO.Path.Combine(folder,"Scripts","main.lua");if(claimed.Contains(rel)||!File.Exists(main)||(Compare.Equals(rel,LegacyRoot)&&IsLegacyShim(main)))continue;var detected=new ModRecord{Id="external-"+HashText(rel).Substring(0,16),Name=IsBeyondIdentity(name)?"Beyond Apocalypse":name,Version="",Kind="Lua",Enabled=IsLuaEnabled(name,folder),Managed=false,LuaRoots=new List<string>{rel}};if(IsBeyondIdentity(name))ReadLocalRelease(detected,rel);records.Add(detected);}
   foreach(var record in records.Where(x=>IsBeyondIdentity(x.Id)))record.Name="Beyond Apocalypse";
   var owned=new HashSet<string>(records.Where(x=>x.Managed).SelectMany(x=>x.Files).Select(x=>x.Path),Compare);
   foreach(var scope in new[]{"LogicMods","~mods"}){var dir=Destination(GameInstallation.PaksRoot+"/"+scope);if(Directory.Exists(dir))foreach(var pak in Directory.EnumerateFiles(dir,"*.pak")){NoLinks(pak);var rel=GameInstallation.PaksRoot+"/"+scope+"/"+System.IO.Path.GetFileName(pak);if(!owned.Contains(rel))records.Add(new ModRecord{Id="external-"+HashText(rel).Substring(0,16),Name=System.IO.Path.GetFileNameWithoutExtension(pak),Version="",Kind="Packages",Enabled=true,Managed=false});}}
   var companion=GameInstallation.ModsRoot+"/BeyondApocolypseDevMenu";var attach=Destination(companion+"/Scripts/attach.lua");
   var parentEnabled=new[]{BeyondRoot,LegacyRoot}.Any(root=>{var folder=Destination(root);var main=System.IO.Path.Combine(folder,"Scripts","main.lua");return File.Exists(main)&&!IsLegacyShim(main)&&IsLuaEnabled(root.Split('/').Last(),folder);});
   if(parentEnabled&&File.Exists(attach)&&!claimed.Contains(companion)&&!records.Any(x=>x.LuaRoots.Contains(companion,Compare)))records.Add(new ModRecord{Id="external-"+HashText(companion).Substring(0,16),Name="Personal Dev Menu",Version="Local companion",Kind="Companion",Description="Optional companion loaded by Beyond Apocalypse. It follows the parent mod and is not loaded independently.",Enabled=true,Managed=false});
   return records.Where(x=>!Compare.Equals(x.Id,"bmm-runtime")&&(x.Managed||x.Enabled)).OrderBy(x=>x.Name,Compare).ToList();
  }
  void ReadLocalRelease(ModRecord record,string root){var file=Destination(root+"/Scripts/release.lua");if(!File.Exists(file)||new FileInfo(file).Length>16384)return;var text=File.ReadAllText(file);var version=Regex.Match(text,"Version\\s*=\\s*['\"]([0-9]+\\.[0-9]+\\.[0-9]+)['\"]");var channel=Regex.Match(text,"Channel\\s*=\\s*['\"]([A-Za-z0-9._-]{1,40})['\"]");if(version.Success)record.Version=version.Groups[1].Value;if(channel.Success)record.Channel=channel.Groups[1].Value;}
  bool IsLuaEnabled(string name,string folder){if(File.Exists(System.IO.Path.Combine(folder,"enabled.txt")))return true;var list=Destination(GameInstallation.ModsRoot+"/mods.txt");return File.Exists(list)&&Regex.IsMatch(File.ReadAllText(list),@"(?im)^\s*"+Regex.Escape(name)+@"\s*:\s*1\s*(?:;.*)?$");}
  void Ready() {if(running())throw new InvalidOperationException("Close Drive Beyond Horizons before changing installed mods.");NoLinks(GamePath);NoLinks(DataPath);}
  FileStream Lock(){Directory.CreateDirectory(DataPath);return new FileStream(Under(DataPath,"operation.lock"),FileMode.OpenOrCreate,FileAccess.ReadWrite,FileShare.None);}
  public ModRecord Install(InstallPlan plan) {return InstallCore(plan,false,false,false);}
  public ModRecord Install(InstallPlan plan,bool adoptExisting) {return InstallCore(plan,false,false,adoptExisting);}
  public ModRecord AdoptFromPackage(InstallPlan plan) {return Install(plan,true);}
  public void InstallDependencies(string zipPath,bool requireBlueprintLoader) {
   Ready();var status=GameInstallation.Inspect(GamePath);if(status.HasUE4SS&&(!requireBlueprintLoader||status.HasBPModLoader))return;
   const string expected="e14657eec1c3fb08d1d0e4d5b24f69a9343cd06359e1af27ae6c9c84c5f010cf";
   var dll=Destination(GameInstallation.BinaryRoot+"/ue4ss/UE4SS.dll");
   if(status.HasUE4SS&&(!File.Exists(dll)||!Compare.Equals(HashFile(dll),expected)))throw new InvalidOperationException("The existing UE4SS version is different. Install its matching BPModLoaderMod manually; BMM will not replace a working loader.");
   var plan=PreviewZip(zipPath);var runtime=plan.Files.FirstOrDefault(x=>Compare.Equals(x.Path,GameInstallation.BinaryRoot+"/ue4ss/UE4SS.dll"));
   if(runtime==null||!Compare.Equals(runtime.Hash,expected)||plan.LuaRoots.Any(x=>!Compare.Equals(x,GameInstallation.ModsRoot+"/BPModLoaderMod"))||plan.Files.Any(x=>!x.Shared&&!Prefix(x.Path,GameInstallation.ModsRoot+"/BPModLoaderMod")))throw new InvalidDataException("The dependency bundle did not match the supported runtime.");
   InstallCore(plan,true,requireBlueprintLoader,false);
  }
  ModRecord InstallCore(InstallPlan plan,bool dependencyMode,bool requireBlueprintLoader,bool adoptExisting) {
   if(plan==null)throw new ArgumentNullException("plan");Ready();using(var gate=Lock()){RecoverPending();
    // Rebuild from the archive rather than trusting mutable UI-supplied paths.
    if(!Compare.Equals(HashFile(plan.SourceZip),plan.ArchiveHash))throw new InvalidDataException("The archive changed after preview. Import it again.");
    var fresh=PreviewZip(plan.SourceZip);
    if(dependencyMode){fresh.Id="bmm-runtime";fresh.Name="UE4SS mod support";fresh.Update=null;if(!requireBlueprintLoader){fresh.LuaRoots.Clear();fresh.Files.RemoveAll(x=>!x.Shared);}Dependencies(fresh);}
    if(fresh.MissingDependencies.Count>0)throw new InvalidOperationException("Install or enable the required dependencies first: "+String.Join(", ",fresh.MissingDependencies));plan=fresh;
    var records=Records();var previous=records.FirstOrDefault(x=>SameMod(x.Id,plan.Id));bool reinstall=false;
    var removedPath=RemovedPath(plan.Id);if(IsBeyondIdentity(plan.Id)&&!File.Exists(removedPath))removedPath=RemovedPath("basicm4");
    if(previous==null&&File.Exists(removedPath)){previous=Json.Deserialize<ModRecord>(File.ReadAllText(removedPath));ValidateRecord(previous);if(!SameMod(previous.Id,plan.Id))throw new InvalidDataException("The previous-install record does not match this mod.");reinstall=true;}
    if(previous!=null&&!previous.Enabled&&!reinstall)throw new InvalidOperationException("Enable this mod before updating it.");
    bool canonicalBeyond=plan.LuaRoots.Contains(BeyondRoot,Compare);var legacySource=Destination(LegacyRoot);
    if(canonicalBeyond&&previous!=null&&reinstall&&!previous.Enabled&&previous.LuaRoots.Contains(LegacyRoot,Compare))legacySource=DisabledPath(previous.Id,LegacyRoot);
    bool migrateLegacy=canonicalBeyond&&Directory.Exists(legacySource);if(migrateLegacy){NoTreeLinks(legacySource);if(previous==null&&!adoptExisting)throw new IOException("Review and adopt the existing Beyond Apocalypse installation before migrating it.");}
    if(!canonicalBeyond&&IsBeyondIdentity(plan.Id)&&(Directory.Exists(Destination(BeyondRoot))||previous!=null&&previous.LuaRoots.Contains(BeyondRoot,Compare)))throw new IOException("This older package uses the legacy folder. Use a package for the current Beyond Apocalypse installation instead.");
    var own=previous==null?new Dictionary<string,ModFile>(Compare):previous.Files.ToDictionary(x=>canonicalBeyond?RenamedPath(x.Path):x.Path,Compare);
    var other=new HashSet<string>(records.Where(x=>!SameMod(x.Id,plan.Id)).SelectMany(x=>x.Files.Where(f=>!f.Shared)).Select(x=>x.Path),Compare);
    foreach(var root in plan.LuaRoots){var p=Destination(root);NoTreeLinks(p);if(records.Any(x=>!SameMod(x.Id,plan.Id)&&x.LuaRoots.Contains(root,Compare)))throw new IOException("Another managed mod owns "+root);if(Directory.Exists(p)&&Directory.EnumerateFiles(p,"*",SearchOption.AllDirectories).Any()&&(previous==null||!previous.LuaRoots.Contains(root,Compare))&&!dependencyMode&&!adoptExisting)throw new IOException("The mod folder already exists outside this manager: "+root+". Review and explicitly adopt it before updating.");}
    var status=GameInstallation.Inspect(GamePath);var installed=new List<ModFile>();
    foreach(var f in plan.Files){var target=Destination(f.Path);if(other.Contains(f.Path))throw new IOException("Another managed mod owns "+f.Path);if(f.Shared){if(status.HasUE4SS)continue;if(File.Exists(target)){if(!Compare.Equals(HashFile(target),f.Hash))throw new IOException("An existing loader-support file needs manual review: "+f.Path);continue;}}
     var existing=reinstall&&!previous.Enabled?DisabledPath(previous.Id,f.Path):target;
     if(migrateLegacy&&Prefix(f.Path,BeyondRoot)&&!File.Exists(existing))existing=Under(legacySource,f.Path.Substring(BeyondRoot.Length+1));
     ModFile old;own.TryGetValue(f.Path,out old);if(File.Exists(existing)&&old==null&&!adoptExisting&&!(migrateLegacy&&previous!=null&&f.Preserve)&&!(dependencyMode&&!f.Shared&&Compare.Equals(HashFile(existing),f.Hash)))throw new IOException("An existing file is not owned by this mod: "+f.Path);
     if(File.Exists(existing)&&old!=null&&!Compare.Equals(HashFile(existing),old.Hash)&&!old.Preserve&&!f.Preserve)throw new IOException("An installed mod file was changed locally: "+f.Path+". Back it up before replacing it.");
     var copy=new ModFile{Path=f.Path,Hash=f.Hash,Bytes=f.Bytes,Preserve=f.Preserve||(old!=null&&old.Preserve),Shared=f.Shared,Source=f.Source};
     if(File.Exists(existing)&&copy.Preserve){copy.Hash=HashFile(existing);copy.Bytes=new FileInfo(existing).Length;}installed.Add(copy);
    }
    foreach(var root in plan.LuaRoots){var marker=root+"/enabled.txt";if(!installed.Any(x=>Compare.Equals(x.Path,marker)))installed.Add(new ModFile{Path=marker,Hash=HashText(""),Bytes=0});}
    var next=new ModRecord{Id=plan.Id,Name=plan.Name,Version=plan.Version,Channel=plan.Channel,Kind=plan.Kind,Description=plan.Description,Changelog=plan.Changelog,Readme=plan.Readme,Enabled=true,Managed=true,InstalledUtc=DateTime.UtcNow.ToString("o"),ArchiveHash=plan.ArchiveHash,Files=installed,LuaRoots=plan.LuaRoots,Dependencies=plan.Dependencies,LoadAfter=plan.LoadAfter,Update=plan.Update??(previous==null||!Compare.Equals(previous.Channel,plan.Channel)?null:previous.Update)};
    ValidateOrder(next);
    using(var tx=new Transaction(DataPath,GamePath))try {
     if(migrateLegacy)MigrateLegacy(tx,legacySource);
     if(reinstall&&!previous.Enabled)foreach(var folder in previous.LuaRoots.Where(x=>plan.LuaRoots.Contains(x,Compare))){var source=DisabledPath(previous.Id,folder);var destination=Destination(folder);if(Directory.Exists(source)){if(Directory.Exists(destination))throw new IOException("Both active and saved mod folders exist; restore needs review.");tx.Move(source,destination);}}
     using(var archive=ZipFile.OpenRead(plan.SourceZip))foreach(var f in installed){var target=Destination(f.Path);if(File.Exists(target)&&(f.Preserve||Compare.Equals(HashFile(target),f.Hash)))continue;if(f.Source==null){tx.Write(target,new byte[0]);continue;}var entry=archive.GetEntry(f.Source);if(entry==null)entry=archive.Entries.FirstOrDefault(x=>Compare.Equals(x.FullName.Replace('\\','/'),f.Source));if(entry==null)throw new InvalidDataException("A previewed archive file is missing.");using(var stream=entry.Open())tx.Write(target,stream,f.Bytes,f.Hash);}
     if(previous!=null)foreach(var f in previous.Files.Where(x=>!x.Shared&&!installed.Any(n=>Compare.Equals(n.Path,canonicalBeyond?RenamedPath(x.Path):x.Path)))){var target=Destination(canonicalBeyond?RenamedPath(f.Path):f.Path);if(File.Exists(target)&&!f.Preserve&&Compare.Equals(HashFile(target),f.Hash))tx.Delete(target);}
     if(plan.LuaRoots.Count>0)tx.Write(Destination(GameInstallation.ModsRoot+"/mods.txt"),Encoding.UTF8.GetBytes(ModList(plan.LuaRoots,true,OrderDependencies(plan.LoadAfter.Concat(plan.Dependencies)),false)));
     tx.Write(ManifestPath(plan.Id),Encoding.UTF8.GetBytes(Json.Serialize(next)));if(previous!=null&&!reinstall&&!Compare.Equals(previous.Id,plan.Id))tx.Delete(ManifestPath(previous.Id));if(reinstall)tx.Delete(removedPath);tx.Commit();return next;
    }catch{tx.Rollback();throw;}
   }
  }
  void MigrateLegacy(Transaction tx,string source){var destination=Destination(BeyondRoot);if(!Directory.Exists(destination)){tx.Move(source,destination);return;}foreach(var file in Directory.EnumerateFiles(source,"*",SearchOption.AllDirectories)){var relative=file.Substring(source.Length+1).Replace('\\','/');var target=Under(destination,relative);if(!File.Exists(target))using(var input=File.OpenRead(file))tx.Write(target,input,new FileInfo(file).Length,HashFile(file));}var recovery=Under(GamePath,".bmm-migrations/"+Guid.NewGuid().ToString("N")+"/BasicM4");tx.Move(source,recovery);}
  ModRecord Get(string id){return Records().FirstOrDefault(x=>SameMod(x.Id,Id(id)))??throwMissing();}
  static ModRecord throwMissing(){throw new InvalidOperationException("This mod is not managed by BMM. Existing unmanaged files cannot be changed automatically.");}
  public void SetUpdateSource(string id,UpdateSource source) {
   if(source!=null)Updates.ValidateSource(source);NoLinks(DataPath);using(var gate=Lock()){var record=Get(id);record.Update=source;using(var tx=new Transaction(DataPath,GamePath))try{tx.Write(ManifestPath(record.Id),Encoding.UTF8.GetBytes(Json.Serialize(record)));tx.Commit();}catch{tx.Rollback();throw;}}
  }
  IEnumerable<string> OrderDependencies(IEnumerable<string> requested) {var records=Records();return requested.SelectMany(d=>{var r=records.FirstOrDefault(x=>SameMod(x.Id,d));return r==null?new[]{d}:r.LuaRoots.Select(x=>x.Split('/').Last());}).Distinct(Compare);}
  void ValidateOrder(ModRecord candidate) {
   var records=Records().Where(x=>x.Enabled&&!SameMod(x.Id,candidate.Id)).Concat(new[]{candidate}).ToList();var visiting=new HashSet<string>(Compare);var done=new HashSet<string>(Compare);
   Action<ModRecord> visit=null;visit=r=>{if(done.Contains(r.Id))return;if(!visiting.Add(r.Id))throw new InvalidDataException("The declared mod dependencies contain a load-order cycle.");foreach(var name in r.Dependencies.Concat(r.LoadAfter)){var dependency=records.FirstOrDefault(x=>SameMod(x.Id,name)||x.LuaRoots.Any(p=>SameMod(p.Split('/').Last(),name)));if(dependency!=null)visit(dependency);}visiting.Remove(r.Id);done.Add(r.Id);};foreach(var r in records)visit(r);
  }
  void Dependents(ModRecord record) {var roots=record.LuaRoots.Select(x=>x.Split('/').Last()).Concat(new[]{record.Id}).ToArray();var dependents=Records().Where(x=>x.Enabled&&!SameMod(x.Id,record.Id)&&x.Dependencies.Any(d=>roots.Any(name=>SameMod(name,d)))).Select(x=>x.Name).ToArray();if(dependents.Length>0)throw new InvalidOperationException("Other enabled mods need this mod: "+String.Join(", ",dependents));if(roots.Contains("BPModLoaderMod",Compare)&&Directory.Exists(Destination(GameInstallation.PaksRoot+"/LogicMods"))&&Directory.EnumerateFiles(Destination(GameInstallation.PaksRoot+"/LogicMods"),"*.pak").Any())throw new InvalidOperationException("Enabled LogicMods packages still need BPModLoaderMod.");}
  public void SetEnabled(string id,bool enabled) {
   Ready();using(var gate=Lock()){RecoverPending();var record=Get(id);id=record.Id;if(record.LuaRoots.Count==0&&record.Files.All(x=>x.Shared))throw new InvalidOperationException("Shared UE4SS support is kept installed. Enable or disable individual mods instead.");if(record.Enabled==enabled)return;if(!enabled)Dependents(record);
    if(enabled){var check=new InstallPlan{Files=record.Files,LuaRoots=record.LuaRoots,Dependencies=record.Dependencies};Dependencies(check);if(check.MissingDependencies.Count>0)throw new InvalidOperationException("Enable required dependencies first: "+String.Join(", ",check.MissingDependencies));ValidateOrder(record);}
    var moves=new List<KeyValuePair<string,string>>();foreach(var root in record.LuaRoots)moves.Add(new KeyValuePair<string,string>(enabled?DisabledPath(id,root):Destination(root),enabled?Destination(root):DisabledPath(id,root)));
    foreach(var f in record.Files.Where(x=>!x.Shared&&!record.LuaRoots.Any(r=>Prefix(x.Path,r))))moves.Add(new KeyValuePair<string,string>(enabled?DisabledPath(id,f.Path):Destination(f.Path),enabled?Destination(f.Path):DisabledPath(id,f.Path)));
    foreach(var m in moves){NoTreeLinks(m.Key);NoLinks(m.Value);if(!File.Exists(m.Key)&&!Directory.Exists(m.Key))throw new IOException("A managed file or folder is missing: "+m.Key);if(File.Exists(m.Value)||Directory.Exists(m.Value))throw new IOException("The destination already exists: "+m.Value);}
    using(var tx=new Transaction(DataPath,GamePath))try{foreach(var m in moves)tx.Move(m.Key,m.Value);if(record.LuaRoots.Count>0)tx.Write(Destination(GameInstallation.ModsRoot+"/mods.txt"),Encoding.UTF8.GetBytes(ModList(record.LuaRoots,enabled,OrderDependencies(record.LoadAfter.Concat(record.Dependencies)),false)));record.Enabled=enabled;tx.Write(ManifestPath(id),Encoding.UTF8.GetBytes(Json.Serialize(record)));tx.Commit();}catch{tx.Rollback();throw;}
   }
  }
  public OperationResult Uninstall(string id) {
   Ready();using(var gate=Lock()){RecoverPending();var record=Get(id);id=record.Id;if(record.Enabled)Dependents(record);var result=new OperationResult();
    using(var tx=new Transaction(DataPath,GamePath))try {
     foreach(var f in record.Files.Where(x=>!x.Shared)){var p=record.Enabled?Destination(f.Path):DisabledPath(id,f.Path);if(!File.Exists(p))continue;if(f.Preserve||!Compare.Equals(HashFile(p),f.Hash)){
      if(Prefix(f.Path,GameInstallation.PaksRoot)||f.Path.EndsWith("/enabled.txt",StringComparison.OrdinalIgnoreCase)){var saved=Under(DataPath,"preserved/"+Guid.NewGuid().ToString("N")+System.IO.Path.GetExtension(f.Path));using(var input=File.OpenRead(p))tx.Write(saved,input,new FileInfo(p).Length,HashFile(p));tx.Delete(p);result.PreservedFiles.Add(saved);}else result.PreservedFiles.Add(p);continue;
     }tx.Delete(p);}
     if(record.LuaRoots.Count>0)tx.Write(Destination(GameInstallation.ModsRoot+"/mods.txt"),Encoding.UTF8.GetBytes(ModList(record.LuaRoots,false,record.LoadAfter,true)));tx.Write(RemovedPath(id),Encoding.UTF8.GetBytes(Json.Serialize(record)));tx.Delete(ManifestPath(id));tx.Commit();result.BackupPath=tx.Folder;return result;
    }catch{tx.Rollback();throw;}
   }
  }
  string ModList(IList<string> roots,bool enabled,IEnumerable<string> after,bool remove) {
   var file=Destination(GameInstallation.ModsRoot+"/mods.txt");var text=File.Exists(file)?File.ReadAllText(file):"";
   var newline=text.Contains("\r\n")?"\r\n":"\n";var lines=text.Replace("\r\n","\n").Split('\n').ToList();if(lines.Count>0&&lines.Last()=="")lines.RemoveAt(lines.Count-1);
   var names=roots.Select(x=>x.Split('/').Last()).ToArray();
   if(names.Contains("BeyondApocalypse",Compare)){var oldRows=lines.Select((line,index)=>new{line,index}).Where(x=>Regex.IsMatch(x.line,@"^\s*BasicM4\s*:\s*[01]\s*(?:;.*)?$",RegexOptions.IgnoreCase)).Select(x=>x.index).ToArray();if(oldRows.Length>1)throw new InvalidDataException("Duplicate legacy load-order rows need review.");if(oldRows.Length==1){if(lines.Any(line=>Regex.IsMatch(line,@"^\s*BeyondApocalypse\s*:\s*[01]\s*(?:;.*)?$",RegexOptions.IgnoreCase)))lines.RemoveAt(oldRows[0]);else lines[oldRows[0]]=Regex.Replace(lines[oldRows[0]],@"BasicM4","BeyondApocalypse",RegexOptions.IgnoreCase);}}
   foreach(var name in names){var matches=lines.Select((line,index)=>new{line,index}).Where(x=>Regex.IsMatch(x.line,@"^\s*"+Regex.Escape(name)+@"\s*:\s*[01]\s*(?:;.*)?$")).Select(x=>x.index).ToArray();if(matches.Length>1)throw new InvalidDataException("Duplicate load-order entries for "+name+" need review.");
    if(remove){if(matches.Length==1)lines.RemoveAt(matches[0]);continue;}var row=name+" : "+(enabled?"1":"0");if(matches.Length==1)lines[matches[0]]=row;else lines.Add(row);
   }
   if(enabled&&!remove)foreach(var dependency in after??new string[0]){
    if(names.Contains(dependency,Compare))throw new InvalidDataException("A package cannot declare itself in loadAfter.");
    var dep=lines.FindIndex(x=>Regex.IsMatch(x,@"^\s*"+Regex.Escape(dependency)+@"\s*:\s*1\s*(?:;.*)?$"));if(dep<0)continue;
    foreach(var name in names){var current=lines.FindIndex(x=>Regex.IsMatch(x,@"^\s*"+Regex.Escape(name)+@"\s*:\s*[01]\s*(?:;.*)?$"));if(current>=0&&current<dep){var row=lines[current];lines.RemoveAt(current);lines.Insert(dep,row);}}
   }
   return String.Join(newline,lines)+(lines.Count>0?newline:"");
  }
  public void Recover() {Ready();using(var gate=Lock())RecoverPending();}
  void RecoverPending() {
   var root=Under(DataPath,"transactions");if(!Directory.Exists(root))return;
   foreach(var dir in Directory.EnumerateDirectories(root)){NoTreeLinks(dir);var pending=System.IO.Path.Combine(dir,"pending.json");if(File.Exists(pending))Transaction.Recover(dir,DataPath,GamePath);}
  }
  // Files are journaled before mutation, kept as recovery backups after commit,
  // and replaced atomically. No archive file is executed or loaded by BMM.
  sealed class Transaction:IDisposable {
   public readonly string Folder;readonly string data,game;readonly List<Change> changes=new List<Change>();bool finished;
   public sealed class Change {public string Path {get;set;}public string Destination {get;set;}public string Backup {get;set;}public bool Existed {get;set;}public bool Move {get;set;}}
   public Transaction(string dataRoot,string gameRoot){data=dataRoot;game=gameRoot;Folder=Under(data,"transactions/"+DateTime.UtcNow.ToString("yyyyMMdd-HHmmss")+"-"+Guid.NewGuid().ToString("N"));Directory.CreateDirectory(Folder);Journal();}
   void Check(string path){var full=System.IO.Path.GetFullPath(path);if(!full.StartsWith(game+System.IO.Path.DirectorySeparatorChar,StringComparison.OrdinalIgnoreCase)&&!full.StartsWith(data+System.IO.Path.DirectorySeparatorChar,StringComparison.OrdinalIgnoreCase))throw new IOException("A transaction path is outside BMM's folders.");NoLinks(full);}
   void Journal(){var p=System.IO.Path.Combine(Folder,"pending.json");var temp=p+".new";File.WriteAllText(temp,Json.Serialize(changes),Encoding.UTF8);if(File.Exists(p))File.Replace(temp,p,null);else File.Move(temp,p);}
   void Capture(string path){Check(path);if(changes.Any(x=>Compare.Equals(x.Path,path)&&!x.Move))return;var existed=File.Exists(path);var backup=System.IO.Path.Combine(Folder,changes.Count.ToString("D6")+".bak");if(existed)File.Copy(path,backup,false);changes.Add(new Change{Path=path,Backup=backup,Existed=existed});Journal();}
   public void Write(string path,byte[] bytes){using(var stream=new MemoryStream(bytes,false))Write(path,stream,bytes.LongLength,null);}
   public void Write(string path,Stream content,long size,string hash){Capture(path);Directory.CreateDirectory(System.IO.Path.GetDirectoryName(path));var temp=System.IO.Path.Combine(System.IO.Path.GetDirectoryName(path),".bmm-"+Guid.NewGuid().ToString("N").Substring(0,12)+".tmp");
    try{using(var f=new FileStream(temp,FileMode.CreateNew,FileAccess.Write,FileShare.None)){var buffer=new byte[81920];long count=0;int n;while((n=content.Read(buffer,0,buffer.Length))>0){count+=n;if(count>size||count>MaxEntry)throw new InvalidDataException("An extracted file exceeded its advertised size.");f.Write(buffer,0,n);}if(count!=size)throw new InvalidDataException("An extracted file was incomplete.");f.Flush(true);}if(hash!=null&&!Compare.Equals(HashFile(temp),hash))throw new InvalidDataException("Extracted-file verification failed.");NoLinks(path);if(File.Exists(path))File.Replace(temp,path,null);else File.Move(temp,path);}finally{if(File.Exists(temp))File.Delete(temp);}}
   public void Delete(string path){Capture(path);if(File.Exists(path))File.Delete(path);}
   public void Move(string source,string destination){Check(source);Check(destination);NoTreeLinks(source);changes.Add(new Change{Path=source,Destination=destination,Move=true});Journal();Directory.CreateDirectory(System.IO.Path.GetDirectoryName(destination));if(Directory.Exists(source))Directory.Move(source,destination);else File.Move(source,destination);}
   public void Commit(){File.Move(System.IO.Path.Combine(Folder,"pending.json"),System.IO.Path.Combine(Folder,"committed.json"));finished=true;}
   public void Rollback(){if(finished)return;Restore(changes,data,game);File.Move(System.IO.Path.Combine(Folder,"pending.json"),System.IO.Path.Combine(Folder,"rolled-back.json"));finished=true;}
   static void Restore(List<Change> entries,string data,string game){foreach(var c in entries.AsEnumerable().Reverse()){
    var p=System.IO.Path.GetFullPath(c.Path);if(!p.StartsWith(game+System.IO.Path.DirectorySeparatorChar,StringComparison.OrdinalIgnoreCase)&&!p.StartsWith(data+System.IO.Path.DirectorySeparatorChar,StringComparison.OrdinalIgnoreCase))throw new IOException("Recovery journal path is outside BMM folders.");NoLinks(p);
    if(c.Move){var d=System.IO.Path.GetFullPath(c.Destination);if(!d.StartsWith(game+System.IO.Path.DirectorySeparatorChar,StringComparison.OrdinalIgnoreCase)&&!d.StartsWith(data+System.IO.Path.DirectorySeparatorChar,StringComparison.OrdinalIgnoreCase))throw new IOException("Recovery destination is outside BMM folders.");NoLinks(d);if(File.Exists(p)||Directory.Exists(p)){if(File.Exists(d)||Directory.Exists(d))throw new IOException("Both recovery locations exist; manual recovery is required.");continue;}Directory.CreateDirectory(System.IO.Path.GetDirectoryName(p));if(Directory.Exists(d))Directory.Move(d,p);else if(File.Exists(d))File.Move(d,p);
    }else if(c.Existed){if(String.IsNullOrEmpty(c.Backup)||!System.IO.Path.GetFullPath(c.Backup).StartsWith(data+System.IO.Path.DirectorySeparatorChar,StringComparison.OrdinalIgnoreCase))throw new IOException("Invalid recovery backup.");NoLinks(c.Backup);if(File.Exists(p)&&Compare.Equals(HashFile(p),HashFile(c.Backup)))continue;Directory.CreateDirectory(System.IO.Path.GetDirectoryName(p));File.Copy(c.Backup,p,true);}else if(File.Exists(p))File.Delete(p);
   }}
   public static void Recover(string folder,string data,string game){var file=System.IO.Path.Combine(folder,"pending.json");var changes=Json.Deserialize<List<Change>>(File.ReadAllText(file));Restore(changes,data,game);File.Move(file,System.IO.Path.Combine(folder,"recovered.json"));}
   public void Dispose(){if(!finished)Rollback();}
  }
 }
}
