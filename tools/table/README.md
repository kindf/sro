# sro/tools/table · 配置表工具链

四个工具，覆盖“数据在哪 → 字段是什么 → 怎么转成 Lua”。

## 背景

`config/LuaServer/Table/*.lua` 不是数据，是 ProtoGen 生成的 **C++ 绑定访问器**：

```lua
_GetSceneType = function(rowPoint)
    return ROGameLibs.RowDataLuaProxy:GetValueUInt(rowPoint, 1)
end
```

数据在 C++ `TableDataMgr` / `.bytes`；访问器编码了 **字段名 / 类型 / 服务器列序**，当 schema 用。

## 工具链

```
scan_tables.py      四套来源对账
      ↓
gen_table_schema.py 访问器 → table_schema.json（字段名/类型/列号）
      ↓
ro_bytes.py         .bytes → Python 结构（数据 + 类型 + 行）
      ↓
gen_table_data.py   生成 sro/gamedata/generated/*.lua
```

### 1. scan_tables.py —— 四套来源对账

```powershell
python sro\tools\table\scan_tables.py --root F:\RO
```

输出 `table_inventory.csv`、`table_inventory.md`、`table_stats.txt`。

当前：表名 493 / Lua 445 / CSV 489 / ServerBytes 403 / 三套齐全 378。

### 2. gen_table_schema.py —— 访问器 → schema

```powershell
python sro\tools\table\gen_table_schema.py --root F:\RO
```

输出 `table_schema.json`：392 张表、3222 个字段，字段含 `name/type/index/csv_col`。

### 3. ro_bytes.py —— .bytes 解析器

```powershell
python sro\tools\table\ro_bytes.py --file F:\RO\config\Table\ServerBytes\SceneTable.bytes
```

格式来自 `rogamelibs/table/table_data.cpp` + `parser/*`：

```
int64 size, uint64 hash, uint64 time,
string_set, head(uint32 count, int16 bin, fields...),
uint32 row_count, rows...
```

已验证 **403/403** 个 `.bytes` 全部解析通过、无尾部残留。

### 4. gen_table_data.py —— 生成 Lua

```powershell
python sro\tools\table\gen_table_data.py --root F:\RO
```

输出到 `sro/gamedata/generated/`：398 张表、109,361 行、38.8MB。

文件名统一为 `tb` + 原表名小写（`SceneTable` → `tbscenetable.lua`），
同时生成 `allconfigfiles.lua` 列出全部文件：

```lua
return {
    "tbaccessorytable",
    "tbachievementbadgetable",
    ...
}
```

文件格式：

```lua
return {
    [1] = {ID = 1, SceneType = 2, ...},
}
```

主键唯一时 key = 主键值；8 张复合主键表 key = 行号（文件头 `key: ordinal`）。

## 关键结论

1. **必须按名字对齐**：CSV 有 `Comment`、`EventID` 等服务器不用的列，列号会错位。
2. **类型不能从 CSV 猜**：`1` 可能是数字或字符串，数组是 `a|b`，序列是 `x=y=z`。
3. **`.bytes` 才是权威**：`GlobalTable` 的 CSV 只有表头，bytes 有 1385 行。
4. 398 张可自动生成；5 张空表跳过；8 张复合主键表用行号做 key。
5. 全量加载 2.49s / 198MB（LuaJIT），跨服务共享必须用 `sharedata`。

## 数据量

- CSV：489 个文件、124,476 行、15.6MB
- ServerBytes：403 个文件、13.4MB（前 4 字节 = 文件长度）
- 生成 Lua：398 个文件、109,361 行、38.8MB

## 重新生成顺序

```powershell
python sro\tools\table\scan_tables.py --root F:\RO
python sro\tools\table\gen_table_schema.py --root F:\RO
python sro\tools\table\gen_table_data.py --root F:\RO
```
