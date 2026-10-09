using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Net;
using System.Net.Http;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading.Tasks;
using System.Web.Script.Serialization;

namespace BeyondModManager
{
    // Optional declarative bmm.json data. No source means manual updates only.
    public sealed class UpdateSource
    {
        public string Provider { get; set; }
        public string Repository { get; set; }
        public string TagPrefix { get; set; }
        public string AssetPattern { get; set; }
        public string ManifestAsset { get; set; }
        public string Sha256Asset { get; set; }
        public string Kind { get; set; }
    }

    public sealed class UpdateCandidate
    {
        public string Version { get; set; }
        public string Url { get; set; }
        public string Sha256 { get; set; }
        public long Size { get; set; }
        public string Notes { get; set; }
        public string AssetName { get; set; }
        public string Repository { get; set; }
        public string Tag { get; set; }
        public string Kind { get; set; }
    }

    public sealed class StagedManagerUpdate
    {
        public string ExecutablePath { get; set; }
        public string Sha256 { get; set; }
        public string Version { get; set; }
        public string WorkDirectory { get; set; }
    }

    public sealed class GitHubUpdateAsset
    {
        public long id { get; set; }
        public string name { get; set; }
        public string url { get; set; }
        public string browser_download_url { get; set; }
        public string digest { get; set; }
        public long size { get; set; }
        public string state { get; set; }
    }

    public sealed class GitHubUpdateRelease
    {
        public bool draft { get; set; }
        public bool prerelease { get; set; }
        public string tag_name { get; set; }
        public string name { get; set; }
        public string body { get; set; }
        public GitHubUpdateAsset[] assets { get; set; }
    }

    public sealed class PublicUpdateManifest
    {
        public int schema { get; set; }
        public string version { get; set; }
        public string channel { get; set; }
        public string asset { get; set; }
        public string url { get; set; }
        public string sha256 { get; set; }
        public long size { get; set; }
        public string[] notes { get; set; }
    }

    public static class Updates
    {
        public const string ManagerExecutableName = "Beyond Mod Manager.exe";
        public const long MaximumPackageBytes = 1024L * 1024 * 1024;
        public const long MaximumManagerBytes = 64L * 1024 * 1024;
        static readonly Regex RepositoryPattern = new Regex(@"^[A-Za-z0-9][A-Za-z0-9_.-]*/[A-Za-z0-9][A-Za-z0-9_.-]*$");
        static readonly Regex HashPattern = new Regex(@"^[0-9a-fA-F]{64}$");
        static readonly Regex RestrictedLabel = new Regex(@"(^|[^a-z])(alpha|private|internal|development|dev|nda|confidential)([^a-z]|$)", RegexOptions.IgnoreCase);
        static readonly Regex RestrictedNotes = new Regex(@"(^|[^a-z])(alpha|internal|development|nda|confidential)([^a-z]|$)|\b(private|dev)[ -]+(build|release|branch|test|version)\b", RegexOptions.IgnoreCase);
        static JavaScriptSerializer Serializer() { return new JavaScriptSerializer { MaxJsonLength = 2 * 1024 * 1024, RecursionLimit = 32 }; }

        public static Version ParseVersion(string value)
        {
            if (value == null || !Regex.IsMatch(value, @"^\d+\.\d+(?:\.\d+){0,2}$"))
                throw new InvalidDataException("Update version must contain two to four numeric components.");
            var parts = value.Split('.');
            int[] n = new int[4];
            for (int i = 0; i < parts.Length; i++)
                if (!Int32.TryParse(parts[i], out n[i])) throw new InvalidDataException("Invalid update version.");
            return new Version(n[0], n[1], n[2], n[3]);
        }

        static bool SafeName(string name)
        {
            return !String.IsNullOrWhiteSpace(name) && name.Length <= 180 &&
                name.IndexOfAny(Path.GetInvalidFileNameChars()) < 0 && name != "." && name != ".." &&
                !name.EndsWith(".") && !name.EndsWith(" ");
        }

