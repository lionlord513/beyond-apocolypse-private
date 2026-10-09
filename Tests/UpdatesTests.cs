using System;
using System.IO;
using System.IO.Compression;
using System.Text;
using BeyondModManager;

public static class UpdatesTests
{
    static int checks;
    static void Assert(bool value, string label) { checks++; if (!value) throw new Exception(label); }
    static void Reject(Action operation, string label)
    {
        try { operation(); } catch (InvalidDataException) { checks++; return; }
        throw new Exception("Accepted " + label);
    }
    static GitHubUpdateRelease Release(string tag, string file, string hash, long size)
    {
        return new GitHubUpdateRelease { tag_name = tag, name = "Public release", body = "Public changes.",
            assets = new[] { new GitHubUpdateAsset { name = file, size = size, digest = "sha256:" + hash,
                state = "uploaded", browser_download_url = "https://github.com/example/public-mod/releases/download/" + tag + "/" + file } } };
    }
    public static int Run()
    {
        string temporary = Path.Combine(Path.GetTempPath(), "BMM-UpdateTests-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(temporary);
        try
        {
            Assert(Updates.ParseVersion("0.9.3.1") > Updates.ParseVersion("0.9.3"), "Four-part versions");
            Assert(Updates.ParseVersion("1.2") == Updates.ParseVersion("1.2.0.0"), "Canonical numeric comparison");
            Assert(Updates.ParseVersion("1.10.0") > Updates.ParseVersion("1.9.99"), "Numeric rather than lexical ordering");
            foreach (var invalid in new[] { "v1.0.0", "1.0.0-preview", "1.0.0.0.1", "../1.0", "99999999999.0" })
                Reject(() => Updates.ParseVersion(invalid), "bad version");
            Assert(Updates.QueryModUpdateAsync(null, "1.0.0").Result == null, "Missing metadata never queries network");
            Assert(Updates.QueryManagerUpdateAsync(null, "1.0.0").Result == null, "Missing manager feed disabled");
            foreach (var bad in new[] { "http://github.com/example/public-mod", "https://github.com.evil.test/file", "https://user:pass@github.com/file", "https://github.com:8443/file", "file:///C:/temp/file", "https://evil.test/file", "https://github.com/file#fragment" })
                Assert(!Updates.IsAllowedUrl(bad), "Reject URL " + bad);
            Assert(Updates.IsAllowedUrl("https://release-assets.githubusercontent.com/release/file?signature=123"), "GitHub asset redirects");
            var source = new UpdateSource { Provider = "github", Repository = "example/public-mod", AssetPattern = "Mod-{version}.zip" };
            Updates.ValidateSource(source);
            Reject(() => Updates.ValidateSource(new UpdateSource { Provider = "github", Repository = "../escape", AssetPattern = "x.zip" }), "bad repo");
            Reject(() => Updates.ValidateSource(new UpdateSource { Provider = "github", Repository = "example/public-mod", AssetPattern = "../x.zip" }), "asset traversal");
            string hash = new string('a', 64), otherHash = new string('b', 64);
            var release = Release("v0.9.3.1", "Mod-0.9.3.1.zip", hash, 123);
            Assert(Updates.ResolveCandidate(source, release, null, null).Version == "0.9.3.1", "Generic verified GitHub digest");
            var currentCandidate = Updates.ResolveCandidate(source, release, null, null);
            Assert(currentCandidate.Url.EndsWith("?bmm_revision=sha256-" + hash), "ZIP URL bound to validated API digest");
            var replacement = Release("v0.9.3.1", "Mod-0.9.3.1.zip", otherHash, 124);
            Assert(Updates.ResolveCandidate(source, replacement, null, null).Url != currentCandidate.Url, "Same-version replacement gets a distinct ZIP cache key");
            Assert(Updates.ResolveCandidate(source, release, null, null).Url == currentCandidate.Url, "Unchanged asset revision has a stable cache key");
            var metadata = new GitHubUpdateAsset { id = 123, name = "release.json", digest = "sha256:" + hash, browser_download_url = "https://github.com/example/public-mod/releases/download/v0.9.3.1/release.json" };
            string oldMetadataUrl = Updates.AssetUrl(metadata, source, release);
            metadata.digest = "sha256:" + otherHash;
            Assert(Updates.AssetUrl(metadata, source, release) != oldMetadataUrl && Updates.AssetUrl(metadata, source, release).EndsWith("sha256-" + otherHash), "Replacement metadata bypasses cached previous manifest");
            metadata.digest = null; string oldIdUrl = Updates.AssetUrl(metadata, source, release); metadata.id = 124;
            Assert(oldIdUrl.EndsWith("bmm_revision=id-123") && Updates.AssetUrl(metadata, source, release).EndsWith("bmm_revision=id-124"), "Metadata uses stable GitHub asset id when API digest is absent");
            metadata.browser_download_url += "?download=1&bmm_revision=old";
            var revisedUrl = Updates.AssetUrl(metadata, source, release);
            Assert(revisedUrl.Contains("download=1&bmm_revision=id-124") && !revisedUrl.Contains("bmm_revision=old"), "Revision query replaces stale token and preserves other query parameters");
            metadata.id = 0; Reject(() => Updates.AssetUrl(metadata, source, release), "metadata without revision identifier");
            metadata.id = 124; metadata.digest = "sha256:invalid"; Reject(() => Updates.AssetUrl(metadata, source, release), "malformed asset digest revision");
            metadata.digest = null; metadata.browser_download_url = "https://github.com/other/repository/releases/download/v0.9.3.1/release.json";
            Reject(() => Updates.AssetUrl(metadata, source, release), "revision URL from another repository");
            Assert(!Updates.NeedsUpdate(currentCandidate, "0.9.3.1", hash), "Matching same-version package stays current");
            Assert(Updates.NeedsUpdate(currentCandidate, "0.9.3.1", otherHash), "Same-version hotfix detected by digest");
            Assert(Updates.NeedsUpdate(currentCandidate, "0.9.3.1", null), "Unknown installed digest offers verified repair");
            Assert(!Updates.NeedsUpdate(currentCandidate, "0.9.4", otherHash), "Never downgrade a newer installed version");
            release.draft = true; Assert(Updates.ResolveCandidate(source, release, null, null) == null, "Draft excluded"); release.draft = false;
            release.prerelease = true; Assert(Updates.ResolveCandidate(source, release, null, null) == null, "Prerelease excluded"); release.prerelease = false;
            foreach (string label in new[] { "private release", "alpha test", "dev build", "NDA", "confidential" })
            { release.name = label; Assert(!Updates.IsPublicRelease(release), "Restricted release excluded"); }
            release.name = "Public release";
            release.body = "Private co-op support."; Assert(Updates.IsPublicRelease(release), "Ordinary gameplay description accepted");
            release.body = "Private build."; Assert(!Updates.IsPublicRelease(release), "Private build notes excluded"); release.body = "Public changes.";
            release.assets[0].browser_download_url = "https://github.com/other/repo/releases/download/v0.9.3.1/Mod-0.9.3.1.zip";
            Reject(() => Updates.ResolveCandidate(source, release, null, null), "asset from another repository");
            release = Release("v0.9.3.1", "Mod-0.9.3.1.zip", hash, 123);
            release.assets[0].digest = null;
            Reject(() => Updates.ResolveCandidate(source, release, null, null), "unverifiable digest");
            source.Sha256Asset = "SHA256SUMS";
            Assert(Updates.ResolveCandidate(source, release, null, hash + "  Mod-0.9.3.1.zip").Sha256 == hash, "Exact checksum fallback");
            Assert(Updates.ResolveCandidate(source, release, null, hash + "  Mod-0.9.3.1.zip").Url.EndsWith("bmm_revision=sha256-" + hash), "Verified checksum binds fallback ZIP revision");
            Reject(() => Updates.ReadChecksum(hash + "  other.zip", "Mod-0.9.3.1.zip"), "checksum for unrelated file");
            Reject(() => Updates.ReadChecksum(hash + "  Mod-0.9.3.1.zip\n" + otherHash + "  Mod-0.9.3.1.zip", "Mod-0.9.3.1.zip"), "ambiguous checksum");
            source.Sha256Asset = null; source.ManifestAsset = "release.json"; source.Kind = "beyond-apocolypse";
            var manifest = new PublicUpdateManifest { schema = 1, version = "0.9.3.1", channel = "beta", size = 123, sha256 = hash, notes = new[] { "Public changes." } };
            Assert(Updates.ResolveCandidate(source, release, manifest, null) != null, "Approved public beta");
            manifest.channel = "stable"; Assert(Updates.ResolveCandidate(source, release, manifest, null) != null, "Approved public stable");
            manifest.channel = "alpha"; Assert(Updates.ResolveCandidate(source, release, manifest, null) == null, "Restricted channel excluded");
            manifest.channel = "beta"; manifest.version = "0.9.3.2";
            Reject(() => Updates.ResolveCandidate(source, release, manifest, null), "manifest tag mismatch"); manifest.version = "0.9.3.1";
            release.assets[0].digest = "sha256:" + otherHash;
            Reject(() => Updates.ResolveCandidate(source, release, manifest, null), "API manifest digest mismatch");
            release.assets[0].digest = "sha256:" + hash; manifest.size = 124;
            Reject(() => Updates.ResolveCandidate(source, release, manifest, null), "API manifest size mismatch"); manifest.size = 123;
            source.AssetPattern = null; manifest.url = release.assets[0].browser_download_url;
            Assert(Updates.ResolveCandidate(source, release, manifest, null).AssetName == "Mod-0.9.3.1.zip", "Legacy manifest selects listed asset");
            manifest.url = "https://evil.test/update.zip";
            Reject(() => Updates.ResolveCandidate(source, release, manifest, null), "untrusted manifest URL");
            string file = Path.Combine(temporary, "download.zip"); File.WriteAllText(file, "verified content");
            var candidate = new UpdateCandidate { Sha256 = Updates.HashFile(file), Size = new FileInfo(file).Length };
            Updates.VerifyFile(file, candidate); checks++;
            File.WriteAllText(file, "tampered content"); Reject(() => Updates.VerifyFile(file, candidate), "changed update file");
            string managerZip = Path.Combine(temporary, "manager.zip");
            using (var archive = ZipFile.Open(managerZip, ZipArchiveMode.Create))
            using (var stream = archive.CreateEntry(Updates.ManagerExecutableName).Open())
            { var bytes = new byte[100]; bytes[0] = (byte)'M'; bytes[1] = (byte)'Z'; stream.Write(bytes, 0, bytes.Length); }
            candidate = new UpdateCandidate { Version = "1.1.0", Kind = "manager", Sha256 = Updates.HashFile(managerZip), Size = new FileInfo(managerZip).Length };
            var staged = Updates.ExtractManagerUpdate(managerZip, Path.Combine(temporary, "staged"), candidate);
            Assert(File.Exists(staged.ExecutablePath) && staged.Sha256 == Updates.HashFile(staged.ExecutablePath), "Verified manager stage");
            string badZip = Path.Combine(temporary, "bad.zip");
            using (var archive = ZipFile.Open(badZip, ZipArchiveMode.Create))
            using (var writer = new StreamWriter(archive.CreateEntry("../Beyond Mod Manager.exe").Open())) writer.Write(new string('x', 100));
            candidate = new UpdateCandidate { Kind = "manager", Sha256 = Updates.HashFile(badZip), Size = new FileInfo(badZip).Length };
            Reject(() => Updates.ExtractManagerUpdate(badZip, Path.Combine(temporary, "bad-stage"), candidate), "manager ZIP traversal");
            Console.WriteLine("PASS: " + checks + " update validation checks (offline; no game files or network changed).");
            return 0;
        }
        finally
        {
            string root = Path.GetFullPath(Path.GetTempPath()).TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar;
            if (Path.GetFullPath(temporary).StartsWith(root, StringComparison.OrdinalIgnoreCase) && Path.GetFileName(temporary).StartsWith("BMM-UpdateTests-")) Directory.Delete(temporary, true);
        }
    }
#if UPDATE_TEST_STANDALONE
    public static int Main() { return Run(); }
#endif
}
