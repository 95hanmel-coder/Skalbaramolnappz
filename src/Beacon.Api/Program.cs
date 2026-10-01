var builder = WebApplication.CreateBuilder(args);
var app = builder.Build();

app.MapGet("/", () => new
{
    app = "Beacon",
    status = "live via pipeline"
});

app.MapGet("/health", () => Results.Ok("OK"));

app.Run();

public partial class Program { }