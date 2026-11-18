"""Run from the repository root on Linux: python3 tests/integration/test_client_reconnect.py.

Starts an isolated server and bot processes on a temporary port. Only those child
processes are stopped. Existing server configurations and protocol files stay intact.
"""

import argparse
import concurrent.futures
import io
import pathlib
import re
import socket
import struct
import subprocess
import tempfile
import time


def receive_exact(client, size):
    """Read a complete response or fail if the server closes the connection."""
    result = b""
    while len(result) < size:
        data = client.recv(size - len(result))
        assert data, "server disconnected before response"
        result += data
    return result


def read_varint(stream):
    """Read an integer field from a protobuf response."""
    value = 0
    for shift in range(0, 64, 7):
        byte = stream.read(1)
        assert byte, "truncated varint in movement response"
        value |= (byte[0] & 127) << shift
        if byte[0] < 128:
            return value
    raise AssertionError("invalid varint in movement response")


def numeric_fields(body):
    """Decode scalar integer and float fields used by movement and unit notifications."""
    stream = io.BytesIO(body)
    fields = {}
    while stream.tell() < len(body):
        tag = read_varint(stream)
        if tag & 7 == 5:
            fields[tag >> 3] = struct.unpack("<f", stream.read(4))[0]
        else:
            assert tag & 7 == 0, f"unexpected numeric field wire type: {tag & 7}"
            fields[tag >> 3] = read_varint(stream)
    return fields


def receive_packet(client):
    """Read one server packet and split its header from the protobuf body."""
    size = struct.unpack(">H", receive_exact(client, 2))[0]
    response = receive_exact(client, size)
    pid, flag = struct.unpack("<IB", response[:5])
    assert flag == 0
    return pid, response[5:]


def check_scene_updates(port, ids):
    """A stationary player must see a spawned monster move on successive scene ticks."""
    with socket.create_connection(("127.0.0.1", port), timeout=5) as client:
        positions = {}
        moved = set()
        deadline = time.monotonic() + 5
        while time.monotonic() < deadline:
            pid, body = receive_packet(client)
            if pid == ids["Scene.UnitEnter"]:
                fields = numeric_fields(body)
                if fields.get(9) == 1:
                    positions[fields[1]] = fields[2], fields[4]
            elif pid == ids["Scene.RespMove"]:
                fields = numeric_fields(body)
                uid = fields[7]
                position = fields[3], fields[5]
                if uid in positions and positions[uid] != position:
                    if uid in moved:
                        return
                    moved.add(uid)
                    positions[uid] = position
        raise AssertionError("spawned monsters did not continue moving")


def stop_process(process):
    """Reap only a child created by this test, with bounded shutdown time."""
    if process.poll() is None:
        process.terminate()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=5)


def wait_for_log(process, log, marker):
    """Wait for readiness while detecting startup failures and crashes."""
    deadline = time.monotonic() + 10
    while time.monotonic() < deadline:
        assert process.poll() is None, f"process exited: {process.returncode} ({log})"
        if marker in log.read_text(errors="replace"):
            return
        time.sleep(0.02)
    raise AssertionError(f"timed out waiting for {marker!r} ({log})")


