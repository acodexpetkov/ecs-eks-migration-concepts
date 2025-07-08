var builder = WebApplication.CreateBuilder(args);
var app = builder.Build();

// Change the text here to update your visible version
app.MapGet("/", () => "Hello World Final ver.11");

app.Run();
