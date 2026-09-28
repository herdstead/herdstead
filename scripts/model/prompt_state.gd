class_name PromptState
extends RefCounted
## Whether a shell's terminal text ends at a prompt a start may type
## after. herdr types the kind's command and Enter into the shell as it is,
## after whatever is on its last line (a half-typed `echo PARTIAL` ran as
## `echo PARTIALmaki`, measured), and does not look first. So the office looks:
## PLAIN when the last line ends like a prompt, UNSURE when it ends otherwise
## (many prompt themes do, oh-my-zsh's `➜  repo git:(main) ✗` among them, and
## so does a half-typed line), NO_PROMPT when there is nothing whole to look
## at. A start goes after PLAIN, after UNSURE only once the viewer confirmed
## it (CommandContext.confirmed), and never after NO_PROMPT
## (HerdrCommands.prompt_refusal()). Pure; it reads terminal text and keeps
## only the last line, bounded, for the card to show.
##
## Best effort, like every look before a write: the viewer can type into the
## shell between the look and the start.

enum Kind {
	## Nothing whole to look at: no text, only blank lines, text that was cut,
	## or text from another source than the recent output.
	NO_PROMPT,
	## A last line that does not end in one of ENDINGS.
	UNSURE,
	## A last line that ends in one of ENDINGS, trailing blanks aside.
	PLAIN,
}

## The characters a prompt commonly ends in: sh and bash (`$`, `#` for root),
## zsh (`%`), cmd-like and continuation prompts (`>`), and the arrows and
## lambdas of common themes (`❯`, `➜`, `λ`, `»`).
const ENDINGS := "$%>#❯➜λ»"

var kind := Kind.NO_PROMPT
## The last line that is not blank, trailing blanks removed, grapheme
## clusters bounded (TerminalText.bound()); empty for NO_PROMPT. Terminal
## text: shown on the card, never logged or audited.
var last_line := ""


## What `text` (a whole recent output, as PaneReadResult cleaned it) ends in.
static func of_text(text: String) -> PromptState:
	var state := PromptState.new()
	var rows := text.split("\n")
	for index in range(rows.size() - 1, -1, -1):
		var row := rows[index].strip_edges(false, true)
		if row.is_empty():
			continue
		state.last_line = TerminalText.bound(row)
		var ending := row.substr(row.length() - 1)
		state.kind = Kind.PLAIN if ENDINGS.contains(ending) else Kind.UNSURE
		return state
	return state


## What the terminal text `preview` froze ends in: NO_PROMPT for none, one
## that was cut, and one read from another source than the recent output
## (CommandContext.SOURCE_RECENT).
static func of(preview: CommandPreview) -> PromptState:
	if preview == null or preview.cut or preview.source != CommandContext.SOURCE_RECENT:
		return PromptState.new()
	return of_text(preview.text)


## The Kind's enum name, for logs and tests: `UNSURE`.
static func name_of(of_kind: Kind) -> String:
	return str(Kind.find_key(of_kind))
