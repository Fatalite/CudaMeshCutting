#ifndef Cutting_h
#define Cutting_h
#include <chrono>
#include <thrust/host_vector.h>
#include <thrust/device_vector.h>
#include "DataStructures.cuh"
#define CUDA_CHECK(val) { \
    if (val != cudaSuccess) { \
        fprintf(stderr, "Error %s at line %d in file %s\n", cudaGetErrorString(val), __LINE__, __FILE__); \
        exit(1); \
    } \
}
__global__
void vecAddKernel(const float* A, const float* B, float* C, int numElements)
{
    int i = blockIdx.x * blockDim.x + threadIdx.x;

    if (i < numElements) {

        C[i] = A[i] + B[i];
    }
}

//CUDA DEVICE CODE
template<typename T>
__device__ void Dot(T* result, const T* a, const T* b, int size) {
    for (int i = 0; i < size; ++i) {
        (*result) += a[i] * b[i];
    }
}

template<typename T>
__device__ void Cross(T* result, const T* a, const T* b) {
    result[0] = a[1] * b[2] - a[2] * b[1];
    result[1] = a[2] * b[0] - a[0] * b[2];
    result[2] = a[0] * b[1] - a[1] * b[0];
}

template<typename T>
__device__ void Subtract(T* result, const T* a, const T* b, int size) {
    for (int i = 0; i < size; ++i)
        result[i] = a[i] - b[i];
}

template<typename T>
__device__ void Volume(const T* node1, const T* node2, const T* node3, const T* node4, T* nodeReturn) {
    T temp1[3], temp2[3], temp3[3], cross_result[3];
   //printf("%f", node1);
    Subtract(temp1, node2, node1, 3);
    Subtract(temp2, node3, node1, 3);
    Subtract(temp3, node4, node1, 3);
    Cross(cross_result, temp1, temp2);
    //printf("%f", cross_result);
    Dot( nodeReturn,cross_result, temp3, 3);
}

template<typename T>
__global__
void computeIntersectionCUDA(T* nodes1, T* nodes2, T* w1, T* w2, bool* b, int numElements) {
    int i = blockIdx.x * blockDim.x + threadIdx.x;

    if (i < numElements) {
        T v1, v2, v3, v4, v5;
        //printf("%f", v1[0]);
        Volume<T>(&nodes1[i * 6 + 0], &nodes2[0], &nodes2[3], &nodes2[6], &v1);
        Volume<T>(&nodes1[i * 6 + 3], &nodes2[0], &nodes2[3], &nodes2[6], &v2);
        Volume<T>(&nodes1[i * 6 + 0], &nodes1[i * 6 + 3], &nodes2[0], &nodes2[3], &v3);
        Volume<T>(&nodes1[i * 6 + 0], &nodes1[i * 6 + 3], &nodes2[3], &nodes2[6], &v4);
        Volume<T>(&nodes1[i * 6 + 0], &nodes1[i * 6 + 3], &nodes2[6], &nodes2[0], &v5);
        
        if (v1 * v2 < 0 && (v3 > 0) == (v4 > 0) && (v4 > 0) == (v5 > 0)) {
            w1[i * 4 + 0] = fabs(v2) / (fabs(v1) + fabs(v2));
            w1[i * 4 + 1] = 1 - w1[0];
            T v = fabs(v3) + fabs(v4) + fabs(v5);
            w2[i * 4 + 0] = fabs(v4) / v;
            w2[i * 4 + 1] = fabs(v5) / v;
            w2[i * 4 + 2] = 1 - w2[i * 4 + 0] - w2[i * 4 + 1];
            b[i] = true;
        }
        else {
            b[i] =  false;
        }
    }

}
template<typename T>
class Cutter3D {
    typedef std::array<int, 1> I1;
    typedef std::array<int, 2> I2;
    typedef std::array<int, 3> I3;
    typedef std::array<int, 4> I4;
    typedef std::array<int, 5> I5;
    typedef std::array<T, 2> T2;
    typedef std::array<T, 3> T3;
    typedef std::array<T, 4> T4;
    typedef map<I4, T4> Intersections;
    typedef map<I4, vector<int>> TetBoundary2TetIds;

