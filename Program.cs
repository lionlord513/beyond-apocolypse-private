using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Text;
using System.Threading.Tasks;
using System.Web.Script.Serialization;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Markup;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using Microsoft.Win32;

namespace BeyondModManager
{
    public sealed class ManagerPreferences { public string GamePath { get; set; } }
    public sealed class CatalogHistory { public string Version { get; set; } public string Released { get; set; } public string Channel { get; set; } public string[] Notes { get; set; } }
    public sealed class PublicCatalog
    {
        public string Id { get; set; } public string Name { get; set; } public string Version { get; set; }
        public string Description { get; set; } public string Website { get; set; } public UpdateSource Update { get; set; }
        public CatalogHistory[] History { get; set; }
    }
    public sealed class ModTile
    {
        public ModRecord Record { get; set; }
        public bool Catalog { get; set; }
        public string Name { get { return Program.IsBeyond(Record) ? "Beyond Apocalypse" : Record.Name; } }
        public string Subtitle { get { return Catalog ? "Ready to install" : Record.Enabled ? "Enabled" : "Disabled"; } }
    }

    public static class Program
    {
        public const string ManagerVersion = "1.0.6";
        static readonly string DataRoot = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "BeyondModManager");
        static readonly JavaScriptSerializer Json = new JavaScriptSerializer { MaxJsonLength = 2 * 1024 * 1024, RecursionLimit = 32 };
        static readonly Dictionary<string, UpdateCandidate> Available = new Dictionary<string, UpdateCandidate>(StringComparer.OrdinalIgnoreCase);
        static readonly Queue<string> Imports = new Queue<string>();
        static readonly StringBuilder Activity = new StringBuilder();
        static Window Window;
        static PublicCatalog Beyond, Manager;
        static ManagerPreferences Preferences;
        static ModStore Store;
        static InstallPlan Pending;
        static UpdateCandidate ManagerCandidate;
        static bool Busy, PreviewOnly;
        static string Page = "Mods";
        static string PreferencesFile { get { return Path.Combine(DataRoot, "settings.json"); } }
        static string LogFile { get { return Path.Combine(DataRoot, "activity.log"); } }

        static T View<T>(string name) where T : class { return Window.FindName(name) as T; }
        static void Text(string name, string value) { View<TextBlock>(name).Text = value ?? ""; }
        static Stream Resource(string name)
        {
            var stream = typeof(Program).Assembly.GetManifestResourceStream(name);
            if (stream == null) throw new InvalidDataException("A required manager resource is missing: " + name);
            return stream;
        }
        static string ResourceText(string name) { using (var reader = new StreamReader(Resource(name))) return reader.ReadToEnd(); }
        static void Status(string value) { Text("Status", value); }
        static void Log(string value)
        {
            string line = DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss") + "  " + value + Environment.NewLine;
            Activity.Append(line); View<TextBox>("ActivityText").Text = Activity.ToString(); View<TextBox>("ActivityText").ScrollToEnd();
            if (!PreviewOnly) try { Directory.CreateDirectory(DataRoot); File.AppendAllText(LogFile, line, Encoding.UTF8); } catch (IOException) { } catch (UnauthorizedAccessException) { }
            Status(value);
        }
        static string Friendly(Exception exception)
        {
            if (exception is AggregateException) exception = ((AggregateException)exception).Flatten().InnerExceptions[0];
            return exception.Message;
        }
        static string Size(long bytes) { return bytes >= 1024 * 1024 ? (bytes / 1048576.0).ToString("0.0") + " MB" : (bytes / 1024.0).ToString("0.0") + " KB"; }
        public static bool IsBeyond(ModRecord record) { return record != null && (ModStore.IsBeyondIdentity(record.Id) || (record.LuaRoots ?? new List<string>()).Any(x => ModStore.IsBeyondIdentity(Path.GetFileName(x.Replace('/', Path.DirectorySeparatorChar))))); }
        static bool SameIdentity(string first, string second) { return String.Equals(first, second, StringComparison.OrdinalIgnoreCase) || (ModStore.IsBeyondIdentity(first) && ModStore.IsBeyondIdentity(second)); }
        static string CollectionCount(IEnumerable<ModTile> tiles)
        {
            var detected = tiles.Where(x => !x.Catalog).ToList();
            return detected.Count + (detected.Count == 1 ? " MOD / " : " MODS / ") + detected.Count(x => x.Record.Enabled) + " ENABLED";
        }
        static bool ShowMod(ModRecord record) { return !SupportOnly(record) && (record.Managed || record.Enabled); }
        static string VersionText(ModRecord record)
        {
            string version = record.Version;
            return String.IsNullOrWhiteSpace(version) || version == "Existing installation" || version == "Imported" || version == "Local companion" || version == "Unknown" ? "Version unavailable" : "Version " + version;
        }
        static bool Companion(ModRecord record) { return record != null && record.Kind == "Companion"; }
        static ModTile Selected { get { return View<ListBox>("ModList").SelectedItem as ModTile; } }
        static bool PublicBeyond(ModRecord record)
        {
            string channel = MetadataText(record, "Channel");
            return IsBeyond(record) && (channel == "beta" || channel == "stable");
        }
        static UpdateSource Source(ModTile tile)
        {
            if (tile == null) return null;
            // The built-in public feed also upgrades records saved by older manager versions.
            if (IsBeyond(tile.Record)) return tile.Catalog || PublicBeyond(tile.Record) ? Beyond.Update : null;
            return tile.Record.Update;
        }
        static bool GameReady { get { return Store != null && GameInstallation.IsGame(Store.GamePath); } }
        static bool SupportOnly(ModRecord record) { return record != null && String.Equals(record.Id, "bmm-runtime", StringComparison.OrdinalIgnoreCase); }

