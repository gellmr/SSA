using Microsoft.AspNetCore.Mvc;
using ssa.server.Models;
using ssa.server.Services;

namespace ssa.server.Controllers
{
    [ApiController]
    [Route("api/[controller]")]
    public class SafetyController : ControllerBase
    {
        private readonly ISafetySearchService _safetyService;

        public SafetyController(ISafetySearchService safetyService)
        {
            _safetyService = safetyService;
        }

        [HttpPost("ask")]
        public async Task<IActionResult> Ask([FromBody] SafetyQueryRequest request)
        {
            if (request == null || string.IsNullOrWhiteSpace(request.Query))
            {
                return BadRequest(new { message = "Query cannot be empty." });
            }

            var result = await _safetyService.AskSafetyQuestionAsync(request.Query);
            return Ok(result);
        }
    }
}
