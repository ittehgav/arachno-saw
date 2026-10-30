@tool
class_name SplitCut
extends Resource

enum Axis { X, Y, Z }
enum DropSide { NONE, NEGATIVE_SIDE, POSITIVE_SIDE }

## Axis the cut plane is perpendicular to.
@export var axis: Axis = Axis.X
## Position of the cut along that axis, in the SOURCE body's local space.
@export var offset: float = 0.0
## Which half falls off after this cut (negative = lower coordinates along the axis).
## Later cuts only apply to what remains. NONE keeps both halves attached.
@export var drop_side: DropSide = DropSide.NONE


## True if this cut drops the given side of the plane.
func drops(negative_side: bool) -> bool:
	return drop_side == (DropSide.NEGATIVE_SIDE if negative_side else DropSide.POSITIVE_SIDE)
