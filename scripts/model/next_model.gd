class_name NextModel
extends RefCounted
## Whom `N` would pick next (OfficeNavigator.peek_next()), as the staff panel's
## NEXT button says it: what a press does to them, provider, space and herdr's
## word for the state. How long they have waited is not here: OfficeAttention
## ticks it (attention.gd).

## HerdrFleet.pane_key() of the pane.
var key := ""
## herdr's agent name; empty for a shell.
var provider := ""
## The pane's workspace label; `?` when the snapshot carries none.
var space := ""
## herdr's word for the state: `blocked` or `done`.
var state := ""
## The machine's label, only when the office shows more than one machine.
var machine := ""
## What pressing NEXT (or `N`) does to them: `Answer` for an agent that
## asks (its answer keys open, nothing is sent), `Read` for a done one (its
## panel opens); empty when the office cannot write, where NEXT only picks.
var verb := ""


## `may_write` is the office being an operator (not `--read-only`, not the
## showroom): only then does NEXT say a verb.
static func of(pane: PaneModel, machine_label: String, may_write := false) -> NextModel:
	var next := NextModel.new()
	next.key = pane.key
	next.provider = pane.provider
	next.space = pane.workspace_label if not pane.workspace_label.is_empty() else "?"
	next.state = pane.state
	next.machine = machine_label
	if may_write:
		if pane.asks():
			next.verb = "Answer"
		elif pane.state == "done":
			next.verb = "Read"
	return next