        public static void ValidateSource(UpdateSource source)
        {
            if (source == null) throw new InvalidDataException("This mod does not declare automatic updates.");
            if (!String.Equals(source.Provider, "github", StringComparison.OrdinalIgnoreCase) ||
                source.Repository == null || !RepositoryPattern.IsMatch(source.Repository) || source.Repository.Contains(".."))
                throw new InvalidDataException("A valid GitHub update repository is required.");
            if (source.TagPrefix != null && !Regex.IsMatch(source.TagPrefix, @"^[A-Za-z0-9_-]{0,32}$"))
                throw new InvalidDataException("Invalid release tag prefix.");
            foreach (var file in new[] { source.ManifestAsset, source.Sha256Asset })
                if (file != null && !SafeName(file)) throw new InvalidDataException("Invalid update metadata filename.");
            if (source.AssetPattern != null)
            {
                string expanded = source.AssetPattern.Replace("{version}", "1.2.3").Replace("{tag}", "v1.2.3");
                if (!SafeName(expanded) || expanded.Contains("{") || expanded.Contains("}"))
                    throw new InvalidDataException("Use an exact asset name with optional {version} or {tag} placeholders.");
            }
            if (String.IsNullOrEmpty(source.AssetPattern) && String.IsNullOrEmpty(source.ManifestAsset))
                throw new InvalidDataException("Update metadata must identify a release ZIP or manifest.");
            if (source.Kind != null && source.Kind != "mod" && source.Kind != "manager" && source.Kind != "beyond-apocolypse")
                throw new InvalidDataException("Unknown update package kind.");
            if ((source.Kind == "manager" || source.Kind == "beyond-apocolypse") && String.IsNullOrEmpty(source.ManifestAsset))
                throw new InvalidDataException("This update source requires a public release manifest.");
        }

        public static bool IsAllowedUrl(string value)
        {
            Uri uri;
            if (!Uri.TryCreate(value, UriKind.Absolute, out uri) || uri.Scheme != Uri.UriSchemeHttps ||
                !uri.IsDefaultPort || !String.IsNullOrEmpty(uri.UserInfo) || !String.IsNullOrEmpty(uri.Fragment)) return false;
            return new[] { "api.github.com", "github.com", "release-assets.githubusercontent.com", "objects.githubusercontent.com", "github-releases.githubusercontent.com" }
                .Contains(uri.Host, StringComparer.OrdinalIgnoreCase);
        }

        static bool IsReleaseAssetUrl(string value, string repository, string tag)
        {
            if (!IsAllowedUrl(value) || repository == null || !RepositoryPattern.IsMatch(repository)) return false;
            var uri = new Uri(value);
            string path = Uri.UnescapeDataString(uri.AbsolutePath);
            if (uri.Host.Equals("api.github.com", StringComparison.OrdinalIgnoreCase))
                return Regex.IsMatch(path, "^/repos/" + Regex.Escape(repository) + @"/releases/assets/\d+$", RegexOptions.IgnoreCase);
            return uri.Host.Equals("github.com", StringComparison.OrdinalIgnoreCase) && tag != null &&
                path.StartsWith("/" + repository + "/releases/download/" + tag + "/", StringComparison.OrdinalIgnoreCase) &&
                SafeName(path.Substring(("/" + repository + "/releases/download/" + tag + "/").Length));
        }

        public static bool IsPublicRelease(GitHubUpdateRelease release)
        {
            return release != null && !release.draft && !release.prerelease &&
                !RestrictedLabel.IsMatch(release.tag_name ?? "") && !RestrictedLabel.IsMatch(release.name ?? "") &&
                !RestrictedNotes.IsMatch(release.body ?? "");
        }

        static string VersionFromTag(UpdateSource source, string tag)
        {
            var prefix = source.TagPrefix ?? "v";
            if (tag == null || !tag.StartsWith(prefix, StringComparison.Ordinal)) return null;
            string version = tag.Substring(prefix.Length);
            try { ParseVersion(version); return version; } catch (InvalidDataException) { return null; }
        }

        static bool PublicManifest(PublicUpdateManifest manifest)
        {
            return manifest != null && manifest.schema == 1 &&
                (manifest.channel == "stable" || manifest.channel == "beta") &&
                !RestrictedLabel.IsMatch(manifest.version ?? "") &&
                !(manifest.notes ?? new string[0]).Any(x => RestrictedNotes.IsMatch(x ?? ""));
        }