def main():
    """Exercise valid requests, early closes, TCP resets, and bot termination."""
    parser = argparse.ArgumentParser()
    parser.add_argument("--cycles", type=int, default=200)
    parser.add_argument("--bot-cycles", type=int, default=10)
    parser.add_argument("--lua-prefix", default="", help="optional diagnostic module overlay")
    args = parser.parse_args()
    pids = pathlib.Path("protocol/pids.lua").read_text()
    ids = {name: int(pid) for name, pid in re.findall(r'\["([^"]+)"\]=(\d+)', pids)}

    with socket.socket() as reservation:
        reservation.bind(("127.0.0.1", 0))
        port = reservation.getsockname()[1]

    with tempfile.TemporaryDirectory(prefix="sro-reconnect-") as temporary:
        directory = pathlib.Path(temporary)
        config = directory / "server.config"
        config.write_text('include "' + str(pathlib.Path("etc/config.game").resolve())
                          + f'"\ngateport = {port}\n'
                          + (f'lua_path = "{args.lua_prefix}/?.lua;" .. lua_path\n'
                             if args.lua_prefix else ""))
        log = directory / "server.log"
        with log.open("wb") as output:
            server = subprocess.Popen(["./skynet/skynet", str(config)], stdout=output, stderr=output)
            try:
                wait_for_log(server, log, "Listen on")
                check_scene_updates(port, ids)

                # Each worker owns its socket; no protocol handshake or artificial delay needed.
                def connect_cycle(index):
                    """Alternate successful exchanges and disconnects at different packet stages."""
                    # An exactly representable time distinguishes this client's moves from AOI broadcasts.
                    move_time = (index % 4096 + 1) / 4096
                    x, y, z = 155.5, 7.8, 130.5
                    body = b"\x08\x5a" + b"".join(
                        bytes([(field << 3) | 5]) + struct.pack("<f", value)
                        for field, value in enumerate((move_time, x, y, z), 2)
                    )
                    payload = struct.pack("<IB", ids["Scene.ReqMove"], 0) + body
                    packet = struct.pack(">H", len(payload)) + payload
                    with socket.create_connection(("127.0.0.1", port), timeout=3) as client:
                        mode = index % 5
                        if mode == 1:
                            return
                        if mode == 2:
                            client.sendall(packet[:3])
                            return
                        if mode == 3:
                            client.sendall(packet)
                            client.setsockopt(socket.SOL_SOCKET, socket.SO_LINGER, struct.pack("ii", 1, 0))
                            return
                        client.sendall(packet * 3)
                        matched = 0
                        deadline = time.monotonic() + 3
                        while matched < 3:
                            assert time.monotonic() < deadline, "timed out waiting for own movement"
                            pid, body = receive_packet(client)
                            if pid != ids["Scene.RespMove"]:
                                continue
                            fields = numeric_fields(body)
                            if fields[2] != move_time or fields[1] != 90:
                                continue
                            assert not fields.get(6), "valid move was forced back"
                            assert (fields[3], fields[5]) == (x, z) and abs(fields[4] - y) < 0.001
                            matched += 1

                connect_cycle(0)
                time.sleep(0.2)
                fd_path = pathlib.Path(f"/proc/{server.pid}/fd")
                before_fds = len(list(fd_path.iterdir()))
                with concurrent.futures.ThreadPoolExecutor(max_workers=8) as workers:
                    list(workers.map(connect_cycle, range(args.cycles)))

                bot_config = directory / "bot.config"
                bot_config.write_text('include "' + str(pathlib.Path("etc/config.botclient").resolve())
                                      + f'"\ngateport = {port}\n')
                for index in range(args.bot_cycles):
                    bot_log = directory / f"bot-{index}.log"
                    with bot_log.open("wb") as bot_output:
                        bot = subprocess.Popen(["./skynet/skynet", str(bot_config)],
                                               stdout=bot_output, stderr=bot_output)
                        try:
                            wait_for_log(bot, bot_log, "[Receive] recv id:Scene.RespMove ")
                        finally:
                            stop_process(bot)
                    assert server.poll() is None, "server crashed after bot shutdown"

                time.sleep(0.5)
                connect_cycle(0)
                time.sleep(0.2)
                assert server.poll() is None, f"server crashed: {server.returncode}"
                after_fds = len(list(fd_path.iterdir()))
                assert after_fds <= before_fds + 2, f"socket leak: {before_fds} -> {after_fds}"
                content = log.read_text(errors="replace")
                assert "Player not found" not in content, "forward removed a live player"
                for line in content.splitlines():
                    assert "stack traceback" not in line, f"server logged an exception: {line}"
                print(f"OK reconnect: {args.cycles} connections, {args.bot_cycles} bot restarts, "
                      f"server fds {before_fds} -> {after_fds}")
            except BaseException:
                print(log.read_text(errors="replace")[-6000:])
                raise
            finally:
                stop_process(server)


if __name__ == "__main__":
    main()
