AddCSLuaFile()

local function NoiseLerp(Start, Goal, Theta) return Start + (Goal - Start) * Theta end

local function fade(t) 
    return t * t * t * (t * (t * 6 - 15) + 10)
end

local function remap(iMin, iMax, oMin, oMax, v)
    local t = InverseLerp(iMin, iMax, v)
    return NoiseLerp(oMin, oMax, t)
end

local function grad(hash, x)
    local h = hash % 2
    return (h % 2) == 0 and x or -x
end

local function grad2D(hash, x, y)
    local h = hash % 8
    local u = h < 4 and x or y
    return (h % 2) == 0 and u or -u
end

local function grad3D(hash, x, y, z)
    local h = hash % 16
    local u = h < 8 and x or y
    local v = h < 4 and y or z
    return (h % 2) == 0 and u or -u + (h % 4) == 0 and v or -v
end

local p = {
    160,137,91,90,15,
    131,13,201,95,96,53,194,233,7,225,140,36,103,30,69,142,8,99,37,240,21,10,23,
    190, 6,148,247,120,234,75,0,26,197,62,94,252,219,203,117,35,11,32,57,177,33,
    88,237,149,56,87,174,20,125,136,171,168, 68,175,74,165,71,134,139,48,27,166,
    77,146,158,231,83,111,229,122,60,211,133,230,220,105,92,41,55,46,245,40,244,
    102,143,54, 65,25,63,161, 1,216,80,73,209,76,132,187,208, 89,18,169,200,196,
    135,130,116,188,159,86,164,100,109,198,173,186, 3,64,52,217,226,250,124,123,
    5,202,38,147,118,126,255,82,85,212,207,206,59,227,47,16,58,17,182,189,28,42,
    223,183,170,213,119,248,152, 2,44,154,163, 70,221,153,101,155,167, 43,172,9,
    129,22,39,253, 19,98,108,110,79,113,224,232,178,185, 112,104,218,246,97,228,
    251,34,242,193,238,210,144,12,191,179,162,241, 81,51,145,235,249,14,239,107,
    49,192,214, 31,181,199,106,157,184, 84,204,176,115,121,50,45,127, 4,150,254,
    138,236,205,93,222,114,67,29,24,72,243,141,128,195,78,66,215,61,156,180
}

p[0] = 151
for i = 0, 255 do p[256+i] = p[i] end

function perlinNoise1D(x)
    local X = math.floor(x) % 256
    x = x - math.floor(x)
    local u = fade(x)
    
    local A = p[X]
    local B = p[X+1]

    return NoiseLerp(
        grad(p[A], x), 
        grad(p[B], x-1),
        u
    )
end

function perlinNoise2D(x, y)
    local X = math.floor(x) % 256
    local Y = math.floor(y) % 256
    x = x - math.floor(x)
    y = y - math.floor(y)
    local u, v = fade(x), fade(y)
    
    local A = p[X] + Y
    local B = p[X+1] + Y

    local AA = p[A] + X
    local BB = p[B+1] + X

    return NoiseLerp(
        NoiseLerp(
            grad2D(p[A], x, y), 
            grad2D(p[B], x-1, y),
            u
        ),
        NoiseLerp(
            grad2D(p[AA], x, y-1), 
            grad2D(p[BB], x-1, y-1),
            u
        ),
        v
    )
end

function perlinNoise3D(x, y, z)
    local X = math.floor(x) % 256
    local Y = math.floor(y) % 256
    local Z = math.floor(z) % 256
    x = x - math.floor(x)
    y = y - math.floor(y)
    z = z - math.floor(z)
    local u, v, w = fade(x), fade(y), fade(z)
    
    local A = p[X] + Y
    local AA = p[A] + Z
    local AB = p[A+1] + Z
    local B = p[X+1] + Y
    local BA = p[B] + Z
    local BB = p[B+1] + Z

    return NoiseLerp(
        NoiseLerp(
            NoiseLerp(
                grad3D(p[AA], x, y, z), 
                grad3D(p[BA], x-1, y, z),
                u
            ),
            NoiseLerp(
                grad3D(p[AB], x, y-1, z), 
                grad3D(p[BB], x-1, y-1, z),
                u
            ),
            v
        ),
        NoiseLerp(
            NoiseLerp(
                grad3D(p[AA+1], x, y, z-1), 
                grad3D(p[BA+1], x-1, y, z-1),
                u
            ),
            NoiseLerp(
                grad3D(p[AB+1], x, y-1, z-1), 
                grad3D(p[BB+1], x-1, y-1, z-1),
                u
            ),
            v
        ),
        w
    )
end

function FractalNoise(x, y, z, scale, octaves, lacunarity, gain)
	scale = scale or 1
	octaves = octaves or 1
	lacunarity = lacunarity or 2
	gain = gain or 0.5
	
	local total = 0
	local amplitude = 1
	local frequency = 1

	for i = 0, octaves do
		local v = perlinNoise3D(x / scale * frequency, y / scale * frequency, z) * amplitude
		total = total + v
		frequency = frequency * lacunarity
		amplitude = amplitude * gain
	end	

	return total
end

function NoisePatternRough(x, y, z, scale, octaves, lacunarity, gain)
	local q = {
		FractalNoise(x, y, z, scale, octaves, lacunarity, gain), 
		FractalNoise(x + 5.2, y + 1.3, z, scale, octaves, lacunarity, gain), 
	}

	return math.Clamp(FractalNoise(x + 90 * q[1], y + 90 * q[2], z, scale, octaves, lacunarity, gain), -1, 1);
end

function SpiralNoise(position, center, swirlSize, swirlAmount, noiseTime)
	local angle = math.atan2(position.X - center.X, position.Y - center.Y) + noiseTime
	local distance = ((position - center) * Vector(1, 1, 0)):Length() / 1000 * swirlAmount

	local noisePosition = Vector(math.sin(angle - distance), 0, math.cos(angle - distance)) / swirlSize
	return perlinNoise2D(noisePosition.X, noisePosition.Z)
end

function XT3WindfieldNoise(Position, Center, NoiseTime, WindfieldData)
    local NoiseMultiplier = 1
    local NoisePosition = (Position - Center)

    local RMW = 100
    local SwirlScaler = -(1 * math.min(RMW/10000, 1)^0.255) * 2
    
    local NoiseTimeScalar = (NoiseTime * (200/RMW)) * 4
    if NoiseTimeScalar ~= NoiseTimeScalar then NoiseTimeScalar = 1 end

    NoiseMultiplier = NoisePatternRough(NoisePosition[1], NoisePosition[2], NoisePosition[3] + (NoiseTimeScalar), math.max(RMW, 100) * 1, 2) + 0.5
    
    local SpiralNoiseMultiplier = SpiralNoise(Position, Center, 1, 2 + SwirlScaler, NoiseTimeScalar) + 0.5
    SpiralNoiseMultiplier = Lerp(SpiralNoiseMultiplier, 0.725, 1)
    NoiseMultiplier = Lerp((NoiseMultiplier+SpiralNoiseMultiplier)/2, 0.825, 1.125)

    return math.min(NoiseMultiplier, 1), math.min(SpiralNoiseMultiplier, 1)
end