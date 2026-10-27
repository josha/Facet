--!strict
return function(origin: Vector3, direction: Vector3, plane: CFrame): Vector3?
	local normal = plane.UpVector
	local denominator = direction:Dot(normal)
	if math.abs(denominator) < 1e-6 then
		return nil
	end
	local distance = (plane.Position - origin):Dot(normal) / denominator
	return if distance >= 0 then origin + direction * distance else nil
end
