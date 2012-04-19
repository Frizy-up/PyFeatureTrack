# cython: profile=False
# cython: cdivision=True
# cython: boundscheck=False
# cython: wraparound=False

import numpy as np
cimport numpy as np
from klt import *
import scipy.optimize
import scipy.ndimage

#*********************************************************************

def extractImagePatchSlow(np.ndarray[np.float32_t,ndim=2] img, float x, float y, int height, int width):

	patch = np.empty((height, width), np.float32)
	extractImagePatchOptimised(img, x, y, patch)
	return patch

cdef extractImagePatchOptimised(np.ndarray[np.float32_t,ndim=2] img, float x, float y, np.ndarray[np.float32_t,ndim=2] out):

	cdef int i, j, vx, vy
	cdef int ix = int(x)
	cdef int iy = int(y)
	cdef int patchCols = out.shape[1]
	cdef int patchRows = out.shape[0]
	cdef int hh = out.shape[0] / 2
	cdef int hw = out.shape[1] / 2
	cdef float val
	cdef float ax = x - int(x) #Get decimal part of x and y
	cdef float ay = y - int(y)
	cdef int ncols = img.shape[1]
	cdef int nrows = img.shape[0]

	assert ix - hw >= 0 and iy - hh >= 0 and ix + hw + 1 <= ncols - 2 and iy + hh + 1 <= nrows - 2

	# Compute values
	for j in range(patchCols):
		for i in range(patchRows):

			vx = ix+i-hw
			vy = iy+j-hh

			val = (1.-ax) * (1.-ay) * img[vy,vx] + \
				ax   * (1.-ay) * img[vy,vx+1] + \
				(1.-ax) *   ay   * img[vy+1,vx] + \
				ax   *   ay   * img[vy+1,vx+1]

			out[j,i] = val

	i = 0 #All done, but this line makes cython profiling easier to read

#*********************************************************************
#* _computeIntensityDifference
#*
#* Given two images and the window center in both images,
#* aligns the images wrt the window and computes the difference 
#* between the two overlaid images.
#*

cdef _computeIntensityDifference(np.ndarray[np.float32_t,ndim=2] img1Patch,   # images 
	np.ndarray[np.float32_t,ndim=2] img2,
	float x2, 
	float y2,     # center of window in 2nd img
	np.ndarray[np.float32_t,ndim=2] workingPatch, # temporary memory for patch storage, size determines window size
	np.ndarray[np.float32_t,ndim=1] out):

	cdef int hw = workingPatch.shape[1]/2
	cdef int hh = workingPatch.shape[0]/2
	cdef float g1, g2
	cdef int i, j, ind = 0

	#imgdiff = []
	#imgl1 = img1.load()
	#imgl2 = img2.load()

	extractImagePatchOptimised(img2, x2, y2, workingPatch)

	# Compute values
	for j in range(-hh, hh + 1):
		for i in range(-hw, hw + 1):
			g1 = img1Patch[j + hh, i + hw]
			g2 = workingPatch[j + hh, i + hw]
			#imgdiff.append(g1 - g2)
			out[ind] = g1 - g2
			ind += 1

	return None

def computeIntensityDifference(np.ndarray[np.float32_t,ndim=2] img1Patch,   # images 
	np.ndarray[np.float32_t,ndim=2] img2,
	float x2, 
	float y2,     # center of window in 2nd img
	np.ndarray[np.float32_t,ndim=2] workingPatch,
	np.ndarray[np.float32_t,ndim=1] out): # temporary memory for patch storage, size determines window size

	return _computeIntensityDifference(img1Patch, img2, x2, y2, workingPatch, out)

#*********************************************************************
#* _computeGradientSum
#*
#* Given two gradients and the window center in both images,
#* aligns the gradients wrt the window and computes the sum of the two 
#* overlaid gradients.
#*

cdef _computeGradientSum(np.ndarray[np.float32_t,ndim=2] img1GradxPatch,  # gradient images
	np.ndarray[np.float32_t,ndim=2] gradx2,
	float x2, float y2,      # center of window in 2nd img
	np.ndarray[np.float32_t,ndim=2] workingPatch, # temporary memory for patch storage, size determines window size
	np.ndarray[np.float32_t,ndim=2] out,
	int row): 

	cdef int hw = workingPatch.shape[1]/2
	cdef int hh = workingPatch.shape[0]/2
	cdef float g1, g2
	cdef int i, j
	#gradx, grady = [], []

	extractImagePatchOptimised(gradx2, x2, y2, workingPatch)

	# Compute values
	for j in range(workingPatch.shape[0]):
		for i in range(workingPatch.shape[1]):
			g1 = img1GradxPatch[j, i]
			g2 = workingPatch[j, i]

			out[j*workingPatch.shape[0] + i, row] = - g1 - g2

