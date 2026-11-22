using ssa.server.Services;

var builder = WebApplication.CreateBuilder(args);

// Configure CORS allowed origins
var allowedOrigins = new List<string>
{
    "https://safety.mikegelldemo.tech",
    "https://ssa-gcp-515109.web.app"
};

if (builder.Environment.IsDevelopment())
{
    allowedOrigins.Add("https://localhost:5173");
    allowedOrigins.Add("http://localhost:5173");
    allowedOrigins.Add("https://localhost:7225");
    allowedOrigins.Add("http://localhost:5225");
}

builder.Services.AddCors(options =>
{
    options.AddPolicy("StrictOriginPolicy", policy =>
    {
        policy.WithOrigins(allowedOrigins.ToArray())
              .AllowAnyHeader()
              .AllowAnyMethod();
    });
});

builder.Services.AddHttpClient<ISafetySearchService, SafetySearchService>();
builder.Services.AddControllers();
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen();

var app = builder.Build();

if (app.Environment.IsDevelopment())
{
    app.UseSwagger();
    app.UseSwaggerUI();
}

app.UseDefaultFiles();
app.UseStaticFiles();
app.UseHttpsRedirection();
app.UseCors("StrictOriginPolicy");
app.UseAuthorization();

app.MapControllers();
app.MapFallbackToFile("/index.html");

app.Run();

