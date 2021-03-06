/*
 * InitializerGPU.cu
 *
 * This class executes the initializing phase of the match graph algorithm.
 * This is done by random image comparisons on device for the GPU-implementation.
 * At this point, no duplicated entries or symmetric entries should be handed
 * over to the image comparison.
 *
 *  Created on: Jun 29, 2013
 *      Author: Fabian
 */

#include "InitializerGPU.h"
#include <iostream>
#include <stdio.h>
#include <time.h>
#include <curand.h>
#include <curand_kernel.h>
#include <thrust/sort.h>
#include <thrust/device_ptr.h>
#include <thrust/device_vector.h>
#include "Tester.h"
#include "GPUSparse.h"

#define CUDA_CHECK_ERROR() {							\
    cudaError_t err = cudaGetLastError();					\
    if (cudaSuccess != err) {						\
        fprintf (stderr, "Cuda error in file '%s' in line %i : %s.",	\
                __FILE__, __LINE__, cudaGetErrorString(err) );	\
        exit(EXIT_FAILURE);						\
    }									\
}

const int THREADS = 128;

/*
 * Initialize index arrays with it's index.
 */
static __global__ void initIndexArrays(int* d_idx1, int* d_idx2, int* d_res, int dim, int initArraySize)
{
	int idx = blockIdx.x * blockDim.x + threadIdx.x;

	if (idx < dim)
	{
		d_idx1[idx] = idx;
		d_idx2[idx] = idx;
		if (idx < initArraySize) d_res[idx] = 0;
	}
}

/*
 * Simple kernel to shuffle an array on GPU (prevents memcpy). To be called only with ONE thread!
 * Since the initialization phase is only executed once, runtime is no crucial here.
 */
static __global__ void shuffleArrayKernel(int* array, int dim, int initArraySize, curandState* globalStates, unsigned long seed)
{
	int idx = threadIdx.x;
	curand_init(seed, idx, 0, &globalStates[idx]);
	curandState localState = globalStates[idx];
	for(int i = 0; i < initArraySize; i++) //just for the needed index array size
	{
		int shift = curand_uniform(&localState) * dim;
		int shift_idx = (i+shift)%dim;
		//shuffle
		int tmp = array[i];
		array[i] = array[shift_idx];
		array[shift_idx] = tmp;
	}
}

/*
 * Kernel to swap upper diagonal matrix elements, to get more image-pairs, since the upper
 * diagonal matrix is masked out.
 */
static __global__ void swapUpperDiagonal(int* idx1, int* idx2, int initArraySize)
{
	int idx = blockIdx.x * blockDim.x + threadIdx.x;

	if (idx < initArraySize)
	{
		//swap upper diagonal elements
		if (idx1[idx] <= idx2[idx])
		{
			int tmp = idx1[idx];
			idx1[idx] = idx2[idx];
			idx2[idx] = tmp;
		}
	}
}

/*
 * Check for duplicates caused by prior swapping of upper diagonal matrix elements.
 */
static __global__ void checkForDuplicates(int* idx1, int* idx2, int initArraySize, int dim)
{
	int idx = blockIdx.x * blockDim.x + threadIdx.x;

	if (idx < (initArraySize-1))
	{
		if (idx1[idx] == idx2[idx]) //diagonal element (can not occur twice)
		{
			//mask out
			idx1[idx] = dim+1;
			idx2[idx] = dim+1;
		}
		else
		{
			int compareIdx = idx2[idx];
			for(int j = idx+1; j < initArraySize && idx1[idx] == idx1[j]; j++)
			{
				if (compareIdx == idx2[j])
				{
					//mask out
					idx1[idx] = dim+1;
					idx2[idx] = dim+1;
					break; //only one duplicate possible
				}
			}
		}
	}
}

/*
 * Constructor
 */
InitializerGPU::InitializerGPU()
{
}

/*
 * Destructor
 */
InitializerGPU::~InitializerGPU()
{
}

/*
 * Initializes the T-Matrix with random image comparisons.
 */