def computeGradientSum(np.ndarray[np.float32_t,ndim=2] img1GradxPatch,  # gradient images
	np.ndarray[np.float32_t,ndim=2] gradx2,
	float x2, float y2,      # center of window in 2nd img
	np.ndarray[np.float32_t,ndim=2] workingPatch, # temporary memory for patch storage, size determines window size
	np.ndarray[np.float32_t,ndim=2] out,
	int row):

	return _computeGradientSum(img1GradxPatch,
		gradx2,
		x2, y2,
		workingPatch,
		out,
		row)

#*********************************************************************
#* _computeIntensityDifferenceLightingInsensitive
#*
#* Given two images and the window center in both images,
#* aligns the images wrt the window and computes the difference 
#* between the two overlaid images; normalizes for overall gain and bias.
#*

#static void _computeIntensityDifferenceLightingInsensitive(
#  _KLT_FloatImage img1,   /* images */
#  _KLT_FloatImage img2,
#  float x1, float y1,     /* center of window in 1st img */
#  float x2, float y2,     /* center of window in 2nd img */
#  int width, int height,  /* size of window */
#  _FloatWindow imgdiff)   /* output */
#{
#  register int hw = width/2, hh = height/2;
#  float g1, g2, sum1_squared = 0, sum2_squared = 0;
#  register int i, j;
#  
#  float sum1 = 0, sum2 = 0;
#  float mean1, mean2,alpha,belta;
#  /* Compute values */
#  for (j = -hh ; j <= hh ; j++)
#    for (i = -hw ; i <= hw ; i++)  {
#      g1 = trackFeaturesUtils.interpolate(x1+i, y1+j, img1);
#      g2 = trackFeaturesUtils.interpolate(x2+i, y2+j, img2);
#      sum1 += g1;    sum2 += g2;
#      sum1_squared += g1*g1;
#      sum2_squared += g2*g2;
#   }
#  mean1=sum1_squared/(width*height);
#  mean2=sum2_squared/(width*height);
#  alpha = (float) sqrt(mean1/mean2);
#  mean1=sum1/(width*height);
#  mean2=sum2/(width*height);
#  belta = mean1-alpha*mean2;
#
#  for (j = -hh ; j <= hh ; j++)
#    for (i = -hw ; i <= hw ; i++)  {
#      g1 = trackFeaturesUtils.interpolate(x1+i, y1+j, img1);
#      g2 = trackFeaturesUtils.interpolate(x2+i, y2+j, img2);
#      *imgdiff++ = g1- g2*alpha-belta;
#    } 
#}


#*********************************************************************
#* _computeGradientSumLightingInsensitive
#*
#* Given two gradients and the window center in both images,
#* aligns the gradients wrt the window and computes the sum of the two 
#* overlaid gradients; normalizes for overall gain and bias.
#*

#static void _computeGradientSumLightingInsensitive(
#  _KLT_FloatImage gradx1,  /* gradient images */
#  _KLT_FloatImage grady1,
#  _KLT_FloatImage gradx2,
#  _KLT_FloatImage grady2,
#  _KLT_FloatImage img1,   /* images */
#  _KLT_FloatImage img2,
# 
#  float x1, float y1,      /* center of window in 1st img */
#  float x2, float y2,      /* center of window in 2nd img */
#  int width, int height,   /* size of window */
#  _FloatWindow gradx,      /* output */
#  _FloatWindow grady)      /*   " */
#{
#  register int hw = width/2, hh = height/2;
#  float g1, g2, sum1_squared = 0, sum2_squared = 0;
#  register int i, j;
#  
#  float sum1 = 0, sum2 = 0;
#  float mean1, mean2, alpha;
#  for (j = -hh ; j <= hh ; j++)
#    for (i = -hw ; i <= hw ; i++)  {
#      g1 = trackFeaturesUtils.interpolate(x1+i, y1+j, img1);
#      g2 = trackFeaturesUtils.interpolate(x2+i, y2+j, img2);
#      sum1_squared += g1;    sum2_squared += g2;
#    }
#  mean1 = sum1_squared/(width*height);
#  mean2 = sum2_squared/(width*height);
#  alpha = (float) sqrt(mean1/mean2);
#  
#  /* Compute values */
#  for (j = -hh ; j <= hh ; j++)
#    for (i = -hw ; i <= hw ; i++)  {
#      g1 = trackFeaturesUtils.interpolate(x1+i, y1+j, gradx1);
#      g2 = trackFeaturesUtils.interpolate(x2+i, y2+j, gradx2);
#      *gradx++ = g1 + g2*alpha;
#      g1 = trackFeaturesUtils.interpolate(x1+i, y1+j, grady1);
#      g2 = trackFeaturesUtils.interpolate(x2+i, y2+j, grady2);
#      *grady++ = g1+ g2*alpha;
#    }  
#}

