

struct AABB
{
	float xMin, xMax, yMin, yMax, zMin, zMax;
};

struct BVHNode
{
	AABB bounds;
	BVHNode* childLeft, * childRight;
	BVHNode* parent; 
	BVHNode * self; 
	int idxSelf, idxChildL, idxChildR, isLeafChildL, isLeafChildR; 
	int triangleID;
	int atomic;
	int rangeLeft, rangeRight;
};
