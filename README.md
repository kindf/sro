# SRO — Skynet MMORPG 服务端

SRO 是一个基于 [Skynet](https://github.com/cloudwu/skynet) 和 Lua 构建的 MMORPG 服务端项目。当前代码包含游戏节点启动入口、网关看门狗、世界与场景服务、Bot 客户端配置，以及游戏配置数据和协议生成工具。

> 项目仍在开发中。当前 `protocol/` 中的正式协议尚未完整恢复，目录 README 记录了现有测试协议和恢复流程；请按实际代码状态使用。

## 架构概览

游戏节点由 Skynet 启动，入口服务会启动世界服务、场景服务和 watchdog 网关。客户端接入端口默认是 `9000`，游戏配置中的最大客户端数为 `1000`。

```text
service/
├── botclient/   # Bot 客户端服务
├── config/      # 配置服务
├── game/        # 游戏节点入口
├── mongodb/     # MongoDB 相关服务
├── public/      # 公共服务
├── scene/       # 场景服务
├── watchdog/    # 网关与连接管理
└── world/       # 世界服务及客户端消息处理
```

其他主要目录：

- `lualib/`：Lua 通用库和业务模块。
- `gamedata/`：服务端配置表及其说明。
- `protocol/`：协议定义和生成产物；当前协议恢复进度见 [`protocol/README.md`](protocol/README.md)。
- `etc/`：Skynet 启动配置，包括 `config.game` 和 `config.botclient`。
- `tools/`、`tool/`：协议及相关资源生成工具。
- `tests/`：测试相关内容。
- `skynet/`：Skynet 框架子模块。

## 环境准备

- Linux/macOS 或其他已配置好 Skynet 构建环境的平台。
- Git、Make、Python 3，以及 Skynet 构建所需的编译工具链。
- 如需使用游戏数据或协议生成流程，请另行准备相应的原始数据和工具依赖。

克隆仓库并初始化 Skynet 子模块：

```bash
git clone --recurse-submodules https://github.com/kindf/sro.git
cd sro
```

若已先行克隆仓库，可运行：

```bash
git submodule update --init --recursive
```

请先根据 Skynet 及目标平台要求构建框架，再运行下方启动命令。

## 启动

启动游戏节点：

```bash
make game
```

该命令使用 `etc/config.game` 启动 Skynet，默认监听 `9000` 端口。

启动 Bot 客户端节点：

```bash
make bot
```

查看 Makefile 中的可用命令：

```bash
make
```

## 协议生成

`make proto` 会依次运行 Python 生成脚本，并调用协议编译脚本：

```bash
make proto
```

生成流程会更新协议列表和消息 ID 映射，并编译 `protocol/proto/` 中的 `.proto` 文件。当前协议目录的详细状态、消息 ID 规则和恢复建议请参阅 [`protocol/README.md`](protocol/README.md)。

## 游戏配置数据

服务端表数据位于 `gamedata/`。数据来源、生成文件格式、加载方式及重新生成说明见 [`gamedata/README.md`](gamedata/README.md)。配置数据由外部游戏配置资源转换生成，重新生成时需要提供对应资源目录。

## 许可与第三方组件

仓库包含 Skynet 子模块及其他第三方组件。使用或分发前，请分别查阅本仓库及相关依赖各自的许可文件。