        internal static string AssetUrl(GitHubUpdateAsset asset, UpdateSource source, GitHubUpdateRelease release, string verifiedHash = null)
        {
            var value = asset.browser_download_url ?? asset.url;
            if (!IsReleaseAssetUrl(value, source.Repository, release.tag_name))
                throw new InvalidDataException("The release asset URL does not belong to its declared GitHub repository.");
            var hash = NormalizeHash(asset.digest) ?? NormalizeHash(verifiedHash);
            string revision = hash != null ? "sha256-" + hash : asset.id > 0 ? "id-" + asset.id.ToString(System.Globalization.CultureInfo.InvariantCulture) : null;
            if (revision == null) throw new InvalidDataException("The release asset has no verifiable revision identifier.");
            // A replacement keeps its filename/tag URL but has a new API digest or
            // asset id. Bind every metadata/ZIP request to that immutable revision.
            var uri = new UriBuilder(value);
            var query = uri.Query.TrimStart('?').Split(new[] { '&' }, StringSplitOptions.RemoveEmptyEntries)
                .Where(part => !Uri.UnescapeDataString(part.Split('=')[0]).Equals("bmm_revision", StringComparison.OrdinalIgnoreCase)).ToList();
            query.Add("bmm_revision=" + revision);
            uri.Query = String.Join("&", query);
            return uri.Uri.AbsoluteUri;
        }

        static string NormalizeHash(string value)
        {
            if (String.IsNullOrEmpty(value)) return null;
            if (value.StartsWith("sha256:", StringComparison.OrdinalIgnoreCase)) value = value.Substring(7);
            if (!HashPattern.IsMatch(value)) throw new InvalidDataException("Invalid SHA-256 update digest.");
            return value.ToLowerInvariant();
        }

