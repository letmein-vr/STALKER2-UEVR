local uevrLib = require('libs/core/uevr_lib')

local M = {}

function M.print(text, logLevel)
	print("[math_lib] " .. text)
end

function M.vectorSize(v)
	if v == nil then return 0.0 end
	local x = v.X or v.x or v[1] or 0.0
	local y = v.Y or v.y or v[2] or 0.0
	local z = v.Z or v.z or v[3] or 0.0
	return math.sqrt((x * x) + (y * y) + (z * z))
end

function M.vectorSizeSquared(v)
	if v == nil then return 0.0 end
	local x = v.X or v.x or v[1] or 0.0
	local y = v.Y or v.y or v[2] or 0.0
	local z = v.Z or v.z or v[3] or 0.0
	return (x * x) + (y * y) + (z * z)
end

function M.vectorLengthGreaterThan(v, len)
	return M.vectorSizeSquared(v) > (len * len)
end

function M.vectorLengthLessThan(v, len)
	return M.vectorSizeSquared(v) < (len * len)
end

function M.vectorDistance(vector1, vector2, preferKismet)
	if preferKismet and kismet_math_library and kismet_math_library.Vector_Distance then
		return kismet_math_library:Vector_Distance(vector1, vector2)
	end
	if vector1 == nil or vector2 == nil then return 0.0 end
	local x1 = vector1.X or vector1.x or vector1[1] or 0.0
	local y1 = vector1.Y or vector1.y or vector1[2] or 0.0
	local z1 = vector1.Z or vector1.z or vector1[3] or 0.0
	local x2 = vector2.X or vector2.x or vector2[1] or 0.0
	local y2 = vector2.Y or vector2.y or vector2[2] or 0.0
	local z2 = vector2.Z or vector2.z or vector2[3] or 0.0
	local dx = x2 - x1
	local dy = y2 - y1
	local dz = z2 - z1
	return math.sqrt((dx * dx) + (dy * dy) + (dz * dz))
end

function M.vectorDistanceSquared(vector1, vector2, preferKismet)
	if preferKismet and kismet_math_library and kismet_math_library.Vector_Distance then
		return kismet_math_library:Vector_Distance(vector1, vector2)
	end
	if vector1 == nil or vector2 == nil then return 0.0 end
	local x1 = vector1.X or vector1.x or vector1[1] or 0.0
	local y1 = vector1.Y or vector1.y or vector1[2] or 0.0
	local z1 = vector1.Z or vector1.z or vector1[3] or 0.0
	local x2 = vector2.X or vector2.x or vector2[1] or 0.0
	local y2 = vector2.Y or vector2.y or vector2[2] or 0.0
	local z2 = vector2.Z or vector2.z or vector2[3] or 0.0
	local dx = x2 - x1
	local dy = y2 - y1
	local dz = z2 - z1
	return (dx * dx) + (dy * dy) + (dz * dz)
end

function M.vectorMultiply(v, s)
	return v * s
end

function M.vectorSet(v, x, y, z)
	if v == nil then return end
	if v.X ~= nil then
		v.X = x; v.Y = y; v.Z = z
	else
		v.x = x; v.y = y; v.z = z
	end
end

function M.vectorCross(a, b, preferKismet)
	if preferKismet and  kismet_math_library and kismet_math_library.Cross_VectorVector then
		return kismet_math_library:Cross_VectorVector(a, b)
	end
	local ax = a.X or a[1] or a.x or 0
	local ay = a.Y or a[2] or a.y or 0
	local az = a.Z or a[3] or a.z or 0
	local bx = b.X or b[1] or b.x or 0
	local by = b.Y or b[2] or b.y or 0
	local bz = b.Z or b[3] or b.z or 0
	local cx = ay * bz - az * by
	local cy = az * bx - ax * bz
	local cz = ax * by - ay * bx
	if kismet_math_library and kismet_math_library.MakeVector then
		return kismet_math_library:MakeVector(cx, cy, cz)
	end
	return M.vector(cx, cy, cz)
end

function M.vectorDot(a, b, preferKismet)
	if preferKismet and kismet_math_library and kismet_math_library.Dot_VectorVector then
		return kismet_math_library:Dot_VectorVector(a, b)
	end
	local ax = a.X or a[1] or a.x or 0
	local ay = a.Y or a[2] or a.y or 0
	local az = a.Z or a[3] or a.z or 0
	local bx = b.X or b[1] or b.x or 0
	local by = b.Y or b[2] or b.y or 0
	local bz = b.Z or b[3] or b.z or 0
	return ax * bx + ay * by + az * bz
end

function M.vectorSafeNormalize(v)
	if v == nil then return M.vector(0,0,0) end
	local len = M.vectorSize(v)
	if len == nil or len < 0.0001 then
		return M.vector(0,0,0)
	end
	return v * (1.0 / len)
