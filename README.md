# 基于OpenMP、Pthread、Cuda的图片卷积实现
## 基于OpenMP的图片卷积

```c++
g++ -fopenmp OpenMP.cpp -o OpenMP
```

## 基于Pthread的图片卷积

```c++
g++ Pthread.cpp -o Pthread -lpthread
```

​	由于 pthread 和 OpenMP 用于共享内存系统，因此每个线程都可以直接读取图片矩阵。本程序的并行思路是，将图片矩阵按行划分成多个部分，每个线程分别针对本线程对应的部分进行高斯模糊，然后把结果存入结果矩阵对应的位置中。这样划分的好处是，并行计算时几乎不会涉及到临界区的问题，并且由于行读取，能够减少 cache 失效的次数。

## 基于Cuda的图片卷积
```C++
nvcc -gencode=arch=compute_50,code=\"sm_50,compute_50\" -o cuda Cuda.cu
```

​	本程序采用分离卷积的方式，将图片的RGB通道分离、图片行卷积、图片列卷积、最大池化、图片的通道合并全部在GPU中进行，并且每一个线程仅进行一次卷积或者池化操作，在CPU中仅进行图片的读取保存。由于最大程度利用的GPU多线程的优势，使得图片卷积池化所使用的时间接近于0，由于总时间约80ms、图片读取保存的时间约10ms、图片传入传出GPU的时间约60ms，因此最终的瓶颈在于GPU总线的限制。

# 三种实现的时间

![](C:\Users\86132\AppData\Roaming\Typora\typora-user-images\image-20230227180356731.png)

