
from __future__ import print_function
import math, numpy as np
from PIL import Image

#Attempt to use scipy to speed up convolution
useScipyConvolution = False
try:
	import scipy.ndimage
	useScipyConvolution = True
except:
	print("Warning: Failed to import scipy.ndimage")

class ConvolutionKernel:
	def __init__(self, maxKernelWidth = 71):
		self.width = None
		self.data = [0. for i in range(maxKernelWidth)]

#*********************************************************************
#* _computeKernels
#*

cachegauss = None
cachegaussderiv = None
cached_sigma_last = None

def _computeKernels(sigma):
	maxKernelWidth = 71
	gauss = ConvolutionKernel(maxKernelWidth)
	gaussderiv = ConvolutionKernel(maxKernelWidth)

	factor = 0.01   # for truncating tail

	assert maxKernelWidth % 2 == 1
	assert sigma >= 0.0

	# Compute kernels, and automatically determine widths */

	hw = int(maxKernelWidth / 2)
	max_gauss = 1.0
	max_gaussderiv = float(sigma*math.exp(-0.5))
	
	# Compute gauss and deriv 
	for i in range(-hw,hw+1):
		gauss.data[i+hw] = float (math.exp(-i*i / (2*sigma*sigma)))
		gaussderiv.data[i+hw] = -i * gauss.data[i+hw]

    	# Compute widths
	gauss.width = maxKernelWidth;
	i = -hw
	while(abs(gauss.data[i+hw] / max_gauss) < factor):
		i = i + 1
		gauss.width -= 2
	gaussderiv.width = maxKernelWidth

	i = -hw
	while(abs(gaussderiv.data[i+hw] / max_gaussderiv) < factor) :
		gaussderiv.width -= 2
		i = i + 1

	if gauss.width == maxKernelWidth or gaussderiv.width == maxKernelWidth:
		KLTError("(_computeKernels) maxKernelWidth {0} is too small for a sigma of {1}".format(maxKernelWidth, sigma))

	# Shift if width less than maxKernelWidth 
	for i in range(gauss.width):
		gauss.data[i] = gauss.data[int(i+(maxKernelWidth-gauss.width)/2)]
	for i in range(gaussderiv.width):
		gaussderiv.data[i] = gaussderiv.data[int(i+(maxKernelWidth-gaussderiv.width)/2)]

	# Normalize gauss and deriv 
	hw = int(gaussderiv.width / 2)
	den = 0.0;
	for i in range(gauss.width): 
		den += gauss.data[i]
	for i in range(gauss.width): 
		gauss.data[i] /= den

	den = 0.0
	for i in range(-hw,hw+1): 
		den -= i*gaussderiv.data[i+hw]
	for i in range(-hw,hw+1): 
		gaussderiv.data[i+hw] /= den

	#Extract the valid portion of the kernel
	gauss.data = gauss.data[:gauss.width]
	gaussderiv.data = gaussderiv.data[:gaussderiv.width]

	global cachegauss, cachegaussderiv, cached_sigma_last
	cachegauss = gauss.data
	cachegaussderiv = gaussderiv.data
	cached_sigma_last = sigma

	return gauss.data, gaussderiv.data

#*********************************************************************
#* KLTGetKernelWidths
#*
#*

def KLTGetKernelWidths(sigma):
	gauss_kernel, gaussderiv_kernel = _computeKernels(sigma)
	return len(gauss_kernel), len(gaussderiv_kernel)

#*********************************************************************
#* _convolveImageHoriz
#*

def _convolveImageHoriz(imgin,kernel):

	imgin = Image.fromarray(imgin)
	radius = len(kernel) / 2
	imgout = Image.new("F", imgin.size)
	imgoutl = imgout.load()
	imginl = imgin.load()
	ncols, nrows = imgin.size

	# Kernel width must be odd 
	assert len(kernel) % 2 == 1

	# Must read from and write to different images 
	#assert(imgin != imgout);

	# Output image must be large enough to hold result 
	#assert imgout->ncols >= imgin->ncols
	#assert imgout->nrows >= imgin->nrows

	# For each row, do ... 
	for j in range(nrows):

		# Zero leftmost columns 
		for i in range(radius):
			imgoutl[i,j] = 0.

		# Convolve middle columns with kernel 
		for i in range(radius,ncols - radius):
			sumv = 0.0
			ind = 0
			for k in range(len(kernel)-1,-1,-1):
				sumv += imginl[i+ind-radius,j] * kernel[k]
				ind += 1
			imgoutl[i,j] = sumv
		

		# Zero rightmost columns 
		for i in range(ncols - radius, ncols):
			imgoutl[i,j] = 0.

	return np.array(imgout)