end

function M.vectorRotate(vec, rot, preferKismet)
	if preferKismet and kismet_math_library and kismet_math_library.GreaterGreater_VectorRotator then
		return kismet_math_library:GreaterGreater_VectorRotator(vec, rot)
	end
	if vec == nil or rot == nil then return M.vector(0,0,0) end
	-- build quaternion from rotator (use engine helper if present)
	local quat = M.quatFromEuler(rot, preferKismet)
	-- Testing shows kismet_math_library.Quat_MakeFromEuler is twice as slow
	-- if preferKismet and kismet_math_library and kismet_math_library.Quat_MakeFromEuler then
	-- 	quat = kismet_math_library:Quat_MakeFromEuler(euler) --this expects roll, pitch yaw i think
	-- else
	-- 	quat = M.quatFromEuler(euler, preferKismet)
	-- end

	-- fallback: if we couldn't make a quaternion, return the input vector unchanged
	if quat == nil then
		return vec
	end

	-- extract components
	local vx = vec.X or vec.x or vec[1] or 0.0
	local vy = vec.Y or vec.y or vec[2] or 0.0
	local vz = vec.Z or vec.z or vec[3] or 0.0

	local qw = quat.W or quat.w or 1.0
	local qx = quat.X or quat.x or 0.0
	local qy = quat.Y or quat.y or 0.0
	local qz = quat.Z or quat.z or 0.0

	-- v' = v + 2*cross(q_vec, v)*qw + 2*cross(q_vec, cross(q_vec, v))
	local tx = 2.0 * (qy * vz - qz * vy)
	local ty = 2.0 * (qz * vx - qx * vz)
	local tz = 2.0 * (qx * vy - qy * vx)

	local vpx = vx + qw * tx + (qy * tz - qz * ty)
	local vpy = vy + qw * ty + (qz * tx - qx * tz)
	local vpz = vz + qw * tz + (qx * ty - qy * tx)

	if kismet_math_library and kismet_math_library.MakeVector then
		return kismet_math_library:MakeVector(vpx, vpy, vpz)
	end
	return M.vector(vpx, vpy, vpz)
end

function M.getForwardVector(rotator, preferKismet)
	if preferKismet and kismet_math_library and kismet_math_library.GetForwardVector then
		return kismet_math_library:GetForwardVector(rotator)
	end
	if rotator == nil then return M.vector(0,0,0) end
	local pitch = rotator.Pitch or rotator.pitch or rotator.X or rotator.x or rotator[1] or 0.0
	local yaw   = rotator.Yaw   or rotator.yaw   or rotator.Y or rotator.y or rotator[2] or 0.0
	local deg2rad = math.pi / 180.0
	local p = pitch * deg2rad
	local y = yaw * deg2rad
	local cp = math.cos(p)
	local sp = math.sin(p)
	local cy = math.cos(y)
	local sy = math.sin(y)
	local fx = cp * cy
	local fy = cp * sy
	local fz = sp
	if kismet_math_library and kismet_math_library.MakeVector then
		return kismet_math_library:MakeVector(fx, fy, fz)
	end
	return M.vector(fx, fy, fz)
end

-- Given a location and a rotation, return the point that is distance units in front of it.
function M.pointAhead(loc, rot, distance)
    return loc + (M.getForwardVector(rot) * distance)
end

-- This is not the same as composing rotators. Only use if you know your offsets are additive
function M.sumRotators(...)
    local arg = {...}
	local rollTotal,pitchTotal,yawTotal = 0,0,0
	if arg ~= nil then
		for i = 1, #arg do
			if arg[i] ~= nil then
				if arg[i]["Pitch"] ~= nil then pitchTotal = pitchTotal + arg[i]["Pitch"] else pitchTotal = pitchTotal + arg[i]["pitch"] end
				if arg[i]["Yaw"] ~= nil then yawTotal = yawTotal + arg[i]["Yaw"] else yawTotal = yawTotal + arg[i]["yaw"] end
				if arg[i]["Roll"] ~= nil then rollTotal = rollTotal + arg[i]["Roll"] else rollTotal = rollTotal + arg[i]["roll"] end
			end
		end
	end
	return kismet_math_library:MakeRotator(rollTotal, pitchTotal, yawTotal)
end

function M.rotatorFromQuat(x, y, z, w)
	return kismet_math_library:Quat_Rotator(M.quat(x, y, z, w))
end

