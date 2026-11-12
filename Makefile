.PHONY: game bot proto 

PYTHON ?= python3

all : help

help:
	@echo "make game: 启动game节点"
	@echo "make bot: 启动botclient节点"
	@echo "make proto: 编译 protocol/proto 下的 pb"

game:
	./skynet/skynet etc/config.game

bot:
	./skynet/skynet etc/config.botclient

proto:
	$(PYTHON) tools/proto/gen_protos.py
	$(PYTHON) tools/proto/gen_pids.py
	sh tool/proto.sh