    struct CutElement {
        int parentElementIndex;
        array<bool, 4> subElements; // in the same order as the tet nodes

        CutElement(int i, bool fill = true) : parentElementIndex(i) {
            subElements.fill(fill);
        }

        int numPieces() const {
            return (int)subElements[0] + (int)subElements[1] + (int)subElements[2] + (int)subElements[3];
        }
    };

    static bool computeIntersection(const array<T3, 2>& nodes1, const array<T3, 3>& nodes2, array<T, 2>& w1, array<T, 3>& w2) {
        T v1 = volume<T>(nodes1[0], nodes2[0], nodes2[1], nodes2[2]);
        T v2 = volume<T>(nodes1[1], nodes2[0], nodes2[1], nodes2[2]);
        T v3 = volume<T>(nodes1[0], nodes1[1], nodes2[0], nodes2[1]);
        T v4 = volume<T>(nodes1[0], nodes1[1], nodes2[1], nodes2[2]);
        T v5 = volume<T>(nodes1[0], nodes1[1], nodes2[2], nodes2[0]);
        if (v1 * v2 < 0 && (v3 > 0) == (v4 > 0) && (v4 > 0) == (v5 > 0)) {
            w1[0] = fabs(v2) / (fabs(v1) + fabs(v2));
            w1[1] = 1 - w1[0];
            T v = fabs(v3) + fabs(v4) + fabs(v5);
            w2[0] = fabs(v4) / v;
            w2[1] = fabs(v5) / v;
            w2[2] = 1 - w2[0] - w2[1];
            printf("%f, %f", w1[0], w1[1]);
            return true;
        }
        else {
            return false;
        }
    }

    static bool computeIntersection(const array<T3, 2>& nodes1, const array<T3, 3>& nodes2, array<T, 2>& w) {
        array<T, 3> w1;
        return computeIntersection(nodes1, nodes2, w, w1);
    }
    struct EdgeTriangle {
        float FirstPointXOfEdge;
        float FirstPointYOfEdge;
        float FirstPointZOfEdge;
    };
    static bool computeIntersection(const array<T3, 3>& nodes1, const array<T3, 2>& nodes2, array<T, 3>& w) {
        array<T, 2> w1;
        return computeIntersection(nodes2, nodes1, w1, w);
    }
   