#*********************************************************************
#* _compute2by1ErrorVector
#*
#*

def _compute2by1ErrorVector(np.ndarray[np.float32_t,ndim=1] imgdiff,
	np.ndarray[np.float32_t,ndim=1] gradx,
	np.ndarray[np.float32_t,ndim=1] grady,
	int width, # size of window
	int height,
	float step_factor): # 2.0 comes from equations, 1.0 seems to avoid overshooting

	# Compute values
	cdef float ex = 0.
	cdef float ey = 0.
	cdef int ind = 0
	cdef int i = 0
	cdef float diff = 0.

	for i in range(width * height):
		diff = imgdiff[ind]
		ex += diff * gradx[ind]
		ey += diff * grady[ind]
		ind += 1

	ex *= step_factor
	ey *= step_factor

	return ex, ey

#*********************************************************************
#* _compute2by2GradientMatrix
#*
#*

def _compute2by2GradientMatrix(np.ndarray[np.float32_t,ndim=1] gradx, 
	np.ndarray[np.float32_t,ndim=1] grady,
	int width,   # size of window
	int height):

	# Compute values 
	cdef float gx, gy
	cdef float gxx = 0.0
	cdef float gxy = 0.0
	cdef float gyy = 0.0
	cdef int ind = 0, i

	for i in range(width * height):
		gx = gradx[ind]
		gy = grady[ind]
		gxx += gx*gx;
		gxy += gx*gy;
		gyy += gy*gy;
		ind += 1

	return gxx, gxy, gyy

#*********************************************************************
#* _solveEquation
#*
#* Solves the 2x2 matrix equation
#*         [gxx gxy] [dx] = [ex]
#*         [gxy gyy] [dy] = [ey]
#* for dx and dy.
#*
#* Returns KLT_TRACKED on success and KLT_SMALL_DET on failure
#*

def _solveEquation(float gxx, float gxy, float gyy,
	float ex, float ey,
	float small):

	cdef float det = gxx*gyy - gxy*gxy, dx, dy
	
	if det < small: 
		return kltState.KLT_SMALL_DET, None, None

	dx = (gyy*ex - gxy*ey)/det
	dy = (gxx*ey - gxy*ex)/det
	return kltState.KLT_TRACKED, dx, dy

def minFunc(np.ndarray[double,ndim=1] xData, 
	np.ndarray[np.float32_t,ndim=2] img1Patch, 
	np.ndarray[np.float32_t,ndim=2] img1GradxPatch, 
	np.ndarray[np.float32_t,ndim=2] img1GradyPatch, 
	np.ndarray[np.float32_t,ndim=2] img2, 
	np.ndarray[np.float32_t,ndim=2] workingPatch, 
	np.ndarray[np.float32_t,ndim=2] jacobianMem, 
	int lightInsensitive,
	np.ndarray[np.float32_t,ndim=2] gradx2, 
	np.ndarray[np.float32_t,ndim=2] grady2):

	cdef float x2 = xData[0]
	cdef float y2 = xData[1]

	#print img1, img2, x1, y1, width, height
	if lightInsensitive:
		raise Exception("Not implemented")
		#imgdiff = _computeIntensityDifferenceLightingInsensitive(img1, img2, x1, y1, x2, y2, workingPatch)
	else:
		_computeIntensityDifference(img1Patch, img2, x2, y2, workingPatch, jacobianMem[:,0])

	#print "test", x2, y2, np.array(imgdiff).sum()
	return jacobianMem[:,0]

def jacobian(np.ndarray[double,ndim=1] xData, 
	np.ndarray[np.float32_t,ndim=2] img1Patch, 
	np.ndarray[np.float32_t,ndim=2] img1GradxPatch, 
	np.ndarray[np.float32_t,ndim=2] img1GradyPatch, 
	np.ndarray[np.float32_t,ndim=2] img2, 
	np.ndarray[np.float32_t,ndim=2] workingPatch, 
	np.ndarray[np.float32_t,ndim=2] jacobianMem, 
	int lightInsensitive,
	np.ndarray[np.float32_t,ndim=2] gradx2, 
	np.ndarray[np.float32_t,ndim=2] grady2):

	cdef float x2 = xData[0]
	cdef float y2 = xData[1]

	#print img1, img2, x1, y1, width, height
	if lightInsensitive:
		raise Exception("Not implemented")
		#gradx, grady = _computeGradientSumLightingInsensitive(gradx1, grady1, gradx, grady2, img1, img2, x1, y1, x2, y2, workingPatch, jacobianMem)
	else:
		_computeGradientSum(img1GradxPatch, gradx2, x2, y2, workingPatch, jacobianMem, 0)
		_computeGradientSum(img1GradyPatch, grady2, x2, y2, workingPatch, jacobianMem, 1)

	return jacobianMem

