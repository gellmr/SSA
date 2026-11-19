namespace ssa.server.Models
{
    public class SafetyQueryRequest
    {
        public string Query { get; set; } = string.Empty;
    }

    public class SafetyCitation
    {
        public string DocumentTitle { get; set; } = string.Empty;
        public string Snippet { get; set; } = string.Empty;
        public string Uri { get; set; } = string.Empty;
        public string DocUrl { get; set; } = string.Empty;
    }

    public class SafetyQueryResponse
    {
        public string Query { get; set; } = string.Empty;
        public string Answer { get; set; } = string.Empty;
        public List<SafetyCitation> Citations { get; set; } = new List<SafetyCitation>();
        public string EngineId { get; set; } = string.Empty;
    }
}