    static bool computeIntersection(const array<T3, 4>& nodes1, const array<T3, 1>& nodes2, array<T, 4>& w) {
        T v1 = volume<T>(nodes1[0], nodes1[1], nodes1[2], nodes2[0]);
        T v2 = volume<T>(nodes1[0], nodes1[2], nodes1[3], nodes2[0]);
        T v3 = volume<T>(nodes1[0], nodes1[3], nodes1[1], nodes2[0]);
        T v4 = volume<T>(nodes2[0], nodes1[1], nodes1[2], nodes1[3]);
        if (v1 == 0 || v2 == 0 || v3 == 0 || v4 == 0) {
            cout << "point tet degenerate case" << endl;
        }
        // cout << v1 << ", " << v2 << ", " << v3 << ", " << v4 << endl;
        if ((v1 > 0) == (v2 > 0) && (v2 > 0) == (v3 > 0) && (v3 > 0) == (v4 > 0)) {
            T v = fabs(v1) + fabs(v2) + fabs(v3) + fabs(v4);
            w[0] = fabs(v4) / v;
            w[1] = fabs(v2) / v;
            w[2] = fabs(v3) / v;
            w[3] = 1 - w[0] - w[1] - w[2];
            return true;
        }
        else {
            return false;
        }
        return false;
    }
    struct TetNodesEdges {

    };
    template<int d1, int d2>
    static void computeIntersections(const vector<T3>& nodes1, const vector<T3>& nodes2, 
        const vector<array<int, d1>>& e1, const vector<array<int, d2>>& e2, 
        const BoxHierarchy<T, 3>& b1, const BoxHierarchy<T, 3>& b2, map<I4, T4>& intersections) {
        
        vector<vector<int>> intersectingBoxes; // intersecting boxes
        if (d1 == 2 && d2 == 3) {
            b2.intersect(b1, intersectingBoxes);
        }
        else {
            b1.intersect(b2, intersectingBoxes);
        }
        for (size_t i = 0; i < intersectingBoxes.size()-1; i++) {

            //Edge and Triangle Case
            //Using Cuda Intersections
            if (d1 == 2 && d2 == 3) {
                //2 point(= 1 Edge) and Geometry Point
                //2 * 3
                //Assign
                int Size = intersectingBoxes[i].size();
                if (Size == 0) continue;
                float* TetNodesForEdge = new  float[6 * Size];
                float* d_TetNodesForEdge;// = new float[6];
                float* TriNodesForTriangle = new float[9];
                float* d_TriNodesForTriangle;// = new float[9 * Size];
                float* w1 = new float[4 * Size];
                float* d_w1;// = new float[4 * Size];
                float* w2 = new float[4 * Size];
                float* d_w2;// = new float[4 * Size];
                bool* ba = new bool[Size];
                bool* d_ba;// = new bool[4 * Size];


                // 000 000 | 000 000 ||
                int idx = 0;
                for (int u = 0; u < 3; u++) {
                    TriNodesForTriangle[0 + u] = nodes2[e2[i][0]][u];
                    TriNodesForTriangle[3 + u] = nodes2[e2[i][1]][u];
                    TriNodesForTriangle[6 + u] = nodes2[e2[i][2]][u];
                }
                // 000 000 000 | 000 000 000 | 000 000 000 || ....
                for (auto j : intersectingBoxes[i]) {
                    for (int m = 0; m < 3; m++) {
                        TetNodesForEdge[idx * 6 + 0 + m] = nodes1[e1[j][0]][m];
                        TetNodesForEdge[idx * 6 + 3 + m] = nodes1[e1[j][1]][m];
                    }
                    idx++;
                }

                //Device Allocation
                CUDA_CHECK(cudaMalloc((void**)&d_TetNodesForEdge, sizeof(float) * 6 * Size));
                CUDA_CHECK(cudaMalloc((void**)&d_TriNodesForTriangle, sizeof(float) * 9));
                CUDA_CHECK(cudaMalloc((void**)&d_w1, sizeof(float) * Size * 4));
                CUDA_CHECK(cudaMalloc((void**)&d_w2, sizeof(float) * Size * 4));
                CUDA_CHECK(cudaMalloc((void**)&d_ba, sizeof(bool) * Size));

                //Copy Host To Device
                CUDA_CHECK(cudaMemcpy(d_TetNodesForEdge, TetNodesForEdge, sizeof(float) * Size * 6, cudaMemcpyHostToDevice));
                CUDA_CHECK(cudaMemcpy(d_TriNodesForTriangle, TriNodesForTriangle, sizeof(float) *  9, cudaMemcpyHostToDevice));
                CUDA_CHECK(cudaMemcpy(d_w1, w1, sizeof(float) * Size * 4, cudaMemcpyHostToDevice));
                CUDA_CHECK(cudaMemcpy(d_w2, w2, sizeof(float) * Size * 4, cudaMemcpyHostToDevice));
                CUDA_CHECK(cudaMemcpy(d_ba, ba, sizeof(bool) * Size, cudaMemcpyHostToDevice));

                
                //// Launch the Vector Add CUDA Kernel
                int ThreadsPerBlock = 256;
                int BlocksPerKernelGrid = (Size + ThreadsPerBlock - 1) / ThreadsPerBlock;

                CUDA_CHECK(cudaDeviceSynchronize());

                //Kernel Function Start
                computeIntersectionCUDA << < BlocksPerKernelGrid, ThreadsPerBlock >> >
                    (d_TetNodesForEdge, d_TriNodesForTriangle, d_w1, d_w2, d_ba, Size);

                

                // Copy Device To Host
                CUDA_CHECK(cudaMemcpy(w1, d_w1, Size * sizeof(float) * 4, cudaMemcpyDeviceToHost));
                CUDA_CHECK(cudaMemcpy(w2, d_w2, Size * sizeof(float) * 4, cudaMemcpyDeviceToHost));
                CUDA_CHECK(cudaMemcpy(ba, d_ba, Size * sizeof(bool), cudaMemcpyDeviceToHost));
                //Triangle to Edge
                //size = one triangle to edge

                CUDA_CHECK(cudaDeviceSynchronize());
                CUDA_CHECK(cudaGetLastError());
                
                int u = 0;
                for (auto j : intersectingBoxes[i]) {
                    if (ba[u] == true) {
                        array<int, 4> a;
                        array<T, 4> w;
                        cout << a[0] << " " << a[1] << endl;
                        a[0] = e1[j][0];
                        a[1] = e1[j][1];
                        a[2] = 0;
                        a[3] = 0;
                        w[0] = w1[u * 4 + 0];
                        w[1] = 1- w[0];
                        w[2] = 0;
                        w[3] = 0;
                        intersections[a] = w;
                    }
                    u++;
                }

                //Host allocation
                cudaFree(d_TetNodesForEdge);
                cudaFree(d_TriNodesForTriangle);
                cudaFree(d_w1);
                cudaFree(d_w2);
                cudaFree(d_ba);

                //Host Deallocation
                delete[] TetNodesForEdge;
                delete[] ba;
                delete[] TriNodesForTriangle;
                delete[] w1;
                delete[] w2;

                continue;
            }

            for (auto j : intersectingBoxes[i]) {
                auto tetNodes = elementNodes<T, 3, d1>(nodes1, e1[i]);
                auto triNodes = elementNodes<T, 3, d2>(nodes2, e2[j]);
                array<T, d1> w;
                if (computeIntersection(tetNodes, triNodes, w)) {
                    intersections[toI4<int, d1>(e1[i])] = toI4<T, d1>(w, 0);
                }
            }
        }
    }

