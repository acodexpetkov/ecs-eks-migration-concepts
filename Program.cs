var builder = WebApplication.CreateBuilder(args);
var app = builder.Build();

// Change the text here to update your visible version
app.MapGet("/", () => "Hello World version Final for Presentation ver.1");

app.Run();