-- Build a rotator that represents rotation around an arbitrary axis by angleDeg (degrees).
-- Fallback path: axis-angle -> quaternion -> euler (Pitch,Yaw,Roll) using standard formulas.
function M.rotatorFromAxisAndAngle(axis, angleDeg, preferKismet)
	if preferKismet and kismet_math_library and kismet_math_library.RotatorFromAxisAndAngle then
		return kismet_math_library:RotatorFromAxisAndAngle(axis, angleDeg)
	end
	if axis == nil or angleDeg == nil then return M.rotator(0,0,0) end

	local ax = axis.X or axis.x or axis[1] or 0.0
	local ay = axis.Y or axis.y or axis[2] or 0.0
	local az = axis.Z or axis.z or axis[3] or 0.0
	local len = math.sqrt((ax * ax) + (ay * ay) + (az * az))
	if len < 1e-12 then return M.rotator(0,0,0) end
	ax = ax / len
	ay = ay / len
	az = az / len

	local half = angleDeg * (math.pi / 360.0)
	local s = math.sin(half)
	local qw = math.cos(half)
	local qx = ax * s
	local qy = ay * s
	local qz = az * s

	local sinp = 2.0 * ((qw * qy) - (qz * qx))
	if sinp > 1.0 then sinp = 1.0 elseif sinp < -1.0 then sinp = -1.0 end

	local pitch = -math.asin(sinp)
	local roll = -math.atan(2.0 * ((qw * qx) + (qy * qz)), 1.0 - (2.0 * ((qx * qx) + (qy * qy))))
	local yaw = math.atan(2.0 * ((qw * qz) + (qx * qy)), 1.0 - (2.0 * ((qy * qy) + (qz * qz))))

	local rad2deg = 180.0 / math.pi
	return M.rotator(pitch * rad2deg, yaw * rad2deg, roll * rad2deg)
end

