# sro/tools/proto

协议生成工具，两个脚本。

## gen_protos.py

扫描 `protocol/proto/*.proto` 的 `import`，拓扑排序后生成 `protocol/protos.lua`：

```lua
return {
"common",
"move",
"scene",
}
```

- 被依赖的 proto 排在前面；
- `--check` 只检查缺失 import / 循环依赖；
- 目录为空时生成空表。

## gen_pids.py

为每个 message 分配唯一协议号，生成 `protocol/pids.lua`。

规则：

- 一个 message 一个 id；
- 每个 message 两个条目：

```lua
["KKSG.MoveInfo"]=123456,
[123456]="KKSG.MoveInfo",
```

- id = `crc32("package.message")`，确定性；冲突时线性探测；
- `--check` 校验 id 唯一。

## make proto

```make
proto:
	$(PYTHON) tools/proto/gen_protos.py
	$(PYTHON) tools/proto/gen_pids.py
	sh tool/proto.sh
```

`tool/proto.sh` 再把每个 proto 编译成同名 `.pb`（不加 `--include_imports`）。

## 注意

- `pids.lua` 不再使用原来的 `PTCC2G_*` 协议号，而是“message 名 ↔ 新 id”；
  `head_codec` 的 `id` 字段就是这里的 id。
- 包名必须写进 message 全名；`package test;` 会生成 `test.Test` 这类 key。
- 原来的 `proto_map.csv` / `proto_api.lua` / `slim_proto.py` 已删除。
