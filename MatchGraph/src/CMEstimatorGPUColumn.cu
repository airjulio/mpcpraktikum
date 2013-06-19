/*
 * CMEstimatorGPUColumn.cpp
 *
 * Generates a list of indices containing the i, j index of approx. the 
 * k-best confidence measure values. 
 * The List of indices is generated column wise after Cula solved the
 * linear equation system. This class uses the already stored memory
 * of the equation solver and extracts the k best values of the specific
 * column.
 * Specifically created to be used inside of the GPUSparse MatrixHandler.
 *
 *  Created on: 19.06.2013
 *      Author: Fabian
 */

#include "CMEstimatorGPUColumn.h"
#include <stdlib.h>     /* srand, rand */
#include <time.h>       /* time */
#include <vector>
#include <algorithm> /* std::find */
#include <stdio.h> /* printf */
#include <float.h> /* FLT_MAX */
#include <thrust/sort.h>
#include <thrust/device_ptr.h>
#include <thrust/device_vector.h>
#include <thrust/copy.h>

#define CUDA_CHECK_ERROR() {							\
    cudaError_t err = cudaGetLastError();					\
    if (cudaSuccess != err) {						\
        fprintf (stderr, "Cuda error in file '%s' in line %i : %s.",	\
                __FILE__, __LINE__, cudaGetErrorString(err) );	\
        exit(EXIT_FAILURE);						\
    }									\
}

const int THREADS = 128;

//Initialize indices
static __global__ void initKernel(long* gpuIndices, float* x, const float* b, const int dim, const int columnIdx)
{
	int idx = blockIdx.x * blockDim.x + threadIdx.x;

	if (idx < dim)
	{
		if (columnIdx == idx || 0 != b[idx]) //diagonal element or known element //|| 0 != b[idx]
		{
			gpuIndices[idx] = -1;
			//assign very low value to elements already known
			x[idx] = -FLT_MAX;
		}
		else
		{
			//assign index value based on the overall matrix dimension (continuous idx)
			gpuIndices[idx] = columnIdx + idx * dim;
		}
	}
}

CMEstimatorGPUColumn::CMEstimatorGPUColumn() {
	// TODO Auto-generated constructor stub

}

Indices* CMEstimatorGPUColumn::getInitializationIndices(MatrixHandler* T, int initNr)
{
	Indices* initIndices = new Indices[initNr];
	std::vector<int> chosenOnes; //max size will be initNr
	int dim = T->getDimension();

	//generate random index
	srand (time(NULL));
	const int MAX_ITERATIONS = dim*(dim/2) + dim; //#elements in upper diagonal matrix + dim

	//generate initialization indices
	for(int i = 0; i < initNr; i++)
	{
		int rIdx = -1;
		int x, y;

		int c = 0;
		do {
			//get random number
			rIdx = rand() % (dim*dim);

			//compute matrix indices with given continuous index sequence
			x = rIdx/dim;
			y = rIdx%dim;
			c++;
		} while ( ((rIdx < 1+(rIdx/dim)+(rIdx/dim)*dim)
					|| (T->getVal(x,y) != 0)
					|| (std::find(chosenOnes.begin(), chosenOnes.end(), rIdx) != chosenOnes.end()))
				&& (c <= MAX_ITERATIONS) );
		/* :TRICKY:
		 * As long as the random number is not within the upper diagonal matrix w/o diagonal elements
		 * or T(idx) != 0 generate or already in the list of Indices, a new random index but maximal
		 * MAX_ITERAtION times.
		 */

		if (c <= MAX_ITERATIONS) //otherwise initIndices contains -1 per struct definition
		{
			chosenOnes.push_back(rIdx);
			initIndices[i].i = x;
			initIndices[i].j = y;
		}
	}

	return initIndices;
}

//A*x_i = b_i
Indices* CMEstimatorGPUColumn::getKBestConfMeasures(float* xColumnDevice, float* bColumnDevice, int columnIdx, int dim, int kBest)
{
	printf("Determine kBest confidence measures column-wise on GPU:\n");
	//storage for the kBest indices
	Indices* kBestIndices = new Indices[kBest];

	//Allocate index array on GPU
	long* gpuIndices;
	cudaMalloc((void**) &gpuIndices, dim * sizeof(long));
	CUDA_CHECK_ERROR();
	//wrap raw pointer with device pointer
	thrust::device_ptr<long> dp_gpuIndices = thrust::device_pointer_cast(gpuIndices);
	CUDA_CHECK_ERROR();

	//Kernel settings for index array
	int numBlocks = (dim + THREADS - 1) / THREADS;
	dim3 threadBlock(THREADS);
	dim3 blockGrid(numBlocks);

	//Init indices array such that indices = [-1,1,2,-1,...,dim-1], whereas the respective
	//diagonal element is -1 as well as elements that are already compared.
	//For already known elements (i.e. bColumnDevice[i] != 0), xColumnDevice[i] will be
	//assigned a very low value to prevent them from getting chosen later.
	initKernel<<<blockGrid, threadBlock>>>(gpuIndices, xColumnDevice, bColumnDevice, dim, columnIdx);
	CUDA_CHECK_ERROR();

	//wrap column device pointer
	thrust::device_ptr<float> dp_xColumn = thrust::device_pointer_cast(xColumnDevice);
	CUDA_CHECK_ERROR();

	//sort x column and index array respectively
	//already known values will be the last ones due to initialization
	thrust::sort_by_key(dp_xColumn, dp_xColumn + dim, dp_gpuIndices, thrust::greater<float>());
	CUDA_CHECK_ERROR();

	//download device memory
	long* indices = new long[kBest]; //at most kBest indices are needed
	//the first kBest indices are also the best conf. measure values after sorting
	thrust::copy(dp_gpuIndices, dp_gpuIndices + kBest, indices);
	CUDA_CHECK_ERROR();

	//free memory
	cudaFree(gpuIndices);
	cudaFree(xColumnDevice);
	cudaFree(bColumnDevice);

	//build indices list structure
	for(int i = 0; i<kBest; i++)
	{
		long idx = indices[i];
		if (indices[i] > -1)
		{
			kBestIndices[i].i = idx/dim;
			kBestIndices[i].j = idx%dim;
		}
		else
		{
			//after the first index with -1 all following
			//will contain -1.
			break;
		}
		//if some of the indices contained -1, the remaining
		//kBestIndices will contain also -1 as i,j index per
		//struct definition.
	}

	//print
	if (true)
	{
		printf("%i best entries:\n", kBest);
		for(int i = 0; i < kBest; i++)
		{
			if (kBestIndices[i].i != -1)
			{
				//value can't be printed because it is not saved in the Indices-list
				printf("%i: at [%i,%i]\n",i,kBestIndices[i].i,kBestIndices[i].j);
			}
		}
	}

	return kBestIndices;
}

//not needed in this CMEstimator implementation.
Indices* CMEstimatorGPUColumn::getKBestConfMeasures(MatrixHandler* T, float* F, int kBest)
{
	return 0;
}
