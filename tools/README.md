# sro/tools

离线工具目录。**不参与运行时**，只做代码/数据生成与校验。

| 目录 | 作用 |
|---|---|
| `proto/` | 从老 C++ 服务端头文件生成协议映射表（迁移期网关用） |

约定：

- 生成器用 Python（Windows 下用 DSH 自带解释器，见各目录 README）。
- 生成物（`.lua` / `.csv` / `.txt`）提交仓库；生成器只在源数据变更时重跑。
- 运行时的 shell 脚本在 `sro/tool/`（注意是单数），不要混。

与现有目录的关系：

| 路径 | 是什么 |
|---|---|
| `sro/proto/` | 新 sro 自己跑的协议：`*.proto` + `pb/*.pb` + 手写 `proto_map.lua` |
| `sro/tools/proto/` | 老 roserver 的 1649 个协议号 → 名字映射，给迁移网关用 |
