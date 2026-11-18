using ssa.server.Models;

namespace ssa.server.Services
{
    public interface ISafetySearchService
    {
        Task<SafetyQueryResponse> AskSafetyQuestionAsync(string query);
    }
}
