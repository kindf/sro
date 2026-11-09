# sro/gamedata · 服务端配置表

由 `config/Table/ServerBytes/*.bytes` 转换，统一放在 `generated/` 下。

## 目录

```
sro/gamedata/
  generated/
    allconfigfiles.lua      -- 所有表文件名
    tbscenetable.lua        -- return { [id] = {Field=..., ...}, ... }
    tbentitytable.lua
    ...
  README.md
```

## 命名

| 原表名 | 文件 |
|---|---|
| `SceneTable` | `tbscenetable.lua` |
| `EntityTable` | `tbentitytable.lua` |
| `GlobalTable` | `tbglobaltable.lua` |

小写后重名的表会加序号：
`tbrefineornamenttransfer.lua`、`tbrefineornamenttransfer_2.lua`。

## 规模

```
表数      398（403 张 server 表中 5 张空表，跳过）
行数      109,361
Lua       38.8 MB
加载      2.5s / 198MB（LuaJIT 全量）
```

## 文件格式

```lua
-- generated/tbscenetable.lua
return {
[1]={ID=1,SceneType=2,SceneCfgFile="RO_Ximen",...},
[2]={...},
}
```

- 主键唯一时 key = 主键值；8 张复合主键表 key = 行号（文件头 `key: ordinal`）。
- 空值用类型默认值（0 / "" / false / {}），字段始终存在。

## 用法

本地（不经过 skynet）：

```lua
package.path = package.path .. ";F:/RO/sro/?.lua"
local sceneTable = require "gamedata.generated.tbscenetable"
print(sceneTable[1].SceneType)   --> 2
```

skynet 内（sharedata）：

```lua
local ConfigRepository = require "common.config_repository"
local sceneTable = ConfigRepository.Get("tbscenetable")
for id, row in pairs(sceneTable) do
    -- row 是只读代理
end
```

## 注意事项

1. **5 张空表未生成**：`ItemAchieveBlackList`、`TaskEdenLevelTable`、`TaskExclusiveTable`、`TdRatingTable`、`TitleIndexTable`。
2. **8 张复合主键表**用行号做 key：`BusinessSellTable`、`GiftLimitTable`、`ItemUseCountTable`、`LeaderBoardColumnInfoTable`、`ServerBaseBonusTable`、`ServerJobBonusTable`、`TimeActivityTable`、`TimeLimitActivityTable`。
3. **部分文本字段是 `uint` 哈希**（如 `SceneTable.MapEntryName`、`Comment`），服务端原始设计如此。
4. **`_cN` 列名**：20 张表有 bytes 里存在、访问器没暴露的隐藏列。
5. **内存**：全量 198MB。跨服务共享用 `sharedata`，否则每个 scene 服务各一份。

## 重新生成

```powershell
python sro\tools\table\gen_table_data.py --root F:\RO
```
