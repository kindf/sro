# sro/gamedata · 服务端配置表

由 `config/Table/ServerBytes/*.bytes` 转换，统一放在 `generated/` 下。

## 当前状态（课程裁剪）

只保留当前用到的表：

```
gamedata/
  generated/
    allconfigfiles.lua   -- 1 张表
    tbscenetable.lua     -- 585 行，约 948 KB
  keep_tables.txt        -- 当前保留清单
  README.md
```

全量 398 张表已暂时删除；需要时从 `.bytes` 重新生成。

## 裁剪/恢复

`keep_tables.txt` 一行一个表名（不带 `.lua`）：

```
tbscenetable
```

裁剪：

```powershell
python sro\tools\table\prune_generated.py
```

恢复某张表：

```powershell
# 1. 先生成全量
python sro\tools\table\gen_table_data.py --root F:\RO

# 2. 把表名加进 keep_tables.txt
# 3. 再裁剪（会删掉清单外的，重写 allconfigfiles.lua）
python sro\tools\table\prune_generated.py
```

`prune_generated.py` 会：

- 删除 `generated/tb*.lua` 中不在清单里的文件；
- 按清单重写 `allconfigfiles.lua`；
- 清单里的表缺失时直接报错，不会静默跳过。

## 命名

| 原表名 | 文件 |
|---|---|
| `SceneTable` | `tbscenetable.lua` |
| `EntityTable` | `tbentitytable.lua` |
| `GlobalTable` | `tbglobaltable.lua` |

小写后重名的表会加序号：
`tbrefineornamenttransfer.lua`、`tbrefineornamenttransfer_2.lua`。

## 文件格式

```lua
-- generated/tbscenetable.lua
return {
[1]={ID=1,SceneType=2,SceneCfgFile="RO_Ximen",...},
[2]={...},
}
```

- 主键唯一时 key = 主键值；8 张复合主键表 key = 行号。
- 空值用类型默认值（0 / "" / false / {}），字段始终存在。

## 用法

本地（不经过 skynet）：

```lua
package.path = package.path .. ";F:/RO/sro/?.lua"
local sceneTable = require "gamedata.generated.tbscenetable"
print(sceneTable[1].SceneType)   --> 2
print(sceneTable[1].StartPos[1][1]) --> 154.7
```

skynet 内（sharedata）：

```lua
local ConfigRepository = require "common.config_repository"
local sceneTable = ConfigRepository.Get("tbscenetable")
```

## 全量参考（重新生成后）

```
表数      398（403 张 server 表中 5 张空表，跳过）
行数      109,361
Lua       38.8 MB
加载      2.5s / 198MB（LuaJIT 全量）
```

## 重新生成全量

```powershell
python sro\tools\table\gen_table_data.py --root F:\RO
```

生成后如果直接启动，`allconfigfiles.lua` 会列 398 张表；课程环境建议再跑一次
`prune_generated.py`，只发布当前用到的表，启动更快、内存更小。
