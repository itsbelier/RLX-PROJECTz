--!strict
-- ReplicatedStorage/Shared/Obstacles/ObstaclesCatalog
-- Shared source of truth for what obstacles exist and basic placement rules.

export type ObstacleDef = {
	name: string,
	displayName: string,
	previewColor: Color3?, -- optional for later
}

local Catalog: {ObstacleDef} = {
	{ name = "ob1", displayName = "Obstacle 1" },
	{ name = "ob2", displayName = "Obstacle 2" },
	{ name = "ob3", displayName = "Obstacle 3" },
	{ name = "ob4", displayName = "Obstacle 4" },
	{ name = "ob5", displayName = "Obstacle 5" },
}

local byName: {[string]: ObstacleDef} = {}
for _, def in ipairs(Catalog) do
	byName[def.name] = def
end

local ObstaclesCatalog = {}

function ObstaclesCatalog.GetAll(): {ObstacleDef}
	return Catalog
end

function ObstaclesCatalog.Exists(name: string): boolean
	return byName[name] ~= nil
end

return ObstaclesCatalog