-- Build a rotator from X and Z direction vectors. Matches kismet_math_library:MakeRotFromXZ.
function M.makeRotFromXZ(xVec, zVec, preferKismet)
	if kismet_math_library and kismet_math_library.MakeRotFromXZ then
		return kismet_math_library:MakeRotFromXZ(xVec, zVec)
	end
	-- if xVec == nil or zVec == nil then return M.rotator(0,0,0) end

	-- local eps = 1e-9
	-- local xx = xVec.X or xVec.x or xVec[1] or 0.0
	-- local xy = xVec.Y or xVec.y or xVec[2] or 0.0
	-- local xz = xVec.Z or xVec.z or xVec[3] or 0.0

	-- local zx = zVec.X or zVec.x or zVec[1] or 0.0
	-- local zy = zVec.Y or zVec.y or zVec[2] or 0.0
	-- local zz = zVec.Z or zVec.z or zVec[3] or 0.0

	-- -- normalize input X
	-- local xlen = math.sqrt(xx*xx + xy*xy + xz*xz)
	-- if xlen < eps then return M.rotator(0,0,0) end
	-- local xnx, xny, xnz = xx / xlen, xy / xlen, xz / xlen

	-- -- make Z orthogonal to X: z' = z - proj_z_on_x
	-- local dot_zx = (zx * xnx) + (zy * xny) + (zz * xnz)
	-- local zx_ort_x = zx - dot_zx * xnx
	-- local zy_ort_x = zy - dot_zx * xny
	-- local zz_ort_x = zz - dot_zx * xnz
	-- local zlen = math.sqrt(zx_ort_x*zx_ort_x + zy_ort_x*zy_ort_x + zz_ort_x*zz_ort_x)

	-- local znx, zny, znz
	-- if zlen < eps then
	-- 	-- X and Z are nearly parallel; pick an arbitrary axis to build orthonormal basis
	-- 	-- choose world-up-like vector that's not parallel to X
	-- 	local ax, ay, az = 0.0, 0.0, 1.0
	-- 	if math.abs(xnz) > 0.9 then ax, ay, az = 1.0, 0.0, 0.0 end
	-- 	-- z = normalize(cross(x, arbitrary)) to get a perpendicular vector
	-- 	znx = (xny * az - xnz * ay)
	-- 	zny = (xnz * ax - xnx * az)
	-- 	znz = (xnx * ay - xny * ax)
	-- 	local znlen = math.sqrt(znx*znx + zny*zny + znz*znz)
	-- 	if znlen < eps then return M.rotator(0,0,0) end
	-- 	znx, zny, znz = znx / znlen, zny / znlen, znz / znlen
	-- 	-- recompute x to be orthogonal: x = cross(y,z) later
	-- else
	-- 	znx, zny, znz = zx_ort_x / zlen, zy_ort_x / zlen, zz_ort_x / zlen
	-- end

	-- -- recompute orthogonal Y = cross(Z, X)
	-- local ynx = (zny * xnz) - (znz * xny)
	-- local yny = (znz * xnx) - (znx * xnz)
	-- local ynz = (znx * xny) - (zny * xnx)
	-- local ylen = math.sqrt(ynx*ynx + yny*yny + ynz*ynz)
	-- if ylen < eps then return M.rotator(0,0,0) end
	-- ynx, yny, ynz = ynx / ylen, yny / ylen, ynz / ylen

	-- -- ensure X is orthogonal and normalized: X = cross(Y, Z)
	-- local rxx = (yny * znz) - (ynz * zny)
	-- local rxy = (ynz * znx) - (ynx * znz)
	-- local rxz = (ynx * zny) - (yny * znx)
	-- local rlen = math.sqrt(rxx*rxx + rxy*rxy + rxz*rxz)
	-- if rlen < eps then return M.rotator(0,0,0) end
	-- rxx, rxy, rxz = rxx / rlen, rxy / rlen, rxz / rlen

	-- -- Build rotation matrix with columns = (X, Y, Z)
	-- local m00 = rxx; local m01 = ynx; local m02 = znx
	-- local m10 = rxy; local m11 = yny; local m12 = zny
	-- local m20 = rxz; local m21 = ynz; local m22 = znz

	-- -- Convert rotation matrix to quaternion
	-- local trace = m00 + m11 + m22
	-- local qw, qx, qy, qz = 0,0,0,0
	-- if trace > 0 then
	-- 	local s = 0.5 / math.sqrt(trace + 1.0)
	-- 	qw = 0.25 / s
	-- 	qx = (m21 - m12) * s
	-- 	qy = (m02 - m20) * s
	-- 	qz = (m10 - m01) * s
	-- else
	-- 	if m00 > m11 and m00 > m22 then
	-- 		local s = 2.0 * math.sqrt(1.0 + m00 - m11 - m22)
	-- 		qw = (m21 - m12) / s
	-- 		qx = 0.25 * s
	-- 		qy = (m01 + m10) / s
	-- 		qz = (m02 + m20) / s
	-- 	elseif m11 > m22 then
	-- 		local s = 2.0 * math.sqrt(1.0 + m11 - m00 - m22)
	-- 		qw = (m02 - m20) / s
	-- 		qx = (m01 + m10) / s
	-- 		qy = 0.25 * s
	-- 		qz = (m12 + m21) / s
	-- 	else
	-- 		local s = 2.0 * math.sqrt(1.0 + m22 - m00 - m11)
	-- 		qw = (m10 - m01) / s
	-- 		qx = (m02 + m20) / s
	-- 		qy = (m12 + m21) / s
	-- 		qz = 0.25 * s
	-- 	end
	-- end

	-- -- Prefer engine conversion if available
	-- -- if kismet_math_library and kismet_math_library.Quat_Rotator then
	-- -- 	return kismet_math_library:Quat_Rotator(M.quat(qx, qy, qz, qw))
	-- -- end

	-- -- Fallback: convert quaternion -> Euler
	-- local sinp = 2.0 * (qw * qy - qz * qx)
	-- local pitch
	-- if sinp >= 1.0 then
	-- 	pitch = math.pi / 2
	-- elseif sinp <= -1.0 then
	-- 	pitch = -math.pi / 2
	-- else
	-- 	pitch = math.asin(sinp)
	-- end
	-- local roll = math.atan(2.0 * (qw * qx + qy * qz), 1.0 - 2.0 * (qx * qx + qy * qy))
	-- local yaw  = math.atan(2.0 * (qw * qz + qx * qy), 1.0 - 2.0 * (qy * qy + qz * qz))
	-- local rad2deg = 180.0 / math.pi
	-- return M.rotator(pitch * rad2deg, yaw * rad2deg, roll * rad2deg)
end

function M.quat(x, y, z, w, reuseable, preferKismet)
	local quat = uevrLib.get_struct_object("ScriptStruct /Script/CoreUObject.Quat", reuseable)
	if quat ~= nil then
		if preferKismet and kismet_math_library.Quat_SetComponents ~= nil then
			kismet_math_library:Quat_SetComponents(quat, x, y, z, w)
		else
			quat.X = x
			quat.Y = y
			quat.Z = z
			quat.W = w
		end
	end
	return quat
end

