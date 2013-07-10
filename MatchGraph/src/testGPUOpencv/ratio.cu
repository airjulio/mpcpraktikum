#include <stdio.h>
#include <vector_types.h>
#include <thrust/host_vector.h>
#include <thrust/device_vector.h>
#include <thrust/remove.h>
#include <thrust/iterator/zip_iterator.h>
#include <thrust/tuple.h>

struct is_bad_match
{
    template <typename Tuple>
    __device__ bool operator()(const Tuple& tuple) const
    {
        // unpack the tuple
        const int2 trainIdx = thrust::get<0>(tuple);
        const float2 distance = thrust::get<1>(tuple);
        // check if it is a bad match
		/*
		if ((distance.x / distance.y) < 0.85) {
			trainIdx = NULL;
			//trainIdx.x = NULL;
			//trainIdx.y = NULL;
			//printf("(%d, %d)\n", trainIdx1.x, trainIdx1.y);
			//printf("distance.x = %f\n", distance1.x);
			//printf("distance.y = %f\n", distance1.y);
		}*/
		
        return (distance.x / distance.y) > 0.85f;
    }
};
/*
__global__
void ratio(const int2 * trainIdx1, int2 * trainIdx2,
                            const float2 * distance1, const float2 * distance2)
{
 
  	int i = blockIdx.x * blockDim.x + threadIdx.x;

    int x1 = trainIdx1[i].x;
    int y1 = trainIdx1[i].y;
    float d11 = distance1[i].x;
    float d21 = distance1[i].y;

    if ((d11 / d21) < 0.85f) {

	//printf("%d\n",i);
		//printf("1. Distances: %f,%f\n", d11, d21);
    	//printf("1. Points: (%d,%d)\n", x1,y1);
        
    }
	//out[i] = x1;

    int x2 = trainIdx2[i].x;
    int y2 = trainIdx2[i].y;
    float d12 = distance2[i].x;
    float d22 = distance2[i].y;

    if ((d12 / d22) < 0.85f) {
	//printf("%d\n",i);
    	printf("2. Points: (%d,%d)\n", x2,y2);
        //printf("2. Distances: %f,%f\n", d12, d22);
    }
}
*/

void ratio_aux(int2 * trainIdx_ptr, float2 * distance_ptr, const size_t size)
{

	thrust::device_ptr<int2> d_train_ptr(trainIdx_ptr);
	thrust::device_ptr<float2> d_dist_ptr(distance_ptr);

	//size_t new_size = 
	//TODO: instead of remove_it, transform the stored value
	
	
	thrust::remove_if(
							thrust::make_zip_iterator(thrust::make_tuple(d_train_ptr, d_dist_ptr)),
	                  		thrust::make_zip_iterator(thrust::make_tuple(d_train_ptr + size, d_dist_ptr + size)),
							is_bad_match())
	     - thrust::make_zip_iterator(thrust::make_tuple(d_train_ptr, d_dist_ptr));
	//std::cout << "new_size: " << new_size << std::endl;
	
  //const int thread = 32;
  //const dim3 blockSize( thread );
  //const dim3 gridSize( 8, 1 );
  //ratio <<< gridSize, blockSize >>>(trainIdx1_ptr, trainIdx2,
    //                                distance1_ptr, distance2);
}