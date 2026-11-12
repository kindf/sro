"""Run from the repository root on Linux: python3 tests/integration/test_client_reconnect.py.

Starts an isolated server and bot processes on a temporary port. Only those child
processes are stopped. Existing server configurations and protocol files stay intact.
"""

import argparse
import concurrent.futures
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
    request_id = int(re.search(r'\["Scene.ReqMove"\]=(\d+)', pids)[1])
    response_id = int(re.search(r'\["Scene.RespMove"\]=(\d+)', pids)[1])
    # scene.proto: int32 common=1, float time/dx/dy/dz=2/3/4/5.
    body = b"\x08\x5a" + b"".join(
        bytes([(field << 3) | 5]) + struct.pack("<f", value)
        for field, value in [(2, 0.1), (3, 10), (4, 0), (5, 20)]
    )
    payload = struct.pack("<IB", request_id, 0) + body
    packet = struct.pack(">H", len(payload)) + payload

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

                # Each worker owns its socket; no protocol handshake or artificial delay needed.
                def connect_cycle(index):
                    """Alternate successful exchanges and disconnects at different packet stages."""
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
                        for _ in range(3):
                            size = struct.unpack(">H", receive_exact(client, 2))[0]
                            response = receive_exact(client, size)
                            assert struct.unpack("<IB", response[:5]) == (response_id, 0)

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
                            wait_for_log(bot, bot_log, "收到移动响应")
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
                assert "stack traceback" not in content, "server logged an exception"
                print(f"OK reconnect: {args.cycles} connections, {args.bot_cycles} bot restarts, "
                      f"server fds {before_fds} -> {after_fds}")
            except BaseException:
                print(log.read_text(errors="replace")[-6000:])
                raise
            finally:
                stop_process(server)


if __name__ == "__main__":
    main()
