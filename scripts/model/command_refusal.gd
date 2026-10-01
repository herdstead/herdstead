class_name CommandRefusal
extends RefCounted
## Why a command to herdr is not sent. HerdrCommands decides it, at the send
## port: before any socket is opened, and for an input command once more right
## after its re-read, before the write. The agent card shows these same reasons
## ("Not sent: …", "No switch: …", "No writes: …", and why its answer controls
## are off), and adds two of its own about the reply box (LINE_COMPOSING,
## LINE_EDITED), decided at the press and release of "Send line".

enum Reason {
	## Nothing stands in the way.
	NONE,
	## Started with `--read-only`: this office has no write capability at all.
	READ_ONLY,
	## Nothing here is wired to herdr (the showroom, a panel shown on its own).
	NOT_CONNECTED,
	## A method, source, format or line count outside the allowlist.
	NOT_ALLOWED,
	## The handshake announced a protocol this office was not verified against.
	UNKNOWN_PROTOCOL,
	## No machine by that key is shown any more.
	MACHINE_GONE,
	## The machine's generation moved on since the command was aimed: it was
	## replaced, disabled and enabled again, or it reconnected.
	MACHINE_REPLACED,
	MACHINE_OFFLINE,
	## Online, but no complete snapshot has been read on this connection yet.
	SNAPSHOT_NOT_CURRENT,
	## The machine's current snapshot has no pane by that id.
	PANE_GONE,
	## The pane has no terminal id, so nothing tells this terminal from the next.
	IDENTITY_UNKNOWN,
	## Same pane id, but another terminal, agent or session than was aimed at.
	IDENTITY_CHANGED,
	## herdr spells the pane id differently from the id the office cleaned.
	WIRE_ID_MISMATCH,
	## herdr lists that pane id more than once.
	WIRE_ID_DUPLICATE,
	## A write to this pane is still under way: one at a time per pane.
	IN_FLIGHT,
	## A write to this pane ended and no preview read after it has been shown
	## yet: look before writing again.
	LOOK_FIRST,
	## A key outside the answer keys (`1`–`9`, `y`, `n`, `enter`, `esc`).
	KEY_NOT_ALLOWED,
	## A line that is empty or only whitespace.
	LINE_BLANK,
	## A line over HerdrCommands.LINE_BYTES_MAX bytes of UTF-8.
	LINE_TOO_LONG,
	## A line with a control character: C0 (tab, CR, LF, ESC …), DEL, C1 (NEL
	## …), U+2028 or U+2029.
	LINE_CONTROL,
	## A line with an invisible or direction-changing format character.
	LINE_INVISIBLE,
	## A line with U+FFFD, a lone surrogate or a noncharacter: what it would
	## send is not what was typed.
	LINE_BROKEN,
	## The pane runs no agent: text to a shell is a command.
	NOT_AN_AGENT,
	## herdr is still launching the agent; its state says nothing yet.
	AGENT_STARTING,
	## Answer keys go only to an agent herdr reports blocked.
	NOT_ASKING,
	## A line never goes to a blocked agent: its Enter could confirm the default.
	AGENT_ASKING,
	## A line goes only to an idle or done agent: a working one's screen keeps
	## changing, and an unknown state says nothing.
	AGENT_BUSY,
	## No usable terminal text of this pane was frozen at the press: none shown,
	## another pane's or binding's, cut, or from the wrong source.
	UNSEEN,
	## The re-read right before the write differs from the text frozen at the press.
	SCREEN_CHANGED,
	## The re-read came back cut, so it could not be compared.
	SCREEN_CUT,
	## The re-read right before the write brought no text back.
	RECHECK_FAILED,
	## The card's own, at the press or release of "Send line": an input method
	## is still composing in the reply box, so what it holds is not the line yet.
	LINE_COMPOSING,
	## The card's own, at the release of "Send line": the reply box no longer
	## holds the line aimed at the press.
	LINE_EDITED,
	## The monitor's raw mode (docs/WRITE_BOUNDARY.md §3): a key its key map does not send
	## (a Cmd chord, an F key with a modifier, Ctrl+Shift+letter …).
	KEY_UNSUPPORTED,
	## Home, End, PgUp, PgDn, Insert or Delete: herdr 0.9.0 has no name for
	## them (measured: every spelling is `invalid_key`).
	KEY_UNREACHABLE,
	## Typed text with a control character: those go as keys, never as text.
	TEXT_CONTROL,
	## Typed text or a paste with U+FFFD, a lone surrogate or a noncharacter.
	TEXT_BROKEN,
	## Typed text over HerdrCommands.TEXT_BYTES_MAX bytes in one request.
	TEXT_TOO_LONG,
	## Nothing to send: no key, no character, an empty clipboard.
	INPUT_EMPTY,
	## A paste holding ESC or a C1 control, which could end herdr's bracketed
	## paste early and run the rest as typed input.
	PASTE_ESCAPE,
	## A paste over HerdrCommands.PASTE_BYTES_MAX bytes: refused, never cut.
	PASTE_TOO_LONG,
	## The pane's raw input queue already holds HerdrCommands.RAW_QUEUE_EVENTS
	## events: the newest is refused, nothing queued is dropped.
	QUEUE_FULL,
	## A paste holding a control character a terminal acts on: C0 but tab,
	## newline and carriage return, DEL, U+2028 or U+2029.
	PASTE_CONTROL,
	## A paste holding a direction control: what the viewer sees would not be
	## what the shell reads (U+061C, U+200E, U+200F, U+202A–U+202E, U+2066–U+2069).
	PASTE_INVISIBLE,
	## Start only: herdr detects an agent in the pane; an agent starts only in a shell.
	NOT_A_SHELL,
	## Start only: no whole recent output of the terminal was there to look for a
	## prompt in (empty, cut, or another source): PromptState.Kind.NO_PROMPT.
	NO_PROMPT,
	## Start only: the last line does not end like a prompt
	## (PromptState.Kind.UNSURE) and the viewer did not confirm starting anyway.
	PROMPT_UNSURE,
	## Start only: no agent of that kind is seen on this machine's snapshot.
	KIND_UNKNOWN,
	## Start only: a kind not spelled `^[a-z][a-z0-9_-]{0,31}$`.
	KIND_INVALID,
	## Start only: a name not spelled `^[a-z][a-z0-9_-]{0,31}$`.
	NAME_INVALID,
	## Start only: an agent on this machine's snapshot already has that name.
	NAME_TAKEN,
	## Split only: not `right` or `down`, or not the side the pane's shape gives.
	DIRECTION_INVALID,
	## Split only: either half would be under 40 columns or 10 rows.
	PANE_TOO_SMALL,
	## Split only: herdr's layout gives this pane no size.
	SIZE_UNKNOWN,
	## Close only: the last pane of a repository's own floor while its linked
	## worktrees are open here: herdr would close the whole group (or stop its
	## own view on a confirm dialog). Never sent.
	GROUP_PARENT,
	## Close only: the card's own, at a first click: a second click within ten
	## seconds sends; nothing was sent.
	CONFIRM_NEEDED,
	## Close only: what the close would take with it (its tab, its floor, the
	## pane's state) changed since the first click, or the pane is not listed.
	SCOPE_CHANGED,
	## New space only: the pane's directory is unknown, empty or not absolute.
	CWD_UNKNOWN,
	## New space only: herdr spelled the pane's directory with characters the
	## office does not show: what would be sent is not what is shown.
	CWD_UNCLEAN,
	## New space only: the pane's directory moved between the press and the send.
	CWD_CHANGED,
	## New worktree only: the pane's floor is itself a linked worktree (a
	## mezzanine); herdr starts one only from the repository's own floor.
	MEZZANINE_SOURCE,
	## New worktree only: no branch name, or whitespace anywhere in it.
	BRANCH_BLANK,
	## New worktree only: a branch name over HerdrCommands.BRANCH_BYTES_MAX bytes.
	BRANCH_TOO_LONG,
	## New worktree only: a character outside letters, digits, `.`, `_`, `/` and `-`.
	BRANCH_CHARS,
	## New worktree only: a shape git refuses (`..`, `//`, a segment starting
	## with `.` or ending in `.lock`, ending in `/` or `.`, `HEAD`, `refs/`, a
	## first character that is not a letter or digit).
	BRANCH_SHAPE,
	## The card's own, at the release of New worktree: the branch box no longer
	## holds the name aimed at the press.
	BRANCH_EDITED,
	## New worktree only: the pane stands on another floor than the one aimed at.
	FLOOR_CHANGED,
	## New worktree only: the snapshot no longer lists the pane's floor.
	FLOOR_GONE,
}

