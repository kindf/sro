# sro/gamedata · 服务端配置表

由 `config/Table/ServerBytes/*.bytes` 直接转换，格式：

```lua
return {
    [1] = {ID = 1, SceneType = 2, SceneCfgFile = "RO_Ximen", ...},
    [2] = {...},
}
```

## 规模

```
表数      398（403 张 server 表中 5 张空表，跳过）
行数      109,361
Lua       38.8 MB
生成耗时  24.8 s
加载      2.49 s / 198 MB（LuaJIT 全量 398 张）
```

对比数组格式（`rows={{...}}`）：16.4MB / 0.75s / 133MB。
key-value 大约多 1.4 倍体积、1.5 倍内存，换来 `Scene[1].SceneType` 的直接写法。

## 主键规则

| 情况 | key | 表 |
|---|---|---|
| 主键唯一（390 张） | 主键值 | 绝大多数表 |
| 主键重复（8 张复合主键） | **行号 1..n** | `BusinessSellTable`、`GiftLimitTable`、`ItemUseCountTable`、`LeaderBoardColumnInfoTable`、`ServerBaseBonusTable`、`ServerJobBonusTable`、`TimeActivityTable`、`TimeLimitActivityTable` |

文件头注释里有 `key: id` / `key: ordinal`，`_manifest.lua` 里也有 `key` 字段。
复合主键表请用 `pairs` 遍历，不要用业务 id 直接索引。

## 用法

```lua
package.path = package.path .. ";F:/RO/sro/?.lua;F:/RO/sro/?/init.lua"

local GD = require "gamedata.init"

local Scene = GD.Get("SceneTable")
print(Scene[1].SceneType)        --> 2
print(Scene[1].SceneCfgFile)     --> "RO_Ximen"
print(Scene[1].StartPos[1][1])   --> 154.7

local Global = GD.Get("GlobalTable")
print(Global["105ActivitiesNum"].Value)  --> "1"

local row = GD.GetRow("SceneTable", 1)
```

## 注意事项

1. **5 张空表未生成**：`ItemAchieveBlackList`、`TaskEdenLevelTable`、`TaskExclusiveTable`、`TdRatingTable`、`TitleIndexTable`（bytes 里 0 字段或 0 行）。
2. **部分文本字段是 `uint` 哈希**，不是显示字符串。例如 `SceneTable.MapEntryName`、`Comment`、`MiniMap`；这是服务端原始设计（客户端用哈希查本地化文本），不是转换错误。
3. **`_cN` 列名**：bytes 里有、访问器没暴露的隐藏列，暂时占位命名（20 张表）。
4. **`GlobalTable`** 是 key-value 表（1385 行），key 是 `Name` 字段。
5. **内存**：全量 198MB。跨服务共享请用 `sharedata`，否则每个 scene 服务各一份。

## 重新生成

```powershell
python sro\tools\table\gen_table_data.py --root F:\RO
```

单表调试：

```powershell
python sro\tools\table\gen_table_data.py --root F:\RO --only SceneTable,GlobalTable
```