function M.vectorRotate_Quat(vec, quat, preferKismet)
	if preferKismet and kismet_math_library and kismet_math_library.GreaterGreater_VectorRotator then
		return kismet_math_library:Quat_RotateVector(quat, vec)
	end
	-- support method-call style: (self, quat, vec) or function-call style (quat, vec)
	if vec == nil and type(quat) == "table" and quat.X ~= nil and quat.Y ~= nil and quat.Z ~= nil and quat.W == nil then
		-- unlikely, keep signature robust
	end

	local q = quat
	-- extract quaternion components (accept many naming conventions)
	local qx = (q.X or q.x or q[1]) or 0
	local qy = (q.Y or q.y or q[2]) or 0
	local qz = (q.Z or q.z or q[3]) or 0
	local qw = (q.W or q.w or q[4]) or 0

	local v = vec or {X=0,Y=0,Z=0}
	local vx = (v.X or v.x or v[1]) or 0
	local vy = (v.Y or v.y or v[2]) or 0
	local vz = (v.Z or v.z or v[3]) or 0

	-- t = 2 * cross(q_vec, v)
	local tx = 2 * ( qy * vz - qz * vy )
	local ty = 2 * ( qz * vx - qx * vz )
	local tz = 2 * ( qx * vy - qy * vx )

	-- v' = v + qw * t + cross(q_vec, t)
	local cx = qy * tz - qz * ty
	local cy = qz * tx - qx * tz
	local cz = qx * ty - qy * tx

	if kismet_math_library and kismet_math_library.MakeVector then
		return kismet_math_library:MakeVector(vx + qw * tx + cx, vy + qw * ty + cy, vz + qw * tz + cz)
	end
	return M.vector(vx + qw * tx + cx, vy + qw * ty + cy, vz + qw * tz + cz)

	--return { X = vx + qw * tx + cx, Y = vy + qw * ty + cy, Z = vz + qw * tz + cz }
end

function M.quatFromEuler(euler, preferKismet)
	if preferKismet and kismet_math_library and kismet_math_library.Quat_MakeFromEuler then
		return kismet_math_library:Quat_MakeFromEuler(euler)
	end
	if euler == nil then return nil end
	local pitch  = euler.X or euler.x or euler.Pitch or euler.pitch or euler[1] or 0.0
	local yaw = euler.Y or euler.y or euler.Yaw or euler.yaw or euler[2] or 0.0
	local roll   = euler.Z or euler.z or euler.Roll or euler.roll or euler[3] or 0.0

	local deg2rad = math.pi / 180.0
	local hr = (roll  * deg2rad) * 0.5
	local hp = (pitch * deg2rad) * 0.5
	local hy = (yaw   * deg2rad) * 0.5

	local sr, cr = math.sin(hr), math.cos(hr)
	local sp, cp = math.sin(hp), math.cos(hp)
	local sy, cy = math.sin(hy), math.cos(hy)

	local x = (cr * sp * sy) - (sr * cp * cy)
	local y = -(cr * sp * cy) - (sr * cp * sy)
	local z = (cr * cp * sy) - (sr * sp * cy)
	local w = (cr * cp * cy) + (sr * sp * sy)

	return {W = w, X = x, Y = y, Z = z}
end

-- output range [-180, 180)
-- returns -180 for input 180 and for -180
function M.normalizeDeg180(angleDeg)
	if angleDeg == nil then return nil end
	return (((angleDeg + 180.0) % 360.0) - 180.0)
end

-- output range (-180, 180]
-- returns 180 for input 180 and for -180
-- This is an alternate to normalizeDeg180, may be faster or slower depending on input distribution.
function M.clampAngle180(angle)
    angle = angle % 360
    if angle > 180 then
        angle = angle - 360
    end
    return angle
end

-- Unwrap an angle to be continuous vs a previous sample.
-- Keeps the returned value within +/-180 of prevAngleDeg.
function M.unwrapDeg(angleDeg, prevAngleDeg)
	if angleDeg == nil or prevAngleDeg == nil then return angleDeg end
	local delta = angleDeg - prevAngleDeg
	delta = M.normalizeDeg180(delta)
	return prevAngleDeg + delta
end

function M.signedAngleDegAroundAxis(a, b, axis)
	-- Signed angle from a->b around axis.
	local cross = M.vectorCross(a, b)
	local y = M.vectorDot(axis, cross) or 0.0
	local x = M.vectorDot(a, b) or 1.0
	return math.atan(y, x) * (180.0 / math.pi)
end


