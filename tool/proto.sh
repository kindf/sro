#!/bin/sh
# 一个 proto 对应一个 pb；目录为空时跳过。
set -e
cd "$(dirname "$0")/../protocol/proto"

set -- *.proto
if [ ! -e "$1" ]; then
    echo "protocol/proto: no .proto, skip"
    exit 0
fi

for file in "$@"; do
    protoc --proto_path=. --descriptor_set_out=../pb/"${file%.proto}.pb" "$file"
done
echo "protoc: protocol/proto/*.proto -> protocol/pb/*.pb"