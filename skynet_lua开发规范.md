# Skynet Lua 开发目录与命名规范

适用范围：基于 Skynet 的 Lua 游戏服务端。

Skynet 官方区分服务入口 `service` 和 Lua 库 `lualib`。本文在此基础上规定业务分层与团队命名方式；大小写、业务目录和函数前缀属于项目约定，并非框架强制要求。

参考：[Skynet 官方仓库](https://github.com/cloudwu/skynet)、[官方配置说明](https://github.com/cloudwu/skynet/wiki/Config)。

## 1. 文件目录组织

```text
game_server/
├── skynet/                         # 框架，独立管理版本
├── service/                        # 服务入口、消息分发和生命周期
│   ├── main.lua                    # 节点启动入口
│   ├── gateway/
│   │   ├── gate_service.lua
│   │   └── watchdog_service.lua
│   ├── login/
│   │   └── login_service.lua
│   ├── game/
│   │   ├── agent_service.lua        # 玩家代理服务入口
│   │   └── world_service.lua        # 世界服务入口
│   └── database/
│       └── database_service.lua
├── lualib/                         # require 加载的模块
│   ├── common/                     # 跨业务复用能力
│   │   ├── class.lua
│   │   ├── error_code.lua
│   │   ├── time_util.lua
│   │   └── table_util.lua
│   ├── infrastructure/             # 基础设施
│   │   ├── logger.lua
│   │   ├── database_client.lua
│   │   └── service_proxy.lua
│   ├── protocol/                   # 编解码和分发
│   │   ├── protocol_codec.lua
│   │   └── request_dispatcher.lua
│   └── game/                       # 按业务域聚合
│       ├── player/
│       │   ├── player.lua
│       │   ├── player_manager.lua
│       │   ├── player_repository.lua
│       │   └── item/
│       │       ├── item_module.lua
│       │       └── item_handler.lua
│       ├── mail/
│       │   ├── mail_manager.lua
│       │   └── mail_repository.lua
│       └── arena/
│           ├── arena_manager.lua
│           ├── arena_handler.lua
│           └── arena_def.lua
├── config/                         # 启动和部署配置
│   ├── common.lua
│   ├── development/
│   │   └── game.lua
│   └── production/
│       └── game.lua
├── gamedata/                       # 策划配置
│   ├── source/
│   └── generated/
├── protocol/                       # 协议定义和生成产物
│   ├── source/
│   └── generated/
├── scripts/                        # 启停、生成和运维脚本
├── tests/
│   ├── unit/
│   └── integration/
├── docs/                           # 架构、接口和开发文档
├── logs/                           # 日志，不提交版本库
└── run/                            # PID 等运行文件，不提交版本库
```

组织规则：

- `service/` 只放服务入口，业务实现放入 `lualib/game/`。
- 按业务聚合代码，例如竞技场代码统一放在 `game/arena/`。
- `common/` 只接收多个业务真正复用的能力。
- 部署配置、策划配置和协议定义分别管理。
- 生成文件统一放在 `generated/`，通过工具更新。
- Lua 模块不等于 Skynet 服务。新增玩家功能通常先作为玩家服务内模块；是否拆分服务，根据状态归属、通信成本和负载决定。

## 2. 目录与文件命名

目录和文件统一使用小写字母与下划线。

| 对象 | 命名规则 | 示例 |
| --- | --- | --- |
| 目录 | snake_case | treasure_arena/ |
| Lua 文件 | snake_case.lua | player_manager.lua |
| 服务入口 | xxx_service.lua | login_service.lua |
| 玩家功能模块 | xxx_module.lua | item_module.lua |
| 管理器 | xxx_manager.lua | arena_manager.lua |
| 请求处理器 | xxx_handler.lua | arena_handler.lua |
| 数据访问模块 | xxx_repository.lua | player_repository.lua |
| 外部服务客户端 | xxx_client.lua | database_client.lua |
| 业务定义 | xxx_def.lua | arena_def.lua |
| 工具模块 | xxx_util.lua | time_util.lua |
| 测试文件 | test_xxx.lua | test_arena_manager.lua |

补充要求：

- 避免 `misc.lua`、`other.lua`、`new_manager.lua` 等含义不清的名称。
- 固定使用 `manager`、`config` 等完整单词，避免同项目混用 `mgr`、`manager`。
- 文件名与引用路径大小写严格一致，避免 Windows 正常、Linux 加载失败。
- 同一业务使用固定词汇，例如全项目统一使用 `arena`。

模块引用使用点分路径：

```lua
local PlayerManager = require "game.player.player_manager"
local TimeUtil = require "common.time_util"
```

## 3. Lua 代码命名

| 对象 | 命名规则 | 示例 |
| --- | --- | --- |
| 类、业务模块表 | PascalCase | Player、ArenaManager |
| 对外函数、方法 | PascalCase | GetPlayer、AddItem |
| 局部辅助函数 | camelCase | calculateReward |
| 参数、局部变量 | camelCase | playerId、rewardList |
| 对象字段 | camelCase | self.playerId |
| 内部方法 | _PascalCase | _LoadData |
| 常量 | UPPER_SNAKE_CASE | MAX_MAIL_COUNT |
| 枚举类型 | PascalCase | ArenaState |
| 枚举项 | UPPER_SNAKE_CASE | ArenaState.SETTLEMENT |

Skynet 自身接口保持原名，例如 `skynet.call`、`skynet.newservice`。内部方法的下划线仅表达约定，不提供访问权限隔离。

### 3.1 变量表达业务含义

```lua
local playerId = 10001
local onlinePlayerCount = 0
local isOnline = true
local hasReward = false
local canChallenge = true

local playerList = {}          -- 数组
local playerById = {}          -- playerId -> Player
local onlinePlayerIdSet = {}   -- playerId -> true
```

避免用 `a`、`tmp`、`data1` 表达重要业务数据。不使用 `nCount`、`strName`、`tbPlayer` 等类型前缀代替业务含义。

### 3.2 数量与时间写清语义

```lua
local usedChallengeCount = 0
local remainingChallengeCount = 5
local expireAtSec = 0          -- 到期时间戳，秒
local cooldownSec = 30         -- 时长，秒
local requestTimeoutMs = 1000  -- 时长，毫秒
local retryDelayTicks = 100    -- Skynet tick 数
```

已有字段必须保留确定的业务语义，同一个字段不能在不同位置分别表示“已使用次数”和“剩余次数”。

### 3.3 函数名称使用动词

| 前缀 | 用途 | 示例 |
| --- | --- | --- |
| Get | 获取数据，通常不修改状态 | GetPlayer |
| Find | 查找对象，允许不存在 | FindPlayer |
| Is / Has / Can | 布尔判断 | IsOnline、CanChallenge |
| Check | 校验条件，可返回失败原因 | CheckCanUseItem |
| Add / Remove | 增减成员或资源 | AddItem |
| Create / Destroy | 创建和销毁对象 | CreatePlayer |
| Load / Save | 加载和保存数据 | SavePlayer |
| Handle | 处理请求 | HandleChallenge |
| On | 事件和生命周期回调 | OnLogin |
| Sync | 同步状态 | SyncArenaInfo |

`Get` 函数应避免隐藏修改行为，例如 `GetReward()` 不应同时发奖并清空奖励。

## 4. 模块职责与调用方式

| 后缀 | 职责 |
| --- | --- |
| Service | 服务启动、消息分发和退出 |
| Handler | 请求解析、参数检查和调用业务接口 |
| Module | 挂载于玩家等对象上的功能模块 |
| Manager | 管理一组业务对象或业务生命周期 |
| Repository | 数据查询与持久化 |
| Client | 封装对外部系统的访问 |
| Util | 无业务状态的通用辅助逻辑 |
| Def | 常量、枚举和静态定义 |

建议调用方向：

```text
Service → Handler → Module / Manager → Repository / Client
                           ↓
                        Common
```

不要为了分层而强制每个功能创建全部文件，简单功能可以从一个模块开始。

对象方法使用冒号，模块静态函数使用点：

```lua
-- 获取实例所属玩家的 ID。
function Player:GetPlayerId()
    return self.playerId
end

-- 获取当前时间戳，单位为秒。
function TimeUtil.GetNowSec()
    return os.time()
end
```

模块优先使用 `local`，通过 `return` 导出接口，避免意外创建全局变量。

## 5. Skynet 消息与服务命名

项目自定义的 Lua 服务命令统一使用 `snake_case`：

```lua
local CMD = {}

-- 获取指定玩家的在线状态。
function CMD.get_player_status(playerId)
    return PlayerManager.GetPlayerStatus(playerId)
end
```

调用端保持完全一致：

```lua
local status = skynet.call(
    worldAddress,
    "lua",
    "get_player_status",
    playerId
)
```

| 类型 | 示例 | 含义 |
| --- | --- | --- |
| 服务脚本名 | "game/agent_service" | 加载服务入口 |
| 本地注册名 | ".world" | 定位本节点注册服务 |
| 服务地址变量 | worldAddress | 保存服务句柄 |

服务脚本名能否使用子目录取决于 `luaservice` 搜索路径。业务库的 `require` 由 Lua 模块搜索路径决定，应在启动配置中分别设置。

通信要求：

- `skynet.call` 用于需要响应的调用，`skynet.send` 用于单向消息。
- 存在协程让出的调用，不能默认调用前后的共享状态保持不变。
- 服务内部方法和消息接口分开管理，避免把内部函数自动全部暴露为远程命令。

## 6. 注释与代码组织

每个函数都应有准确的用途注释。重要函数补充说明：

- 参数、返回值及失败原因。
- 修改的状态。
- 是否写库、发消息或发放资源。
- 前置条件和调用顺序。
- 是否可能让出协程，以及并发处理要求。

示例：

```lua
local ItemModule = {}
ItemModule.__index = ItemModule

-- 创建玩家背包模块；在玩家数据加载后调用。
function ItemModule.New(player)
    local self = setmetatable({}, ItemModule)
    self.player = player
    return self
end

-- 检查道具是否可使用；不扣除道具，不发放奖励。
-- 返回：成功为 true；失败为 false, errorCode。
function ItemModule:CheckCanUseItem(itemId, count)
    if count <= 0 then
        return false, "INVALID_COUNT"
    end

    if self:GetItemCount(itemId) < count then
        return false, "ITEM_NOT_ENOUGH"
    end

    return true
end

-- 获取指定道具的持有数量；道具不存在时返回 0。
function ItemModule:GetItemCount(itemId)
    return self.player.itemCountById[itemId] or 0
end

return ItemModule
```

示例假定调用方已校验 `itemId`、`count` 的类型，且玩家数据包含 `itemCountById`；实际业务还应校验道具配置及其他使用条件。

单文件按以下顺序组织：

```text
依赖引用
→ 常量与枚举
→ 模块表
→ 局部辅助函数
→ 构造与初始化
→ 对外业务接口
→ 内部方法
→ 生命周期与清理
→ return 模块
```

## 7. 落地原则

- 新项目统一执行本规范。
- 已有项目优先保持一致的风格，逐步落实职责边界和业务语义。
- 涉及协议、持久化字段和跨服务命令的改名，必须检查所有生产者和消费者。
- 日志、注释和测试使用与代码一致的业务术语。
- 不为简单功能添加无实际用途的目录和抽象层。