    static Intersections computeIntersections(const TetMesh<T>& tetMesh, const TriMesh<T>& triMesh, TetBoundary2TetIds& tetBoundary2TetIds) {
        map<I4, T4> intersections;

        // build box hierarchies for tetMesh
        set<I3> tetMeshFaces;
        set<I2> tetMeshEdges;
        for (int i = 0; i < tetMesh.mesh_.size(); ++i) {
            auto tet = tetMesh.mesh_[i];
            sort(tet.begin(), tet.end());
            tetBoundary2TetIds[tet].push_back(i);
            auto faces = tetFaces(tet);
            for (auto& face : faces) {
                sort(face.begin(), face.end());
                tetBoundary2TetIds[toI4<int, 3>(face)].push_back(i);
                tetMeshFaces.insert(face);
            }
            auto edges = tetEdges(tet);
            for (auto& edge : edges) {
                sort(edge.begin(), edge.end());
                tetBoundary2TetIds[toI4<int, 2>(edge)].push_back(i);
                tetMeshEdges.insert(edge);
            }
        }
        vector<I1> tetMeshNodeVec;
        for (int i = 0; i < tetMesh.nodes_.size(); ++i) {
            tetMeshNodeVec.push_back(I1{ i });
        }
        vector<I3> tetMeshFaceVec(tetMeshFaces.begin(), tetMeshFaces.end());
        vector<I2> tetMeshEdgeVec(tetMeshEdges.begin(), tetMeshEdges.end());
        cout << "buliding tet mesh hierarchy" << endl;
        auto start_time = std::chrono::high_resolution_clock::now();
        auto tetMeshHierarchy = buildBoxHierarchy<T, 3, 4>(tetMesh.nodes_, tetMesh.mesh_);
        auto tetMeshFaceHierarchy = buildBoxHierarchy<T, 3, 3>(tetMesh.nodes_, tetMeshFaceVec);
        auto tetMeshEdgeHierarchy = buildBoxHierarchy<T, 3, 2>(tetMesh.nodes_, tetMeshEdgeVec);
        auto tetMeshNodeHierarchy = buildBoxHierarchy<T, 3, 1>(tetMesh.nodes_, tetMeshNodeVec);
        auto end_time = std::chrono::high_resolution_clock::now();

        std::chrono::duration<double, std::milli> elapsed_time = end_time - start_time;
        std::cout << "Building Tetrahedron Mesh time: " << elapsed_time.count() << " ms" << std::endl;
        // box hierarchy for triMesh
        set<I2> triMeshEdges;
        for (const auto& tri : triMesh.mesh_) {
            auto edges = faceEdges(tri);
            for (auto& edge : edges) {
                sort(edge.begin(), edge.end());
                triMeshEdges.insert(edge);
            }
        }
        vector<I2> triMeshEdgeVec(triMeshEdges.begin(), triMeshEdges.end());
        vector<I1> triMeshNodeVec;
        for (int i = 0; i < triMesh.nodes_.size(); ++i) {
            triMeshNodeVec.push_back(I1{ i });
        }
        auto triMeshHierarchy = buildBoxHierarchy<T, 3, 3>(triMesh.nodes_, triMesh.mesh_);
        auto triMeshEdgeHierarchy = buildBoxHierarchy<T, 3, 2>(triMesh.nodes_, triMeshEdgeVec);
        auto triMeshNodeHierarchy = buildBoxHierarchy<T, 3, 1>(triMesh.nodes_, triMeshNodeVec);

        // compute intersections
        // v-v
        // v-e
        // v-f
        // e-v
        // e-e
        // e-f
        computeIntersections<2, 3>(tetMesh.nodes_, triMesh.nodes_, tetMeshEdgeVec, triMesh.mesh_, tetMeshEdgeHierarchy, triMeshHierarchy, intersections);
        // f-v
        // f-e
        computeIntersections<3, 2>(tetMesh.nodes_, triMesh.nodes_, tetMeshFaceVec, triMeshEdgeVec, tetMeshFaceHierarchy, triMeshEdgeHierarchy, intersections);
        // t-v
        computeIntersections<4, 1>(tetMesh.nodes_, triMesh.nodes_, tetMesh.mesh_, triMeshNodeVec, tetMeshHierarchy, triMeshNodeHierarchy, intersections);

        return intersections;
    }

