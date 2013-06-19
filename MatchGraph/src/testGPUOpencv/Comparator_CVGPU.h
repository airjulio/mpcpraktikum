/*
 * Comparator_CVGPU.h
 *
 *  Created on: Jun 5, 2013
 *      Author: rodrigpro
 */

#ifndef COMPARATORCVGPU_H_
#define COMPARATORCVGPU_H_

class ComparatorCVGPU {
public:
	int compareGPU(char* img1, char* img2, bool showMatches=true, bool drawEpipolar=false);
    
    	int ratioTest(std::vector< std::vector<cv::DMatch> >& matches);
    
	void symmetryTest(const std::vector< std::vector<cv::DMatch> >& matches1,
                      const std::vector< std::vector<cv::DMatch> >& matches2,
                      std::vector<cv::DMatch>& symMatches);
    
    	cv::Mat ransacTest(const std::vector<cv::DMatch>& matches,
                       const std::vector<cv::KeyPoint>& keypoints1,
                       const std::vector<cv::KeyPoint>& keypoints2,
                       std::vector<cv::DMatch>& outMatches);

	void match2(cv::gpu::GpuMat& im1_descriptors_gpu, 
				cv::gpu::GpuMat& im2_descriptors_gpu,
				std::vector<cv::DMatch>& symMatches);

	~ComparatorCVGPU(){};
};

#endif /* COMPARATORCVGPU_H_ */