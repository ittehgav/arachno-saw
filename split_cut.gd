@tool
class_name SplitCut
extends Resource

enum Axis { X, Y, Z }

## Axis the cut plane is perpendicular to.
@export var axis: Axis = Axis.X
## Position of the cut along that axis, in the SOURCE body's local space.
@export var offset: float = 0.0
