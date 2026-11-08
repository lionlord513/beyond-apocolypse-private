using System;
using System.IO;
using System.Reflection;
using System.Web.Script.Serialization;
using BeyondModManager;

// Explicit, read-only live-service check. Stages downloads only in the supplied fixture.
class LiveUpdateProbe
{
    static void Main(string[] args)
    {
        var assembly = typeof(Program).Assembly;
        PublicCatalog catalog;
        using (var reader = new StreamReader(assembly.GetManifestResourceStream("bmm-public.json")))
            catalog = new JavaScriptSerializer().Deserialize<PublicCatalog>(reader.ReadToEnd());
        var current = args[0]; var expected = args[1]; var root = Path.GetFullPath(args[2]);
        var candidate = Updates.QueryManagerUpdateAsync(catalog.Update, current).GetAwaiter().GetResult();
        if (candidate == null || candidate.Version != expected) throw new Exception("Expected update " + expected);
        Console.WriteLine("PASS BMM " + Program.ManagerVersion + " updater discovers " + expected + " from " + current);
        var staged = Updates.StageManagerUpdateAsync(candidate, root).GetAwaiter().GetResult();
        if (staged.Sha256 != Updates.HashFile(args[3])) throw new Exception("Published EXE differs from tested build");
        Console.WriteLine("PASS live manifest, ZIP and extracted EXE match the tested release");
        if (Updates.QueryManagerUpdateAsync(catalog.Update, expected).GetAwaiter().GetResult() != null)
            throw new Exception("Current manager offered itself as an update");
        Console.WriteLine("PASS current version is not offered its own update");
        // Reflection keeps this probe usable with the unmodified 1.0.8/1.0.9 client.
        var alternate = typeof(UpdateCandidate).GetProperty("AlternateUrl");
        if (alternate != null)
        {
            candidate.Url = (string)alternate.GetValue(candidate, null);
            if (String.IsNullOrEmpty(candidate.Url)) throw new Exception("Live release has no alternate asset route");
            alternate.SetValue(candidate, null, null);
            var apiStage = Updates.StageManagerUpdateAsync(candidate, root).GetAwaiter().GetResult();
            if (apiStage.Sha256 != staged.Sha256) throw new Exception("API route returned different bytes");
            Console.WriteLine("PASS anonymous alternate GitHub API asset route delivers the same verified EXE");
        }
    }
}
