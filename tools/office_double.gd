extends OfficeScene
## The live office with the viewport size the test decides, for the suites that
## drive it headlessly, and, when a suite sets one, its own command line.
##
## `OfficeScene._screen()` reads the real viewport; a test either runs outside
## the tree, where there is none, or wants a window size it did not open. This
## is the whole of the difference, and it is a file rather than a GDScript built
## from a source string at runtime so that it parses under
## tools/check_scripts.gd and the suites can type the office they are driving.
##
## `OfficeScene._app_args()` reads the process's command line. A suite that runs
## offices in more than one mode (tools/test_commands.gd: operator and
## `--read-only`) hands each its own through `test_args`, parsed by AppArgs the
## same way; left null, the office reads the suite's own command line.
##
## Preloaded, not a `class_name`: a test double has no business in the project's
## global class list.

var test_screen := Vector2.ZERO
var test_args: AppArgs
## Whether the bubbles' question reader reads (OfficeScene._question_reads()).
## The write-boundary suites assert exact request sequences and turn it off
## unless a case is about the bubbles; set it before the office is in the tree.
var test_question_reads := true
## How many refreshes ran, how deep they are nested now, and the deepest they
## ever were: a refresh that starts inside another shows up as 2.
var refreshes := 0
var refresh_depth := 0
var deepest_refresh := 0


func _init() -> void:
	super()
	# A test office is lit by day, whatever the clock says; a case about the
	# light sets light_mode, or the clock, itself.
	light_mode = LightMode.DAY
	# Its window is the suite's or the capture's, never maximized.
	may_fill_screen = false


func _screen() -> Vector2:
	return test_screen


func _app_args() -> AppArgs:
	return test_args if test_args != null else super()


func _question_reads() -> bool:
	return test_question_reads


func _refresh() -> void:
	refreshes += 1
	refresh_depth += 1
	deepest_refresh = maxi(deepest_refresh, refresh_depth)
	super()
	refresh_depth -= 1


## Walk every walk on the shown floor to its end, through the office's own
## steps and landings (OfficePresentation.settle()): what a case compares with
## a rebuild, which walks nobody, once it has seen the walk start. It lands a
## stale machine's frozen walkers too, which the office itself never does.
func settle() -> void:
	floor_view.settle()
