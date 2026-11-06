# sro/tools/proto · 老服务端协议清单工具

从 C++ 协议头文件生成 skynet 侧可用的协议映射表。
**生成物提交仓库，生成器只在协议变更时跑。**

> 注意：这里生成的是**老 C++ 服务端（roserver）的协议表**，用于迁移期网关。
> 它与 `sro/proto/proto_map.lua`（新 sro 自己的协议注册表，只有 battle/login/player_base 几个）
> 是两套东西，模块名不要混用。

## 快速开始

```powershell
# 生成（默认 --root F:/RO，输出到本目录）
& "C:\Users\QQ\.dsh\dsh-runtimes\dsh-primary-runtime\dependencies\python\python.exe" `
  F:\RO\sro\tools\proto\gen_proto_map.py

# 只自检，不写文件
& "...python.exe" F:\RO\sro\tools\proto\gen_proto_map.py --check

# 验证 Lua 侧加载
F:\RO\clientproj\Luajit64\luajit64.exe F:\RO\sro\tools\proto\test_proto_api.lua
```

## 输出

| 文件 | 说明 |
|---|---|
| `proto_map.lua` | 运行时数据，`require "proto_map"` |
| `proto_api.lua` | 访问器（手写，不随生成覆盖） |
| `proto_map.csv` | 给测试/策划，Excel 可直接打开 |
| `proto_stats.txt` | 统计、空包清单、老协议清单、复用消息 |

### proto_map.lua 结构

```lua
[id] = { name, cls, kind, req, res, from, to, flags }
-- kind: 1=ptc, 2=rpc
-- flags: bit0=空包, bit1=客户端协议
-- req/res: "KKSG.Xxx" 或 false
```

### proto_api.lua

```lua
local api = require "proto_api"
api.count()          --> 1649
api.count_client()   --> 978   任意一端是 C
api.count_gate()     --> 609   走游戏网关：C<->G / C<->T
api.name(1128751369) --> "PTCC2G_MOVEOPERATIONREQ"
api.req(1128751369)  --> "KKSG.MoveInfo"
api.dir(1128751369)  --> "C->G"
api.is_empty(id)
api.is_gate(id)
for id, e in api.iter_gate() do ... end
```

## 当前数据（2026-11）

```
total=1649  ptc=794  rpc=855  empty=20
client=978  client_gate=609  legacy=80  unknown=0
rpc impl macros=411
```

## 解析规则

1. 协议号：`#define <NAME>_TYPE <id>`
2. 类型：`class X : public CRpc`（rpc） / `public CProtocol`（ptc）
3. PTC payload：`KKSG::X m_Data;`，没有则为空包（20 个）
4. RPC req/res：头文件 `OnCall(const X &, Y &)`，覆盖 855/855
5. 方向：优先 `(id>>24)&0xFF`、`(id>>16)&0xFF`；
   老协议（80 个，id < 0x01000000，如 7369 `PTCG2C_SKILLRESULT`）回退到名字前缀 `PTC<X>2<Y>_`

## 注意事项

- **源文件是 GBK**：只解析 ASCII 片段，按 latin-1 读，别用 UTF-8。
- **头文件位置**：`roserver/protocol/**/*.h`，不是 `gameserver/protocol/`（那里只有 `.cpp`）。
- **`.cpp` 宏只有 411 个**：只作交叉校验，不作主数据源。
- **`C->M` 有 205 个**：客户端也会经网关访问 masterserver（登录/区服/支付），路由表别只做 C→G。
- **descriptor 未生成**：本机没有 protoc。需要时用
  `protoc --proto_path=config/AutoGen/protobuf/cpp --include_imports --descriptor_set_out=sro/tools/proto/ro.pb config/AutoGen/protobuf/cpp/*.proto`，
  再用 lua-protobuf `pb.loadfile` 校验 978 个客户端消息名。

## 协议变更后

1. 重新跑生成器
2. `git diff proto_stats.txt` 看新增/删除
3. 跑 `test_proto_api.lua`
4. 若数量变化，更新文档里的数字
