#define _CRT_SECURE_NO_WARNINGS

#include<math.h>
#include <iomanip> 
#include <stdlib.h>
//#include <windows.h>
#include <stdio.h>
#include <stdlib.h>
#include <iostream>
#include <fstream>
#include<omp.h>
#include <sys/time.h>
#include<time.h>
using namespace std;

int thread_count;

int bmpWidth = 0;//图像的宽
int bmpHeight = 0;//图像的高
int width;
int lineByte;
unsigned char* pBmpBuf = NULL;//读入图像数据的指针
unsigned char* result = NULL;//读入图像数据的指针

typedef struct thread_data {
	long thread_no;
	unsigned char* pBmpBuf = NULL;

} thread_data_t;

//编译环境不支持windows.h,bmp头结构体
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
void read_bmp(unsigned char*& pBmpBuf, int& bmpWidth, int& bmpHeight)
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
	bfType = 0x4D42;//bmp类型
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

void* cur_thread(thread_data_t* data) {
	/*
	timeval starttime, endtime;
	gettimeofday(&starttime, 0);
*/
	int my_rank = omp_get_thread_num();

	int my_height = bmpHeight / thread_count;

	int myWidth = 0;//图像的宽
	int myHeight = bmpHeight;//图像的高

	unsigned char* mypBmpBuf = data->pBmpBuf;//读入图像数据的指针
	//cout << int(mypBmpBuf[1]) << endl;
	//unsigned char* mypBmpBuf = NULL;
	//read_bmp(mypBmpBuf, myWidth, myHeight);
	int start = my_rank * my_height;
	int end = (my_rank + 1) * my_height;
	int lines = lineByte;
	int width0 = lines / 3;
	double out = 0;
	double kernel[5] = { 0.1200783842,0.2338807566,0.2920817183,0.2338807566,0.1200783842 };
	int* cur_channel = new int[width0 * (end - start + 4)];

	double* pro_channel = new double[width0 * (end - start + 4)];
	double* T = new double[width0];

	for (int channel = 0; channel < 3; channel++)
	{
		for (int i = 0; i < width * (end - start + 4); i++) {
			int CurPos = i * 3 + channel - 2 * lineByte + lineByte * start;
			if (CurPos < 0 || CurPos > lines * myHeight)
				cur_channel[i] = 0;
			else
				cur_channel[i] = mypBmpBuf[CurPos];
		}

		for (int i = 0; i < end - start + 4; i++) {
			for (int j = 0; j < width0; j++) {
				out = 0;

				for (int k = -2; k < 3; k++) {
					if (j + k >= 0 && j + k < width0) {

						out += cur_channel[i * width0 + j + k] * kernel[k + 2];
					}
				}

				pro_channel[i * width0 + j] = out;
			}
		}


		for (int i = 2; i < end - start + 2; i++) {
			for (int j = 0; j < width0; j++) {
				T[j] = 0;
			}
			for (int j = -2; j < 3; j++) {
				for (int k = 0; k < width0; k++) {
					T[k] += pro_channel[(i + j) * width0 + k] * kernel[j + 2];
				}
			}
			for (int k = 0; k < width0; k++) {
				result[(i - 2 + start) * lines + 3 * k + channel] = (unsigned char)(T[k]);
			}
		}
		/*
		gettimeofday(&endtime0, 0);
		double timeuse = 1000000 * (endtime0.tv_sec - starttime0.tv_sec) + endtime0.tv_usec - starttime0.tv_usec;
		timeuse /= 1000;//除以1000则进行毫秒计时，如果除以1000000则进行秒级别计时，如果除以1则进行微妙级别计时
		cout << my_rank <<" "<<channel << " time: " << timeuse << " ms" << std::endl;*/
	}
	/*
	gettimeofday(&endtime, 0);
	double timeuse = 1000000 * (endtime.tv_sec - starttime.tv_sec) + endtime.tv_usec - starttime.tv_usec;
	timeuse /= 1000;//除以1000则进行毫秒计时，如果除以1000000则进行秒级别计时，如果除以1则进行微妙级别计时
	printf("my_rank = %d, core time = %.3f ms\n", my_rank, timeuse);
*/
	return NULL;
}

int main(int argc, char* argv[])
{
	/*
	clock_t start, end;
	start = clock();
	*/
	timeval starttime, endtime;
	gettimeofday(&starttime, 0);

	read_bmp(pBmpBuf, bmpWidth, bmpHeight);
	width = lineByte / 3;
	result = new unsigned char[lineByte * bmpHeight];

	thread_data_t* data = NULL; 
	thread_count = strtol(argv[1], NULL, 10);
	#pragma omp parallel num_threads(thread_count)
	{
		data = (thread_data_t*)malloc(sizeof(thread_data_t));
		data->pBmpBuf = pBmpBuf;
		cur_thread(data);
	}

	char writePath[] = "OpenMP1952934.bmp";
	saveBmp(writePath, result, bmpWidth, bmpHeight);
	
	gettimeofday(&endtime, 0);
	double timeuse = 1000000 * (endtime.tv_sec - starttime.tv_sec) + endtime.tv_usec - starttime.tv_usec;
	timeuse /= 1000;//除以1000则进行毫秒计时，如果除以1000000则进行秒级别计时，如果除以1则进行微妙级别计时
	printf("total time = %.3f ms\n", timeuse);
/*
	end = clock();
	cout << "time = " << double(end - start) / CLOCKS_PER_SEC << "s" << endl;*/
	return 0;
}


