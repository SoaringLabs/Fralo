#!/usr/bin/env python3
"""Stop only matching preview executables from this workspace before relaunch."""
from pathlib import Path
import argparse
import ctypes
import os
import signal
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
PREVIEWS = {
    "workbench": ("workbench-preview", "Fralo Workbench Preview.app"),
    "design-lab": ("design-lab-preview", "Fralo Design Lab.app"),
}


def matches_preview(executable, root, kind):
    directory, bundle = PREVIEWS[kind]
    try:
        relative = Path(executable).relative_to(root / ".build" / directory)
    except ValueError:
        return False
    parts = relative.parts
    return (len(parts) == 5 and parts[0].startswith("session-")
            and parts[1:] == (bundle, "Contents", "MacOS", "FraloApp"))


def executable_reader():
    library = ctypes.CDLL("/usr/lib/libproc.dylib", use_errno=True)
    library.proc_pidpath.argtypes = [ctypes.c_int, ctypes.c_void_p, ctypes.c_uint32]
    library.proc_pidpath.restype = ctypes.c_int

    def read(pid):
        buffer = ctypes.create_string_buffer(4096)
        if library.proc_pidpath(pid, buffer, len(buffer)) <= 0:
            return None
        return os.fsdecode(buffer.value)

    return read


def stop_previews(targets, read_executable, send_signal=os.kill,
                  clock=time.monotonic, sleep=time.sleep):
    # Recheck the executable before every signal and while waiting: PIDs can be reused.
    def active():
        return {pid: path for pid, path in targets.items()
                if read_executable(pid) == path}

    def terminate(sig):
        for pid in active():
            try:
                send_signal(pid, sig)
            except ProcessLookupError:
                pass

    def wait(seconds):
        deadline = clock() + seconds
        while active() and clock() < deadline:
            sleep(0.05)
        return active()

    terminate(signal.SIGTERM)
    if wait(3):
        terminate(signal.SIGKILL)
    remaining = wait(2)
    if remaining:
        raise RuntimeError(f"Preview processes did not exit: {sorted(remaining)}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("kind", choices=PREVIEWS)
    args = parser.parse_args()
    read_executable = executable_reader()
    pids = subprocess.check_output(["ps", "-axo", "pid="], text=True).split()
    targets = {}
    for value in pids:
        pid = int(value)
        executable = read_executable(pid)
        if executable and matches_preview(executable, ROOT, args.kind):
            targets[pid] = executable
    stop_previews(targets, read_executable)
    if targets:
        print(f"Stopped old {args.kind} previews: {sorted(targets)}", file=sys.stderr)


if __name__ == "__main__":
    main()
