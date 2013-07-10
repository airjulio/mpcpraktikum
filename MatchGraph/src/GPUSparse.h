/*
 * GPUSparse.h
 *
 *  Created on: Jun 12, 2013
 *      Author: gufler
 */

#ifndef GPUSPARSE_H_
#define GPUSPARSE_H_

#include "MatrixHandler.h"
#include <set>
#include <map>
#include <string>


typedef std::map<int,std::set<int> > myElemMap;

class GPUSparse : public MatrixHandler{
private:
	const unsigned int dim;
	const float lambda;
	unsigned int num_similar; //# of similarities that is (number of 1s / 2)

	int* _gpuDiagPos; //position of diagonal elements within row
	int* _gpuDegrees;
	int* _gpuRowPtr;
	int* _gpuColIdx;
	
	myElemMap dissimilarMap;

	void addNewToRow(const int row, const int j);
	void addDissimilarToColumn(const int column, const int row);
	void incrementDegree(const int row);

public:
	GPUSparse();
	GPUSparse(unsigned int _dim, float _lambda);
	void updateSparseStatus(int* _idx1, int* _idx2, int* _res, int _k);
	void handleDissimilar(int* idxData, int num);

	~GPUSparse();
	void set(int i, int j, bool val);
	unsigned int getDimension();
	float* getConfMatrixF();
	char* getMatrAsArray();
	char getVal(int i, int j);
	int getSimilarities();
	void print();
	void writeGML(char* filename, bool similar, bool dissimilar, bool potential);

	/* SPARSE-specific */
	float* getValueArr(bool gpuPointer) const;
	double* getValueArrDouble(bool gpuPointer) const;

	float* getColumn(int i) const;
	double* getColumnDouble(int i) const;

	int* getColIdx() const;
	int* getColIdxDevice() const;
	int* getRowPtr() const;
	int* getRowPtrDevice() const;
	unsigned int getNNZ() const;
	void setRandom(int num);

	static int* prefixSumGPU(int* result, const int* array, const int dimension);
	static void printGpuArray(int* devPtr, const int size, const std::string message);
	static void printGpuArrayF(float* devPtr, const int size, const std::string message);
	static void printGpuArrayD(double * devPtr, const int size, std::string message);
	static int* downloadGPUArrayInt(int* devPtr, const int size);
	static float* downloadGPUArrayFloat(float* devPtr, const int size);
	static double* downloadGPUArrayDouble(double* devPtr, const int size);
};

#endif /* GPUSPARSE_H_ */