    static vector<CutElement> split(const TetMesh<T>& tetMesh, const Intersections& intersections, TetBoundary2TetIds& tetBoundary2TetIds, set<int>& cutTets) {
        cutTets.clear();
        for (const auto& t : tetBoundary2TetIds) {
            if (intersections.count(t.first)) {
                for (auto i : t.second) {
                    cutTets.insert(i);
                }
            }
        }
        cout << cutTets.size() << " tets cut\n";
        vector<CutElement> v;
        for (int i = 0; i < tetMesh.mesh_.size(); ++i) {
            if (cutTets.count(i)) {
                array<bool, 4> added;
                added.fill(false);
                auto tet = tetMesh.mesh_[i];
                for (int j = 0; j < 4; ++j) {
                    if (!added[j]) {
                        // find all connected pieces
                        CutElement ce(i, false);
                        stack<int> s;
                        s.push(j);
                        while (s.size()) {
                            auto top = s.top();
                            ce.subElements[top] = true;
                            added[top] = true;
                            s.pop();
                            // add all the connected pieces that are not added yet
                            for (int k = 0; k < 4; ++k) {
                                if (!added[k]) {
                                    if (!intersections.count(toI4<int, 2>(sorted(I2{ tet[top],tet[k] })))) {
                                        s.push(k);
                                    }
                                }
                            }
                        }
                        v.push_back(ce);
                    }
                }
            }
        }
        return v;
    }

    void static newTet(int parentId, const I4& tet, const TetMesh<T>& tetMesh, vector<T3>& newNodes, vector<I4>& newMesh, map<int, int>& nodeMapping, UnionFind& uf) {
        I4 newTet;
        //cout << "parent id " << parentId << endl;
        for (int i = 0; i < 4; ++i) { // for each node
            int newId = uf.find(tet[i]);
            //cout << tet[i] << ", " << newId << endl;
            const auto& it = nodeMapping.find(newId);
            if (it != nodeMapping.end()) {
                newTet[i] = it->second;
            }
            else {
                newTet[i] = newNodes.size();
                nodeMapping[newId] = newNodes.size();
                newNodes.push_back(tetMesh.nodes_[tetMesh.mesh_[parentId][i]]);
            }
        }

        newMesh.push_back(newTet);
    }

