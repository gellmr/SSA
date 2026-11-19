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

        [HttpGet("docs/{fileName}")]
        public IActionResult GetPdfDocument(string fileName)
        {
            var cleanFileName = System.IO.Path.GetFileName(fileName);
            var candidatePaths = new[]
            {
                System.IO.Path.Combine(Directory.GetCurrentDirectory(), "gcp", "ragdocs", cleanFileName),
                System.IO.Path.Combine(AppContext.BaseDirectory,        "gcp", "ragdocs", cleanFileName),
                System.IO.Path.Combine(Directory.GetCurrentDirectory(), "..", "gcp", "ragdocs", cleanFileName),
                System.IO.Path.Combine(Directory.GetCurrentDirectory(), "ragdocs", cleanFileName),
                System.IO.Path.Combine(AppContext.BaseDirectory,        "ragdocs", cleanFileName)
            };

            string? filePath = candidatePaths.FirstOrDefault(System.IO.File.Exists);

            if (!string.IsNullOrEmpty(filePath))
            {
                var bytes = System.IO.File.ReadAllBytes(filePath);
                Response.Headers.Append("Content-Disposition", $"inline; filename=\"{cleanFileName}\"");
                return File(bytes, "application/pdf");
            }

            // Fallback for cloud deployment: Redirect to GCS public storage object
            var publicUrl = $"https://storage.googleapis.com/ssa-safety-docs/{cleanFileName}";
            return Redirect(publicUrl);
        }
    }
}
