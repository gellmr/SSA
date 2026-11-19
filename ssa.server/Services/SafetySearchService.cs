using Google.Apis.Auth.OAuth2;
using System.Net.Http.Headers;
using System.Text.Json;
using ssa.server.Models;

namespace ssa.server.Services
{
    public class SafetySearchService : ISafetySearchService
    {
        private readonly IConfiguration _config;
        private readonly ILogger<SafetySearchService> _logger;
        private readonly HttpClient _http;

        public SafetySearchService(IConfiguration config, ILogger<SafetySearchService> logger, HttpClient http)
        {
            _config = config;
            _logger = logger;
            _http = http;
        }

        public async Task<SafetyQueryResponse> AskSafetyQuestionAsync(string query)
        {
            var res = new SafetyQueryResponse { Query = query };
            if (string.IsNullOrWhiteSpace(query))
            {
                res.Answer = "Please enter a valid workplace safety question.";
                return res;
            }

            var projId = _config["GCP:ProjectId"];
            var loc = string.IsNullOrWhiteSpace(_config["GCP:Location"]) ? "global" : _config["GCP:Location"];
            var col = string.IsNullOrWhiteSpace(_config["GCP:Collection"]) ? "default_collection" : _config["GCP:Collection"];

            if (string.IsNullOrWhiteSpace(projId))
            {
                _logger.LogError("GCP ProjectId is not configured.");
                res.Answer = "GCP ProjectId configuration is missing. Ensure GCP__ProjectId is injected.";
                return res;
            }

            try
            {
                GoogleCredential cred = await GoogleCredential.GetApplicationDefaultAsync();
                var scoped = cred.CreateScoped("https://www.googleapis.com/auth/cloud-platform");
                string token = await scoped.UnderlyingCredential.GetAccessTokenForRequestAsync();

                string? engineId = await DiscoverEngineAsync(projId, loc, col, token);
                if (string.IsNullOrEmpty(engineId))
                {
                    res.Answer = "Site Safety RAG engine is currently offline (or still initializing)";
                    return res;
                }
                res.EngineId = engineId;

                var url = $"https://discoveryengine.googleapis.com/v1/projects/{projId}/locations/{loc}/collections/{col}/engines/{engineId}/servingConfigs/default_search:search";
                var reqBody = new
                {
                    query = query,
                    pageSize = 15,
                    contentSearchSpec = new
                    {
                        summarySpec = new
                        {
                            summaryResultCount = 10,
                            includeCitations = true,
                            ignoreAdversarialQuery = true,
                            modelPromptSpec = new
                            {
                                preamble = "You are an official Australian Workplace Safety Assistant. Provide a detailed, comprehensive, and exhaustive answer. Do not omit any relevant findings."
                            }
                        },
                        snippetSpec = new { maxSnippetCount = 5 },
                        extractiveContentSpec = new { maxExtractiveAnswerCount = 5 }
                    }
                };

                using var req = new HttpRequestMessage(HttpMethod.Post, url);
                req.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
                req.Headers.Add("X-Goog-User-Project", projId);
                req.Content = new StringContent(JsonSerializer.Serialize(reqBody), System.Text.Encoding.UTF8, "application/json");

                using var httpRes = await _http.SendAsync(req);
                string json = await httpRes.Content.ReadAsStringAsync();

                if (!httpRes.IsSuccessStatusCode)
                {
                    _logger.LogError("Discovery Engine returned {StatusCode}: {Error}", httpRes.StatusCode, json);
                    if (httpRes.StatusCode == System.Net.HttpStatusCode.TooManyRequests)
                    {
                        res.Answer = "Site Safety RAG engine is currently warming up... Please try again in a few minutes.";
                    }
                    else
                    {
                        res.Answer = "Unable to retrieve safety guidance at this moment. Please try again shortly.";
                    }
                    return res;
                }

                ParseSearchResults(json, res);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error processing RAG query");
                res.Answer = "Error connecting to Safety RAG Engine: " + ex.Message;
            }

            return res;
        }