## A few words, for a line of the agent card after "No preview:", "No switch:"
## or "Not sent:". Each fits the card's 124 units with any of those in front.
const _TEXTS: Dictionary[Reason, String] = {
	Reason.NONE: "",
	Reason.READ_ONLY: "read-only",
	Reason.NOT_CONNECTED: "no herdr",
	Reason.NOT_ALLOWED: "not allowed",
	Reason.UNKNOWN_PROTOCOL: "new protocol",
	Reason.MACHINE_GONE: "no machine",
	Reason.MACHINE_REPLACED: "reconnected",
	Reason.MACHINE_OFFLINE: "offline",
	Reason.SNAPSHOT_NOT_CURRENT: "not current",
	Reason.PANE_GONE: "pane gone",
	Reason.IDENTITY_UNKNOWN: "no identity",
	Reason.IDENTITY_CHANGED: "new terminal",
	Reason.WIRE_ID_MISMATCH: "odd pane id",
	Reason.WIRE_ID_DUPLICATE: "pane id twice",
	Reason.IN_FLIGHT: "in flight",
	Reason.LOOK_FIRST: "look first",
	Reason.KEY_NOT_ALLOWED: "not an answer key",
	Reason.LINE_BLANK: "empty line",
	Reason.LINE_TOO_LONG: "over 1024 bytes",
	Reason.LINE_CONTROL: "control character",
	Reason.LINE_INVISIBLE: "invisible character",
	Reason.LINE_BROKEN: "broken character",
	Reason.NOT_AN_AGENT: "a shell",
	Reason.AGENT_STARTING: "starting",
	Reason.NOT_ASKING: "not asking",
	Reason.AGENT_ASKING: "asking: use keys",
	Reason.AGENT_BUSY: "busy",
	Reason.UNSEEN: "look first",
	Reason.SCREEN_CHANGED: "the terminal changed, look again",
	Reason.SCREEN_CUT: "text cut, look again",
	Reason.RECHECK_FAILED: "no re-read",
	Reason.LINE_COMPOSING: "still composing",
	Reason.LINE_EDITED: "the line changed",
	Reason.KEY_UNSUPPORTED: "key not in the key map",
	Reason.KEY_UNREACHABLE: "Home/End/PgUp/PgDn/Insert/Delete can't be sent by herdr 0.9.0",
	Reason.TEXT_CONTROL: "control character in text",
	Reason.TEXT_BROKEN: "broken character",
	Reason.TEXT_TOO_LONG: "text too long",
	Reason.INPUT_EMPTY: "nothing to send",
	Reason.PASTE_ESCAPE: "paste holds ESC",
	Reason.PASTE_TOO_LONG: "paste over 64 KiB",
	Reason.QUEUE_FULL: "input queue full",
	Reason.PASTE_CONTROL: "paste holds a control character",
	Reason.PASTE_INVISIBLE: "paste holds a direction mark",
	Reason.NOT_A_SHELL: "an agent is here",
	Reason.NO_PROMPT: "no whole output read",
	Reason.PROMPT_UNSURE: "prompt not sure",
	Reason.KIND_UNKNOWN: "kind not seen here",
	Reason.KIND_INVALID: "bad kind name",
	Reason.NAME_INVALID: "bad agent name",
	Reason.NAME_TAKEN: "name taken",
	Reason.DIRECTION_INVALID: "bad direction",
	Reason.PANE_TOO_SMALL: "pane too small to split",
	Reason.SIZE_UNKNOWN: "pane size unknown",
	Reason.GROUP_PARENT: "the repo's own space: close its mezzanines first",
	Reason.CONFIRM_NEEDED: "click again to close",
	Reason.SCOPE_CHANGED: "what closes changed, look again",
	Reason.CWD_UNKNOWN: "directory unknown",
	Reason.CWD_UNCLEAN: "directory not shown as sent",
	Reason.CWD_CHANGED: "the directory changed",
	Reason.MEZZANINE_SOURCE: "a mezzanine: use the repo's own space",
	Reason.BRANCH_BLANK: "no branch name",
	Reason.BRANCH_TOO_LONG: "branch over 64 bytes",
	Reason.BRANCH_CHARS: "branch: letters, digits, . _ / - only",
	Reason.BRANCH_SHAPE: "not a branch name git takes",
	Reason.BRANCH_EDITED: "the branch changed",
	Reason.FLOOR_CHANGED: "the pane's space changed",
	Reason.FLOOR_GONE: "space gone",
}
## The same in full, for the tooltips that carry what a line has no room for.
const _DETAILS: Dictionary[Reason, String] = {
	Reason.NONE: "",
	Reason.READ_ONLY: "this office was started read-only and sends herdr nothing but reads of its state.",
	Reason.NOT_CONNECTED: "nothing here is connected to herdr.",
	Reason.NOT_ALLOWED: "that request is outside what this office may send herdr.",
	Reason.UNKNOWN_PROTOCOL: "this machine's herdr announced a protocol this office was not verified against.",
	Reason.MACHINE_GONE: "that machine is no longer shown.",
	Reason.MACHINE_REPLACED: "the machine was replaced, re-enabled or reconnected since this was aimed.",
	Reason.MACHINE_OFFLINE: "the machine is offline.",
	Reason.SNAPSHOT_NOT_CURRENT: "no current snapshot has been read from this machine yet.",
	Reason.PANE_GONE: "herdr no longer lists this pane.",
	Reason.IDENTITY_UNKNOWN: "herdr sent no terminal id for this pane, so nothing tells this terminal from the next.",
	Reason.IDENTITY_CHANGED: "another terminal, agent or session has this pane id now.",
	Reason.WIRE_ID_MISMATCH: "herdr spells this pane id with characters the office does not show.",
	Reason.WIRE_ID_DUPLICATE: "herdr lists this pane id more than once.",
	Reason.IN_FLIGHT: "the last write to this pane is still on its way.",
	Reason.LOOK_FIRST: "a write to this pane just ended. Wait for the preview to read the terminal again, then look.",
	Reason.KEY_NOT_ALLOWED: "that key is not one this office sends: only 1 to 9, y, n, Enter and Esc.",
	Reason.LINE_BLANK: "the line is empty or only spaces.",
	Reason.LINE_TOO_LONG: "the line is longer than 1024 bytes of UTF-8. Nothing is cut to make it fit.",
	Reason.LINE_CONTROL:
	"the line holds a control character (a tab, a newline, an escape, or another a terminal acts on).",
	Reason.LINE_INVISIBLE:
	"the line holds an invisible or direction-changing character: what you see would not be what is sent.",
	Reason.LINE_BROKEN: "the line holds a character that cannot be sent as typed (U+FFFD or a broken surrogate).",
	Reason.NOT_AN_AGENT: "herdr detects no agent in this pane: text sent to a shell runs as a command.",
	Reason.AGENT_STARTING: "herdr is still launching this agent, so its state says nothing yet.",
	Reason.NOT_ASKING: "herdr does not report this agent blocked: answer keys go only to an agent asking a question.",
	Reason.AGENT_ASKING:
	(
		"the agent is blocked on a question: herdr refuses a prompt to it too (agent_blocked, nothing written)."
		+ " Answer with the keys."
	),
	Reason.AGENT_BUSY:
	(
		"a line goes only to an idle or done agent: a working one's screen keeps changing, and an unknown state"
		+ " says nothing. herdr would type into a working agent; this office does not."
	),
	Reason.UNSEEN: "no uncut terminal text of this pane was on the card when you pressed. Look at it first.",
	Reason.SCREEN_CHANGED: "the terminal read differently right before sending, so nothing was sent. Look again.",
	Reason.SCREEN_CUT: "the terminal text came back cut right before sending, so it could not be compared.",
	Reason.RECHECK_FAILED: "the terminal could not be read again right before sending, so nothing was sent.",
	Reason.LINE_COMPOSING: "an input method is still composing in the reply box. Finish it, then press Send line.",
	Reason.LINE_EDITED: "the reply box changed between your press and release. Press Send line again.",
	Reason.KEY_UNSUPPORTED: "that key or chord is not in the monitor's key map, so nothing was sent for it.",
	Reason.KEY_UNREACHABLE:
	"herdr 0.9.0 has no key name for Home, End, PgUp, PgDn, Insert or Delete, so they cannot be sent.",
	Reason.TEXT_CONTROL: "typed text may not hold control characters; those keys are sent by name.",
	Reason.TEXT_BROKEN: "the text holds a character that cannot be sent as typed (U+FFFD or a broken surrogate).",
	Reason.TEXT_TOO_LONG: "that much text at once is more than one request carries. Nothing was cut.",
	Reason.INPUT_EMPTY: "there was nothing to send.",
	Reason.PASTE_ESCAPE:
	"the clipboard holds an escape character, which could end a bracketed paste early. Nothing was pasted.",
	Reason.PASTE_TOO_LONG: "the clipboard holds more than 64 KiB. Nothing is cut to make it fit; nothing was pasted.",
	Reason.QUEUE_FULL: "256 input events are already waiting for this pane. The newest was refused; nothing else.",
	Reason.PASTE_CONTROL:
	"the clipboard holds a control character (Ctrl-C, DEL, a line separator …) a terminal would act on. Nothing was pasted.",
	Reason.PASTE_INVISIBLE:
	"the clipboard holds a direction control, so what you see is not what the shell reads. Nothing was pasted.",
	Reason.NOT_A_SHELL: "herdr detects an agent in this pane: an agent starts only in a shell.",
	Reason.NO_PROMPT:
	"no whole recent output of this terminal was read, so nothing shows a prompt for herdr to type the command at.",
	Reason.PROMPT_UNSURE:
	(
		"the last row of this terminal does not end like a prompt: whatever is typed there would be run together"
		+ " with what herdr types. Confirm to start anyway."
	),
	Reason.KIND_UNKNOWN: "no agent of this kind is seen on this machine, so herdr may not have it.",
	Reason.KIND_INVALID: "an agent kind is lowercase letters, digits, - and _, at most 32, starting with a letter.",
	Reason.NAME_INVALID: "an agent name is lowercase letters, digits, - and _, at most 32, starting with a letter.",
	Reason.NAME_TAKEN: "an agent on this machine already has this name.",
	Reason.DIRECTION_INVALID: "a pane splits right or down, the way its shape gives: this is not that side.",
	Reason.PANE_TOO_SMALL:
	"splitting would leave less than 40 columns or 10 rows on a side; herdr would split it anyway.",
	Reason.SIZE_UNKNOWN: "herdr's layout gives this pane no size, so nothing says a split would fit.",
	Reason.GROUP_PARENT:
	(
		"this is the last pane of the repo's own space and its mezzanines are open: herdr would close them too."
		+ " Close them first, or close it in herdr."
	),
	Reason.CONFIRM_NEEDED: "a first click only shows what closes. Click Close again within ten seconds to close it.",
	Reason.SCOPE_CHANGED:
	"what closing this pane takes with it changed since your first click (its tab, its space or its state).",
	Reason.CWD_UNKNOWN: "herdr gave no absolute directory for this pane, so there is nowhere to start the new space.",
	Reason.CWD_UNCLEAN:
	"herdr spells this pane's directory with characters the office does not show, so it is not sent.",
	Reason.CWD_CHANGED: "this pane's directory changed between your press and release. Press again.",
	Reason.MEZZANINE_SOURCE:
	"this space is itself a linked worktree: herdr starts a new worktree only from the repo's own space.",
	Reason.BRANCH_BLANK: "type a branch name first; it may hold no spaces.",
	Reason.BRANCH_TOO_LONG: "a branch name here is at most 64 bytes of UTF-8. Nothing is cut to make it fit.",
	Reason.BRANCH_CHARS: "a branch name here holds only letters, digits, `.`, `_`, `/` and `-`.",
	Reason.BRANCH_SHAPE:
	(
		"git would refuse that name: no `..` or `//`, no segment starting with `.` or ending in `.lock`,"
		+ " not ending in `/` or `.`, not `HEAD`, `@` or `refs/…`, and it starts with a letter or a digit."
	),
	Reason.BRANCH_EDITED: "the branch box changed between your press and release. Press New worktree again.",
	Reason.FLOOR_CHANGED:
	"this pane moved to another space since the press, so the worktree's source is not the one aimed at.",
	Reason.FLOOR_GONE: "herdr no longer lists this pane's space.",
}


## A few words for `reason`, for a line of the agent card; empty for NONE.
static func text(reason: Reason) -> String:
	return _TEXTS.get(reason, "")


## `reason` as a sentence, for a tooltip; empty for NONE.
static func detail(reason: Reason) -> String:
	return _DETAILS.get(reason, "")


## The enum name, for logs and tests: `MACHINE_REPLACED`.
static func name_of(reason: Reason) -> String:
	return str(Reason.find_key(reason))
