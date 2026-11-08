using System;
using System.IO;
using System.Linq;
using System.Net;
using System.Net.Http;
using System.Threading;
using System.Threading.Tasks;

namespace BeyondModManager
{
    internal sealed class UpdateConnectionException : IOException
    {
        internal readonly bool CanRetry;
        internal UpdateConnectionException(string message, Exception inner, bool canRetry = true) : base(message, inner) { CanRetry = canRetry; }
    }

    // One instance per transfer. No credentials, global test hooks or unchecked mirrors.
    internal sealed class UpdateTransport : IDisposable
    {
        readonly HttpClient client;
        readonly Func<TimeSpan, Task> delay;
        readonly TimeSpan metadataTimeout, packageTimeout, idleTimeout;
        readonly Random jitter = new Random();
        const int Attempts = 3;

        internal UpdateTransport() : this(new HttpClientHandler { AllowAutoRedirect = false },
            wait => Task.Delay(wait), TimeSpan.FromSeconds(20), TimeSpan.FromHours(1), TimeSpan.FromSeconds(30)) { }

        internal UpdateTransport(HttpMessageHandler handler, Func<TimeSpan, Task> wait,
            TimeSpan metadataLimit, TimeSpan packageLimit, TimeSpan idleLimit)
        {
            ServicePointManager.SecurityProtocol |= SecurityProtocolType.Tls12;
            client = new HttpClient(handler) { Timeout = Timeout.InfiniteTimeSpan };
            delay = wait; metadataTimeout = metadataLimit; packageTimeout = packageLimit; idleTimeout = idleLimit;
        }

        sealed class Failure : Exception
        {
            internal readonly bool Retry;
            internal readonly TimeSpan? Wait;
            internal Failure(string message, bool retry, TimeSpan? wait = null, Exception inner = null)
                : base(message, inner) { Retry = retry; Wait = wait; }
        }

        internal async Task Fetch(string original, Stream destination, long maxBytes, bool json, string alternate = null, bool exactSize = false)
        {
            if (!Updates.IsAllowedUrl(original) || (alternate != null && !Updates.IsAllowedUrl(alternate)))
                throw new InvalidDataException("Update downloads require an approved HTTPS GitHub host.");
            if (!destination.CanSeek || !destination.CanWrite || destination.Position != 0 || destination.Length != 0)
                throw new InvalidOperationException("Updates must download into an empty staging stream.");
            for (int attempt = 1; attempt <= Attempts; attempt++)
            {
                // Restart from the original URL to obtain a fresh signed redirect. Never append
                // a second response to a partial file, or retry a stale CDN signature directly.
                destination.SetLength(0); destination.Position = 0;
                TimeSpan backoff;
                try
                {
                    await FetchOnce(attempt == Attempts && alternate != null ? alternate : original,
                        destination, maxBytes, json, exactSize).ConfigureAwait(false);
                    return;
                }
                catch (Failure error)
                {
                    destination.SetLength(0); destination.Position = 0;
                    // Long rate limits are reported, not shortened or bypassed via another route.
                    if (!error.Retry || attempt == Attempts || error.Wait > TimeSpan.FromSeconds(10))
                    {
                        string retry = error.Wait.HasValue ? " Wait at least " + Math.Ceiling(error.Wait.Value.TotalSeconds) + " seconds before retrying." : " Try again shortly, or download the latest BMM ZIP from its release page.";
                        throw new UpdateConnectionException("Update request failed after " + attempt + (attempt == 1 ? " attempt: " : " attempts: ") +
                            error.Message + ". Installed files were not changed." + retry, error, error.Retry);
                    }
                    backoff = TimeSpan.FromMilliseconds(1000 * Math.Pow(2, attempt) + jitter.Next(0, 251));
                    if (error.Wait.HasValue && error.Wait.Value > backoff) backoff = error.Wait.Value;
                }
                await delay(backoff).ConfigureAwait(false);
            }
        }

        static string Header(HttpResponseMessage response, string name)
        {
            System.Collections.Generic.IEnumerable<string> values;
            return response.Headers.TryGetValues(name, out values) ? values.FirstOrDefault() : null;
        }

        static Failure HttpFailure(HttpResponseMessage response)
        {
            int status = (int)response.StatusCode;
            TimeSpan? wait = null;
            var retry = response.Headers.RetryAfter;
            if (retry != null)
            {
                wait = retry.Delta ?? (retry.Date.HasValue ? retry.Date.Value - DateTimeOffset.UtcNow : (TimeSpan?)null);
                if (wait < TimeSpan.Zero) wait = TimeSpan.Zero;
            }
            bool limited = status == 429 || (status == 403 && (wait.HasValue || Header(response, "X-RateLimit-Remaining") == "0"));
            long reset;
            if (limited && Int64.TryParse(Header(response, "X-RateLimit-Reset"), out reset) && reset > 0 && reset < 253402300800L)
            {
                var remaining = new DateTimeOffset(1970, 1, 1, 0, 0, 0, TimeSpan.Zero).AddSeconds(reset) - DateTimeOffset.UtcNow;
                if (!wait.HasValue || remaining > wait.Value) wait = remaining > TimeSpan.Zero ? remaining : TimeSpan.Zero;
            }
            if (limited && !wait.HasValue) wait = TimeSpan.FromMinutes(1);
            string reason = limited ? "the update service is rate limiting requests (HTTP " + status + ")" : "the update server returned HTTP " + status + " (" + response.StatusCode + ")";
            return new Failure(reason, limited || status == 408 || status == 500 || status == 502 || status == 503 || status == 504, wait);
        }