-- Robust twist extraction: swing–twist decomposition of the relative rotation.
-- This avoids the fundamental instability of using raw up/right vectors when wrist pitch/yaw changes.
local RAD2DEG = 180.0 / math.pi
local _reuseEulerA = nil
local _reuseEulerB = nil
function M.computeSwingTwistAroundAxis_Rotators(rotA, rotB, axis, twistOnly)
	if rotA == nil or rotB == nil or axis == nil then return nil end

	-- Axis is expected to already be normalized (call sites pass SafeNormalize(lowerDirCS)).
	-- Keep this hot path sqrt-free: just guard against a degenerate axis.
	local ax = axis.X or axis.x or 0.0
	local ay = axis.Y or axis.y or 0.0
	local az = axis.Z or axis.z or 0.0
	local len2 = (ax * ax) + (ay * ay) + (az * az)
	if len2 < 1e-8 then return nil end

	-- IMPORTANT: use Unreal's own Euler->Quat conversion.
	-- Rotator (Pitch/Yaw/Roll) can represent the same orientation with different Euler triples;
	-- hand-rolling conversion/order can disagree with engine conventions and leak pitch/yaw into "twist".
	if _reuseEulerA == nil then
		_reuseEulerA = M.vector(0.0, 0.0, 0.0)
		_reuseEulerB = M.vector(0.0, 0.0, 0.0)
	end
	M.vectorSet(_reuseEulerA, rotA.Roll or 0.0, rotA.Pitch or 0.0, rotA.Yaw or 0.0) -- Roll, Pitch, Yaw
	M.vectorSet(_reuseEulerB, rotB.Roll or 0.0, rotB.Pitch or 0.0, rotB.Yaw or 0.0)

	local qa = kismet_math_library:Quat_MakeFromEuler(_reuseEulerA)
	local qb = kismet_math_library:Quat_MakeFromEuler(_reuseEulerB)
	if qa == nil or qb == nil then return nil end

	local aw = qa.W or qa.w or 1.0
	local axq = qa.X or qa.x or 0.0
	local ayq = qa.Y or qa.y or 0.0
	local azq = qa.Z or qa.z or 0.0

	local bw = qb.W or qb.w or 1.0
	local bxq = qb.X or qb.x or 0.0
	local byq = qb.Y or qb.y or 0.0
	local bzq = qb.Z or qb.z or 0.0

	-- Relative rotation qRel = qb * conj(qa) (qa assumed unit).
	local rw = (bw * aw) + (bxq * axq) + (byq * ayq) + (bzq * azq)
	local rx = (-bw * axq) + (bxq * aw) - (byq * azq) + (bzq * ayq)
	local ry = (-bw * ayq) + (bxq * azq) + (byq * aw) - (bzq * axq)
	local rz = (-bw * azq) - (bxq * ayq) + (byq * axq) + (bzq * aw)

	-- No normalization required: atan2(k*dot, k*w) == atan2(dot, w) for k>0.
	-- Still guard against degenerate quats.
	local n2 = (rw * rw) + (rx * rx) + (ry * ry) + (rz * rz)
	if n2 < 1e-12 then return 0.0, nil, nil, nil, nil end

	-- Twist angle around axis for qRel: theta = 2 * atan2(dot(v, axis), w)
	local dot = (rx * ax) + (ry * ay) + (rz * az)
	local twistDeg = (2.0 * math.atan(dot, rw)) * RAD2DEG
	if twistOnly then return twistDeg, nil, nil, nil, nil end

	-- Normalized twist quaternion projected onto the supplied axis.
	local twx = ax * dot
	local twy = ay * dot
	local twz = az * dot
	local tww = rw
	local twistLen2 = (twx * twx) + (twy * twy) + (twz * twz) + (tww * tww)
	if twistLen2 < 1e-12 then
		local invRelLen = 1.0 / math.sqrt(n2)
		return twistDeg, rx * invRelLen, ry * invRelLen, rz * invRelLen, rw * invRelLen
	end

	local invTwistLen = 1.0 / math.sqrt(twistLen2)
	twx = twx * invTwistLen
	twy = twy * invTwistLen
	twz = twz * invTwistLen
	tww = tww * invTwistLen

	-- swing = qRel * conj(qTwist)
	local swingW = (rw * tww) + (rx * twx) + (ry * twy) + (rz * twz)
	local swingX = (-rw * twx) + (rx * tww) - (ry * twz) + (rz * twy)
	local swingY = (-rw * twy) + (rx * twz) + (ry * tww) - (rz * twx)
	local swingZ = (-rw * twz) - (rx * twy) + (ry * twx) + (rz * tww)
	local swingLen2 = (swingW * swingW) + (swingX * swingX) + (swingY * swingY) + (swingZ * swingZ)
	if swingLen2 < 1e-12 then return twistDeg, nil, nil, nil, nil end

	local invSwingLen = 1.0 / math.sqrt(swingLen2)
	return twistDeg, swingX * invSwingLen, swingY * invSwingLen, swingZ * invSwingLen, swingW * invSwingLen
end

function M.computeTwistDegAroundAxis_Rotators(rotA, rotB, axis)
	local twistDeg = M.computeSwingTwistAroundAxis_Rotators(rotA, rotB, axis, true)
	return twistDeg
end

