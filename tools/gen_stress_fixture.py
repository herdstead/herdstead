#!/usr/bin/env python3
"""Write the synthetic herdr snapshots `make perf` measures the office against.

Standard library only. Each file has the shape of tools/fixtures/*.json (a
`snapshot` as herdr 0.9.0 sends it), so tools/fake_herdr.py serves it with
`--fixtures=<dir> --fixture=<name>`:

- snapshot_medium:   3 workspaces x 3 tabs x 4 panes = 3 floors, 36 panes
- snapshot_stress80: 1 workspace x 10 tabs x 8 panes = 1 floor, 80 panes
- snapshot_stress400: 1 workspace x 50 tabs x 8 panes = 1 floor, 400 panes
  (the strategic view's big floor)
- snapshot_floors30: 30 workspaces of one tab, 1 to 12 panes each; five
  repositories each have a source floor and two linked worktrees, so 10 of
  the 30 floors are mezzanines (the building section's tall case)

Every pane runs a `claude` agent; the states cycle working, idle, blocked,
done, working, working, so a floor carries blocked and UNREAD badges too.

`make perf WALKS=1` walks the stress floor's people (tools/perf_probe.gd
--walk=), from one of these to another:

- snapshot_stress80_shells:  the stress floor with no agents, nobody at a desk
- snapshot_stress80_working: every pane an agent at work, nobody done
- snapshot_stress80_done40:  the same, the first 40 panes done
- snapshot_stress92_grown:   every pane at work, tab 0 grown by 12 panes

and, for the entry band's queue and pantry:

- snapshot_stress80_blocked40: at work but the 40 panes of tabs 0-4 blocked
- snapshot_stress80_idle40:    at work but the 40 panes of tabs 0-4 idle
- snapshot_stress80_blocked40_a<k>: the same 40 blocked but the first k of
  them answered (at work again), k = 1..8: the head of a full queue, answered
  over and over
- snapshot_stress92_blocked40: the same 40 blocked, tab 0 grown by 12 panes at work

The files are generated, not committed: they are large and say nothing a
reader needs.

    python3 tools/gen_stress_fixture.py --output /tmp/perf-fixtures
"""

import argparse
import json
import os

STATES = ("working", "idle", "blocked", "done", "working", "working")
# name -> (workspaces, tabs per workspace, panes per tab, how its panes differ)
SCENARIOS = {
    "snapshot_medium": (3, 3, 4, {}),
    "snapshot_stress80": (1, 10, 8, {}),
    "snapshot_stress400": (1, 50, 8, {}),
    "snapshot_floors30": (30, 1, 1, {"worktrees": (5, 2), "spread": 12}),
    "snapshot_stress80_shells": (1, 10, 8, {"agents": False}),
    "snapshot_stress80_working": (1, 10, 8, {"states": ("working",)}),
    "snapshot_stress80_done40": (1, 10, 8, {"states": ("working",), "done": 40}),
    "snapshot_stress92_grown": (1, 10, 8, {"states": ("working",), "grow": 12}),
    "snapshot_stress80_blocked40": (1, 10, 8, {"states": ("working",), "resting": ("blocked", 5)}),
    "snapshot_stress80_idle40": (1, 10, 8, {"states": ("working",), "resting": ("idle", 5)}),
    "snapshot_stress92_blocked40": (1, 10, 8, {"states": ("working",), "resting": ("blocked", 5), "grow": 12}),
}
for _answered in range(1, 9):
    SCENARIOS["snapshot_stress80_blocked40_a%d" % _answered] = (
        1, 10, 8, {"states": ("working",), "resting": ("blocked", 5), "answered": _answered}
    )


