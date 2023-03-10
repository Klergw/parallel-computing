
#include <iostream>
#include <fstream>
#include <stdio.h>
#include <iostream>
#include <iomanip>
#include <cuda_runtime.h>
using namespace std;
#include <sys/time.h>
double cpuSecond()
{
  struct timeval tp;
  gettimeofday(&tp,NULL);
  return((double)tp.tv_sec+(double)tp.tv_usec*1e-6);
}



__constant__ double kernel[5] = { 0.1200783842,0.2338807566,0.2920817183,0.2338807566,0.1200783842 };

int bmpWidth = 0;
int bmpHeight = 0;
int width;
int lineByte;
unsigned char* pBmpBuf = NULL;
unsigned char* result = NULL;
unsigned char* picture[3] = {NULL,NULL,NULL};
unsigned char* channel[3] = {NULL,NULL,NULL};
pthread_key_t g_key;
typedef struct thread_data {
	long thread_no;
	unsigned char* pBmpBuf = NULL;
	
} thread_data_t;


typedef unsigned int DWORD;
typedef int LONG;
typedef unsigned short WORD;
typedef struct tagBITMAPFILEHEADER {
	WORD    bfType;
	DWORD   bfSize;
	WORD    bfReserved1;
	WORD    bfReserved2;
	DWORD   bfOffBits;
} BITMAPFILEHEADER;
typedef struct tagBITMAPINFOHEADER {
	DWORD      biSize;
	LONG       biWidth;
	LONG       biHeight;
	WORD       biPlanes;
	WORD       biBitCount;
	DWORD      biCompression;
	DWORD      biSizeImage;
	LONG       biXPelsPerMeter;
	LONG       biYPelsPerMeter;
	DWORD      biClrUsed;
	DWORD      biClrImportant;
} BITMAPINFOHEADER;
void read_bmp(unsigned char* &pBmpBuf, int &bmpWidth, int &bmpHeight)
{
	FILE* fp = fopen("timg.bmp", "rb");
	fseek(fp, 14, 0);
	BITMAPINFOHEADER head;
	fread(&head, sizeof(BITMAPINFOHEADER), 1, fp);
	bmpWidth = head.biWidth;
	bmpHeight = head.biHeight;  
	lineByte = (bmpWidth * 3 + 3) / 4 * 4;

	pBmpBuf = new unsigned char[lineByte * bmpHeight];
	//cout << "bmpWidth " << bmpWidth << " bmpHeight " << bmpHeight << endl;
	fread(pBmpBuf, 1, lineByte * bmpHeight, fp);
	fclose(fp);
}

bool saveBmp(char* bmpName, unsigned char* imgBuf, int width, int height)
{
	if (!imgBuf)
		return 0;
	int colorTablesize = 0;
	int lineByte = (width * 24 / 8 + 3) / 4 * 4;
	FILE* fp = fopen(bmpName, "wb");
	if (fp == 0)
		return 0;
	WORD    bfType;
	DWORD   bfSize;
	WORD    bfReserved1;
	WORD    bfReserved2;
	DWORD   bfOffBits;
	bfType = 0x4D42;//bmp????????
	fwrite(&bfType, sizeof(WORD), 1, fp);
	bfSize = 14 + sizeof(BITMAPINFOHEADER) + colorTablesize + lineByte * height;
	fwrite(&bfSize, sizeof(DWORD), 1, fp);
	bfReserved1 = 0;
	fwrite(&bfReserved1, sizeof(WORD), 1, fp);
	bfReserved2 = 0;
	fwrite(&bfReserved2, sizeof(WORD), 1, fp);
	bfOffBits = 54 + colorTablesize;
	fwrite(&bfOffBits, sizeof(DWORD), 1, fp);
	BITMAPINFOHEADER head;
	head.biBitCount = 24;
	head.biClrImportant = 0;
	head.biClrUsed = 0;
	head.biCompression = 0;
	head.biHeight = height;
	head.biPlanes = 1;
	head.biSize = 40;
	head.biSizeImage = lineByte * height;
	head.biWidth = width;
	head.biXPelsPerMeter = 0;
	head.biYPelsPerMeter = 0;
	fwrite(&head, sizeof(BITMAPINFOHEADER), 1, fp);
	fwrite(imgBuf, height * lineByte, 1, fp);
	fclose(fp);
	return 1;

}