function M.vector(...)
    local arg = {...}
	local x=0.0
	local y=0.0
	local z=0.0
	local reuseable = false

	if #arg == 1 or #arg == 2 then
		if type(arg[1]) == "table" or type(arg[1]) == "userdata" then
			x = (arg[1].X ~= nil) and arg[1].X or ((arg[1].x ~= nil) and arg[1].x or ((#arg[1] > 0) and arg[1][1] or 0.0))
			y = (arg[1].Y ~= nil) and arg[1].Y or ((arg[1].y ~= nil) and arg[1].y or ((#arg[1] > 1) and arg[1][2] or 0.0))
			z = (arg[1].Z ~= nil) and arg[1].Z or ((arg[1].z ~= nil) and arg[1].z or ((#arg[1] > 2) and arg[1][3] or 0.0))
		else
			M.print("Invalid argument 1 passed to vector function", LogLevel.Warning)
		end

		if #arg == 2 then
			if type(arg[2]) == "boolean" then
				reuseable = arg[2]
			else
				M.print("Invalid argument 2 passed to vector function", LogLevel.Warning)
			end
		end
	elseif #arg == 3 or #arg == 4 then
		if type(arg[1]) == "number" then x = arg[1] else M.print("Invalid x value passed to vector function", LogLevel.Warning) end
		if type(arg[2]) == "number" then y = arg[2] else M.print("Invalid y value passed to vector function", LogLevel.Warning) end
		if type(arg[3]) == "number" then z = arg[3] else M.print("Invalid z value passed to vector function", LogLevel.Warning) end

		if #arg == 4 then
			if type(arg[4]) == "boolean" then
				reuseable = arg[4]
			else
				M.print("Invalid argument 4 passed to vector function", LogLevel.Warning)
			end
		end
	end

	local vector = uevrLib.get_struct_object("ScriptStruct /Script/CoreUObject.Vector", reuseable)
	if vector ~= nil then
		if vector["X"] ~= nil then vector.X = x else vector.x = x end
		if vector["Y"] ~= nil then vector.Y = y else vector.y = y end
		if vector["Z"] ~= nil then vector.Z = z else vector.z = z end
	end
	return vector

	--this should work but doesnt, at least in robocop
	--return kismet_math_library:MakeVector(x, y, z)

end

function M.rotator(...)
    local arg = {...}
	local pitch=0
	local yaw=0
	local roll=0
	local reuseable = false

	if #arg == 1 or #arg == 2 then
		if type(arg[1]) == "userdata" then --maybe a rotator was sent in
			--if arg[1]:is_a(M.get_class("ScriptStruct /Script/CoreUObject.Rotator")) then
			return arg[1]
		elseif type(arg[1]) == "table" then
			pitch = (arg[1].Pitch ~= nil) and arg[1].Pitch or ((arg[1].X ~= nil) and arg[1].X or ((arg[1].x ~= nil) and arg[1].x or ((#arg[1] > 0) and arg[1][1] or 0.0)))
			yaw = (arg[1].Yaw ~= nil) and arg[1].Yaw or ((arg[1].Y ~= nil) and arg[1].Y or ((arg[1].y ~= nil) and arg[1].y or ((#arg[1] > 1) and arg[1][2] or 0.0)))
			roll = (arg[1].Roll ~= nil) and arg[1].Roll or ((arg[1].Z ~= nil) and arg[1].Z or ((arg[1].z ~= nil) and arg[1].z or ((#arg[1] > 2) and arg[1][3] or 0.0)))
		else
			M.print("Invalid argument 1 passed to rotator function", LogLevel.Warning)
		end

		if #arg == 2 then
			if type(arg[2]) == "boolean" then
				reuseable = arg[2]
			else
				M.print("Invalid argument 2 passed to rotator function", LogLevel.Warning)
			end
		end
	elseif #arg == 3 or #arg == 4 then
		if type(arg[1]) == "number" then pitch = arg[1] else M.print("Invalid pitch value passed to rotator function", LogLevel.Warning) end
		if type(arg[2]) == "number" then yaw = arg[2] else M.print("Invalid yaw value passed to rotator function", LogLevel.Warning) end
		if type(arg[3]) == "number" then roll = arg[3] else M.print("Invalid roll value passed to rotator function", LogLevel.Warning) end

		if #arg == 4 then
			if type(arg[4]) == "boolean" then
				reuseable = arg[4]
			else
				M.print("Invalid argument 4 passed to rotator function", LogLevel.Warning)
			end
		end
	end

	if kismet_math_library.MakeRotator ~= nil then
		return kismet_math_library:MakeRotator(roll, pitch, yaw)
	end

	local rotator = uevrLib.get_struct_object("ScriptStruct /Script/CoreUObject.Rotator", reuseable)
	if rotator ~= nil then
		if rotator["Pitch"] ~= nil then rotator.Pitch = pitch else rotator.pitch = pitch end
		if rotator["Yaw"] ~= nil then rotator.Yaw = yaw else rotator.yaw = yaw end
		if rotator["Roll"] ~= nil then rotator.Roll = roll else rotator.roll = roll end
	else
		rotator = {Pitch = pitch, Yaw = yaw, Roll = roll}
	end
	return rotator
end

-- function M.ProjectVectorOnToPlane(vec, planeNormal)
-- 	if kismet_math_library.ProjectVectorOnToPlane ~= nil then
--         return kismet_math_library:ProjectVectorOnToPlane(vec, planeNormal)
--     else
--         if vec == nil then return uevrUtils.vector(0,0,0) end
-- 			if planeNormal == nil then return vec end

-- 			-- Prefer engine helpers if present
-- 			if kismet_math_library.Dot_VectorVector and kismet_math_library.Multiply_VectorFloat and kismet_math_library.Subtract_VectorVector then
-- 				local dotVN = kismet_math_library:Dot_VectorVector(vec, planeNormal) or 0.0
-- 				local denom = kismet_math_library:Dot_VectorVector(planeNormal, planeNormal) or 0.0
-- 				if denom <= 1e-8 then return uevrUtils.vector(0,0,0) end
-- 				local scale = dotVN / denom
-- 				local comp = kismet_math_library:Multiply_VectorFloat(planeNormal, scale)
-- 				return kismet_math_library:Subtract_VectorVector(vec, comp)
-- 			end

-- 			-- Fallback: plain numeric vectors (supports {X,Y,Z} or array)
-- 			local vx = vec.X or vec[1] or 0
-- 			local vy = vec.Y or vec[2] or 0
-- 			local vz = vec.Z or vec[3] or 0
-- 			local nx = planeNormal.X or planeNormal[1] or 0
-- 			local ny = planeNormal.Y or planeNormal[2] or 0
-- 			local nz = planeNormal.Z or planeNormal[3] or 0
-- 			local dotVN = vx*nx + vy*ny + vz*nz
-- 			local denom = nx*nx + ny*ny + nz*nz
-- 			if denom <= 1e-8 then return uevrUtils.vector(0,0,0) end
-- 			local s = dotVN / denom
-- 			return uevrUtils.vector(vx - nx*s, vy - ny*s, vz - nz*s)
-- 	end
-- end

function M.getTransform(position, rotation, scale, reuseable)
	if position == nil then position = {X=0.0, Y=0.0, Z=0.0} end
	if scale == nil then scale = {X=1.0, Y=1.0, Z=1.0} end
	local transform = uevrLib.get_struct_object("ScriptStruct /Script/CoreUObject.Transform", reuseable)
	if transform ~= nil then
		transform.Translation = vector_3f(position.X, position.Y, position.Z)
		if rotation == nil then
			transform.Rotation.X = 0.0
			transform.Rotation.Y = 0.0
			transform.Rotation.Z = 0.0
			transform.Rotation.W = 1.0
		else
			transform.Rotation = rotation
		end
		transform.Scale3D = vector_3f(scale.X, scale.Y, scale.Z)
	end
	return transform
end

function M.vector2D(...)
    local arg = {...}
	local x=0.0
	local y=0.0
	local reuseable = false

	if #arg == 1 or (#arg == 2 and type(arg[2]) == "boolean") then
		if type(arg[1]) == "table" or type(arg[1]) == "userdata" then
			x = (arg[1].X ~= nil) and arg[1].X or ((arg[1].x ~= nil) and arg[1].x or ((#arg[1] > 0) and arg[1][1] or 0.0))
			y = (arg[1].Y ~= nil) and arg[1].Y or ((arg[1].y ~= nil) and arg[1].y or ((#arg[1] > 1) and arg[1][2] or 0.0))
		else
			M.print("Invalid argument 1 passed to vector function", LogLevel.Warning)
		end

		if #arg == 2 then
			if type(arg[2]) == "boolean" then
				reuseable = arg[2]
			else
				M.print("Invalid argument 2 passed to vector function", LogLevel.Warning)
			end
		end
	elseif #arg == 2 or (#arg == 3 and type(arg[3]) == "boolean") then
		if type(arg[1]) == "number" then x = arg[1] else M.print("Invalid x value passed to vector function", LogLevel.Warning) end
		if type(arg[2]) == "number" then y = arg[2] else M.print("Invalid y value passed to vector function", LogLevel.Warning) end

		if #arg == 3 then
			if type(arg[3]) == "boolean" then
				reuseable = arg[3]
			else
				M.print("Invalid argument 3 passed to vector function", LogLevel.Warning)
			end
		end
	end

	local vector = uevrLib.get_struct_object("ScriptStruct /Script/CoreUObject.Vector2D", reuseable)
	if vector ~= nil then
		if vector["X"] ~= nil then vector.X = x else vector.x = x end
		if vector["Y"] ~= nil then vector.Y = y else vector.y = y end
	end
	return vector
end

function M.init()
	kismet_math_library = uevrLib.find_default_instance("Class /Script/Engine.KismetMathLibrary")
end
M.init()

return M