void InitializerGPU::doInitializationPhase(MatrixHandler* T, ImageHandler* iHandler, ImageComparator* comparator, int initArraySize)
{
	bool debugPrint = false;

	unsigned int dim = T->getDimension();

	if (initArraySize > dim)
	{
		printf("[INITIALIZER]: initialization array size must be smaller than dimension!\n");
		exit(EXIT_FAILURE);
	}

	//allocate initialization arrays
	int* d_initIdx1;
	int* d_initIdx2;
	int* d_initRes;
	cudaMalloc(&d_initIdx1, dim*sizeof(int));
	cudaMalloc(&d_initIdx2, dim*sizeof(int));
	cudaMalloc(&d_initRes, initArraySize*sizeof(int));

	//initialize arrays
	int numBlocks = (dim + THREADS - 1) / THREADS;
	initIndexArrays<<<numBlocks, THREADS>>>(d_initIdx1, d_initIdx2, d_initRes, dim, initArraySize);
	CUDA_CHECK_ERROR()

	//allocate memory for debug printing
	int* testResult1 = (int*) malloc(dim*sizeof(int));
	int* testResult2 = (int*) malloc(dim*sizeof(int));
	int* testResult3 = (int*) malloc(initArraySize*sizeof(int));

	if (debugPrint)
	{
		printf("Init-Index-Array initialization\n");
		cudaMemcpy(testResult1, d_initIdx1, dim*sizeof(int), cudaMemcpyDeviceToHost);
		cudaMemcpy(testResult2, d_initIdx2, dim*sizeof(int), cudaMemcpyDeviceToHost);
		cudaMemcpy(testResult3, d_initRes, initArraySize*sizeof(int), cudaMemcpyDeviceToHost);
		Tester::printArray(testResult1, dim);
		Tester::printArray(testResult2, dim);
		Tester::printArray(testResult3, initArraySize);
	}

	//initialize cuRAND
	curandState* states;
	cudaMalloc(&states, sizeof(curandState));

	//shuffle Arrays
	shuffleArrayKernel<<<1, 1>>>(d_initIdx1, dim, initArraySize, states, time(NULL));
	CUDA_CHECK_ERROR()
	shuffleArrayKernel<<<1, 1>>>(d_initIdx2, dim, initArraySize, states, 3*time(NULL)); //ensure different seeds
	CUDA_CHECK_ERROR()

	if (debugPrint)
	{
		printf("shuffled\n");
		cudaMemcpy(testResult1, d_initIdx1, initArraySize*sizeof(int), cudaMemcpyDeviceToHost);
		cudaMemcpy(testResult2, d_initIdx2, initArraySize*sizeof(int), cudaMemcpyDeviceToHost);
		Tester::printArray(testResult1, initArraySize);
		Tester::printArray(testResult2, initArraySize);
	}

	//mask each entry on the upper diagonal matrix (prevents symmetrical image comparisons)
	//swap entries inside upper diagonal-matrix (map to lower diagonal matrix)
	numBlocks = (initArraySize + THREADS - 1) / THREADS;
	swapUpperDiagonal<<<numBlocks, THREADS>>>(d_initIdx1, d_initIdx2, initArraySize);
	CUDA_CHECK_ERROR()

	if (debugPrint)
	{
		printf("swapped\n");
		cudaMemcpy(testResult1, d_initIdx1, initArraySize*sizeof(int), cudaMemcpyDeviceToHost);
		cudaMemcpy(testResult2, d_initIdx2, initArraySize*sizeof(int), cudaMemcpyDeviceToHost);
		Tester::printArray(testResult1, initArraySize);
		Tester::printArray(testResult2, initArraySize);
	}

	//sort index array1 ascending and index array2 respectively
	//wrap device pointers
	thrust::device_ptr<int> dp_initIdx1 = thrust::device_pointer_cast(d_initIdx1);
	thrust::device_ptr<int> dp_initIdx2 = thrust::device_pointer_cast(d_initIdx2);
	CUDA_CHECK_ERROR();
	thrust::sort_by_key(dp_initIdx1, dp_initIdx1 + initArraySize, dp_initIdx2); //ascending
	CUDA_CHECK_ERROR();

	if (debugPrint)
	{
		printf("sorted\n");
		cudaMemcpy(testResult1, d_initIdx1, initArraySize*sizeof(int), cudaMemcpyDeviceToHost);
		cudaMemcpy(testResult2, d_initIdx2, initArraySize*sizeof(int), cudaMemcpyDeviceToHost);
		Tester::printArray(testResult1, initArraySize);
		Tester::printArray(testResult2, initArraySize);
	}

	//check for duplicated entries and mask them out
	checkForDuplicates<<<numBlocks, THREADS>>>(d_initIdx1, d_initIdx2, initArraySize, dim);
	CUDA_CHECK_ERROR();

	if (debugPrint)
	{
		printf("masked duplicates\n");
		cudaMemcpy(testResult1, d_initIdx1, initArraySize*sizeof(int), cudaMemcpyDeviceToHost);
		cudaMemcpy(testResult2, d_initIdx2, initArraySize*sizeof(int), cudaMemcpyDeviceToHost);
		Tester::printArray(testResult1, initArraySize);
		Tester::printArray(testResult2, initArraySize);
	}

	//sort again
	thrust::sort_by_key(dp_initIdx1, dp_initIdx1 + initArraySize, dp_initIdx2); //ascending
	CUDA_CHECK_ERROR();

	if (debugPrint)
	{
		printf("sorted\n");
		cudaMemcpy(testResult1, d_initIdx1, initArraySize*sizeof(int), cudaMemcpyDeviceToHost);
		cudaMemcpy(testResult2, d_initIdx2, initArraySize*sizeof(int), cudaMemcpyDeviceToHost);
		Tester::printArray(testResult1, initArraySize);
		Tester::printArray(testResult2, initArraySize);
	}

	//compare images
	comparator->doComparison(iHandler, T, d_initIdx1, d_initIdx2, d_initRes, initArraySize);

	if (debugPrint)
	{
		printf("result after comparison -> this will be given to GPUSparse to update the Marix\n");
		cudaMemcpy(testResult1, d_initIdx1, initArraySize*sizeof(int), cudaMemcpyDeviceToHost);
		cudaMemcpy(testResult2, d_initIdx2, initArraySize*sizeof(int), cudaMemcpyDeviceToHost);
		cudaMemcpy(testResult3, d_initRes, initArraySize*sizeof(int), cudaMemcpyDeviceToHost);
		Tester::printArray(testResult1, initArraySize);
		Tester::printArray(testResult2, initArraySize);
		Tester::printArray(testResult3, initArraySize);
	}

	//initialize T Matrix with compared images
	//invoked only on sparse matrixhandler
	GPUSparse* T_sparse = dynamic_cast<GPUSparse*> (T);
	T_sparse->updateSparseStatus(d_initIdx1, d_initIdx2, d_initRes, initArraySize);

	//cleanup after completed initialization
	cudaFree(d_initIdx1);
	cudaFree(d_initIdx2);
	cudaFree(d_initRes);

	free(testResult1);
	free(testResult2);
	free(testResult3);
}