def snapshot(workspaces, tabs_per_workspace, panes_per_tab, agents=True, states=STATES, done=0, grow=0,
             resting=None, answered=0, worktrees=(0, 0), spread=0):
    """One session, two panes per layout column: every pane an agent in
    `states` in turn (its first `done` panes done), or with `agents` false a
    shell; the first tab of each workspace `grow` panes bigger than the rest.
    `resting` (a state, a number of tabs) puts the first `panes_per_tab` panes
    of those first tabs in that state, but for the first `answered` of them:
    the same panes, however much tab 0 grew. `worktrees` (repositories,
    linked checkouts each) makes the first workspaces repository groups: a
    source checkout followed by its linked worktrees. With `spread`, a
    workspace's tabs hold 1 to `spread` panes, by its index."""
    result = {
        "version": "0.9.0",
        "protocol": 22,
        "focused_workspace_id": "w0",
        "focused_tab_id": "w0:t0",
        "focused_pane_id": "w0:t0:p0",
        "workspaces": [],
        "tabs": [],
        "panes": [],
        "layouts": [],
        "agents": [],
    }
    count = 0
    repositories, linked = worktrees
    for w in range(workspaces):
        workspace_id = "w%d" % w
        per_tab = 1 + (w * 5) % spread if spread else panes_per_tab
        workspace = {
            "workspace_id": workspace_id,
            "number": w + 1,
            "label": "stress %d" % w,
            "focused": w == 0,
            "pane_count": tabs_per_workspace * per_tab + grow,
            "tab_count": tabs_per_workspace,
            "active_tab_id": "%s:t0" % workspace_id,
            "agent_status": "working",
        }
        if w < repositories * (linked + 1):
            repository, member = divmod(w, linked + 1)
            name = "repo%d" % repository
            workspace["label"] = name if member == 0 else "%s lane %d" % (name, member)
            workspace["worktree"] = {
                "repo_key": "stress/" + name,
                "repo_name": name,
                "repo_root": "/home/t/" + name,
                "checkout_path": "/home/t/%s" % name if member == 0 else "/home/t/wt/%s/lane-%d" % (name, member),
                "is_linked_worktree": member > 0,
            }
        result["workspaces"].append(workspace)
        for t in range(tabs_per_workspace):
            tab_id = "%s:t%d" % (workspace_id, t)
            in_tab = per_tab + (grow if t == 0 else 0)
            result["tabs"].append(
                {
                    "tab_id": tab_id,
                    "workspace_id": workspace_id,
                    "number": t + 1,
                    "label": "tab %d" % t,
                    "focused": False,
                    "pane_count": in_tab,
                    "agent_status": "working",
                }
            )
            slots = []
            for p in range(in_tab):
                pane_id = "%s:p%d" % (tab_id, p)
                state = "done" if count < done else states[count % len(states)]
                if resting is not None and t < resting[1] and p < panes_per_tab:
                    order = t * panes_per_tab + p
                    state = "working" if order < answered else resting[0]
                count += 1
                terminal = "term-" + pane_id
                session = {"source": "fixture", "agent": "claude", "kind": "session_id", "value": "s-" + pane_id}
                column = p // 2
                slots.append(
                    {
                        "pane_id": pane_id,
                        "focused": False,
                        "rect": {"x": column * 80, "y": 0 if p % 2 == 0 else 40, "width": 80, "height": 40},
                    }
                )
                pane = {
                    "pane_id": pane_id,
                    "terminal_id": terminal,
                    "workspace_id": workspace_id,
                    "tab_id": tab_id,
                    "focused": pane_id == "w0:t0:p0",
                    "cwd": "/home/t/" + pane_id,
                    "foreground_cwd": "/home/t/" + pane_id,
                    "agent": "claude",
                    "terminal_title": "x",
                    "terminal_title_stripped": "x",
                    "agent_session": session,
                    "agent_status": state,
                    "revision": 1,
                }
                if not agents:
                    # A shell, as herdr sends one: no agent and no session.
                    pane.update({"agent": None, "agent_status": "idle", "terminal_title_stripped": "zsh"})
                    del pane["agent_session"]
                    result["panes"].append(pane)
                    continue
                result["panes"].append(pane)
                result["agents"].append(
                    {
                        "terminal_id": terminal,
                        "agent": "claude",
                        "agent_status": state,
                        "agent_session": session,
                        "workspace_id": workspace_id,
                        "tab_id": tab_id,
                        "pane_id": pane_id,
                        "focused": False,
                        "revision": 1,
                        "state_change_seq": 1,
                    }
                )
            result["layouts"].append(
                {
                    "workspace_id": workspace_id,
                    "tab_id": tab_id,
                    "zoomed": False,
                    "area": {"x": 0, "y": 0, "width": 80 * ((in_tab + 1) // 2), "height": 80},
                    "focused_pane_id": slots[0]["pane_id"],
                    "panes": slots,
                    "splits": [],
                }
            )
    return result, count


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--output", required=True, help="directory to write the fixtures into")
    options = parser.parse_args()
    os.makedirs(options.output, exist_ok=True)
    for name, (workspaces, tabs, panes_per_tab, extra) in SCENARIOS.items():
        data, panes = snapshot(workspaces, tabs, panes_per_tab, **extra)
        path = os.path.join(options.output, name + ".json")
        with open(path, "w", encoding="utf-8") as target:
            json.dump({"_comment": "generated by tools/gen_stress_fixture.py", "snapshot": data}, target)
        print("%s: %d panes" % (path, panes))


if __name__ == "__main__":
    main()