        static void SelectPage(string page)
        {
            Page = page;
            foreach (string name in new[] { "Mods", "Activity", "Settings" })
            {
                View<FrameworkElement>(name + "Page").Visibility = name == page ? Visibility.Visible : Visibility.Collapsed;
                View<Button>(name + "PageButton").Background = new SolidColorBrush((Color)ColorConverter.ConvertFromString(name == page ? "#36412C" : "#2B3027"));
            }
            Text("PageTitle", page == "Mods" ? "My mods" : page);
        }

        static void ReadPreferences()
        {
            Preferences = new ManagerPreferences();
            try { if (File.Exists(PreferencesFile) && new FileInfo(PreferencesFile).Length < 65536) Preferences = Json.Deserialize<ManagerPreferences>(File.ReadAllText(PreferencesFile)) ?? Preferences; } catch { }
            if (!GameInstallation.IsGame(Preferences.GamePath))
            {
                // Only migrate the game location. Account data and credentials are never imported.
                string legacy = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "BeyondApocolypse", "Launcher", "settings.json");
                try
                {
                    if (File.Exists(legacy) && new FileInfo(legacy).Length < 65536)
                    {
                        var saved = Json.Deserialize<ManagerPreferences>(File.ReadAllText(legacy));
                        if (saved != null && GameInstallation.IsGame(saved.GamePath)) Preferences.GamePath = saved.GamePath;
                    }
                }
                catch { }
            }
            if (!GameInstallation.IsGame(Preferences.GamePath)) Preferences.GamePath = GameInstallation.Find();
            if (GameInstallation.IsGame(Preferences.GamePath)) Store = new ModStore(Preferences.GamePath, DataRoot);
        }
        static void SavePreferences()
        {
            Directory.CreateDirectory(DataRoot); string temporary = PreferencesFile + ".new";
            File.WriteAllText(temporary, Json.Serialize(Preferences), new UTF8Encoding(false));
            if (File.Exists(PreferencesFile)) File.Replace(temporary, PreferencesFile, null); else File.Move(temporary, PreferencesFile);
        }
        static bool BrowseGame()
        {
            if (Busy) return false;
            using (var dialog = new System.Windows.Forms.FolderBrowserDialog { Description = "Choose the main Drive Beyond Horizons game folder.", ShowNewFolderButton = false, SelectedPath = Preferences.GamePath ?? "" })
            {
                if (dialog.ShowDialog() != System.Windows.Forms.DialogResult.OK) return false;
                if (!GameInstallation.IsGame(dialog.SelectedPath)) { Log("That folder does not contain Drive Beyond Horizons. Choose its main Steam game folder."); return false; }
                Store = new ModStore(dialog.SelectedPath, DataRoot); Preferences.GamePath = Store.GamePath; SavePreferences();
                Available.Clear(); RefreshList(); Log("Game folder selected."); return true;
            }
        }
        static void RefreshList(string selectedId = null)
        {
            var selected = Selected; if (selectedId == null && selected != null) selectedId = selected.Record.Id;
            var list = GameReady ? Store.List().Where(ShowMod).Select(x => new ModTile { Record = x }).ToList() : new List<ModTile>();
            if (!list.Any(x => IsBeyond(x.Record))) list.Add(new ModTile { Catalog = true, Record = new ModRecord { Id = "beyondapocalypse", Name = Beyond.Name, Version = Beyond.Version, Update = Beyond.Update } });
            list = list.OrderByDescending(x => IsBeyond(x.Record)).ThenBy(x => x.Name, StringComparer.OrdinalIgnoreCase).ToList();
            View<ListBox>("ModList").ItemsSource = list;
            View<ListBox>("ModList").SelectedItem = list.FirstOrDefault(x => SameIdentity(x.Record.Id, selectedId)) ?? list.FirstOrDefault();
            Text("ModCount", CollectionCount(list));
            View<TextBox>("GamePathText").Text = Preferences.GamePath ?? "Game folder not selected";
            Text("GameState", GameReady ? (GameInstallation.Running() ? "Drive Beyond Horizons is running — changes wait until it closes" : "Drive Beyond Horizons  /  Ready") : "Select your game folder in Settings");
            RefreshDetail(); RefreshButtons();
        }
        static string History(CatalogHistory[] history)
        {
            var text = new StringBuilder();
            foreach (var entry in history ?? new CatalogHistory[0])
            {
                text.AppendLine(entry.Version + "  /  " + entry.Released + "  /  " + (entry.Channel ?? "beta").ToUpperInvariant());
                foreach (var note in entry.Notes ?? new string[0]) text.AppendLine("• " + note);
                text.AppendLine();
            }
            return text.ToString().TrimEnd();
        }
        static string MetadataText(ModRecord record, string field)
        {
            var property = typeof(ModRecord).GetProperty(field);
            return property == null ? "" : (property.GetValue(record, null) as string ?? "");
        }
        static void RefreshDetail()
        {
            var tile = Selected; if (tile == null) return;
            var record = tile.Record; bool beyond = IsBeyond(record);
            Text("DetailName", beyond ? Beyond.Name : record.Name);
            Text("DetailType", tile.Catalog ? "FEATURED MOD" : record.Enabled ? "ENABLED" : "DISABLED");
            Text("DetailVersion", tile.Catalog ? "Public release " + Beyond.Version : Companion(record) ? "" : VersionText(record));
            string description = Companion(record) ? "Separate local add-on. Not included with Beyond Apocalypse or installed by BMM." : beyond ? Beyond.Description : MetadataText(record, "Description");
            Text("DetailDescription", String.IsNullOrWhiteSpace(description) ? "No description included." : description);
            View<Image>("ModLogo").Visibility = beyond ? Visibility.Visible : Visibility.Collapsed;
            View<TextBlock>("ModInitials").Visibility = beyond ? Visibility.Collapsed : Visibility.Visible;
            Text("ModInitials", String.Join("", record.Name.Split(new[] { ' ', '-', '_' }, StringSplitOptions.RemoveEmptyEntries).Take(3).Select(x => x.Substring(0, 1))).ToUpperInvariant());
            string note = tile.Catalog ? "Download and install Beyond Apocalypse." : !record.Managed && !Companion(record) ? "Add this mod's ZIP to manage it here." : "";
            View<Border>("ManagedNoteBox").Visibility = note.Length == 0 ? Visibility.Collapsed : Visibility.Visible; Text("ManagedNote", note);
            var source = Source(tile); UpdateCandidate candidate;
            Text("UpdateStatus", Available.TryGetValue(record.Id, out candidate) ? "Update ready: " + candidate.Version + "  ·  " + Size(candidate.Size) : source == null ? "Manual updates" : "Updates available");
            View<TextBlock>("UpdateStatus").Visibility = Companion(record) ? Visibility.Collapsed : Visibility.Visible;
            Text("RequirementsText", record.Dependencies.Length > 0 ? "Requires: " + String.Join(", ", record.Dependencies) : tile.Catalog ? "UE4SS support is included if needed." : "");
            string changes = beyond ? History(Beyond.History) : MetadataText(record, "Changelog");
            Text("DetailHistory", String.IsNullOrWhiteSpace(changes) ? "No changelog was included in this package." : changes);
            View<TextBlock>("HistoryHeading").Visibility = Companion(record) ? Visibility.Collapsed : Visibility.Visible;
            View<TextBlock>("DetailHistory").Visibility = Companion(record) ? Visibility.Collapsed : Visibility.Visible;
            string readme = MetadataText(record, "Readme"); Text("DetailReadme", readme);
            View<TextBlock>("ReadmeHeading").Visibility = String.IsNullOrWhiteSpace(readme) ? Visibility.Collapsed : Visibility.Visible;
            RefreshButtons();
        }
        static void RefreshButtons()
        {
            foreach (string name in new[] { "AddZipButton", "RefreshButton", "BrowseGameButton", "ModsPageButton", "ActivityPageButton", "SettingsPageButton", "ManagerUpdateButton", "CopyExampleButton" }) View<Button>(name).IsEnabled = !Busy;
            View<Button>("PlayButton").IsEnabled = !Busy && GameReady;
            View<Button>("CancelImportButton").IsEnabled = !Busy;
            View<Button>("ConfirmImportButton").IsEnabled = !Busy && Pending != null;
            View<FrameworkElement>("Navigation").IsEnabled = Pending == null;
            View<FrameworkElement>("Workspace").IsEnabled = Pending == null;
            View<ProgressBar>("Progress").Visibility = Busy ? Visibility.Visible : Visibility.Collapsed;
            View<ProgressBar>("Progress").IsIndeterminate = Busy;
            var tile = Selected; var record = tile == null ? null : tile.Record;
            bool manageable = record != null && !tile.Catalog && record.Managed && !SupportOnly(record);
            View<Button>("ToggleModButton").IsEnabled = !Busy && manageable;
            View<Button>("ToggleModButton").Content = record != null && !record.Enabled ? "Enable" : "Disable";
            View<Button>("UninstallModButton").IsEnabled = !Busy && manageable;
            View<Button>("OpenModFolderButton").IsEnabled = !Busy && record != null && !tile.Catalog && !Companion(record) && GameReady;
            View<Button>("UpdateModButton").IsEnabled = !Busy && tile != null && Source(tile) != null && (tile.Catalog || manageable);
            View<Button>("UpdateModButton").Content = tile != null && tile.Catalog ? "Get Beyond Apocalypse" : record != null && Available.ContainsKey(record.Id) ? "Install update" : "Check for update";
        }
        static async Task Run(Func<Task> operation)
        {
            if (Busy) return; Busy = true; RefreshButtons();
            try { await operation(); }
            catch (Exception error) { Log(Friendly(error)); }
            finally { Busy = false; RefreshButtons(); }
        }
        static void RequireClosed()
        {
            if (!GameReady) throw new InvalidOperationException("Select your game folder in Settings first.");
            if (GameInstallation.Running()) throw new InvalidOperationException("Close Drive Beyond Horizons before changing mods. Your files have not been changed.");
        }
        static void ChooseZip()
        {
            if (Busy) return;
            var dialog = new OpenFileDialog { Title = "Add mod ZIPs", Filter = "Mod ZIP archives (*.zip)|*.zip", Multiselect = true };
            if (dialog.ShowDialog(Window) == true) EnqueueImports(dialog.FileNames);
        }
        static async void EnqueueImports(IEnumerable<string> paths)
        {
            if (Busy) { Status("Wait for the current operation to finish before adding another ZIP."); return; }
            foreach (string path in paths)
                if (File.Exists(path) && Path.GetExtension(path).Equals(".zip", StringComparison.OrdinalIgnoreCase)) Imports.Enqueue(path);
            if (Imports.Count == 0) { Status("Add a ZIP archive containing a mod."); return; }
            if (!GameReady && !BrowseGame()) { Imports.Clear(); return; }
            if (Pending == null) await NextImport();
        }
        static async Task NextImport()
        {
            if (Imports.Count == 0) return;
            string path = Imports.Dequeue();
            await Run(async () => { Status("Reading mod package…"); var plan = await Task.Run(() => Store.PreviewZip(path)); ShowPreview(plan); });
        }
        static void ShowPreview(InstallPlan plan)
        {
            Pending = plan; SelectPage("Mods");
            Text("PreviewName", "Do you want to install " + plan.Name + "?");
            var version = VersionText(new ModRecord { Version = plan.Version });
            Text("PreviewSummary", version == "Version unavailable" ? "" : version);
            var description = plan.Description;
            if (String.IsNullOrWhiteSpace(description) && ModStore.IsBeyondIdentity(plan.Id)) description = Beyond.Description;
            if (String.IsNullOrWhiteSpace(description)) description = plan.Changelog;
            Text("PreviewDescription", description);
            View<TextBlock>("PreviewDescription").Visibility = String.IsNullOrWhiteSpace(description) ? Visibility.Collapsed : Visibility.Visible;
            var other = plan.MissingDependencies.Where(x => !x.Equals("UE4SS", StringComparison.OrdinalIgnoreCase) && !x.Equals("BPModLoaderMod", StringComparison.OrdinalIgnoreCase)).ToArray();
            var notices = new List<string>();
            if (other.Length > 0) notices.Add("Install these mods first: " + String.Join(", ", other) + ".");
            if (plan.Warnings.Any(x => x.StartsWith("ZodMenu uses F8", StringComparison.Ordinal))) notices.Add("ZodMenu uses F8. If another mod uses that key, change one of their bindings.");
            Text("PreviewDependencies", String.Join(Environment.NewLine, notices));
            View<TextBlock>("PreviewDependencies").Visibility = notices.Count == 0 ? Visibility.Collapsed : Visibility.Visible;
            View<Button>("ConfirmImportButton").Content = "Install";
            View<Border>("ImportOverlay").Visibility = Visibility.Visible; Status("Select Install to add " + plan.Name + "."); RefreshButtons();
        }
        static string MaterializeResource(string resource, string directory)
        {
            Directory.CreateDirectory(directory); string path = Path.Combine(directory, resource);
            if (!File.Exists(path)) using (var source = Resource(resource)) using (var destination = new FileStream(path, FileMode.CreateNew, FileAccess.Write, FileShare.None)) source.CopyTo(destination);
            return path;
        }
        static async Task ConfirmImport()
        {
            var plan = Pending; if (plan == null) return;
            bool adopt = plan.ExistingUnmanaged;
            await Run(async () =>
            {
                RequireClosed();
                var unknown = plan.MissingDependencies.Where(x => !x.Equals("UE4SS", StringComparison.OrdinalIgnoreCase) && !x.Equals("BPModLoaderMod", StringComparison.OrdinalIgnoreCase)).ToArray();
                if (unknown.Length > 0) throw new InvalidOperationException("Install the required mods first: " + String.Join(", ", unknown));
                bool needSupport = plan.MissingDependencies.Count > 0;
                bool blueprint = plan.MissingDependencies.Any(x => x.Equals("BPModLoaderMod", StringComparison.OrdinalIgnoreCase));
                Status("Installing " + plan.Name + "…");
                var installed = await Task.Run(() =>
                {
                    if (needSupport)
                    {
                        string resource = MaterializeResource("dependency-runtime.zip", Path.Combine(DataRoot, "support", Guid.NewGuid().ToString("N")));
                        Store.InstallDependencies(resource, blueprint);
                        plan = Store.PreviewZip(plan.SourceZip);
                    }
                    var record = Store.Install(plan, adopt);
                    if (PublicBeyond(record)) { Store.SetUpdateSource(record.Id, Beyond.Update); record.Update = Beyond.Update; }
                    return record;
                });
                Available.Remove(installed.Id); Pending = null; View<Border>("ImportOverlay").Visibility = Visibility.Collapsed;
                RefreshList(installed.Id); Log(installed.Name + " " + installed.Version + " installed. Settings and saves retained.");
            });
            if (Pending == null) await NextImport();
        }
        static async Task UpdateSelected()
        {
            var tile = Selected; var source = Source(tile); if (tile == null || source == null) return;
            if (!GameReady && !BrowseGame()) return;
            await Run(async () =>
            {
                UpdateCandidate candidate;
                if (!Available.TryGetValue(tile.Record.Id, out candidate))
                {
                    Status("Checking " + tile.Name + " updates…");
                    string installed = tile.Catalog ? null : tile.Record.Version;
                    try { if (installed != null) Updates.ParseVersion(installed); } catch (InvalidDataException) { installed = null; }
                    candidate = await Updates.QueryModUpdateAsync(source, installed, tile.Record.ArchiveHash);
                    if (candidate == null) { Text("UpdateStatus", "No eligible public package update was found."); Log("No newer or changed public package is available for " + tile.Name + "."); return; }
                    Available[tile.Record.Id] = candidate; RefreshDetail();
                    if (!tile.Catalog) { Log(tile.Name + " update ready. Select Install update to download it."); return; }
                }
                RequireClosed(); Status("Downloading and verifying " + tile.Name + " " + candidate.Version + "…");
                string folder = Path.Combine(DataRoot, "downloads", Guid.NewGuid().ToString("N"));
                string zip;
                try { zip = await Updates.DownloadVerified(candidate, Path.Combine(folder, candidate.AssetName)); }
                catch { Available.Remove(tile.Record.Id); RefreshDetail(); throw; }
                var plan = await Task.Run(() => Store.PreviewZip(zip));
                if (!SameIdentity(plan.Id, tile.Record.Id)) throw new InvalidDataException("The downloaded ZIP identifies a different mod. It was not installed.");
                ShowPreview(plan);
            });
        }
        static async Task ToggleSelected()
        {
            var tile = Selected; if (tile == null || !tile.Record.Managed) return;
            await Run(async () => { RequireClosed(); bool enabled = !tile.Record.Enabled; await Task.Run(() => Store.SetEnabled(tile.Record.Id, enabled)); RefreshList(tile.Record.Id); Log(tile.Name + (enabled ? " enabled." : " disabled. Its settings are retained.")); });
        }
        static async Task UninstallSelected()
        {
            var tile = Selected; if (tile == null || !tile.Record.Managed || Busy) return;
            if (MessageBox.Show(Window, "Uninstall " + tile.Name + "?\n\nYour saves, mod settings and shared support files will be retained.", "Uninstall mod", MessageBoxButton.YesNo, MessageBoxImage.Question, MessageBoxResult.No) != MessageBoxResult.Yes) return;
            await Run(async () => { RequireClosed(); var result = await Task.Run(() => Store.Uninstall(tile.Record.Id)); Available.Remove(tile.Record.Id); RefreshList(); Log(tile.Name + " uninstalled. " + result.PreservedFiles.Count + " modified/settings files retained. Backup: " + result.BackupPath); });
        }
        static async Task CheckManager()
        {
            await Run(async () =>
            {
                if (ManagerCandidate == null)
                {
                    Status("Checking manager updates…"); ManagerCandidate = await Updates.QueryManagerUpdateAsync(Manager.Update, ManagerVersion);
                    Text("ManagerUpdateStatus", ManagerCandidate == null ? "BMM " + ManagerVersion + " is up to date." : "BMM " + ManagerCandidate.Version + " is ready. The manager will reopen after updating.");
                    View<Button>("ManagerUpdateButton").Content = ManagerCandidate == null ? "Check for updates" : "Update manager";
                    Log(ManagerCandidate == null ? "No newer manager release is available." : "Manager update ready: " + ManagerCandidate.Version); return;
                }
                Status("Downloading and verifying the manager update…");
                StagedManagerUpdate staged;
                try { staged = await Updates.StageManagerUpdateAsync(ManagerCandidate, Path.Combine(DataRoot, "manager-updates")); }
                catch { ManagerCandidate = null; View<Button>("ManagerUpdateButton").Content = "Check for updates"; throw; }
                Updates.BeginManagerUpdate(staged, Process.GetCurrentProcess().MainModule.FileName);
                Busy = false; Application.Current.Shutdown();
            });
        }
        static void OpenPath(string path)
        {
            if (String.IsNullOrWhiteSpace(path)) { Status("Choose your game folder first."); return; }
            try { if (!File.Exists(path) && !Directory.Exists(path)) { Status("That folder or log has not been created yet."); return; } Process.Start(new ProcessStartInfo(path) { UseShellExecute = true }); }
            catch (Exception error) { Log(Friendly(error)); }
        }
        static void OpenModFolder()
        {
            var tile = Selected; if (tile == null || !GameReady) return;
            var record = tile.Record;
            string root = record.LuaRoots.FirstOrDefault();
            if (!record.Enabled && record.Managed) { OpenPath(Store.DataPath); return; }
            if (root != null) OpenPath(Path.Combine(Store.GamePath, root.Replace('/', Path.DirectorySeparatorChar)));
            else { var file = record.Files.FirstOrDefault(); OpenPath(file == null ? Path.Combine(Store.GamePath, GameInstallation.PaksRoot.Replace('/', Path.DirectorySeparatorChar)) : Path.GetDirectoryName(Path.Combine(Store.GamePath, file.Path.Replace('/', Path.DirectorySeparatorChar)))); }
        }
        static void Play()
        {
            if (!GameReady || Busy) return;
            if (GameInstallation.Running()) { Status("Drive Beyond Horizons is already running."); return; }
            try
            {
                string executable = Path.Combine(Store.GamePath, "DriveBeyondHorizons.exe");
                if (!File.Exists(executable)) executable = Path.Combine(Store.GamePath, GameInstallation.BinaryRoot.Replace('/', Path.DirectorySeparatorChar), "DriveBeyondHorizons-Win64-Shipping.exe");
                Process.Start(new ProcessStartInfo(executable) { WorkingDirectory = Store.GamePath, UseShellExecute = true }); Log("Starting Drive Beyond Horizons.");
            }
            catch (Exception error) { Log(Friendly(error)); }
        }
        static void Wire()
        {
            foreach (string name in new[] { "Mods", "Activity", "Settings" }) { string captured = name; View<Button>(name + "PageButton").Click += (s, e) => SelectPage(captured); }
            View<Button>("AddZipButton").Click += (s, e) => ChooseZip();
            View<Button>("BrowseGameButton").Click += (s, e) => BrowseGame();
            View<Button>("PlayButton").Click += (s, e) => Play();
            View<Button>("RefreshButton").Click += (s, e) => { try { RefreshList(); Status("Mod collection refreshed."); } catch (Exception error) { Log(Friendly(error)); } };
            View<ListBox>("ModList").SelectionChanged += (s, e) => RefreshDetail();
            View<Button>("ConfirmImportButton").Click += async (s, e) => await ConfirmImport();
            View<Button>("CancelImportButton").Click += async (s, e) => { Pending = null; View<Border>("ImportOverlay").Visibility = Visibility.Collapsed; RefreshButtons(); Status("Installation cancelled."); await NextImport(); };
            View<Button>("UpdateModButton").Click += async (s, e) => await UpdateSelected();
            View<Button>("ToggleModButton").Click += async (s, e) => await ToggleSelected();
            View<Button>("UninstallModButton").Click += async (s, e) => await UninstallSelected();
            View<Button>("ManagerUpdateButton").Click += async (s, e) => await CheckManager();
            View<Button>("OpenLogButton").Click += (s, e) => OpenPath(LogFile);
            View<Button>("OpenGameFolderButton").Click += (s, e) => OpenPath(Preferences.GamePath);
            View<Button>("OpenManagerFolderButton").Click += (s, e) => OpenPath(DataRoot);
            View<Button>("OpenBackupsButton").Click += (s, e) => OpenPath(Store == null ? null : Path.Combine(Store.DataPath, "transactions"));
            View<Button>("OpenModFolderButton").Click += (s, e) => OpenModFolder();
            View<Button>("CopyExampleButton").Click += (s, e) => { try { Clipboard.SetText(ResourceText("bmm-example.json")); Status("Example metadata copied."); } catch (Exception error) { Log(Friendly(error)); } };
            Window.PreviewDragOver += (s, e) => { e.Effects = !Busy && e.Data.GetDataPresent(DataFormats.FileDrop) ? DragDropEffects.Copy : DragDropEffects.None; e.Handled = true; };
            Window.PreviewDrop += (s, e) => { if (e.Data.GetDataPresent(DataFormats.FileDrop)) EnqueueImports((string[])e.Data.GetData(DataFormats.FileDrop)); e.Handled = true; };
            Window.Closing += (s, e) => { if (Busy) { e.Cancel = true; Status("Wait for the current operation to finish before closing the manager."); } };
        }
        static void LoadWindow(bool preview)
        {
            PreviewOnly = preview; Beyond = Json.Deserialize<PublicCatalog>(ResourceText("ba-public.json")); Manager = Json.Deserialize<PublicCatalog>(ResourceText("bmm-public.json"));
            Updates.ValidateSource(Beyond.Update); Updates.ValidateSource(Manager.Update);
            if (Manager.Version != ManagerVersion) throw new InvalidDataException("Manager metadata version mismatch.");
            using (var stream = Resource("MainWindow.xaml")) Window = (Window)XamlReader.Load(stream);
            using (var stream = Resource("bmm-icon.ico")) Window.Icon = BitmapFrame.Create(stream, BitmapCreateOptions.None, BitmapCacheOption.OnLoad);
            using (var stream = Resource("ba-logo.png"))
            {
                var image = new BitmapImage(); image.BeginInit(); image.CacheOption = BitmapCacheOption.OnLoad; image.StreamSource = stream; image.EndInit(); image.Freeze(); View<Image>("ModLogo").Source = image;
            }
            View<TextBox>("CreatorHelp").Text = ResourceText("creator-help.txt");
            Text("ManagerVersion", "BMM " + ManagerVersion); Wire(); SelectPage("Mods");
            if (preview) PopulatePreview();
            else
            {
                ReadPreferences();
                try { if (File.Exists(LogFile)) { var lines = File.ReadLines(LogFile).Reverse().Take(120).Reverse(); Activity.Append(String.Join(Environment.NewLine, lines) + Environment.NewLine); View<TextBox>("ActivityText").Text = Activity.ToString(); } } catch { }
                RefreshList(); if (!GameReady) SelectPage("Settings");
            }
        }
        static void PopulatePreview()
        {
            Preferences = new ManagerPreferences(); Store = null;
            var records = new List<ModTile> {
                new ModTile { Record = new ModRecord { Id = "beyondapocalypse", Name = Beyond.Name, Version = Beyond.Version, Managed = true, Enabled = true, Kind = "Lua", Update = Beyond.Update, Dependencies = new[] { "UE4SS" } } },
                new ModTile { Record = new ModRecord { Id = "chs", Name = "Complete HUD Speedometer", Version = "1.0.0", Managed = true, Enabled = false, Kind = "Lua" } }
            };
            var channel = typeof(ModRecord).GetProperty("Channel");
            if (channel != null) channel.SetValue(records[0].Record, "beta", null);
            View<ListBox>("ModList").ItemsSource = records; View<ListBox>("ModList").SelectedIndex = 0;
            Text("ModCount", CollectionCount(records)); Text("GameState", "Drive Beyond Horizons  /  Ready");
            View<TextBox>("GamePathText").Text = "Steam / steamapps / common / Drive Beyond Horizons";
            Text("Status", "Ready. Drop a mod ZIP anywhere to install it.");
            View<Button>("PlayButton").IsEnabled = true;
        }
        static int Render(string path, string page, int width, int height)
        {
            LoadWindow(true); SelectPage(page == "Import" || page == "Cancelled" ? "Mods" : page == "Creators" ? "Settings" : page);
            if (page == "Creators") View<Expander>("CreatorSection").IsExpanded = true;
            if (page == "Import" || page == "Cancelled") ShowPreview(new InstallPlan { Name = "Complete HUD Speedometer", Version = "1.0.0", Kind = "Lua", MissingDependencies = new List<string> { "UE4SS" }, Warnings = new List<string> { "Existing settings will be retained. This package has no declared automatic update source." } });
            if (page == "Cancelled") View<Button>("CancelImportButton").RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
            var content = (Grid)Window.Content; content.Background = Window.Background;
            content.Measure(new Size(width, height)); content.Arrange(new Rect(0, 0, width, height)); content.UpdateLayout();
            if (page == "Creators") { View<ScrollViewer>("SettingsPage").ScrollToBottom(); content.UpdateLayout(); }
            var image = new RenderTargetBitmap(width, height, 96, 96, PixelFormats.Pbgra32); image.Render(content);
            var encoder = new PngBitmapEncoder(); encoder.Frames.Add(BitmapFrame.Create(image));
            Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(path))); using (var output = File.Create(path)) encoder.Save(output);
            return 0;
        }
        static int SelfTest(string output)
        {
            UpdatesTests.Run(); LoadWindow(true);
            // Exercise the actual Cancel event: the last queued import has no Run/finally to restore controls.
            for (int attempt = 0; attempt < 2; attempt++)
            {
                ShowPreview(new InstallPlan { Name = "Cancel fixture", Version = "1.0.0" });
                if (View<FrameworkElement>("Workspace").IsEnabled || View<FrameworkElement>("Navigation").IsEnabled) throw new Exception("Install confirmation did not gate its background.");
                View<Button>("CancelImportButton").RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
                if (Pending != null || Busy || View<Border>("ImportOverlay").Visibility != Visibility.Collapsed || !View<FrameworkElement>("Workspace").IsEnabled || !View<FrameworkElement>("Navigation").IsEnabled || !View<ListBox>("ModList").IsEnabled || !View<Button>("AddZipButton").IsEnabled) throw new Exception("Cancel left the manager disabled.");
                View<Button>("SettingsPageButton").RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
                if (Page != "Settings") throw new Exception("Navigation failed after cancellation.");
                View<Button>("ModsPageButton").RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
            }

            if (!IsBeyond(new ModRecord { Id = "beyondapocalypse" }) || !IsBeyond(new ModRecord { Id = "basicm4" }) || !SameIdentity("basicm4", "beyondapocalypse") || SameIdentity("beyondapocalypse", "differentmod")) throw new Exception("Mod identity migration failed.");
            var oldFeed = new ModTile { Record = new ModRecord { Id = "basicm4", Channel = "beta", Update = new UpdateSource { ManifestAsset = "release.json" } } };
            if (Source(oldFeed).ManifestAsset != "bmm-mod.json" || Source(oldFeed).AssetPattern != "BeyondApocalypse-{version}-public.zip") throw new Exception("Legacy record still selects the legacy package feed.");
            var countFixture = Enumerable.Range(0, 12).Select(x => new ModTile { Record = new ModRecord { Enabled = x == 0 } }).ToList();
            countFixture.Add(new ModTile { Catalog = true, Record = new ModRecord { Enabled = true } });
            if (CollectionCount(countFixture) != "12 MODS / 1 ENABLED") throw new Exception("Mod count failed.");
            if (countFixture.Where(x => !x.Catalog && ShowMod(x.Record)).Count() != 1 || !ShowMod(new ModRecord { Managed = true, Enabled = false }) || ShowMod(new ModRecord { Id = "bmm-runtime", Managed = true, Enabled = true })) throw new Exception("Mod visibility filter failed.");
            if (VersionText(new ModRecord { Version = "Existing installation" }) != "Version unavailable") throw new Exception("Unknown version label failed.");
            if (!new ModTile { Record = new ModRecord { Enabled = false, Managed = false } }.Subtitle.StartsWith("Disabled")) throw new Exception("Existing disabled mod status missing.");
            var content = (Grid)Window.Content; content.Measure(new Size(1004, 681)); content.Arrange(new Rect(0, 0, 1004, 681)); content.UpdateLayout();
            foreach (string name in new[] { "AddZipButton", "PlayButton", "ModList", "UpdateModButton", "ToggleModButton", "UninstallModButton", "OpenModFolderButton", "Status" })
            {
                var control = View<FrameworkElement>(name); var bounds = control.TransformToAncestor(content).TransformBounds(new Rect(0, 0, control.ActualWidth, control.ActualHeight));
                if (bounds.Left < 0 || bounds.Top < 0 || bounds.Right > 1005 || bounds.Bottom > 682 || control.ActualHeight <= 0) throw new Exception("UI bounds failed: " + name);
            }
            if (Beyond.History == null || Beyond.History.Length < 35) throw new Exception("Public release history missing.");
            if (!ResourceText("bmm.schema.json").Contains("assetPattern")) throw new Exception("Creator schema missing.");
            using (var runtime = Resource("dependency-runtime.zip")) if (runtime.Length < 1000000) throw new Exception("Runtime resource missing.");
            File.WriteAllText(output, "PASS: update validation, canonical/legacy mod identity, enabled/detected counts, embedded public metadata/runtime/logo/help, named controls, minimum-size UI bounds, and repeated import/cancel/navigation recovery.\r\nNo live installation or game process changed.\r\n");
            return 0;
        }
        [STAThread]
        public static int Main(string[] args)
        {
            try
            {
                var app = new Application { ShutdownMode = ShutdownMode.OnMainWindowClose };
                if (args.Length > 0 && args[0] == "--self-test") return SelfTest(args.Length > 1 ? args[1] : Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "self-test.txt"));
                if (args.Length > 1 && args[0] == "--preview") return Render(args[1], args.Length > 2 ? args[2] : "Mods", args.Length > 3 ? Int32.Parse(args[3]) : 1240, args.Length > 4 ? Int32.Parse(args[4]) : 840);
                LoadWindow(false); app.MainWindow = Window;
                Window.Loaded += (s, e) => { if (args.Length > 0) EnqueueImports(args.Where(x => x.EndsWith(".zip", StringComparison.OrdinalIgnoreCase))); };
                app.DispatcherUnhandledException += (s, e) => { Log(Friendly(e.Exception)); Busy = false; RefreshButtons(); e.Handled = true; };
                return app.Run(Window);
            }
            catch (Exception error)
            {
                if (args.Length == 0) MessageBox.Show(error.Message, "Beyond Mod Manager"); else { Console.Error.WriteLine(error); if (args.Length > 1) File.WriteAllText(args[1] + ".error.txt", error.ToString()); }
                return 1;
            }
        }
    }
}
