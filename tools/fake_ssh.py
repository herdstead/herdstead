#!/usr/bin/env python3
"""Stand-in for ssh in tools/test_machines.gd. Never opens a network connection.

Understands exactly the two argv shapes MachineLink builds:

  fake_ssh.py <options> -- <target> <command>            -> runs it with HOME=$FAKE_SSH_HOME
  fake_ssh.py -N <options> -L <local>:<remote> -- <target> -> relays local to remote

The relay accepts on <local> and pipes each connection to the unix socket
<remote>, which is what `ssh -L` does across the network. Every call appends its
argv as one JSON line to $FAKE_SSH_LOG when set, so the test can check that the
target arrived as a single element. FAKE_SSH_FAIL=<message> makes every call
print the message to stderr and exit 255, like ssh refused by the far side.
FAKE_SSH_NOISE=<text> is printed before the command runs, like a login shell's
rc files do, and FAKE_SSH_SWALLOW=1 prints only that and never runs the command.
`%%` in the -L paths is a literal `%`, as in OpenSSH.
"""

import json
import os
import socket
import subprocess
import sys
import threading


def pipe(source, sink):
    try:
        while True:
            data = source.recv(65536)
            if not data:
                break
            sink.sendall(data)
    except OSError:
        pass
    finally:
        for end in (source, sink):
            try:
                end.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass


def relay(local, remote):
    if os.path.exists(local):
        os.unlink(local)
    listener = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    listener.bind(local)
    listener.listen(16)
    while True:
        client, _ = listener.accept()
        upstream = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        try:
            upstream.connect(remote)
        except OSError as error:
            # Real ssh keeps running and complains per connection.
            print(f"channel 2: open failed: connect failed: {error.strerror or error}", file=sys.stderr, flush=True)
            client.close()
            continue
        threading.Thread(target=pipe, args=(client, upstream), daemon=True).start()
        threading.Thread(target=pipe, args=(upstream, client), daemon=True).start()


def main():
    argv = sys.argv[1:]
    log = os.environ.get("FAKE_SSH_LOG")
    if log:
        with open(log, "a", encoding="utf-8") as handle:
            handle.write(json.dumps(argv) + "\n")
    failure = os.environ.get("FAKE_SSH_FAIL")
    if failure:
        print(failure, file=sys.stderr, flush=True)
        return 255
    if "--" not in argv:
        print("fake_ssh: no -- before the target", file=sys.stderr)
        return 255
    if "-N" not in argv:
        sys.stdout.write(os.environ.get("FAKE_SSH_NOISE", ""))
        sys.stdout.flush()
        if os.environ.get("FAKE_SSH_SWALLOW"):
            return 0
        command = argv[argv.index("--") + 2]
        env = dict(os.environ, HOME=os.environ.get("FAKE_SSH_HOME", "/home/fake"))
        return subprocess.run(["/bin/sh", "-c", command], env=env).returncode
    local, remote = argv[argv.index("-L") + 1].split(":", 1)
    relay(local.replace("%%", "%"), remote.replace("%%", "%"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
