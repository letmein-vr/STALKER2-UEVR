-- quat_math.lua - pure-Lua quaternion helpers in Unreal conventions.
-- Quats are {w,x,y,z}, vectors {x,y,z}, rotators in degrees (Pitch, Yaw, Roll).
-- rotatorToQuat / quatToRotator mirror FRotator::Quaternion / FQuat::Rotator and were
-- verified numerically against UE's forward-vector convention (2026-10-02). No UFunction
-- calls, so they are safe on any thread and cost nothing per frame.

local M = {}

function M.mul(a, b)
    return {
        w = a.w * b.w - a.x * b.x - a.y * b.y - a.z * b.z,
        x = a.w * b.x + a.x * b.w + a.y * b.z - a.z * b.y,
        y = a.w * b.y - a.x * b.z + a.y * b.w + a.z * b.x,
        z = a.w * b.z + a.x * b.y - a.y * b.x + a.z * b.w,
    }
end

function M.inv(q)
    return {w = q.w, x = -q.x, y = -q.y, z = -q.z}
end

-- Rotate vector (x,y,z) by unit quat q
function M.rotate(q, x, y, z)
    local tx = 2 * (q.y * z - q.z * y)
    local ty = 2 * (q.z * x - q.x * z)
    local tz = 2 * (q.x * y - q.y * x)
    return {
        x = x + q.w * tx + (q.y * tz - q.z * ty),
        y = y + q.w * ty + (q.z * tx - q.x * tz),
        z = z + q.w * tz + (q.x * ty - q.y * tx),
    }
end

-- FRotator::Quaternion (degrees)
function M.fromRotator(p, y, r)
    local d = math.pi / 360
    local sp, cp = math.sin(p * d), math.cos(p * d)
    local sy, cy = math.sin(y * d), math.cos(y * d)
    local sr, cr = math.sin(r * d), math.cos(r * d)
    return {
        x =  cr * sp * sy - sr * cp * cy,
        y = -cr * sp * cy - sr * cp * sy,
        z =  cr * cp * sy - sr * sp * cy,
        w =  cr * cp * cy + sr * sp * sy,
    }
end

local function normalizeAxis(a)
    a = a % 360
    if a > 180 then a = a - 360 end
    return a
end

-- FQuat::Rotator (degrees) -> pitch, yaw, roll
function M.toRotator(q)
    local rad2deg = 180 / math.pi
    local singularity = q.z * q.x - q.w * q.y
    local yaw = math.atan(2 * (q.w * q.z + q.x * q.y), 1 - 2 * (q.y * q.y + q.z * q.z)) * rad2deg
    local THRESH = 0.4999995
    if singularity < -THRESH then
        return -90, yaw, normalizeAxis(-yaw - 2 * math.atan(q.x, q.w) * rad2deg)
    elseif singularity > THRESH then
        return 90, yaw, normalizeAxis(yaw - 2 * math.atan(q.x, q.w) * rad2deg)
    end
    return math.asin(2 * singularity) * rad2deg, yaw,
        math.atan(-2 * (q.w * q.x + q.y * q.z), 1 - 2 * (q.x * q.x + q.y * q.y)) * rad2deg
end

-- Shortest-path slerp
function M.slerp(a, b, t)
    local bw, bx, by, bz = b.w, b.x, b.y, b.z
    local dot = a.w * bw + a.x * bx + a.y * by + a.z * bz
    if dot < 0 then
        dot = -dot
        bw, bx, by, bz = -bw, -bx, -by, -bz
    end
    local s0, s1
    if dot > 0.9995 then
        s0, s1 = 1 - t, t
    else
        local theta = math.acos(dot)
        local sinTheta = math.sin(theta)
        s0 = math.sin((1 - t) * theta) / sinTheta
        s1 = math.sin(t * theta) / sinTheta
    end
    local w = s0 * a.w + s1 * bw
    local x = s0 * a.x + s1 * bx
    local y = s0 * a.y + s1 * by
    local z = s0 * a.z + s1 * bz
    local len = math.sqrt(w * w + x * x + y * y + z * z)
    if len > 0 then w, x, y, z = w / len, x / len, y / len, z / len end
    return {w = w, x = x, y = y, z = z}
end

return M