        // ResponseHeadersRead does not apply HttpClient.Timeout to the body. Bound every
        // network await as well as the whole attempt; disposal also closes stalled sockets.
        static async Task<T> Network<T>(Func<Task<T>> operation, CancellationToken cancellation)
        {
            try
            {
                cancellation.ThrowIfCancellationRequested();
                var task = operation();
                var cancelled = new TaskCompletionSource<bool>();
                using (cancellation.Register(() => cancelled.TrySetResult(true)))
                {
                    if (await Task.WhenAny(task, cancelled.Task).ConfigureAwait(false) != task)
                    {
                        // A broken stream may ignore cancellation. Its result is never used.
                        var ignored = task.ContinueWith(t => { var observed = t.Exception; },
                            CancellationToken.None, TaskContinuationOptions.OnlyOnFaulted | TaskContinuationOptions.ExecuteSynchronously, TaskScheduler.Default);
                        throw new OperationCanceledException(cancellation);
                    }
                    return await task.ConfigureAwait(false);
                }
            }
            catch (OperationCanceledException error) { throw new Failure("the connection timed out", true, null, error); }
            catch (HttpRequestException error)
            {
                var web = error.InnerException as WebException;
                if (web != null && (web.Status == WebExceptionStatus.TrustFailure || web.Status == WebExceptionStatus.SecureChannelFailure))
                    throw new Failure("the secure connection could not be verified", false, null, error);
                throw new Failure("the connection was interrupted", true, null, error);
            }
            catch (IOException error) { throw new Failure("the download connection was interrupted", true, null, error); }
        }

        async Task FetchOnce(string url, Stream destination, long maxBytes, bool json, bool exactSize)
        {
            using (var total = new CancellationTokenSource(exactSize ? packageTimeout : metadataTimeout))
            {
                for (int redirects = 0; redirects < 6; redirects++)
                {
                    if (!Updates.IsAllowedUrl(url)) throw new InvalidDataException("Update redirect is outside the approved HTTPS GitHub hosts.");
                    using (var request = new HttpRequestMessage(HttpMethod.Get, url))
                    using (var headers = CancellationTokenSource.CreateLinkedTokenSource(total.Token))
                    {
                        headers.CancelAfter(metadataTimeout);
                        request.Headers.UserAgent.ParseAdd("Beyond-Mod-Manager/1.0");
                        request.Headers.CacheControl = new System.Net.Http.Headers.CacheControlHeaderValue { NoCache = true };
                        if (new Uri(url).Host == "api.github.com")
                        {
                            request.Headers.Accept.ParseAdd(json ? "application/vnd.github+json" : "application/octet-stream");
                            request.Headers.Add("X-GitHub-Api-Version", "2022-11-28");
                        }
                        using (var response = await Network(() => client.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, headers.Token), headers.Token).ConfigureAwait(false))
                        {
                            headers.CancelAfter(Timeout.InfiniteTimeSpan);
                            int status = (int)response.StatusCode;
                            if (status >= 300 && status < 400)
                            {
                                if (response.Headers.Location == null) throw new InvalidDataException("Update redirect is missing its destination.");
                                url = new Uri(new Uri(url), response.Headers.Location).AbsoluteUri;
                                continue;
                            }
                            if (!response.IsSuccessStatusCode) throw HttpFailure(response);
                            long? length = response.Content.Headers.ContentLength;
                            if (length > maxBytes) throw new InvalidDataException("Update download exceeds its expected size.");
                            using (var input = await Network(() => response.Content.ReadAsStreamAsync(), total.Token).ConfigureAwait(false))
                            {
                                var buffer = new byte[65536]; long received = 0;
                                while (true)
                                {
                                    int read;
                                    using (var idle = CancellationTokenSource.CreateLinkedTokenSource(total.Token))
                                    {
                                        idle.CancelAfter(idleTimeout);
                                        read = await Network(() => input.ReadAsync(buffer, 0, buffer.Length, idle.Token), idle.Token).ConfigureAwait(false);
                                    }
                                    if (read == 0) break;
                                    received += read;
                                    if (received > maxBytes) throw new InvalidDataException("Update download exceeds its expected size.");
                                    // Local disk errors are not network failures and must never be retried.
                                    await destination.WriteAsync(buffer, 0, read).ConfigureAwait(false);
                                }
                                if ((length.HasValue && received != length.Value) || (exactSize && received != maxBytes))
                                    throw new Failure("the connection ended before the download was complete", true);
                            }
                            return;
                        }
                    }
                }
            }
            throw new InvalidDataException("Too many update redirects.");
        }

        public void Dispose() { client.Dispose(); }
    }
}
