# sro/protocol

协议目录（已清空，按功能逐个恢复）。

## 当前状态

```
protocol/
  proto/test.proto   测试 proto（package test）
  pb/test.pb
  protos.lua         {"test"}
  pids.lua           3 个 message，6 条双向条目
```

`pids.lua` 当前内容（示例）：

```lua
["test.Test"]=3112579714,
[3112579714]="test.Test",
```

## 两个生成文件

| 文件 | 生成器 | 作用 |
|---|---|---|
| `protos.lua` | `tools/proto/gen_protos.py` | proto 基名，按 import 拓扑排序，决定加载顺序 |
| `pids.lua` | `tools/proto/gen_pids.py` | message 全名 ↔ 协议号，双向映射 |

`make proto`：

```
$(PYTHON) tools/proto/gen_protos.py
$(PYTHON) tools/proto/gen_pids.py
sh tool/proto.sh
```

## pids 规则

- 一个 message 一个唯一 id；
- 每个 message 两条：

```lua
["package.Message"]=id,
[id]="package.Message",
```

- id = `crc32("package.Message")`，冲突线性探测；
- 不再使用原 `PTCC2G_*` 协议号；
- `head_codec` 的 `id` 字段用的就是这里的 id。

`protocol_helper` 已同步：

- `RegisterRpcHandler(reqName, respName, handler)` 传 message 全名；
- `UnpackHeader` / `Encode` 走 `head_codec` 的 `id(4)+flag(1)+tag(4)+body`；
- `Encode(respName, resp, flag, tag)`，RPC 回复传 `flag=1, tag=请求 tag`。

## 恢复一个协议

1. 在 `protocol/proto/` 新建 proto，`package KKSG`，字段名/字段号与原 proto 一致；
2. `make proto`：自动更新 `protos.lua`、`pids.lua`，编译出 `.pb`；
3. `Pb.type("KKSG.XXX")` 验证；
4. `ProtocolHelper.RegisterProtocol()` 按 `protos.lua` 顺序加载。

## 建议顺序

| 步骤 | proto | 内容 | 来源 |
|---|---|---|---|
| 1 | `common.proto` | `Vec3`、`ErrorCode`、`NullArg/NullRes` | `pbc_common`、`enumc_unclassified` |
| 2 | `move.proto` | `MoveInfo` | `pbc_unclassified` |
| 3 | `scene.proto` | 进/出场景、场景简报 | `pbc_scene`、`pbc_unclassified` |
| 4 | `sync.proto` | `StepSyncList`、`StepSyncInfo`、位置同步 | `pbc_gamelib` |
| 5 | `combat.proto` | `SingingArg/Res`、技能结果、Buff | `pbc_gamelib`、`pbc_unclassified` |
| 6 | `role.proto` | 角色简报/属性（如需要） | `pbc_role`、`pbc_gamelib` |

## 注意

- pb 一 proto 一文件，不加 `--include_imports`；
- `test.proto` 只是测试，恢复正式协议后可删；
- 原 55 个 proto 在 `config/AutoGen/protobuf/cpp/`。