        private static void ParseSearchResults(string json, SafetyQueryResponse res)
        {
            using var doc = JsonDocument.Parse(json);
            var root = doc.RootElement;

            if (root.TryGetProperty("summary", out var sum) && sum.TryGetProperty("summaryText", out var st) && !string.IsNullOrWhiteSpace(st.GetString()))
            {
                res.Answer = st.GetString()!;
            }

            if (root.TryGetProperty("results", out var results) && results.ValueKind == JsonValueKind.Array)
            {
                var snippets = new List<string>();
                foreach (var item in results.EnumerateArray())
                {
                    if (item.TryGetProperty("document", out var dProp) && dProp.TryGetProperty("derivedStructData", out var structProp))
                    {
                        string title = structProp.TryGetProperty("title", out var t) ? t.GetString() ?? "" : "";
                        string uri = structProp.TryGetProperty("link", out var l) ? l.GetString() ?? "" : "";
                        string snipText = "";

                        if (structProp.TryGetProperty("snippets", out var snips) && snips.ValueKind == JsonValueKind.Array)
                        {
                            foreach (var s in snips.EnumerateArray())
                            {
                                if (s.TryGetProperty("snippet", out var stext)) { snipText = stext.GetString() ?? ""; break; }
                            }
                        }

                        if (string.IsNullOrEmpty(title) && dProp.TryGetProperty("name", out var n))
                        {
                            title = System.IO.Path.GetFileName(n.GetString() ?? "");
                        }

                        string cleanSnip = CleanHtml(snipText);
                        string pageNum = "";

                        if (structProp.TryGetProperty("extractive_answers", out var extAnswers) && extAnswers.ValueKind == JsonValueKind.Array)
                        {
                            foreach (var ext in extAnswers.EnumerateArray())
                            {
                                if (ext.TryGetProperty("pageNumber", out var pNum))
                                {
                                    pageNum = pNum.GetString() ?? "";
                                    if (!string.IsNullOrEmpty(pageNum)) break;
                                }
                            }
                        }

                        if (string.IsNullOrEmpty(pageNum) && structProp.TryGetProperty("extractive_segments", out var extSegs) && extSegs.ValueKind == JsonValueKind.Array)
                        {
                            foreach (var seg in extSegs.EnumerateArray())
                            {
                                if (seg.TryGetProperty("pageNumber", out var pNum))
                                {
                                    pageNum = pNum.GetString() ?? "";
                                    if (!string.IsNullOrEmpty(pageNum)) break;
                                }
                            }
                        }

                        string fileName = System.IO.Path.GetFileName(uri);
                        string pageFragment = !string.IsNullOrEmpty(pageNum) ? $"#page={pageNum}" : (!string.IsNullOrWhiteSpace(res.Query) ? "#search=" + Uri.EscapeDataString(res.Query) : "");
                        string docUrl = !string.IsNullOrEmpty(fileName) ? $"/api/safety/docs/{fileName}{pageFragment}" : "";
                        string displayTitle = !string.IsNullOrEmpty(pageNum) && !title.EndsWith($"(Page {pageNum})") ? $"{title} (Page {pageNum})" : title;

                        if (!string.IsNullOrEmpty(displayTitle) || !string.IsNullOrEmpty(cleanSnip))
                        {
                            res.Citations.Add(new SafetyCitation { DocumentTitle = displayTitle, Snippet = cleanSnip, Uri = uri, DocUrl = docUrl });
                        }
                        if (!string.IsNullOrEmpty(cleanSnip)) snippets.Add(cleanSnip);
                    }
                }

                if (string.IsNullOrWhiteSpace(res.Answer) && snippets.Count > 0)
                {
                    res.Answer = "Here are relevant sections from SafeWork Australia Codes of Practice:\n\n• " + string.Join("\n\n• ", snippets);
                }
            }

            if (string.IsNullOrWhiteSpace(res.Answer))
            {
                res.Answer = "No matching safety information was found in the SafeWork Australia Codes of Practice.";
            }
        }

        private async Task<string?> DiscoverEngineAsync(string projId, string loc, string col, string token)
        {
            try
            {
                var listUrl = $"https://discoveryengine.googleapis.com/v1/projects/{projId}/locations/{loc}/collections/{col}/engines";
                using var req = new HttpRequestMessage(HttpMethod.Get, listUrl);
                req.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
                req.Headers.Add("X-Goog-User-Project", projId);

                using var res = await _http.SendAsync(req);
                if (res.IsSuccessStatusCode)
                {
                    string json = await res.Content.ReadAsStringAsync();
                    using var doc = JsonDocument.Parse(json);
                    if (doc.RootElement.TryGetProperty("engines", out var engines) && engines.ValueKind == JsonValueKind.Array)
                    {
                        var engineList = new List<(string Id, DateTime CreateTime)>();
                        foreach (var e in engines.EnumerateArray())
                        {
                            if (e.TryGetProperty("name", out var nameProp))
                            {
                                string name = nameProp.GetString() ?? "";
                                var m = System.Text.RegularExpressions.Regex.Match(name, @"/engines/(ssa-[^/]+)$");
                                if (m.Success)
                                {
                                    DateTime cTime = DateTime.MinValue;
                                    if (e.TryGetProperty("createTime", out var cProp) && DateTime.TryParse(cProp.GetString(), out var parsed))
                                    {
                                        cTime = parsed;
                                    }
                                    engineList.Add((m.Groups[1].Value, cTime));
                                }
                            }
                        }
                        if (engineList.Count > 0)
                        {
                            return engineList.OrderByDescending(x => x.CreateTime).First().Id;
                        }
                    }
                }
            }
            catch (Exception ex) { _logger.LogWarning(ex, "Engine discovery failed"); }
            return null;
        }

        // This method is for React JSX plain-text rendering ({cit.snippet}), which escapes < and > characters.
        // Do NOT use this method with dangerouslySetInnerHTML as there would be no protection.
        private static string CleanHtml(string text)
        {
            if (string.IsNullOrEmpty(text)) return string.Empty;
            
            // 1. Decode HTML entities (&nbsp; -> space, &amp; -> &, &quot; -> ", etc.)
            var decoded = System.Net.WebUtility.HtmlDecode(text);
            
            // 2. Strip HTML tags (like <b> or <span>)
            var stripped = System.Text.RegularExpressions.Regex.Replace(decoded, "<.*?>", string.Empty);
            
            // 3. Normalize multiple whitespace characters
            return System.Text.RegularExpressions.Regex.Replace(stripped, @"\s+", " ").Trim();
        }
    }
}
