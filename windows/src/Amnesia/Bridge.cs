// What the page can ask C# to do. The page sends {"id":1,"cmd":"preview"}, C# answers
// {"id":1,"ok":true,"data":...}. Unknown commands get ok:false. Nothing here deletes anything yet.
using System.Text.Json;
using System.Text.Json.Nodes;

namespace Amnesia;

sealed class Bridge
{
    public async Task<string> HandleAsync(string json)
    {
        JsonNode? id = null;
        try
        {
            var msg = JsonNode.Parse(json)!;
            id = msg["id"]?.DeepClone();
            var cmd = msg["cmd"]?.GetValue<string>() ?? "";
            JsonNode? data = cmd switch
            {
                "info" => Info(),
                "preview" => await Cleaner.PreviewAsync(),
                _ => throw new InvalidOperationException($"Unknown command: {cmd}"),
            };
            return new JsonObject { ["id"] = id, ["ok"] = true, ["data"] = data }.ToJsonString();
        }
        catch (Exception ex)
        {
            return new JsonObject { ["id"] = id, ["ok"] = false, ["error"] = ex.Message }.ToJsonString();
        }
    }

    static JsonNode Info() => new JsonObject
    {
        ["version"] = AppInfo.Version,
        ["windows"] = Environment.OSVersion.VersionString,
        ["lang"] = System.Globalization.CultureInfo.CurrentUICulture.TwoLetterISOLanguageName == "id" ? "id" : "en",
        ["home"] = AppInfo.Home,
    };
}
