// Standalone Windows launcher. No Python, downloads, or generated sprite copies.
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Linq;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using System.Web.Script.Serialization;
using System.Windows.Forms;

internal static class AtualizarLDtk
{
    private static readonly JavaScriptSerializer Json = new JavaScriptSerializer {
        MaxJsonLength = 64 * 1024 * 1024, RecursionLimit = 256
    };
    private static readonly Dictionary<int, string> DirectSources = new Dictionary<int, string> {
        {101, "assets/tiles/floor/floor_tileset.png"},
        {102, "assets/tiles/inferior/inferior.png"},
        {103, "assets/tiles/wall/wall_tileset.png"},
        {105, "assets/tiles/wall/decor/column_square.png"},
        {502, "assets/tiles/wall/decor/column_round.png"},
        {503, "assets/tiles/wall/decor/stair.png"},
        {104, "assets/tiles/door/door_front_closed_superior.png"},
        {504, "assets/tiles/door/door_front_opened_superior.png"},
        {505, "assets/tiles/door/door_front_closed_inferior.png"},
        {506, "assets/tiles/door/door_front_opened_inferior.png"},
        {106, "assets/tiles/decor/minotaur_chair.png"},
        {107, "assets/tiles/decor/minotaur_chair_back.png"},
        {108, "assets/tiles/decor/minotaur_chair_seat.png"},
        {109, "assets/characters/player/idle/player_idle_01.png"},
        {507, "assets/merchant/character/merchant_idle1.png"},
        {508, "assets/enemies/minotaur/walk/minotaur_walk_01.png"},
        {518, "assets/tiles/wall/leaves.png"}
    };