#*********************************************************************
#* _convolveImageVert
#*

def _convolveImageVert(imgin, kernel):

	imgin = Image.fromarray(imgin)
	radius = len(kernel) / 2;
	imgout = Image.new("F", imgin.size)
	imgoutl = imgout.load()
	imginl = imgin.load()
	ncols, nrows = imgin.size

	# Kernel width must be odd
	assert len(kernel) % 2 == 1

	# Must read from and write to different images
	#assert(imgin != imgout);

	# Output image must be large enough to hold result
	#assert(imgout->ncols >= imgin->ncols);
	#assert(imgout->nrows >= imgin->nrows);

	# For each column, do ... 
	for i in range(ncols):

		# Zero topmost rows 
		for j in range(radius):
			imgoutl[i,j] = 0.

		# Convolve middle rows with kernel 
		for j in range(radius,nrows - radius):

			sumv = 0.
			ind = 0
			for k in range(len(kernel)-1,-1,-1):
				sumv += imginl[i,j+ind-radius] * kernel[k]
				ind += 1
			imgoutl[i,j] = sumv

		# Zero bottommost rows 
		for j in range(nrows - radius,nrows):
			imgoutl[i,j] = 0.
		

		#ptrcol++;
		#ptrout -= nrows * ncols - 1;


	return np.array(imgout)


#*********************************************************************
#* _convolveSeparate
#*

def _convolveSeparate(imgin,horiz_kernel,vert_kernel):

	if useScipyConvolution:
		#Do convolution using scipy (faster)
		tmpimg = scipy.ndimage.filters.convolve1d(imgin, horiz_kernel, axis = 1)
		imgout = scipy.ndimage.filters.convolve1d(tmpimg, vert_kernel, axis = 0)
		return imgout

	# Do convolution in native code (slower)
	tmpimg = _convolveImageHoriz(imgin, horiz_kernel)
	imgout = _convolveImageVert(tmpimg, vert_kernel)
	return imgout


#*********************************************************************
#* KLTComputeGradients
#*

def KLTComputeGradients(img, sigma):
				
	# Output images must be large enough to hold result 
	#assert(gradx->ncols >= img->ncols);
	#assert(gradx->nrows >= img->nrows);
	#assert(grady->ncols >= img->ncols);
	#assert(grady->nrows >= img->nrows);

	# Compute kernels, if necessary 
	global cachegauss, cachegaussderiv, cached_sigma_last
	if abs(sigma - cached_sigma_last) > 0.05:
		gauss_kernel, gaussderiv_kernel = _computeKernels(sigma)
	else:
		gauss_kernel, gaussderiv_kernel = cachegauss, cachegaussderiv
	
	#print(gauss_kernel)
	#plt.plot(gauss_kernel)
	#plt.show()

	gradx = _convolveSeparate(img, gaussderiv_kernel, gauss_kernel)
	grady = _convolveSeparate(img, gauss_kernel, gaussderiv_kernel)

	return gradx, grady

#*********************************************************************
#* KLTComputeSmoothedImage
#*

def KLTComputeSmoothedImage(img,sigma):

	# Compute kernel, if necessary; gauss_deriv is not used
	global cachegauss, cachegaussderiv, cached_sigma_last
	if cached_sigma_last is None or abs(sigma - cached_sigma_last) > 0.05:
		gauss, gaussderiv = _computeKernels(sigma)
	else:
		gauss, gaussderiv = cachegauss, cachegaussderiv

	smooth = _convolveSeparate(img, gauss, gauss)
	return smooth





