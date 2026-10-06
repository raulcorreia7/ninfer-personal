#!/usr/bin/env python3
# Stop only this installation; preview targets with --dry-run.
import argparse
import os
from pathlib import Path
import signal
import sys

import psutil

root = Path(__file__).resolve().parent
parser = argparse.ArgumentParser(description='Stop this NInfer installation and its child processes.')
parser.add_argument('--dry-run', action='store_true', help='list targets without stopping them')
args = parser.parse_args()
excluded = {os.getpid(), *(p.pid for p in psutil.Process().parents())}
uid = os.getuid()


def inside(path, directory=root):
    return Path(path).resolve().is_relative_to(directory)


def related(process):
    if process.pid in excluded or process.uids().real != uid:
        return False
    command = process.cmdline()
    if not command:
        return False
    cwd = Path(process.cwd())
    executable = Path(process.exe())
    name = executable.name
    if inside(executable) and name == 'ninfer-serve':
        return True
    if name.startswith('python') or name in {'bash', 'sh', 'dash'}:
        # Match executable script arguments, not strings embedded in shell commands.
        if len(command) > 1 and not command[1].startswith('-'):
            script = Path(command[1])
            script = script if script.is_absolute() else cwd / script
            if inside(script) and script.suffix in {'.py', '.sh'}:
                return True
        return False
    return inside(cwd) and name in {'cmake', 'ninja', 'make', 'ctest'}


def discover():
    roots, targets = {}, {}
    for process in psutil.process_iter():
        try:
            if not related(process):
                continue
            roots[process.pid] = process
            for child in [process, *process.children(recursive=True)]:
                if child.pid not in excluded and child.uids().real == uid:
                    targets[child.pid] = child
        except (psutil.NoSuchProcess, psutil.AccessDenied):
            continue
    root_ids = set(roots)
    for pid, process in list(roots.items()):
        try:
            if any(parent.pid in root_ids for parent in process.parents()):
                roots.pop(pid)
        except psutil.NoSuchProcess:
            roots.pop(pid, None)
    return roots, targets


roots, targets = discover()
if not targets:
    print('No NInfer processes running.')
    raise SystemExit(0)
for process in targets.values():
    try:
        print(f'{process.pid}: {process.name()}', flush=True)
    except psutil.NoSuchProcess:
        pass
if args.dry_run:
    raise SystemExit(0)

# Let the server flush its state first.
for sig, timeout in [(signal.SIGINT, 15), (signal.SIGTERM, 5), (signal.SIGKILL, 3)]:
    new_roots, new_targets = discover()
    targets.update(new_targets)
    recipients = {**roots, **new_roots} if sig == signal.SIGINT else targets
    for process in recipients.values():
        try:
            process.send_signal(sig)  # psutil checks PID reuse before sending.
        except psutil.NoSuchProcess:
            pass
        except psutil.AccessDenied:
            print(f'Cannot signal PID {process.pid}', file=sys.stderr)
    _, alive = psutil.wait_procs(list(targets.values()), timeout=timeout)
    if not alive and not discover()[1]:
        print('NInfer stopped.')
        raise SystemExit(0)
remaining = set(discover()[1]) | {p.pid for p in alive if p.is_running() and p.status() != psutil.STATUS_ZOMBIE}
if remaining:
    print('Still running: ' + ', '.join(map(str, sorted(remaining))), file=sys.stderr)
    raise SystemExit(1)
print('NInfer stopped.')