    static void merge(const vector<CutElement>& cutElements, const TetMesh<T>& tetMesh, vector<T3>& newNodes, vector<I4>& newMesh, const Intersections& intersections) {
        newNodes.clear();
        newMesh.clear();
        UnionFind uf(tetMesh.nodes_.size() + 4 * cutElements.size());
        map<I5, int> faceNode2NewNode; // key = {face,materialNode,node}
        set<int> cutTets;
        int total = tetMesh.nodes_.size();
        for (const auto& ce : cutElements) { // need to do face-face merging even for tets that are touched by the cut but not split, so that if a neighbor splits they are all connected to it.
            cutTets.insert(ce.parentElementIndex);
            const auto& tet = tetMesh.mesh_[ce.parentElementIndex];
            for (int i = 0; i < 4; ++i) { // for each face
                auto face = tetFace(tet, i);
                sort(face.begin(), face.end());
                I5 key;
                for (int j = 0; j < 3; ++j) {
                    key[j] = face[j];
                }
                for (int j = 0; j < 3; ++j) { // for each node check for material
                    int fij = FaceIndexes[i][j];
                    if (ce.subElements[fij]) {
                        key[3] = tet[fij];
                        uf.merge(total + fij, key[3]);
                        for (int k = 0; k < 3; ++k) { // for each node, merge
                            int fik = FaceIndexes[i][k];
                            key[4] = tet[fik];
                            int newId = total + fik;
                            //print<int,5>(key);
                            const auto& it = faceNode2NewNode.find(key);
                            if (it != faceNode2NewNode.end()) {
                                //cout << "merging " << it->second << ", " << newId << endl;
                                uf.merge(it->second, newId);
                            }
                            else {
                                faceNode2NewNode[key] = newId;
                            }
                        }
                    }
                }
            }
            total += 4;
        }
        total = tetMesh.nodes_.size();
        map<int, int> nodeMapping;
        for (const auto& ce : cutElements) {
            newTet(ce.parentElementIndex, I4{ total, total + 1, total + 2, total + 3 }, tetMesh, newNodes, newMesh, nodeMapping, uf);
            total += 4;
        }
        for (int i = 0; i < tetMesh.mesh_.size(); ++i) {
            if (!cutTets.count(i)) {
                newTet(i, tetMesh.mesh_[i], tetMesh, newNodes, newMesh, nodeMapping, uf);
            }
        }

        //        cout << "merged mesh \n";
        //        print<T,3>(newNodes);
        //        print<int,4>(newMesh);
    }