        public static string ReadChecksum(string text, string assetName)
        {
            var matches = new List<string>();
            foreach (string line in (text ?? "").Split(new[] { '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries))
            {
                var m = Regex.Match(line.Trim(), @"^([a-fA-F0-9]{64})\s+\*?(.+)$");
                if (m.Success && m.Groups[2].Value == assetName) matches.Add(m.Groups[1].Value.ToLowerInvariant());
            }
            if (matches.Count != 1) throw new InvalidDataException("Checksum list must contain exactly one digest for the selected ZIP.");
            return matches[0];
        }

        // Pure selection/validation also used by offline fixtures. Never trust a manifest URL as a download target.
        public static UpdateCandidate ResolveCandidate(UpdateSource source, GitHubUpdateRelease release,
            PublicUpdateManifest manifest, string checksumText)
        {
            ValidateSource(source);
            if (!IsPublicRelease(release)) return null;
            var version = VersionFromTag(source, release.tag_name);
            if (version == null) return null;
            if (source.ManifestAsset != null)
            {
                if (!PublicManifest(manifest)) return null;
                if (manifest.version != version) throw new InvalidDataException("Release tag and manifest version differ.");
            }
            var assets = release.assets ?? new GitHubUpdateAsset[0];
            string name = source.AssetPattern == null ? null : source.AssetPattern.Replace("{version}", version).Replace("{tag}", release.tag_name);
            if (name == null && manifest != null) name = manifest.asset;
            if (name == null && manifest != null && manifest.url != null)
            {
                if (!IsReleaseAssetUrl(manifest.url, source.Repository, release.tag_name))
                    throw new InvalidDataException("Manifest URL is outside the declared release.");
                var match = assets.Where(a => a.url == manifest.url || a.browser_download_url == manifest.url).ToArray();
                if (match.Length == 1) name = match[0].name;
            }
            if (!SafeName(name) || !name.EndsWith(".zip", StringComparison.OrdinalIgnoreCase) || RestrictedLabel.IsMatch(name))
                throw new InvalidDataException("The manifest must select a public release ZIP.");
            var selected = assets.Where(a => a.name == name).ToArray();
            if (selected.Length != 1) throw new InvalidDataException("The declared release ZIP is missing or ambiguous.");
            var asset = selected[0];
            if (asset.state != null && asset.state != "uploaded") throw new InvalidDataException("The release asset is not ready.");
            long max = source.Kind == "manager" ? MaximumManagerBytes : MaximumPackageBytes;
            if (asset.size <= 0 || asset.size > max) throw new InvalidDataException("Update ZIP size is outside supported limits.");
            string hash = NormalizeHash(asset.digest);
            string manifestHash = manifest == null ? null : NormalizeHash(manifest.sha256);
            if (manifest != null && (manifest.size != asset.size || manifestHash == null))
                throw new InvalidDataException("Release size or digest is missing or inconsistent.");
            if (hash != null && manifestHash != null && hash != manifestHash) throw new InvalidDataException("GitHub and manifest digests differ.");
            hash = manifestHash ?? hash;
            if (source.Sha256Asset != null)
            {
                string listed = ReadChecksum(checksumText, name);
                if (hash != null && hash != listed) throw new InvalidDataException("Release digests differ.");
                hash = listed;
            }
            if (hash == null) throw new InvalidDataException("No verifiable SHA-256 digest is published for this update.");
            return new UpdateCandidate { Version = version, Url = AssetUrl(asset, source, release, hash), Sha256 = hash,
                Size = asset.size, AssetName = name, Repository = source.Repository, Tag = release.tag_name,
                Kind = source.Kind ?? "mod", Notes = manifest == null ? (release.body ?? "") : String.Join(Environment.NewLine, manifest.notes ?? new string[0]) };
        }

        static async Task Fetch(string url, Stream destination, long maxBytes, bool json)
        {
            // No embedded credentials; each redirect is revalidated and never receives authentication.
            ServicePointManager.SecurityProtocol |= SecurityProtocolType.Tls12;
            using (var handler = new HttpClientHandler { AllowAutoRedirect = false })
            using (var client = new HttpClient(handler) { Timeout = TimeSpan.FromMinutes(5) })
            {
                for (int redirects = 0; redirects < 6; redirects++)
                {
                    if (!IsAllowedUrl(url)) throw new InvalidDataException("Update downloads require an approved HTTPS GitHub host.");
                    using (var request = new HttpRequestMessage(HttpMethod.Get, url))
                    {
                        request.Headers.UserAgent.ParseAdd("Beyond-Mod-Manager/1.0");
                        if (new Uri(url).Host == "api.github.com")
                        {
                            request.Headers.Accept.ParseAdd(json ? "application/vnd.github+json" : "application/octet-stream");
                            request.Headers.Add("X-GitHub-Api-Version", "2022-11-28");
                        }
                        using (var response = await client.SendAsync(request, HttpCompletionOption.ResponseHeadersRead).ConfigureAwait(false))
                        {
                            int status = (int)response.StatusCode;
                            if (status >= 300 && status < 400)
                            {
                                if (response.Headers.Location == null) throw new IOException("Update redirect is missing its destination.");
                                url = new Uri(new Uri(url), response.Headers.Location).AbsoluteUri;
                                continue;
                            }
                            response.EnsureSuccessStatusCode();
                            if (response.Content.Headers.ContentLength > maxBytes) throw new InvalidDataException("Update download exceeds its expected size.");
                            using (var input = await response.Content.ReadAsStreamAsync().ConfigureAwait(false))
                            {
                                var buffer = new byte[65536]; long total = 0; int read;
                                while ((read = await input.ReadAsync(buffer, 0, buffer.Length).ConfigureAwait(false)) > 0)
                                {
                                    total += read;
                                    if (total > maxBytes) throw new InvalidDataException("Update download exceeds its expected size.");
                                    await destination.WriteAsync(buffer, 0, read).ConfigureAwait(false);
                                }
                            }
                            return;
                        }
                    }
                }
            }
            throw new IOException("Too many update redirects.");
        }

        static async Task<string> ReadText(string url, bool json)
        {
            using (var stream = new MemoryStream())
            {
                await Fetch(url, stream, 2 * 1024 * 1024, json).ConfigureAwait(false);
                return new UTF8Encoding(false, true).GetString(stream.ToArray());
            }
        }

        public static Task<UpdateCandidate> QueryModUpdateAsync(UpdateSource source, string installedVersion, string installedPackageHash = null)
        {
            return QueryCore(source, installedVersion, installedPackageHash, true);
        }

        public static bool NeedsUpdate(UpdateCandidate candidate, string installedVersion, string installedPackageHash)
        {
            if (candidate == null) return false;
            if (String.IsNullOrEmpty(installedVersion)) return true;
            int order = ParseVersion(candidate.Version).CompareTo(ParseVersion(installedVersion));
            return order > 0 || (order == 0 && !String.Equals(candidate.Sha256, installedPackageHash, StringComparison.OrdinalIgnoreCase));
        }

        static async Task<UpdateCandidate> QueryCore(UpdateSource source, string installedVersion, string installedPackageHash, bool sameVersion)
        {
            if (source == null) return null;
            ValidateSource(source);
            var current = String.IsNullOrEmpty(installedVersion) ? new Version(0, 0, 0, 0) : ParseVersion(installedVersion);
            var json = await ReadText("https://api.github.com/repos/" + source.Repository + "/releases?per_page=100", true).ConfigureAwait(false);
            var releases = Serializer().Deserialize<GitHubUpdateRelease[]>(json) ?? new GitHubUpdateRelease[0];
            var ordered = releases.Where(IsPublicRelease).Where(r => VersionFromTag(source, r.tag_name) != null)
                .OrderByDescending(r => ParseVersion(VersionFromTag(source, r.tag_name)));
            int inspected = 0;
            foreach (var release in ordered)
            {
                string version = VersionFromTag(source, release.tag_name);
                int order = ParseVersion(version).CompareTo(current);
                if (order < 0 || (order == 0 && !sameVersion)) continue;
                if (++inspected > 16) break;
                PublicUpdateManifest manifest = null; string checksums = null;
                var assets = release.assets ?? new GitHubUpdateAsset[0];
                if (source.ManifestAsset != null)
                {
                    var meta = assets.Where(a => a.name == source.ManifestAsset).ToArray();
                    if (meta.Length == 0) continue;
                    if (meta.Length != 1) throw new InvalidDataException("Ambiguous update manifest.");
                    manifest = Serializer().Deserialize<PublicUpdateManifest>(await ReadText(AssetUrl(meta[0], source, release), false).ConfigureAwait(false));
                    if (!PublicManifest(manifest)) continue;
                }
                if (source.Sha256Asset != null)
                {
                    var checksum = assets.Where(a => a.name == source.Sha256Asset).ToArray();
                    if (checksum.Length != 1) throw new InvalidDataException("The declared checksum asset is missing.");
                    checksums = await ReadText(AssetUrl(checksum[0], source, release), false).ConfigureAwait(false);
                }
                var candidate = ResolveCandidate(source, release, manifest, checksums);
                if (candidate != null && NeedsUpdate(candidate, installedVersion, installedPackageHash)) return candidate;
            }
            return null;
        }

        public static Task<UpdateCandidate> QueryManagerUpdateAsync(UpdateSource source, string currentVersion)
        {
            if (source == null) return Task.FromResult<UpdateCandidate>(null);
            if (source.Kind != "manager") throw new InvalidDataException("Manager updates require their own manager source.");
            return QueryCore(source, currentVersion, null, false);
        }

        public static string HashFile(string path)
        {
            using (var input = File.OpenRead(path)) using (var hash = SHA256.Create())
                return BitConverter.ToString(hash.ComputeHash(input)).Replace("-", "").ToLowerInvariant();
        }

        public static void VerifyFile(string path, UpdateCandidate candidate)
        {
            if (candidate == null || candidate.Size <= 0 || candidate.Size > MaximumPackageBytes ||
                NormalizeHash(candidate.Sha256) == null || new FileInfo(path).Length != candidate.Size ||
                !String.Equals(HashFile(path), candidate.Sha256, StringComparison.OrdinalIgnoreCase))
                throw new InvalidDataException("Update integrity verification failed. Installed files were not changed.");
        }

        public static async Task<string> DownloadVerified(UpdateCandidate candidate, string destination)
        {
            if (candidate == null || candidate.Size <= 0 || candidate.Size > MaximumPackageBytes ||
                NormalizeHash(candidate.Sha256) == null || !IsReleaseAssetUrl(candidate.Url, candidate.Repository, candidate.Tag))
                throw new InvalidDataException("The update candidate is not verifiable.");
            destination = Path.GetFullPath(destination);
            if (File.Exists(destination)) throw new IOException("Update staging file already exists.");
            EnsureUnlinked(Path.GetDirectoryName(destination));
            Directory.CreateDirectory(Path.GetDirectoryName(destination));
            var temporary = destination + "." + Guid.NewGuid().ToString("N") + ".partial";
            try
            {
                using (var file = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write, FileShare.None))
                    await Fetch(candidate.Url, file, candidate.Size, false).ConfigureAwait(false);
                VerifyFile(temporary, candidate);
                File.Move(temporary, destination);
                return destination;
            }
            finally { if (File.Exists(temporary)) File.Delete(temporary); }
        }

        static void EnsureUnlinked(string path)
        {
            var directory = new DirectoryInfo(Path.GetFullPath(path));
            while (directory != null)
            {
                if (directory.Exists && (directory.Attributes & FileAttributes.ReparsePoint) != 0)
                    throw new IOException("Update folders cannot be symbolic links or junctions.");
                directory = directory.Parent;
            }
        }

        public static StagedManagerUpdate ExtractManagerUpdate(string zip, string workDirectory, UpdateCandidate candidate)
        {
            if (candidate.Kind != "manager" || candidate.Size > MaximumManagerBytes) throw new InvalidDataException("Not a manager update.");
            VerifyFile(zip, candidate);
            workDirectory = Path.GetFullPath(workDirectory);
            EnsureUnlinked(workDirectory);
            Directory.CreateDirectory(workDirectory);
            string executable = Path.Combine(workDirectory, ManagerExecutableName);
            using (var archive = ZipFile.OpenRead(zip))
            {
                if (archive.Entries.Count != 1) throw new InvalidDataException("A manager update must contain only its executable.");
                var entry = archive.Entries[0];
                if (entry.FullName != ManagerExecutableName || entry.Length < 64 || entry.Length > MaximumManagerBytes ||
                    ((entry.ExternalAttributes >> 16) & 0xF000) == 0xA000)
                    throw new InvalidDataException("Invalid manager update archive.");
                entry.ExtractToFile(executable, false);
            }
            using (var file = File.OpenRead(executable))
                if (file.ReadByte() != 'M' || file.ReadByte() != 'Z') throw new InvalidDataException("Manager update is not a Windows executable.");
            return new StagedManagerUpdate { ExecutablePath = executable, Sha256 = HashFile(executable), Version = candidate.Version, WorkDirectory = workDirectory };
        }

        public static async Task<StagedManagerUpdate> StageManagerUpdateAsync(UpdateCandidate candidate, string stagingRoot)
        {
            if (candidate == null || candidate.Kind != "manager" || candidate.Size > MaximumManagerBytes) throw new InvalidDataException("Not a manager update.");
            stagingRoot = Path.GetFullPath(stagingRoot); EnsureUnlinked(stagingRoot);
            var work = Path.Combine(stagingRoot, Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(work);
            string zip = await DownloadVerified(candidate, Path.Combine(work, "manager-update.zip")).ConfigureAwait(false);
            return ExtractManagerUpdate(zip, work, candidate);
        }

        // Called only after the UI's explicit update action. The UI must then exit.
        public static void BeginManagerUpdate(StagedManagerUpdate staged, string currentExe)
        {
            if (staged == null) throw new InvalidDataException("Missing staged manager update.");
            currentExe = Path.GetFullPath(currentExe);
            string work = Path.GetFullPath(staged.WorkDirectory).TrimEnd(Path.DirectorySeparatorChar);
            string candidate = Path.GetFullPath(staged.ExecutablePath);
            EnsureUnlinked(work); EnsureUnlinked(Path.GetDirectoryName(currentExe));
            var process = Process.GetCurrentProcess();
            if (!String.Equals(currentExe, Path.GetFullPath(process.MainModule.FileName), StringComparison.OrdinalIgnoreCase) ||
                !String.Equals(candidate, Path.Combine(work, ManagerExecutableName), StringComparison.OrdinalIgnoreCase) ||
                Path.GetFileName(currentExe) != ManagerExecutableName || HashFile(candidate) != NormalizeHash(staged.Sha256))
                throw new InvalidDataException("Manager update target or staged hash changed.");
            var plan = new { process = process.Id, started = process.StartTime.ToUniversalTime().Ticks.ToString(),
                target = currentExe, candidate = candidate, sha256 = staged.Sha256, original = HashFile(currentExe),
                nonce = Guid.NewGuid().ToString("N") };
            string settings = Path.Combine(work, "apply-update.json"), script = Path.Combine(work, "apply-update.ps1");
            File.WriteAllText(settings, Serializer().Serialize(plan), new UTF8Encoding(false));
            File.WriteAllText(script, ApplyScript, new UTF8Encoding(false));
            var executable = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), @"WindowsPowerShell\v1.0\powershell.exe");
            Process.Start(new ProcessStartInfo(executable, "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File \"" + script + "\" -Settings \"" + settings + "\"")
            { UseShellExecute = false, CreateNoWindow = true, WindowStyle = ProcessWindowStyle.Hidden });
        }

        internal const string ApplyScript = @"param([Parameter(Mandatory=$true)][string]$Settings)
$ErrorActionPreference='Stop'
$change=Get-Content -LiteralPath $Settings -Raw | ConvertFrom-Json
$workspace=[IO.Path]::GetFullPath($PSScriptRoot).TrimEnd('\')
$target=[IO.Path]::GetFullPath($change.target)
$candidate=[IO.Path]::GetFullPath($change.candidate)
if($candidate -ne (Join-Path $workspace 'Beyond Mod Manager.exe') -or [IO.Path]::GetFileName($target) -ne 'Beyond Mod Manager.exe' -or $change.nonce -notmatch '^[a-f0-9]{32}$'){throw 'Invalid update paths.'}
foreach($path in @($workspace,[IO.Path]::GetDirectoryName($target))){$dir=Get-Item -LiteralPath $path;while($null -ne $dir){if($dir.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Linked update path.'};$dir=$dir.Parent}}
if((Get-FileHash -LiteralPath $candidate -Algorithm SHA256).Hash -ne $change.sha256){throw 'Staged update changed.'}
$running=Get-Process -Id $change.process -ErrorAction SilentlyContinue
if($null -ne $running -and $running.StartTime.ToUniversalTime().Ticks.ToString() -eq $change.started){Wait-Process -Id $change.process -Timeout 120 -ErrorAction Stop}
if((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash -ne $change.original){throw 'Current manager changed; update cancelled.'}
$incoming=$target+'.'+$change.nonce+'.new'
$rollback=$target+'.'+$change.nonce+'.previous'
$failed=$target+'.'+$change.nonce+'.failed'
$replaced=$false
try {
 Copy-Item -LiteralPath $candidate -Destination $incoming -ErrorAction Stop
 if((Get-FileHash -LiteralPath $incoming -Algorithm SHA256).Hash -ne $change.sha256){throw 'Copied update changed.'}
 [IO.File]::Replace($incoming,$target,$rollback)
 $replaced=$true
 if((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash -ne $change.sha256){throw 'Installed update verification failed.'}
 Start-Process -FilePath $target -WorkingDirectory ([IO.Path]::GetDirectoryName($target)) -WindowStyle Hidden -ErrorAction Stop
} catch {
 if($replaced -and (Test-Path -LiteralPath $rollback)){[IO.File]::Replace($rollback,$target,$failed)}
 $_ | Out-String | Set-Content -LiteralPath (Join-Path $workspace 'update-error.txt')
 throw
} finally {if(Test-Path -LiteralPath $incoming){Remove-Item -LiteralPath $incoming}}
";
    }
}
