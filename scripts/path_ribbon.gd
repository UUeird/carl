extends MeshInstance3D
class_name PathRibbon

## Generates a flat ribbon mesh along a Path3D using miter joints at each corner.
## Handles any segment angles with no gaps or overlaps; material_override applies the color.

@export var path_node: NodePath
@export var ribbon_width: float = 2.0
@export var ribbon_y: float = 0.12

func _ready() -> void:
	_build()

func _build() -> void:
	var path: Path3D = get_node_or_null(path_node)
	if not path or not path.curve or path.curve.point_count < 2:
		return

	var n := path.curve.point_count
	var hw := ribbon_width * 0.5
	const MITER_LIMIT := 3.0

	var pts: Array[Vector3] = []
	for i in n:
		var p := path.curve.get_point_position(i)
		pts.append(Vector3(p.x, ribbon_y, p.z))

	var L: Array[Vector3] = []
	var R: Array[Vector3] = []

	for i in n:
		var left_n: Vector3
		var miter_len: float

		if i == 0:
			var d := (pts[1] - pts[0]).normalized()
			left_n = Vector3(-d.z, 0, d.x)
			miter_len = hw
		elif i == n - 1:
			var d := (pts[i] - pts[i - 1]).normalized()
			left_n = Vector3(-d.z, 0, d.x)
			miter_len = hw
		else:
			var d_in := (pts[i] - pts[i - 1]).normalized()
			var d_out := (pts[i + 1] - pts[i]).normalized()
			var n_in := Vector3(-d_in.z, 0, d_in.x)
			var n_out := Vector3(-d_out.z, 0, d_out.x)
			var miter_dir := n_in + n_out
			if miter_dir.length_squared() < 0.0001:
				left_n = n_in
				miter_len = hw
			else:
				left_n = miter_dir.normalized()
				var cos_half := left_n.dot(n_in)
				miter_len = minf(hw / maxf(cos_half, 0.01), hw * MITER_LIMIT)

		L.append(pts[i] + left_n * miter_len)
		R.append(pts[i] - left_n * miter_len)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var up := Vector3(0, 1, 0)

	for i in n - 1:
		st.set_normal(up); st.add_vertex(L[i])
		st.set_normal(up); st.add_vertex(R[i])
		st.set_normal(up); st.add_vertex(L[i + 1])
		st.set_normal(up); st.add_vertex(R[i])
		st.set_normal(up); st.add_vertex(R[i + 1])
		st.set_normal(up); st.add_vertex(L[i + 1])

	mesh = st.commit()
