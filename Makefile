.PHONY: all help allstart gamestart battlestart gatestart loginstart clientstart proto pids configtest

PYTHON ?= python3

all : help

help:
	@echo "make allstart: 启动所有节点"
	@echo "make gamestart: 启动game节点"
	@echo "make batlestart: 启动战斗节点"
	@echo "make gatestart: 启动网关节点"
	@echo "make loginstart: 启动登录节点"
	@echo "make clientstart: 启动测试节点"
	@echo "make proto: 编译 protocol/proto 下的 pb"
	@echo "make pids: 生成新 sro 协议的 pids（RO 迁移协议不要跑）"

gamestart:
	./skynet/skynet etc/config.gamenode

battlestart:
	./skynet/skynet etc/config.battlenode

gatestart:
	./skynet/skynet etc/config.gatenode

loginstart:
	./skynet/skynet etc/config.loginnode

allstart:

clientstart:
	./skynet/skynet etc/config.clientnode

proto:
	$(PYTHON) tools/proto/gen_protos.py
	$(PYTHON) tools/proto/gen_pids.py
	sh tool/proto.sh

pids:
	sh tool/gen_pids.sh

configtest:
	./skynet/skynet etc/config.configtest