    static TetMesh<T> subdivide(const vector<CutElement>& cutElements, const TetMesh<T>& tetMesh, vector<T3>& newNodes, vector<I4>& newMesh, Intersections& intersections) {
        // add a new node inside the tet, connect with cuts on each face to subdivide the tet
        auto start_time = std::chrono::high_resolution_clock::now();

        map<I4, int> newNodeMapping;
        for (int i = 0; i < cutElements.size(); ++i) {
            const auto& ce = cutElements[i];
            const auto& originalTet = tetMesh.mesh_[ce.parentElementIndex];
            const auto sortedOriginalTet = sorted(originalTet);
            const auto& tet = newMesh[i];

            // get all edge cuts and add them as new nodes
            const auto originalEdges = tetEdges(originalTet);
            const auto edges = tetEdges(tet);
            int cutEdges = 0;
            T4 averageEdgeWeight{ 0,0,0,0 };
            map<int, T> originalNodeId2Weight;
            for (int k = 0; k < originalEdges.size(); ++k) {
                auto sortedOriginalEdge = toI4<int, 2>(sorted(originalEdges[k]));
                auto sortedEdge = toI4<int, 2>(sorted(edges[k]));
                const auto& it = intersections.find(sortedOriginalEdge);
                if (it != intersections.end()) {
                    ++cutEdges;
                    for (int j = 0; j < 2; ++j) {
                        originalNodeId2Weight[sortedOriginalEdge[j]] += it->second[j];
                    }
                    const auto& idIt = newNodeMapping.find(sortedEdge);
                    if (idIt == newNodeMapping.end()) {
                        newNodeMapping[sortedEdge] = newNodes.size();
                        newNodes.push_back(elementCenter<T, 3>(tetMesh.nodes_, sortedOriginalEdge, it->second));
                        //                        cout << "edge node ";
                        //                        print<T,3>(elementCenter<T,3>(tetMesh.nodes_, sortedOriginalEdge, it->second));
                    }
                }
            }
            for (int j = 0; j < 4; ++j) {
                averageEdgeWeight[j] = originalNodeId2Weight[sortedOriginalTet[j]];
            }
            //cout << "cutEdges " << cutEdges << endl;

            // face cuts
            const auto originalFaces = tetFaces(originalTet);
            const auto faces = tetFaces(tet);
            for (int k = 0; k < faces.size(); ++k) {
                auto sortedOriginalFace = toI4<int, 3>(sorted(originalFaces[k]));
                auto sortedFace = toI4<int, 3>(sorted(faces[k]));
                const auto& it = intersections.find(sortedOriginalFace);
                if (it != intersections.end()) { // face center already computed
                    const auto& idIt = newNodeMapping.find(sortedFace);
                    if (idIt == newNodeMapping.end()) {
                        newNodeMapping[sortedFace] = newNodes.size();
                        newNodes.push_back(elementCenter<T, 3>(tetMesh.nodes_, sortedOriginalFace, it->second));
                    }
                    //                    cout << "face center ";
                    //                    print<T,3>(elementCenter<T,3>(tetMesh.nodes_, sortedOriginalFace, it->second));
                }
                else { // use average of edge cuts if not
                    int numEdges = 0;
                    T4 faceWeights{ 0,0,0,0 };
                    map<int, T> node2weight;
                    for (int j = 0; j < 3; ++j) {
                        auto sortedOriginalEdge = toI4<int, 2>(sorted(array<int, 2>{sortedOriginalFace[j], sortedOriginalFace[(j + 1) % 3]}));
                        const auto& edgeIt = intersections.find(sortedOriginalEdge);
                        if (edgeIt != intersections.end()) {
                            ++numEdges;
                            for (int e = 0; e < 2; ++e) {
                                node2weight[sortedOriginalEdge[e]] += edgeIt->second[e];
                            }
                        }
                    }
                    if (numEdges > 1) { // otherwise don't add new face center
                        newNodeMapping[sortedFace] = newNodes.size();
                        for (int j = 0; j < 3; ++j) {
                            faceWeights[j] = node2weight[sortedOriginalFace[j]] / numEdges;
                        }
                        //                        cout << "face weight ";
                        //                        print<T,4>(faceWeights);
                        //                        cout << "face center ";
                        //                        print<T,3>(elementCenter<T,3>(tetMesh.nodes_, sortedOriginalFace, faceWeights));
                        newNodes.push_back(elementCenter<T, 3>(tetMesh.nodes_, sortedOriginalFace, faceWeights));
                        intersections[sortedOriginalFace] = faceWeights;
                    }
                }
            }

            // tet center
            int tetCenterId = newNodes.size();
            const auto& tetCenterIt = intersections.find(sortedOriginalTet);
            if (tetCenterIt != intersections.end()) {
                newNodes.push_back(elementCenter<T, 3>(tetMesh.nodes_, sortedOriginalTet, tetCenterIt->second));
                //                cout << "tet center ";
                //                print<T,3>(elementCenter<T,3>(tetMesh.nodes_, sortedOriginalTet, tetCenterIt->second));
            }
            else { // if doesn't exist, use average of edge cuts or the center
                if (ce.numPieces() == 4) {
                    averageEdgeWeight.fill(0.25);
                }
                else {
                    averageEdgeWeight = divide<T, 4>(averageEdgeWeight, cutEdges);
                    //                    print<T,4>(averageEdgeWeight);
                }
                newNodes.push_back(elementCenter<T, 3>(tetMesh.nodes_, sortedOriginalTet, averageEdgeWeight));
                //                cout << "tet center ";
                //                print<T,3>(elementCenter<T,3>(tetMesh.nodes_, sortedOriginalTet, averageEdgeWeight));
                intersections[sortedOriginalTet] = averageEdgeWeight;
            }

            // add elements that are created by the new nodes added above
            vector<I4> newTets;
            for (int f = 0; f < faces.size(); ++f) {
                const auto& face = faces[f];
                const auto sortedFace = toI4<int, 3>(sorted(face));
                const auto& newFaceCenterIt = newNodeMapping.find(sortedFace);
                if (newFaceCenterIt != newNodeMapping.end()) {
                    for (int j = 0; j < 3; ++j) {
                        auto sortedEdge = toI4<int, 2>(sorted(array<int, 2>{face[j], face[(j + 1) % 3]}));
                        const auto& newEdgeCenterIt = newNodeMapping.find(sortedEdge);
                        if (newEdgeCenterIt != newNodeMapping.end()) {
                            if (ce.subElements[FaceIndexes[f][j]]) {
                                newTets.push_back(I4{ tetCenterId, newFaceCenterIt->second, face[j], newEdgeCenterIt->second });
                            }
                            if (ce.subElements[FaceIndexes[f][(j + 1) % 3]]) {
                                newTets.push_back(I4{ tetCenterId, newFaceCenterIt->second, newEdgeCenterIt->second, face[(j + 1) % 3] });
                            }
                        }
                        else if (ce.subElements[FaceIndexes[f][j]]) {
                            newTets.push_back(I4{ tetCenterId, newFaceCenterIt->second, face[j], face[(j + 1) % 3] });
                        }
                    }
                }
                else if (ce.subElements[FaceIndexes[f][0]]) { // no face intersection, might have 0 or 1 edge cut
                    bool isSplit = false;
                    for (int j = 0; j < 3; ++j) {
                        auto sortedEdge = toI4<int, 2>(sorted(array<int, 2>{face[j], face[(j + 1) % 3]}));
                        const auto& newEdgeCenterIt = newNodeMapping.find(sortedEdge);
                        if (newEdgeCenterIt != newNodeMapping.end()) {
                            newTets.push_back(I4{ tetCenterId, face[(j + 2) % 3], face[j], newEdgeCenterIt->second });
                            newTets.push_back(I4{ tetCenterId, face[(j + 2) % 3], newEdgeCenterIt->second, face[(j + 1) % 3] });
                            isSplit = true;
                            break;
                        }
                    }
                    if (!isSplit) {
                        newTets.push_back(I4{ tetCenterId, face[0], face[1], face[2] });
                    }
                }
            }
            newMesh[i] = newTets[0];
            for (int j = 1; j < newTets.size(); ++j) {
                newMesh.push_back(newTets[j]);
            }
        }


        auto end_time = std::chrono::high_resolution_clock::now();

        std::chrono::duration<double, std::milli> elapsed_time = end_time - start_time;
        std::cout << "Subdivide time: " << elapsed_time.count() << " ms" << std::endl;

        return TetMesh<T>(move(newNodes), move(newMesh));
    }

public:
    static TetMesh<T> run(const TetMesh<T>& tetMesh, const TriMesh<T>& triMesh) {
        TetBoundary2TetIds tetBoundary2TetIds;


        auto start_time = std::chrono::high_resolution_clock::now();
        auto intersections = computeIntersections(tetMesh, triMesh, tetBoundary2TetIds);
        auto end_time = std::chrono::high_resolution_clock::now();

        std::chrono::duration<double, std::milli> elapsed_time = end_time - start_time;
        std::cout << "Intersection time: " << elapsed_time.count() << " ms" << std::endl;
        cout << "finished computing " << intersections.size() << " intersections\n";
        //        for (auto& a: intersections) {
        //            print<int,4>(a.first);
        //            print<T,4>(a.second);
        //        }
        set<int> cutTets;
        start_time = std::chrono::high_resolution_clock::now();
        vector<CutElement> cutElements = split(tetMesh, intersections, tetBoundary2TetIds, cutTets);
        end_time = std::chrono::high_resolution_clock::now();

        elapsed_time = end_time - start_time;
        std::cout << "Split time: " << elapsed_time.count() << " ms" << std::endl;
        //        for (auto& ce: cutElements) {
        //            cout << ce.parentElementIndex << endl;
        //            print<bool,4>(ce.subElements);
        //        }
        vector<T3> newNodes;
        vector<I4> newMesh;
        start_time = std::chrono::high_resolution_clock::now();
        merge(cutElements, tetMesh, newNodes, newMesh, intersections);
        end_time = std::chrono::high_resolution_clock::now();

        elapsed_time = end_time - start_time;
        std::cout << "Merging time: " << elapsed_time.count() << " ms" << std::endl;
        cout << "finished split-merge\n";
        return subdivide(cutElements, tetMesh, newNodes, newMesh, intersections);
    }
};

#endif /* Cutting_h */