__global__ void picture_separation(unsigned char *picture_device, unsigned char *pic_device, int channel, int width, int lineByte, int height){

	int x = blockIdx.y * 1024 + threadIdx.x;
	int y = blockIdx.x;
    int pos = y * lineByte + x *3 + channel;
    int newpos = y * width + x;
    pic_device[newpos] = picture_device[pos];

}
__global__ void picture_conv_row(unsigned char *pic_device, double *pic_middle, int width, int height){

	int x = blockIdx.y * 1024 + threadIdx.x;
	int y = blockIdx.x;
    int pos = y * width + x;
    int begin_pos = y * width;
    int end_pos = (y + 1) * width;
    double myvalue = 0;
    int begin = pos - 2;
    for(int i = begin; i < begin + 5; i++){
    	if(i >= begin_pos && i < end_pos){
    		myvalue += pic_device[i] * kernel[i - begin];
    	}
    }

    int newpos = x * height + y;
    pic_middle[newpos] = myvalue;

}
//???????????????
__global__ void picture_conv_col(double *pic_middle, double * pic_max_pool, int width, int height){
	//height = threadIdx.x
	//width = blockIdx.x
	int x = blockIdx.y * 1024 + threadIdx.x;
	int y = blockIdx.x;
	int pos = x * height + y;
    int begin_pos = x * height;
    int end_pos = (x + 1) * height;
    double myvalue = 0;
    int begin = pos - 2;
    for(int i = begin; i < begin + 5; i++){
    	if(i >= begin_pos && i < end_pos){
    		myvalue += pic_middle[i] * kernel[i - begin];
    	}
    }

    //??????????????????
    //int newpos = threadIdx.x * width + blockIdx.x;
    //width * 2, height / 2
    
    int x0 = x * 2 + y % 2;
    int y0 = y / 2;//??????
    int newpos = y0 * width * 2 + x0;
    pic_max_pool[newpos] = myvalue;


}
__global__ void max_pooling(double * pic_max_pool, unsigned char * pic_result, int width, int height){
	//width = 4096 * 2
	//height = 2304 / 2
	//blockDim.x = 4096 / 2
	//gridDim.x = 2304 / 2
	int x = blockIdx.y * 1024 + threadIdx.x;
	int y = blockIdx.x;
	int pos = y * width + x;
    double myvalue = pic_max_pool[pos * 4];
    for(int i = pos * 4 + 1; i < pos * 4 + 4; i++){
    	if(myvalue <  pic_max_pool[i]){
    		myvalue = pic_max_pool[i];
    	}
    }
    int newpos = y * width + x;
    pic_result[newpos] = (unsigned char)myvalue;
}
__global__ void picture_combination(unsigned char * pic_result, unsigned char * picture_result, int channel, int width, int lineByte, int height){

	int x = blockIdx.y * 1024 + threadIdx.x;
	int y = blockIdx.x;
    int pos = y * lineByte + x *3 + channel;
    int newpos = y * width + x;
    picture_result[pos] = pic_result[newpos];
}
int main(int argc,char* argv[])
{
	/*
	//????????????cuda????????????????????????
    cudaDeviceProp prop;
    //?????????1???gpu?????????????????????
    cudaGetDeviceProperties(&prop,0);
    //??????block??????????????????
    std::cout<<"maxThreadsPerBlock: "<<prop.maxThreadsPerBlock<<std::endl;
    //block?????????
    for(int i=0;i<3;++i) std::cout<<"maxThreadsDim["<<i<<"]: "<<prop.maxThreadsDim[i]<<std::endl;
    //???????????????gridSize
    std::cout<<std::endl;
    for(int i=0;i<3;++i) std::cout<<"maxGridSize["<<i<<"]: "<<prop.maxGridSize[i]<<std::endl;
	*/

	clock_t start_host = clock();
	read_bmp(pBmpBuf, bmpWidth, bmpHeight);
	cout<<"??????????????????="<<(double)(clock() - start_host)/1000<<"ms"<<endl;
	width = lineByte / 3;
	result = new unsigned char[lineByte * bmpHeight / 4];
	unsigned char *picture_device = NULL;
	unsigned char *pic_device[3] = {NULL, NULL, NULL};
	double *pic_middle[3] = {NULL, NULL, NULL};
	double *pic_max_pool[3] = {NULL, NULL, NULL};
	unsigned char *pic_result[3] = {NULL, NULL, NULL};
	unsigned char *picture_result = NULL;

  	double iStart,iElaps;
  	iStart=cpuSecond();
  	//????????????GPU
	cudaMalloc((void**)&picture_device,sizeof(unsigned char) * lineByte * bmpHeight);
	cudaMemcpy(picture_device, pBmpBuf,sizeof(unsigned char) * lineByte * bmpHeight,cudaMemcpyHostToDevice);

	iElaps=cpuSecond()-iStart;
  	cout<<"????????????GPU??????:" << iElaps*1000<<endl;
	iStart=cpuSecond();
  	//RGB????????????
	for(int i = 0; i < 3; i++){
		cudaMalloc((void**)&pic_device[i],sizeof(unsigned char) * width * bmpHeight);
    	dim3 gridsize(bmpHeight,4,1);
    	dim3 blocksize(1024,1,1);
    	picture_separation<<<gridsize,blocksize>>>(picture_device, pic_device[i], i, width, lineByte, bmpHeight);
			
	}
	//cudaFree(picture_device);	
	//?????????
	for(int i = 0; i < 3; i++){
		
		cudaMalloc((void**)&pic_middle[i],sizeof(double) * width * bmpHeight);
    	dim3 gridsize(bmpHeight,4,1);
    	dim3 blocksize(1024,1,1);
    	picture_conv_row<<<gridsize,blocksize>>>(pic_device[i], pic_middle[i], width, bmpHeight);		
		
		//cudaFree(pic_device[i]);
	}

	//?????????
	for(int i = 0; i < 3; i++){
    	cudaMalloc((void**)&pic_max_pool[i],sizeof(double) * width * bmpHeight);
		dim3 gridsize(bmpHeight,4,1);
    	dim3 blocksize(1024,1,1);

    	picture_conv_col<<<gridsize,blocksize>>>(pic_middle[i], pic_max_pool[i], width, bmpHeight);
		//cudaFree(pic_middle[i]);
	}

	//max pool
	for(int i = 0; i < 3; i++){
		cudaMalloc((void**)&pic_result[i],sizeof(unsigned char) * width * bmpHeight / 4);
    	
    	dim3 gridsize(bmpHeight / 2,2,1);
    	dim3 blocksize(1024,1,1);
    	max_pooling<<<gridsize,blocksize>>>(pic_max_pool[i], pic_result[i], width / 2, bmpHeight / 2);
    	//cudaFree(pic_max_pool[i]);
		
	}
	//????????????
	cudaMalloc((void**)&picture_result,sizeof(unsigned char) * lineByte * bmpHeight / 4);
    for(int i = 0; i < 3; i++){
		
    	dim3 gridsize(bmpHeight / 2,2,1);
    	dim3 blocksize(1024,1,1);
    	picture_combination<<<gridsize,blocksize>>>(pic_result[i], picture_result, i, width / 2, lineByte / 2, bmpHeight / 2);

		//cudaFree(pic_result[i]);
	}
	iElaps=cpuSecond()-iStart;
  	cout<<"GPU????????????:" << iElaps*1000<<endl;
	iStart=cpuSecond();
	cudaMemcpy(result, picture_result,sizeof(unsigned char) * lineByte* bmpHeight / 4,cudaMemcpyDeviceToHost);

	//cudaDeviceSynchronize();
  	iElaps=cpuSecond()-iStart;
  	cout<<"?????????GPU????????????:"<<iElaps*1000<<endl;
	iStart=cpuSecond();
	char writePath[] = "Cuda_????????????_1952934.bmp";
	saveBmp(writePath, result, bmpWidth / 2, bmpHeight / 2); 
  	iElaps=cpuSecond()-iStart;
  	cout<<"??????????????????:"<<iElaps*1000<<endl;
	cout<<"total time="<<(double)(clock() - start_host)/1000<<"ms"<<endl;
	return 0;
}


