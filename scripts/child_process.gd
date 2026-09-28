class_name ChildProcess
extends RefCounted
## One child process started through OS.execute_with_pipe and polled, never
## waited on: MachineLink's ssh and MachineRoster's `herdr machine list` both run
## on this. Knows no rendering and nothing of what the child is for.
##
## The pipes are non-blocking, so draining one that holds nothing costs nothing,
## and each stream keeps only its tail: a chatty or hostile child cannot grow
## either buffer past the bound its owner chose.

## Bytes each drain() asks a pipe for. A child blocks once its pipe is full, so
## this is read every poll whatever the tail keeps.
const READ_CHUNK := 65536

## The child's process id; -1 before a start, after a failed one, and once the
## child has been killed or let go.
var pid := -1
## The last bytes the child wrote to stdout, as drained so far.
var stdout := PackedByteArray()
## The last bytes the child wrote to stderr, as drained so far.
var stderr := PackedByteArray()

var _stdout_keep := 0
var _stderr_keep := 0
var _stdio: FileAccess
var _stderr_pipe: FileAccess


## `stdout_keep` and `stderr_keep` bound each stream's tail, in bytes.
func _init(stdout_keep: int, stderr_keep: int) -> void:
	_stdout_keep = stdout_keep
	_stderr_keep = stderr_keep


## Start `path` with `argv`, forgetting whatever an earlier child printed. False
## when nothing could be started.
func spawn(path: String, argv: PackedStringArray) -> bool:
	stdout = PackedByteArray()
	stderr = PackedByteArray()
	var pipes := OS.execute_with_pipe(path, argv, false)
	if pipes.is_empty():
		release()
		return false
	_stdio = pipes.stdio
	_stderr_pipe = pipes.stderr
	var started: int = pipes.pid
	pid = started
	return true


func running() -> bool:
	return pid > 0 and OS.is_process_running(pid)


## The exit code of a child that is no longer running.
func exit_code() -> int:
	return OS.get_process_exit_code(pid)


## Pull whatever the child printed since the last drain, keeping each tail.
func drain() -> void:
	if _stdio == null:
		return
	stdout.append_array(_stdio.get_buffer(READ_CHUNK))
	stderr.append_array(_stderr_pipe.get_buffer(READ_CHUNK))
	if stdout.size() > _stdout_keep:
		stdout = stdout.slice(stdout.size() - _stdout_keep)
	if stderr.size() > _stderr_keep:
		stderr = stderr.slice(stderr.size() - _stderr_keep)


## Forget what the child printed to stderr, as a complaint that no longer applies.
func clear_stderr() -> void:
	stderr = PackedByteArray()


## Stop the child if it still runs, then let it go. OS.kill also reaps it, so its
## pid must not be asked about again afterwards.
func kill() -> void:
	if running():
		OS.kill(pid)
	release()


## Let go of a child that has exited, keeping what it printed.
func release() -> void:
	pid = -1
	_stdio = null
	_stderr_pipe = null
