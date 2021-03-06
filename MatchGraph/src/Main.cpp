/*
 * Main.cpp
 *
 *	Start class for the match graph algorithm.
 *
 *  Created on: May 29, 2013
 *      Author: Fabian, Armin, Julio
 */

#include "GPUSparse.h"
#include "CPUImpl.h"
#include "GPUComparator.h"
#include "CPUComparator.h"
#include "CMEstimatorCPU.h"
#include "CMEstimatorGPUSparseOPT.h"
#include "CMEstimatorGPUSparseMax.h"
#include "Initializer.h"
#include "InitializerGPU.h"
#include "InitializerCPU.h"
#include "ImageHandler.h"
#include "Tester.h"
#include <iostream>
#include <stdlib.h>
#include <stdio.h>
#include <helper_cuda.h>
#include <string.h>

#define GPU_VERSION 1 //switch between CPU and GPU implementation

inline __int64_t continuousTimeNs()
{
	timespec now;
	clock_gettime(CLOCK_REALTIME, &now);

	__int64_t result = (__int64_t ) now.tv_sec * 1000000000
			+ (__int64_t ) now.tv_nsec;

	return result;
}

int main(int argc, char** argv)
{
	//seed once for the algorithm
	srand((unsigned int)time(NULL));

	////////////////////////
	//Read input arguments//
	////////////////////////
	char* usageBuff = new char[1024];
	strcpy(usageBuff, "Usage: <path> <ext> <iter> [<k>] [<lambda>] [<logDir>] [<randStep>] [<est>]\n"
			"       Starts algorithm for <iter> iterations on images in directory <path> with specified file\n"
			"       extension <ext>. Parameter <k> [1,#numImages] defines how many images shall be compared each\n"
			"       iteration (k-best). Model parameter lambda [0,1] (default = 1) influences the computation of\n"
			"       confidence measures (see algorithm details). <logDir> set path for the logfile (default =\n"
			"	'log/matchGraph.log'. Each <randStep>-th iteration, the algorithm uses random image-pairs\n"
			"	to be compaired. <est> chooses estimator (0 = random columns estimator, 1 = global k-best\n"
			"	estimator, default = 0)."
			"\nOR\n"
			"       -r <dim> <k> <iter> [<lambda>] [<est>]\tRandom mode which does comparison not on real image data\n"
			"       but just in a random fashion for dimension <dim> and <iter> iterations and given\n"
			"       parameter <k> [1,dim] and model parameter lambda [0,1] (default = 1). <est> chooses estimagor\n"
			"	(see above). No image comparison is done is this mode.\n");

	if (argc < 4)
	{
		printf("%s", usageBuff);
		exit(EXIT_FAILURE);
	}

	int acount = 1;

	ImageHandler* iHandler; //handler object for image files
	bool randomMode = false; //no real data is used
	const char* dir = argv[acount++];

	int _dim = -1;
	int _iter = 1;
	int _k = 1;
	float _lambda = 1.0;
	const char* logFilePath = "log/matchGraph.log";
	int _randStep = 0;
	int _est = 0;

	if (strcmp(dir, "-r") == 0)
	{
		if (argc < 5)
		{
			printf("%s", usageBuff);
			exit(EXIT_FAILURE);
		}

		randomMode = true;

		_dim = atoi(argv[acount++]);
		if (_dim < 2)
		{
			printf("ERROR: dimension must at least be 2\n");
			exit(EXIT_FAILURE);
		}

		_k = atoi(argv[acount++]);
		if (_k > _dim || _k < 1)
		{
			printf("ERROR: <k> must be >= 1 and <= dimension\n");
		}

		_iter = atoi(argv[acount++]);

		iHandler = new ImageHandler("", "");
		iHandler->fillWithEmptyImages(_dim);

		if (argc > 5)
		{
			_lambda = atof(argv[acount++]);
		}

		if (argc > 6)
		{
			_est = atoi(argv[acount++]);
		}
	}
	else
	{
		const char* imgExtension = argv[acount++];
		iHandler = new ImageHandler(dir, imgExtension);
		if (iHandler->getTotalNr() < 2)
		{
			printf("ERROR: no images in given path or invalid path name or invalid file extension\n");
			exit(EXIT_FAILURE);
		}

		_iter = atoi(argv[acount++]);

		if (argc > 4) //optional param k seems to be present
		{
			_k = atoi(argv[acount++]);
		}
		else
		{
			_k = iHandler->getTotalNr() / 2;
		}

		if (argc > 5) //optional param lambda seems to be present
		{
			_lambda = atof(argv[acount++]);
		}
		
		if (argc > 6) //optional param log file path
		{
		  	logFilePath = argv[acount++];
		}

		if (argc > 7) //optional random step config
		{
			_randStep = atoi(argv[acount++]);
		}
	
		if (argc > 8) //optional choose estimator: 0 for random 1 for other
                {
                        _est = atoi(argv[acount++]);
                }

	}
	if (_iter < 1)
	{
		printf("ERROR: iteration number has to be >= 1");
		exit(EXIT_FAILURE);
	}
	if (_lambda < 0 || _lambda > 1)
	{
		printf("ERROR: lambda must be a floating point number in [0,1]\n");
		exit(EXIT_FAILURE);
	}

	//Initialize Cuda device
	findCudaDevice(argc, (const char **) argv);

	////////////////////////
	//Computation handlers//
	////////////////////////
	MatrixHandler* T;
	CMEstimator* CME;
	Initializer* init;
	ImageComparator* comparator;

	//////////////////
	//Final Settings//
	//////////////////
	const int dim = iHandler->getTotalNr();
	const int iterations = _iter;
	const float lambda = _lambda;
	const int kBest = _k;
	const int sizeOfInitIndicesList = kBest;

	//determines after what number of iterations a random step should be executed.
	//set to 0 for no random steps at all
	const int randomCompareSteps = _randStep;
	
	if (!randomMode)
		printf("#Directory \t%s\n#Images\t%i\n#k\t%i\n", dir, iHandler->getTotalNr(), kBest);

	if (randomCompareSteps > 0)
		printf("Doing random step all %i iterations\n", randomCompareSteps);
	else
		printf("Doing no random steps at all\n");

	////////////////////////////////////
	// Initialize computation handler //
	////////////////////////////////////
#if GPU_VERSION
	printf("Executing GPU Version.\n");
	T = new GPUSparse(dim, lambda);
	GPUSparse* T_sparse = dynamic_cast<GPUSparse*>(T);
	init = new InitializerGPU();
	if (_est == 0)
		CME = new CMEstimatorGPUSparseOPT();
	else
		CME = new CMEstimatorGPUSparseMax();
	comparator = new GPUComparator();
#else
	printf("Executing CPU Version.\n");
	T = new CPUImpl(dim, lambda);
	CPUImpl* T_cpu = dynamic_cast<CPUImpl*> (T);
	init = new InitializerCPU();
	CME = new CMEstimatorCPU();
	comparator = new CPUComparator();
#endif

	comparator->setRandomMode(randomMode);

	//start runtime measurement
	__int64_t startTime = continuousTimeNs();
	
	/////////////////////////////////////////////////////////
	//Match Graph algorithm (predict & verify step-by-step)//
	/////////////////////////////////////////////////////////
	for (int i = 0; i < iterations; i++)
	{
		if (i == 0)
		{
			////////////////////
			//Initialize Phase//
			////////////////////
			init->doInitializationPhase(T, iHandler, comparator, sizeOfInitIndicesList);
			printf("Initialization of T done. \n");
			printf("#i\tsolver\terror\tcomparator\n");
		}

		/////////////////////////
		//Iterative progression//
		/////////////////////////
		printf("%i\t", i);
		
#if GPU_VERSION
		//get the next images that should be compared (implicitly solving eq. system => confidence measure matrix)

		if(randomCompareSteps > 0 && i % randomCompareSteps  == 0)
			CME->computeRandomComparisons(T, kBest); //a random comparison step
		else
			CME->getKBestConfMeasures(T, NULL, kBest); //a normal step using the solver
		//compare images which are located in the device arrays of CME
		comparator->doComparison(iHandler, T, CME->getIdx1Ptr(), CME->getIdx2Ptr(), CME->getResPtr(), kBest); //device pointer
		//update matrix with new information (compared images)
		T_sparse->updateSparseStatus(CME->getIdx1Ptr(), CME->getIdx2Ptr(), CME->getResPtr(), kBest); //device pointer
#else
		//CPU Version
		//get the next images that should be compared
		CME->getKBestConfMeasures(T, T->getConfMatrixF(), kBest);
		//compare images which are located in the arrays of CME
		comparator->doComparison(iHandler, T, CME->getIdx1Ptr(), CME->getIdx2Ptr(), CME->getResPtr(), kBest);//host pointer
		//update matrix with new information (compared images)
		T_cpu->set(CME->getIdx1Ptr(), CME->getIdx2Ptr(), CME->getResPtr(), kBest);//host pointer
#endif
	}
	//stop runtime measurement
	__int64_t endTime = continuousTimeNs();
	__int64_t diff = endTime - startTime;

	printf("TOTAL RUNTIME:%f\n", diff*(1/(double)1000000000));

	//cleanup and logging
#if GPU_VERSION
	if(!randomMode) //create logfile
	{
		T_sparse->logSimilarToFile(logFilePath, iHandler);
	}

	delete T_sparse;
#else

#endif
	delete init;
	delete[] usageBuff;
	delete CME;
	delete comparator;

	cudaDeviceReset();

	exit(EXIT_SUCCESS);
}
