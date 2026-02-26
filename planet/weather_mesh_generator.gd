class_name WeatherMeshGenerator

static func generate_rain_chunk(atmo: AtmosphereGrid, proj: PlanetProjector, face: int, chunk_u: int, chunk_v: int) -> ArrayMesh:
	var cs := AtmosphereGrid.CHUNK_SIZE
	var fu_start := chunk_u * cs
	var fv_start := chunk_v * cs
	
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	
	var idx := 0
	var rain_height := GameConfig.PLANET_RADIUS * 0.08
	
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(face * 1000 + chunk_u * 100 + chunk_v)
	
	var has_rain := false
	
	for iv in range(cs):
		var fv := fv_start + iv
		for iu in range(cs):
			var fu := fu_start + iu
			var precip := atmo.get_column_precipitation(face, fu, fv)
			if precip < 0.05:
				continue
				
			has_rain = true
			var u := float(fu) / float(AtmosphereGrid.FACE_RES)
			var v := float(fv) / float(AtmosphereGrid.FACE_RES)
			
			var _center_dir := proj.cube_sphere_point(face, u, v).normalized()
			
			var streaks := int(lerpf(3.0, 12.0, precip))
			for i in range(streaks):
				var offset_u := rng.randf_range(-0.5, 0.5) * (1.0 / float(AtmosphereGrid.FACE_RES))
				var offset_v := rng.randf_range(-0.5, 0.5) * (1.0 / float(AtmosphereGrid.FACE_RES))
				var streak_dir := proj.cube_sphere_point(face, u + offset_u, v + offset_v).normalized()
				
				var top_pos := streak_dir * (proj.radius + rain_height + rng.randf_range(-5.0, 5.0))
				var bot_pos := streak_dir * (proj.radius + rng.randf_range(0.0, 2.0))
				
				var width := rng.randf_range(0.3, 0.8)
				var st := streak_dir.cross(Vector3.UP).normalized()
				if st.length_squared() < 0.01:
					st = streak_dir.cross(Vector3.RIGHT).normalized()
				
				var right1 := st * width
				var right2 := streak_dir.cross(st).normalized() * width
				
				var rnd_val := rng.randf()
				var c := Color(rnd_val, 1.0, 1.0, precip)
				
				# Quad 1
				verts.push_back(top_pos - right1); uvs.push_back(Vector2(0, 0)); colors.push_back(c)
				verts.push_back(top_pos + right1); uvs.push_back(Vector2(1, 0)); colors.push_back(c)
				verts.push_back(bot_pos - right1); uvs.push_back(Vector2(0, 1)); colors.push_back(c)
				verts.push_back(bot_pos + right1); uvs.push_back(Vector2(1, 1)); colors.push_back(c)
				indices.push_back(idx); indices.push_back(idx+1); indices.push_back(idx+2)
				indices.push_back(idx+1); indices.push_back(idx+3); indices.push_back(idx+2)
				idx += 4
				
				# Quad 2
				verts.push_back(top_pos - right2); uvs.push_back(Vector2(0, 0)); colors.push_back(c)
				verts.push_back(top_pos + right2); uvs.push_back(Vector2(1, 0)); colors.push_back(c)
				verts.push_back(bot_pos - right2); uvs.push_back(Vector2(0, 1)); colors.push_back(c)
				verts.push_back(bot_pos + right2); uvs.push_back(Vector2(1, 1)); colors.push_back(c)
				indices.push_back(idx); indices.push_back(idx+1); indices.push_back(idx+2)
				indices.push_back(idx+1); indices.push_back(idx+3); indices.push_back(idx+2)
				idx += 4
				
	if not has_rain:
		return null
		
	var mesh := ArrayMesh.new()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func generate_fog_chunk(atmo: AtmosphereGrid, proj: PlanetProjector, face: int, chunk_u: int, chunk_v: int) -> ArrayMesh:
	var cs := AtmosphereGrid.CHUNK_SIZE
	var fu_start := chunk_u * cs
	var fv_start := chunk_v * cs
	
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	
	var has_fog := false
	var fog_alt := 0.2
	
	for iv in range(cs + 1):
		var fv := fv_start + iv
		for iu in range(cs + 1):
			var fu := fu_start + iu
			var u := float(fu) / float(AtmosphereGrid.FACE_RES)
			var v := float(fv) / float(AtmosphereGrid.FACE_RES)
			var dir := proj.cube_sphere_point(face, u, v).normalized()
			
			var cfu := clampi(fu, 0, AtmosphereGrid.FACE_RES - 1)
			var cfv := clampi(fv, 0, AtmosphereGrid.FACE_RES - 1)
			var density := atmo.get_cloud_density_at(face, cfu, cfv, 0)
			if density > 0.15:
				has_fog = true
				
			verts.push_back(dir * (proj.radius + fog_alt))
			uvs.push_back(Vector2(u * AtmosphereGrid.NUM_FACES, v))
			colors.push_back(Color(1.0, 1.0, 1.0, density))
			
	if not has_fog:
		return null
		
	for iv in range(cs):
		for iu in range(cs):
			var i00 := iv * (cs + 1) + iu
			var i10 := i00 + 1
			var i01 := i00 + (cs + 1)
			var i11 := i01 + 1
			
			indices.push_back(i00); indices.push_back(i01); indices.push_back(i10)
			indices.push_back(i10); indices.push_back(i01); indices.push_back(i11)

	var mesh := ArrayMesh.new()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
