class_name CommandRejection
extends RefCounted
## What herdr's own refusal of a command said, typed: a REJECTED ticket keeps
## herdr's error code as it came (`error_code`, cleaned and bounded, for the
## audit and the log) and this Code beside it (`rejection`), which the agent
## card words. Only codes herdr 0.9.0 was seen answering the allowlist with
## (docs/WRITE_BOUNDARY.md §6) have a Code of their own; any other is
## OTHER. herdr's message is remote free text: it stays on the ticket,
## bounded, and never picks a Code.

enum Code {
	## A code this office has no words for.
	OTHER,
	## A one-line prompt to a blocked agent: herdr wrote nothing.
	AGENT_BLOCKED,
	## A prompt to a pane with no agent herdr knows (a shell).
	AGENT_NOT_FOUND,
	## A prompt to an agent herdr is still launching.
	AGENT_NOT_READY,
	## A prompt with no text.
	EMPTY_AGENT_PROMPT,
	## A start with a name another agent holds (a launch still pending keeps
	## its name until herdr settles its timeout).
	AGENT_NAME_TAKEN,
	## A start in a pane that is not a shell at its prompt (an agent, or
	## another program in front).
	AGENT_PANE_BUSY,
	## A start in a pane herdr does not list.
	AGENT_PANE_NOT_FOUND,
	INVALID_AGENT_NAME,
	## A start with a kind herdr cannot start.
	UNSUPPORTED_AGENT_KIND,
	INVALID_AGENT_TIMEOUT,
	INVALID_AGENT_ARGUMENT,
	## Any pane method, to a pane herdr does not list.
	PANE_NOT_FOUND,
	## A request herdr could not read (a missing field, an unknown variant).
	INVALID_REQUEST,
	## A key herdr has no name for.
	INVALID_KEY,
	## herdr gave up waiting.
	TIMEOUT,
	## A close herdr wants its own confirm for: the last pane of a worktree
	## group's parent (never sent by this office; measured when it is).
	CONFIRMATION_REQUIRED,
	## A worktree from a workspace herdr does not list.
	WORKSPACE_NOT_FOUND,
	## A worktree from a workspace that is not inside a git work tree.
	NOT_GIT_WORKTREE,
	## A worktree from a linked worktree (a mezzanine).
	LINKED_WORKTREE_SOURCE,
	## git refused: the message's headline is git's own line (GitWords).
	WORKTREE_CREATE_FAILED,
	WORKSPACE_CREATE_FAILED,
	## A workspace with an environment herdr cannot take (never sent).
	INVALID_ENV,
}

