
í
scene.protoScene"e
ReqMove
common (Rcommon
time (Rtime
dx (Rdx
dy (Rdy
dz (Rdz"ê
RespMove
common (Rcommon
time (Rtime
dx (Rdx
dy (Rdy
dz (Rdz
forced (Rforced
uid (Ruid"”
	UnitEnter
uid (Ruid
x (Rx
y (Ry
z (Rz
common (Rcommon
hp (Rhp
maxHp (RmaxHp
entityId (RentityId
unitType	 (RunitType
count
 (Rcount"
	UnitLeave
uid (Ruid"F
ReqCastSkill
skillId (RskillId
	targetUid (R	targetUid"Z
SkillHit
uid (Ruid
damage (Rdamage
hp (Rhp
maxHp (RmaxHp"ö
RespCastSkill
code (Rcode
	targetUid (R	targetUid
damage (Rdamage
targetHp (RtargetHp#
hits (2.Scene.SkillHitRhits"@
UnitHp
uid (Ruid
hp (Rhp
maxHp (RmaxHp"
UnitDead
uid (Ruid"
	ReqRevive"n

RespRevive
uid (Ruid
x (Rx
y (Ry
z (Rz
hp (Rhp
maxHp (RmaxHp"©
RespExp
uid (Ruid
baseExp (RbaseExp
jobExp (RjobExp"
totalBaseExp (RtotalBaseExp 
totalJobExp (RtotalJobExp
level (Rlevel")
	ReqPickup
	targetUid (R	targetUid"N

RespPickup
code (Rcode
itemId (RitemId
count (Rcount"L
ItemInfo
slot (Rslot
itemId (RitemId
count (Rcount"2
	RespItems%
items (2.Scene.ItemInfoRitems"N

ItemUpdate
slot (Rslot
itemId (RitemId
count (Rcount"6

ReqUseItem
slot (Rslot
count (Rcount"O
RespUseItem
code (Rcode
itemId (RitemId
count (Rcount"7
ReqDropItem
slot (Rslot
count (Rcount"P
RespDropItem
code (Rcode
itemId (RitemId
count (Rcount"P
UnitBuff
uid (Ruid
buffId (RbuffId
duration (Rduration"å
UnitAttr
uid (Ruid
atk (Ratk
def (Rdef
maxHp (RmaxHp
hp (Rhp
sp (Rsp
maxSp (RmaxSp""
ReqEquipItem
slot (Rslot"Y
RespEquipItem
code (Rcode
	equipSlot (R	equipSlot
itemId (RitemId".
ReqUnequipItem
	equipSlot (R	equipSlot"[
RespUnequipItem
code (Rcode
	equipSlot (R	equipSlot
itemId (RitemId"$
ReqEnter
sceneId (RsceneId"O
	RespEnter
sceneId (RsceneId
x (Rx
y (Ry
z (Rz