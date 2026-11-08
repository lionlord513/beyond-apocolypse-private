using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Net;
using System.Net.Http;
using System.Threading;
using System.Threading.Tasks;
using BeyondModManager;

class UpdateTransportTests
{
    const string Url = "https://github.com/example/mod/releases/download/v1.0/test.zip";
    const string Alternate = "https://api.github.com/repos/example/mod/releases/assets/123";
    static readonly byte[] Payload = Enumerable.Range(0, 80).Select(i => (byte)i).ToArray();
    static int checks;
    static void Assert(bool ok, string label) { if (!ok) throw new Exception(label); checks++; Console.WriteLine("PASS " + label); }
    static T Reject<T>(Action action) where T : Exception { try { action(); } catch (T error) { return error; } throw new Exception("Expected " + typeof(T).Name); }
    sealed class Handler : HttpMessageHandler
    {
        internal Func<HttpRequestMessage, int, Task<HttpResponseMessage>> Reply;
        internal readonly List<string> Urls = new List<string>();
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            if (request.Headers.Authorization != null) throw new Exception("Unexpected credentials");
            Urls.Add(request.RequestUri.AbsoluteUri); return Reply(request, Urls.Count);
        }
    }
    static Handler Responses(Func<HttpRequestMessage, int, HttpResponseMessage> reply)
    { return new Handler { Reply = (request, number) => Task.FromResult(reply(request, number)) }; }
    static HttpResponseMessage Status(int status) { return new HttpResponseMessage((HttpStatusCode)status); }
    static HttpResponseMessage Ok(byte[] bytes = null) { return new HttpResponseMessage(HttpStatusCode.OK) { Content = new ByteArrayContent(bytes ?? Payload) }; }
    static UpdateTransport Transport(Handler handler, List<TimeSpan> waits = null, bool shortTimeout = false)
    {
        return new UpdateTransport(handler, wait => { if (waits != null) waits.Add(wait); return Task.FromResult(0); },
            TimeSpan.FromMilliseconds(shortTimeout ? 100 : 2000), TimeSpan.FromMilliseconds(shortTimeout ? 150 : 2000), TimeSpan.FromMilliseconds(shortTimeout ? 60 : 2000));
    }
    static void Fetch(UpdateTransport transport, Stream target, string alternate = null, bool exact = false)
    { transport.Fetch(Url, target, Payload.Length, false, alternate, exact).GetAwaiter().GetResult(); }
    sealed class BrokenStream : MemoryStream
    {
        readonly bool stalls, drips;
        int reads;
        internal bool Closed;
        internal BrokenStream(bool stall = false, bool drip = false) : base(Payload) { stalls = stall; drips = drip; }
        public override bool CanSeek { get { return false; } }
        public override async Task<int> ReadAsync(byte[] buffer, int offset, int count, CancellationToken token)
        {
            if (stalls) return await new TaskCompletionSource<int>().Task;
            if (drips) { await Task.Delay(20); buffer[offset] = 1; return 1; }
            if (reads++ == 0) { Array.Copy(Payload, 0, buffer, offset, 7); return 7; }
            throw new IOException("Simulated socket reset");
        }
        protected override void Dispose(bool disposing) { Closed = true; base.Dispose(disposing); }
    }
    sealed class FullDisk : MemoryStream
    {
        public override Task WriteAsync(byte[] bytes, int offset, int count, CancellationToken token)
        { throw new IOException("Simulated disk full"); }
    }
    static void Main()
    {
        foreach (int status in new[] { 408, 429, 500, 502, 503, 504 })
        {
            var waits = new List<TimeSpan>();
            var handler = Responses((request, number) => { if (number > 1) return Ok(); var r = Status(status); if (status == 429) r.Headers.RetryAfter = new System.Net.Http.Headers.RetryConditionHeaderValue(TimeSpan.FromSeconds(3)); return r; });
            using (var transport = Transport(handler, waits)) using (var target = new MemoryStream())
            {
                Fetch(transport, target); Assert(handler.Urls.Count == 2 && target.ToArray().SequenceEqual(Payload), "recovers from HTTP " + status);
                Assert(waits.Count == 1 && waits[0].TotalSeconds >= (status == 429 ? 3 : 2), "backs off before retrying HTTP " + status);
            }
        }
        var failed = Responses((r, n) => Status(504));
        using (var transport = Transport(failed)) using (var target = new MemoryStream())
        {
            var error = Reject<UpdateConnectionException>(() => Fetch(transport, target));
            Assert(failed.Urls.Count == 3 && target.Length == 0 && error.Message.Contains("504") && error.Message.Contains("3 attempts"), "persistent 504 stops after three attempts with an actionable error");
        }
        foreach (int status in new[] { 401, 403, 404, 410 })
        {
            var handler = Responses((r, n) => Status(status));
            using (var transport = Transport(handler)) using (var target = new MemoryStream())
            { var error = Reject<UpdateConnectionException>(() => Fetch(transport, target, Alternate)); Assert(handler.Urls.Count == 1 && !error.CanRetry, "HTTP " + status + " does not retry or bypass via alternate route"); }
        }
        foreach (bool resetHeader in new[] { false, true })
        {
            var handler = Responses((r, n) => { var response = Status(resetHeader ? 403 : 429);
                if (resetHeader) { response.Headers.Add("X-RateLimit-Remaining", "0"); response.Headers.Add("X-RateLimit-Reset", ((long)(DateTimeOffset.UtcNow.AddMinutes(5) - new DateTimeOffset(1970,1,1,0,0,0,TimeSpan.Zero)).TotalSeconds).ToString()); }
                else response.Headers.RetryAfter = new System.Net.Http.Headers.RetryConditionHeaderValue(TimeSpan.FromSeconds(90)); return response; });
            using (var transport = Transport(handler)) using (var target = new MemoryStream())
            { var error = Reject<UpdateConnectionException>(() => Fetch(transport, target, Alternate)); Assert(handler.Urls.Count == 1 && error.Message.Contains("Wait at least"), "honors long " + (resetHeader ? "GitHub rate reset" : "Retry-After") + " without early requests"); }
        }
        var fallback = Responses((request, n) => { if (n < 3) return Status(504); if (!request.Headers.Accept.Any(h => h.MediaType == "application/octet-stream")) throw new Exception("Missing asset Accept header"); return Ok(); });
        using (var transport = Transport(fallback)) using (var target = new MemoryStream())
        { Fetch(transport, target, Alternate); Assert(fallback.Urls.SequenceEqual(new[] { Url, Url, Alternate }) && target.ToArray().SequenceEqual(Payload), "uses the same asset's GitHub API route after download-route failures"); }
        var broken = new BrokenStream();
        var redirects = Responses((r, n) => {
            if (n == 1 || n == 3) { var response = Status(302); response.Headers.Location = new Uri("https://release-assets.githubusercontent.com/file?signature=" + n); return response; }
            return n == 2 ? new HttpResponseMessage(HttpStatusCode.OK) { Content = new StreamContent(broken) } : Ok(); });
        using (var transport = Transport(redirects)) using (var target = new MemoryStream())
        { Fetch(transport, target); Assert(redirects.Urls[2] == Url && redirects.Urls[3].EndsWith("signature=3") && target.ToArray().SequenceEqual(Payload) && broken.Closed, "partial transfer restarts cleanly with a fresh signed redirect"); }
        var shortRead = Responses((r, n) => { if (n > 1) return Ok(); var response = Ok(new byte[9]); response.Content.Headers.ContentLength = Payload.Length; return response; });
        using (var transport = Transport(shortRead)) using (var target = new MemoryStream())
        { Fetch(transport, target); Assert(shortRead.Urls.Count == 2 && target.ToArray().SequenceEqual(Payload), "truncated Content-Length response recovers"); }
        var shortPackage = Responses((r, n) => n == 1 ? Ok(new byte[10]) : Ok());
        using (var transport = Transport(shortPackage)) using (var target = new MemoryStream())
        { Fetch(transport, target, null, true); Assert(shortPackage.Urls.Count == 2 && target.ToArray().SequenceEqual(Payload), "expected package size detects a prematurely ended response"); }
        foreach (bool drip in new[] { false, true })
        {
            var streams = new List<BrokenStream>();
            var handler = Responses((r, n) => { var stream = new BrokenStream(!drip, drip); streams.Add(stream); return new HttpResponseMessage(HttpStatusCode.OK) { Content = new StreamContent(stream) }; });
            var clock = Stopwatch.StartNew();
            using (var transport = Transport(handler, null, true)) using (var target = new MemoryStream())
            { Reject<UpdateConnectionException>(() => Fetch(transport, target)); Assert(clock.Elapsed < TimeSpan.FromSeconds(3) && handler.Urls.Count == 3 && streams.All(s => s.Closed) && target.Length == 0, drip ? "total deadline bounds a slow trickle" : "idle deadline bounds a body that ignores cancellation"); }
        }
        var stalledHeaders = new Handler { Reply = (r, n) => new TaskCompletionSource<HttpResponseMessage>().Task };
        using (var transport = Transport(stalledHeaders, null, true)) using (var target = new MemoryStream())
        { var clock = Stopwatch.StartNew(); Reject<UpdateConnectionException>(() => Fetch(transport, target)); Assert(stalledHeaders.Urls.Count == 3 && clock.Elapsed < TimeSpan.FromSeconds(3), "header deadline bounds an unresponsive server"); }
        var connection = new Handler { Reply = (r, n) => { if (n == 1) throw new HttpRequestException("Reset"); return Task.FromResult(Ok()); } };
        using (var transport = Transport(connection)) using (var target = new MemoryStream())
        { Fetch(transport, target); Assert(connection.Urls.Count == 2 && target.ToArray().SequenceEqual(Payload), "transient connection failure recovers"); }
        var tls = new Handler { Reply = (r, n) => { throw new HttpRequestException("TLS", new WebException("Certificate", WebExceptionStatus.TrustFailure)); } };
        using (var transport = Transport(tls)) using (var target = new MemoryStream())
        { Reject<UpdateConnectionException>(() => Fetch(transport, target)); Assert(tls.Urls.Count == 1, "certificate failures are not bypassed or retried"); }
        var malicious = Responses((r, n) => { var response = Status(302); response.Headers.Location = new Uri("https://untrusted.invalid/payload"); return response; });
        using (var transport = Transport(malicious)) using (var target = new MemoryStream())
        { Reject<InvalidDataException>(() => Fetch(transport, target)); Assert(malicious.Urls.Count == 1, "unapproved redirect is rejected before requesting it"); }
        var loop = Responses((r, n) => { var response = Status(302); response.Headers.Location = new Uri(Url); return response; });
        using (var transport = Transport(loop)) using (var target = new MemoryStream())
        { Reject<InvalidDataException>(() => Fetch(transport, target)); Assert(loop.Urls.Count == 6, "redirect loops have a hard limit"); }
        foreach (bool header in new[] { false, true })
        {
            var oversize = Responses((r, n) => { var response = Ok(new byte[90]); if (!header) response.Content.Headers.ContentLength = 50; return response; });
            using (var transport = Transport(oversize)) using (var target = new MemoryStream())
            { Reject<InvalidDataException>(() => Fetch(transport, target)); Assert(oversize.Urls.Count == 1, "oversized " + (header ? "Content-Length" : "body") + " fails without retries"); }
        }
        var disk = Responses((r, n) => Ok());
        using (var transport = Transport(disk)) using (var target = new FullDisk())
        { var error = Reject<IOException>(() => Fetch(transport, target)); Assert(error.Message == "Simulated disk full" && disk.Urls.Count == 1, "local disk errors are not retried as network errors"); }

        string root = Path.Combine(Path.GetTempPath(), "BMM-TransportTests-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        try
        {
            var sentinel = Path.Combine(root, "installed.exe"); File.WriteAllBytes(sentinel, Payload);
            var destination = Path.Combine(root, "update.zip");
            var candidate = new UpdateCandidate { Url = Url, AlternateUrl = Alternate, Repository = "example/mod", Tag = "v1.0", Sha256 = Updates.HashFile(sentinel), Size = Payload.Length };
            foreach (bool corrupt in new[] { false, true })
            {
                var handler = Responses((r, n) => corrupt ? Ok(new byte[Payload.Length]) : Status(504));
                using (var transport = Transport(handler))
                {
                    Action download = () => Updates.DownloadVerified(candidate, destination, transport).GetAwaiter().GetResult();
                    if (corrupt) Reject<InvalidDataException>(download); else Reject<UpdateConnectionException>(download);
                    Assert(!File.Exists(destination) && !Directory.GetFiles(root, "*.partial").Any() && Updates.HashFile(sentinel) == candidate.Sha256, (corrupt ? "bad hash" : "persistent 504") + " leaves installed bytes intact and removes partial staging");
                    if (corrupt) Assert(handler.Urls.Count == 1, "hash mismatch never bypasses verification or retries");
                }
            }
            var recovery = Responses((r, n) => n == 1 ? Status(504) : Ok());
            using (var transport = Transport(recovery))
            { Updates.DownloadVerified(candidate, destination, transport).GetAwaiter().GetResult(); Assert(Updates.HashFile(destination) == candidate.Sha256 && !Directory.GetFiles(root, "*.partial").Any(), "verified package is promoted only after successful retry and hash check"); }
            var invalid = Responses((r, n) => Ok());
            candidate.AlternateUrl = "https://api.github.com/repos/other/repository/releases/assets/1";
            using (var transport = Transport(invalid))
            { Reject<InvalidDataException>(() => Updates.DownloadVerified(candidate, Path.Combine(root, "invalid.zip"), transport).GetAwaiter().GetResult()); Assert(invalid.Urls.Count == 0, "alternate asset cannot cross repositories"); }
        }
        finally
        {
            var allowed = Path.GetFullPath(Path.GetTempPath()).TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar;
            if (Path.GetFullPath(root).StartsWith(allowed, StringComparison.OrdinalIgnoreCase) && Path.GetFileName(root).StartsWith("BMM-TransportTests-")) Directory.Delete(root, true);
        }
        Console.WriteLine("PASS: " + checks + " update transport and recovery checks; no live services or game files changed.");
    }
}