## herdr's codes, exactly as it spells them, and the Code each one is.
const _CODES: Dictionary[String, Code] = {
	"agent_blocked": Code.AGENT_BLOCKED,
	"agent_not_found": Code.AGENT_NOT_FOUND,
	"agent_not_ready": Code.AGENT_NOT_READY,
	"empty_agent_prompt": Code.EMPTY_AGENT_PROMPT,
	"agent_name_taken": Code.AGENT_NAME_TAKEN,
	"agent_pane_busy": Code.AGENT_PANE_BUSY,
	"agent_pane_not_found": Code.AGENT_PANE_NOT_FOUND,
	"invalid_agent_name": Code.INVALID_AGENT_NAME,
	"unsupported_agent_kind": Code.UNSUPPORTED_AGENT_KIND,
	"invalid_agent_timeout": Code.INVALID_AGENT_TIMEOUT,
	"invalid_agent_argument": Code.INVALID_AGENT_ARGUMENT,
	"pane_not_found": Code.PANE_NOT_FOUND,
	"invalid_request": Code.INVALID_REQUEST,
	"invalid_key": Code.INVALID_KEY,
	"timeout": Code.TIMEOUT,
	"confirmation_required": Code.CONFIRMATION_REQUIRED,
	"workspace_not_found": Code.WORKSPACE_NOT_FOUND,
	"not_git_worktree": Code.NOT_GIT_WORKTREE,
	"linked_worktree_source": Code.LINKED_WORKTREE_SOURCE,
	"worktree_create_failed": Code.WORKTREE_CREATE_FAILED,
	"workspace_create_failed": Code.WORKSPACE_CREATE_FAILED,
	"invalid_env": Code.INVALID_ENV,
}
## A few words, for the card's line after "herdr refused:".
const _TEXTS: Dictionary[Code, String] = {
	Code.OTHER: "refused",
	Code.AGENT_BLOCKED: "blocked: use the keys",
	Code.AGENT_NOT_FOUND: "no agent here",
	Code.AGENT_NOT_READY: "still starting",
	Code.EMPTY_AGENT_PROMPT: "empty",
	Code.AGENT_NAME_TAKEN: "name taken",
	Code.AGENT_PANE_BUSY: "pane busy",
	Code.AGENT_PANE_NOT_FOUND: "pane gone",
	Code.INVALID_AGENT_NAME: "bad name",
	Code.UNSUPPORTED_AGENT_KIND: "kind unknown to herdr",
	Code.INVALID_AGENT_TIMEOUT: "bad timeout",
	Code.INVALID_AGENT_ARGUMENT: "bad argument",
	Code.PANE_NOT_FOUND: "pane gone",
	Code.INVALID_REQUEST: "bad request",
	Code.INVALID_KEY: "unknown key",
	Code.TIMEOUT: "timed out",
	Code.CONFIRMATION_REQUIRED: "needs herdr's own confirm",
	Code.WORKSPACE_NOT_FOUND: "space gone",
	Code.NOT_GIT_WORKTREE: "not a git repo",
	Code.LINKED_WORKTREE_SOURCE: "start from the repo's own floor",
	Code.WORKTREE_CREATE_FAILED: "git: ",
	Code.WORKSPACE_CREATE_FAILED: "space not made",
	Code.INVALID_ENV: "bad environment",
}
## The same in full, for a tooltip.
const _DETAILS: Dictionary[Code, String] = {
	Code.OTHER: "herdr refused this for a reason this office has no words for.",
	Code.AGENT_BLOCKED: "the agent is blocked on a question, so herdr wrote nothing: answer it with the keys.",
	Code.AGENT_NOT_FOUND: "herdr knows no agent in this pane.",
	Code.AGENT_NOT_READY: "herdr is still launching this agent and takes no prompt for it yet.",
	Code.EMPTY_AGENT_PROMPT: "herdr does not send an empty prompt.",
	Code.AGENT_NAME_TAKEN: "another agent on this machine holds that name; nothing was retried under another.",
	Code.AGENT_PANE_BUSY: "herdr starts an agent only in a shell at its prompt, with nothing else in front.",
	Code.AGENT_PANE_NOT_FOUND: "herdr does not list this pane.",
	Code.INVALID_AGENT_NAME: "herdr does not take that agent name.",
	Code.UNSUPPORTED_AGENT_KIND: "herdr cannot start an agent of that kind.",
	Code.INVALID_AGENT_TIMEOUT: "herdr does not take that start timeout.",
	Code.INVALID_AGENT_ARGUMENT: "herdr cannot pass those arguments to the shell safely.",
	Code.PANE_NOT_FOUND: "herdr does not list this pane.",
	Code.INVALID_REQUEST: "herdr could not read the request.",
	Code.INVALID_KEY: "herdr has no key by that name.",
	Code.TIMEOUT: "herdr gave up waiting; what it did before that is not known.",
	Code.CONFIRMATION_REQUIRED:
	"closing this pane would close a worktree group, which herdr confirms in its own view only; nothing closed.",
	Code.WORKSPACE_NOT_FOUND: "herdr does not list this pane's workspace any more.",
	Code.NOT_GIT_WORKTREE: "herdr found no git work tree for this workspace.",
	Code.LINKED_WORKTREE_SOURCE:
	"this workspace is a linked worktree; herdr makes a new one from the repo's own workspace.",
	Code.WORKTREE_CREATE_FAILED: "git refused to make the worktree; its first line is shown.",
	Code.WORKSPACE_CREATE_FAILED: "herdr could not make the workspace.",
	Code.INVALID_ENV: "herdr could not take the workspace's environment.",
}


## The Code herdr's `code` is, compared exactly; OTHER for any other.
static func of(code: String) -> Code:
	return _CODES.get(code, Code.OTHER)


## A few words for `code`, for a line of the agent card.
static func text(code: Code) -> String:
	return _TEXTS.get(code, _TEXTS[Code.OTHER])


## `code` as a sentence, for a tooltip.
static func detail(code: Code) -> String:
	return _DETAILS.get(code, _DETAILS[Code.OTHER])


## The enum name, for logs and tests: `AGENT_BLOCKED`.
static func name_of(code: Code) -> String:
	return str(Code.find_key(code))