    [STAThread]
    private static int Main(string[] args)
    {
        bool quiet = args.Contains("--refresh-only") || args.Contains("--dry-run") || args.Contains("--no-ui");
        try {
            Console.SetOut(new StreamWriter(Console.OpenStandardOutput(), new UTF8Encoding(false)) { AutoFlush = true });
            Console.SetError(new StreamWriter(Console.OpenStandardError(), new UTF8Encoding(false)) { AutoFlush = true });
            string project = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "monster_booster.ldtk");
            string editor = null;
            for (int i = 0; i < args.Length; i++) {
                if (args[i] == "--project" && i + 1 < args.Length) project = args[++i];
                else if (args[i] == "--editor" && i + 1 < args.Length) editor = args[++i];
                else if (args[i] != "--refresh-only" && args[i] != "--dry-run" && args[i] != "--no-ui")
                    throw new InvalidOperationException("Argumento desconhecido: " + args[i]);
            }
            project = Path.GetFullPath(project);
            if (!File.Exists(project)) throw new FileNotFoundException("Projeto LDtk não encontrado", project);
            // Do not close the editor or rewrite beneath its unsaved in-memory map.
            if (Process.GetProcessesByName("LDtk").Length != 0) {
                Report("Salve e feche o LDtk, depois execute AtualizarLDtk.exe novamente.\n\n" +
                    "Nada foi alterado. O editor aberto pode ter pintura ainda não salva.", quiet, true);
                return 2;
            }
            Dictionary<string, object> report = Refresh(project, args.Contains("--dry-run"));
            Console.WriteLine(Json.Serialize(report));
            if (args.Contains("--dry-run") || args.Contains("--refresh-only")) return 0;
            editor = editor ?? FindEditor();
            if (editor == null || !File.Exists(editor)) {
                Report("O mapa foi atualizado, mas o LDtk.exe não foi encontrado.\nAbra este arquivo manualmente:\n" + project,
                    quiet, true);
                return 3;
            }
            Process.Start(new ProcessStartInfo {
                FileName = Path.GetFullPath(editor), Arguments = "\"" + project + "\"",
                WorkingDirectory = Path.GetDirectoryName(project), UseShellExecute = true
            });
            return 0;
        } catch (Exception error) {
            Report("Não foi possível atualizar o LDtk:\n" + error.Message +
                "\n\nNão force o fechamento do editor. Salve/exporte as alterações em PNG e tente novamente.", quiet, true);
            return 1;
        }
    }

    private static Dictionary<string, object> Refresh(string project, bool dryRun)
    {
        string root = Path.GetDirectoryName(project);
        byte[] original = File.ReadAllBytes(project);
        Dictionary<string, object> data = Parse(Encoding.UTF8.GetString(original).TrimStart('\uFEFF'));
        Dictionary<string, object> definitions = Map(data["defs"]);
        Dictionary<int, Dictionary<string, object>> sources = new Dictionary<int, Dictionary<string, object>>();
        Dictionary<string, string> imageHashes = new Dictionary<string, string>();
        List<string> changed = new List<string>();
        foreach (object entry in Items(definitions["tilesets"])) {
            Dictionary<string, object> source = Map(entry);
            int uid = Int(source["uid"]);
            string relative = Convert.ToString(source["relPath"]).Replace('\\', '/');
            if (relative.StartsWith("./")) relative = relative.Substring(2);
            string full = Inside(root, relative);
            if (!File.Exists(full) || relative.Contains("/editor/")) {
                string replacement;
                if (!DirectSources.TryGetValue(uid, out replacement))
                    throw new FileNotFoundException("Fonte de tileset ausente: " + relative);
                relative = replacement;
                full = Inside(root, relative);
            }
            if (!File.Exists(full)) throw new FileNotFoundException("Salve/exporte o PNG da fonte: " + relative);
            byte[] bytes = File.ReadAllBytes(full);
            imageHashes[full] = Hash(bytes);
            int width, height;
            using (MemoryStream stream = new MemoryStream(bytes))
            using (Image image = Image.FromStream(stream)) { width = image.Width; height = image.Height; }
            int grid = Int(source["tileGridSize"]);
            int padding = Int(source["padding"]), spacing = Int(source["spacing"]);
            if (grid <= 0 || padding < 0 || spacing < 0) throw new InvalidDataException("Grade inválida: " + relative);
            int columns = (int)Math.Ceiling((width - padding * 2.0) / (grid + spacing));
            int rows = (int)Math.Ceiling((height - padding * 2.0) / (grid + spacing));
            if (columns <= 0 || rows <= 0) throw new InvalidDataException("PNG menor que a grade: " + relative);
            int oldColumns = Int(source["__cWid"]);
            bool resized = width != Int(source["pxWid"]) || height != Int(source["pxHei"]);
            bool needsUpdate = resized || source["cachedPixelData"] != null || Convert.ToString(source["relPath"]) != relative;
            if (resized) {
                foreach (object selection in Items(source["savedSelections"]))
                    RemapIds(Map(selection), "ids", oldColumns, columns, rows);
                foreach (object tag in Items(source["enumTags"]))
                    RemapIds(Map(tag), "tileIds", oldColumns, columns, rows);
                foreach (object custom in Items(source["customData"])) {
                    Dictionary<string, object> item = Map(custom);
                    item["tileId"] = RemapId(Int(item["tileId"]), oldColumns, columns, rows);
                }
            }
            source["relPath"] = relative;
            source["pxWid"] = width; source["pxHei"] = height;
            source["__cWid"] = columns; source["__cHei"] = rows;
            // Null is supported by LDtk: the editor rebuilds pixel/opacity caches
            // from the real PNG using its own algorithm, not stale serialized data.
            source["cachedPixelData"] = null;
            sources[uid] = source;
            if (needsUpdate) changed.Add(Convert.ToString(source["identifier"]));
        }
        List<Dictionary<string, object>> levels = Items(data["levels"]).Select(Map).ToList();
        foreach (object world in Items(data["worlds"])) levels.AddRange(Items(Map(world)["levels"]).Select(Map));
        int tiles = 0;
        bool instanceChanged = false;
        foreach (Dictionary<string, object> level in levels) {
            if (level["layerInstances"] == null)
                throw new InvalidOperationException("Mapa externo não suportado pelo atualizador: " + level["identifier"]);
            foreach (object entry in Items(level["layerInstances"])) {
                Dictionary<string, object> layer = Map(entry);
                object sourceUid = layer["__tilesetDefUid"];
                if (sourceUid == null) continue;
                Dictionary<string, object> source;
                if (!sources.TryGetValue(Int(sourceUid), out source)) throw new InvalidDataException("Tileset de camada não encontrado");
                string path = Convert.ToString(source["relPath"]);
                if (Convert.ToString(layer["__tilesetRelPath"]) != path) instanceChanged = true;
                layer["__tilesetRelPath"] = path;
                int grid = Int(source["tileGridSize"]), padding = Int(source["padding"]), spacing = Int(source["spacing"]);
                foreach (object tileEntry in Items(layer["gridTiles"]).Concat(Items(layer["autoLayerTiles"]))) {
                    Dictionary<string, object> tile = Map(tileEntry);
                    object[] at = Items(tile["src"]);
                    int x = Int(at[0]), y = Int(at[1]);
                    if (x < padding || y < padding || x >= Int(source["pxWid"]) || y >= Int(source["pxHei"]))
                        throw new InvalidDataException("O PNG foi reduzido e deixou um tile pintado fora da imagem: " + path +
                            " em [" + x + "," + y + "]. Mapa preservado; ajuste o atlas antes de atualizar.");
                    int id = (y - padding) / (grid + spacing) * Int(source["__cWid"]) + (x - padding) / (grid + spacing);
                    if (Int(tile["t"]) != id) instanceChanged = true;
                    tile["t"] = id;
                    tiles++;
                }
            }
        }
        bool write = changed.Count > 0 || instanceChanged;
        string backup = null;
        if (write && !dryRun) {
            if (!original.SequenceEqual(File.ReadAllBytes(project)))
                throw new IOException("O mapa foi salvo durante a atualização. Nenhuma pintura foi sobrescrita; tente novamente.");
            foreach (KeyValuePair<string, string> source in imageHashes)
                if (Hash(File.ReadAllBytes(source.Key)) != source.Value)
                    throw new IOException("O PNG mudou durante a atualização; espere terminar de salvar e tente novamente: " + source.Key);
            if (Process.GetProcessesByName("LDtk").Length != 0)
                throw new IOException("O LDtk foi aberto durante a atualização. Feche o editor antes de tentar novamente.");
            string backupRoot = Inside(root, "ldtk_backups");
            Directory.CreateDirectory(backupRoot);
            backup = Path.Combine(backupRoot, "before_png_refresh_" + DateTime.Now.ToString("yyyyMMdd_HHmmss_fff") + "_" + Hash(original).Substring(0, 12) + ".ldtk");
            string temporary = project + ".refresh_" + Guid.NewGuid().ToString("N") + ".tmp";
            try {
                File.WriteAllText(temporary, Json.Serialize(data) + "\n", new UTF8Encoding(false));
                File.Replace(temporary, project, backup, true);
            } finally { if (File.Exists(temporary)) File.Delete(temporary); }
        }
        return new Dictionary<string, object> {
            {"ok", true}, {"project", project}, {"dryRun", dryRun}, {"changed", write},
            {"pngsRead", sources.Count}, {"updatedTilesets", changed}, {"paintedTiles", tiles},
            {"backup", backup}, {"editor", FindEditor()}, {"pngHashes", imageHashes}
        };
    }

    private static int RemapId(int id, int oldColumns, int columns, int rows)
    {
        int x = id % oldColumns, y = id / oldColumns;
        if (x >= columns || y >= rows) throw new InvalidDataException("PNG reduzido: um stamp ou metadado ficaria fora do atlas. Nada foi salvo.");
        return y * columns + x;
    }
    private static void RemapIds(Dictionary<string, object> item, string key, int oldColumns, int columns, int rows)
    { item[key] = Items(item[key]).Select(value => (object)RemapId(Int(value), oldColumns, columns, rows)).ToArray(); }
    private static Dictionary<string, object> Map(object value) { return (Dictionary<string, object>)value; }
    private static Dictionary<string, object> Parse(string text)
    {
        // JavaScriptSerializer reserves __type for .NET polymorphic types.
        // LDtk uses that same JSON key for ordinary layer/entity metadata.
        const string sentinel = "__ldtk_type_passthrough_7d26f1";
        if (text.Contains(sentinel)) throw new InvalidDataException("Chave de JSON reservada pelo atualizador");
        string safe = Regex.Replace(text, @"([{,]\s*)""__type""\s*:", "$1\"" + sentinel + "\":");
        object value = Json.DeserializeObject(safe);
        RestoreTypes(value, sentinel);
        return Map(value);
    }
    private static void RestoreTypes(object value, string sentinel)
    {
        Dictionary<string, object> map = value as Dictionary<string, object>;
        if (map != null) {
            if (map.ContainsKey(sentinel)) { map["__type"] = map[sentinel]; map.Remove(sentinel); }
            foreach (object child in map.Values.ToArray()) RestoreTypes(child, sentinel);
        } else {
            object[] array = value as object[];
            if (array != null) foreach (object child in array) RestoreTypes(child, sentinel);
        }
    }
    private static object[] Items(object value) { return value == null ? new object[0] : (object[])value; }
    private static int Int(object value) { return Convert.ToInt32(value); }
    private static string Hash(byte[] bytes)
    { using (SHA256 hash = SHA256.Create()) return BitConverter.ToString(hash.ComputeHash(bytes)).Replace("-", "").ToLowerInvariant(); }
    private static string Inside(string root, string relative)
    {
        string prefix = Path.GetFullPath(root).TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar;
        string full = Path.GetFullPath(Path.Combine(prefix, relative.Replace('/', Path.DirectorySeparatorChar)));
        if (!full.StartsWith(prefix, StringComparison.OrdinalIgnoreCase)) throw new InvalidDataException("Fonte fora da pasta do projeto: " + relative);
        return full;
    }
    private static string FindEditor()
    {
        string[] candidates = {
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Programs", "ldtk", "LDtk.exe"),
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "LDtk", "LDtk.exe")
        };
        return candidates.FirstOrDefault(File.Exists);
    }
    private static void Report(string message, bool quiet, bool error)
    {
        if (quiet) Console.Error.WriteLine(message);
        else MessageBox.Show(message, "Atualizar LDtk — Monster Booster", MessageBoxButtons.OK,
            error ? MessageBoxIcon.Warning : MessageBoxIcon.Information);
    }
}
