----------------------------------------------------------------------
-- This script demonstrates how to load the Face Detector 
-- training data, and pre-process it to facilitate learning.
--
-- It's a good idea to run this script with the interactive mode:
-- $ torch -i 1_data.lua
-- this will give you a Torch interpreter at the end, that you
-- can use to analyze/visualize the data you've just loaded.
--
-- Clement Farabet, Eugenio Culurciello
----------------------------------------------------------------------

require 'torch'   -- torch
require 'image'   -- to visualize the dataset
require 'nnx'      -- provides a normalization operator

local opt = opt or {
   visualize = true,
   size = 'small',
   patches='all'
}

print ('patches: ', opt.patches)

----------------------------------------------------------------------
print '==> downloading dataset'

-- Here we download dataset files. 

-- Note: files were converted from their original Matlab format
-- to Torch's internal format using the mattorch package. The
-- mattorch package allows 1-to-1 conversion between Torch and Matlab
-- files.

local www = 'http://data.neuflow.org/data/'
local train_dir = '../../datasets/faces_cut_yuv_32x32/'
local tar = 'faces_cut_yuv_32x32.tar.gz'

-- file from: http://data.neuflow.org/data/faces_cut_yuv_32x32.tar.gz
if not paths.dirp(train_dir) then
   os.execute('mkdir -p ' .. train_dir)
   os.execute('cd ' .. train_dir)
   os.execute('wget ' .. www .. tar)
   os.execute('tar xvf ' .. tar)
end

if opt.patches ~= 'all' then
   opt.patches = math.floor(opt.patches/3)
end

----------------------------------------------------------------------
print '==> loading dataset'

-- We load the dataset from disk
torch.setdefaulttensortype('torch.DoubleTensor')

-- Faces:
dataFace = nn.DataSet{dataSetFolder=train_dir..'face', 
                      cacheFile=train_dir..'face',
                      nbSamplesRequired=opt.patches,
                      channels=1}
dataFace:shuffle()

-- Backgrounds:
dataBG = nn.DataSet{dataSetFolder=train_dir..'bg',
                    cacheFile=train_dir..'bg',
                    nbSamplesRequired=opt.patches,
                    channels=1}
dataBGext = nn.DataSet{dataSetFolder=train_dir..'bg-false-pos-interior-scene',
                       cacheFile=train_dir..'bg-false-pos-interior-scene',
                       nbSamplesRequired=opt.patches,
                       channels=1}
dataBG:appendDataSet(dataBGext)
dataBG:shuffle()

-- pop subset for testing
testFace = dataFace:popSubset{ratio=opt.ratio}
testBg = dataBG:popSubset{ratio=opt.ratio}

-- training set
trainData = nn.DataList()
trainData:appendDataSet(dataFace,'Faces')
trainData:appendDataSet(dataBG,'Background')

-- testing set
testData = nn.DataList()
testData:appendDataSet(testFace,'Faces')
testData:appendDataSet(testBg,'Background')


torch.setdefaulttensortype('torch.FloatTensor')

----------------------------------------------------------------------
-- convert to new format  and training scripts:

-- training/test size
local trsize = trainData:size()
local tesize = testData:size()

trainData2 = {
   data = torch.Tensor(trsize, 1, 32, 32),
   labels = torch.Tensor(trsize),
   size = function() return trsize end
}

testData2 = {
      data = torch.Tensor(tesize, 1, 32, 32),
      labels = torch.Tensor(tesize),
      size = function() return tesize end
   }

for i=1,trsize do
   trainData2.data[i] = trainData[i][1]:clone()
   trainData2.labels[i] = trainData[i][2][1]
end
for i=1,tesize do
   testData2.data[i] = testData[i][1]:clone()
   trainData2.labels[i] = testData[i][2][1]
end

-- relocate pointers:
trainData = nil
testData = nil
trainData = trainData2
testData = testData2


----------------------------------------------------------------------
print '==> preprocessing data'

-- Preprocessing requires a floating point representation (the original
-- data is stored on bytes). Types can be easily converted in Torch, 
-- in general by doing: dst = src:type('torch.TypeTensor'), 
-- where Type=='Float','Double','Byte','Int',... Shortcuts are provided
-- for simplicity (float(),double(),cuda(),...):

trainData.data = trainData.data:float()
testData.data = testData.data:float()

-- We now preprocess the data. Preprocessing is crucial
-- when applying pretty much any kind of machine learning algorithm.

-- For natural images, we use several intuitive tricks:
--   + images are mapped into YUV space, to separate luminance information
--     from color information
--   + the luminance channel (Y) is locally normalized, using a contrastive
--     normalization operator: for each neighborhood, defined by a Gaussian
--     kernel, the mean is suppressed, and the standard deviation is normalized
--     to one.
--   + color channels are normalized globally, across the entire dataset;
--     as a result, each color component has 0-mean and 1-norm across the dataset.

-- Convert all images to YUV
-- print '==> preprocessing data: colorspace RGB -> YUV'
-- for i = 1,trainData:size() do
--    trainData.data[i] = image.rgb2yuv(trainData.data[i])
-- end
-- for i = 1,testData:size() do
--    testData.data[i] = image.rgb2yuv(testData.data[i])
-- end

-- Name channels for convenience
local channels = {'y'}--,'u','v'}

-- Normalize each channel, and store mean/std
-- per channel. These values are important, as they are part of
-- the trainable parameters. At test time, test data will be normalized
-- using these values.
print '==> preprocessing data: normalize each feature (channel) globally'
local mean = {}
local std = {}
for i,channel in ipairs(channels) do
   -- normalize each channel globally:
   mean[i] = trainData.data[{ {},i,{},{} }]:mean()
   std[i] = trainData.data[{ {},i,{},{} }]:std()
   trainData.data[{ {},i,{},{} }]:add(-mean[i])
   trainData.data[{ {},i,{},{} }]:div(std[i])
end

-- Normalize test data, using the training means/stds
for i,channel in ipairs(channels) do
   -- normalize each channel globally:
   testData.data[{ {},i,{},{} }]:add(-mean[i])
   testData.data[{ {},i,{},{} }]:div(std[i])
end

-- -- Local normalization
-- print '==> preprocessing data: normalize all three channels locally'

-- -- Define the normalization neighborhood:
-- local neighborhood = image.gaussian1D(11)

-- -- Define our local normalization operator (It is an actual nn module, 
-- -- which could be inserted into a trainable model):
-- local normalization = nn.SpatialContrastiveNormalization(1, neighborhood, 1):float()

-- -- Normalize all channels locally:
-- for c in ipairs(channels) do
--    for i = 1,trainData:size() do
--       trainData.data[{ i,{c},{},{} }] = normalization:forward(trainData.data[{ i,{c},{},{} }])
--    end
--    for i = 1,testData:size() do
--       testData.data[{ i,{c},{},{} }] = normalization:forward(testData.data[{ i,{c},{},{} }])
--    end
-- end

----------------------------------------------------------------------
print '==> verify statistics'

-- It's always good practice to verify that data is properly
-- normalized.

for i,channel in ipairs(channels) do
   local trainMean = trainData.data[{ {},i }]:mean()
   local trainStd = trainData.data[{ {},i }]:std()

   local testMean = testData.data[{ {},i }]:mean()
   local testStd = testData.data[{ {},i }]:std()

   print('training data, '..channel..'-channel, mean: ' .. trainMean)
   print('training data, '..channel..'-channel, standard deviation: ' .. trainStd)

   print('test data, '..channel..'-channel, mean: ' .. testMean)
   print('test data, '..channel..'-channel, standard deviation: ' .. testStd)
end

----------------------------------------------------------------------
print '==> visualizing data'

-- Visualization is quite easy, using image.display(). Check out:
-- help(image.display), for more info about options.

if opt.visualize then
   local first256Samples_y = trainData.data[{ {1,256},1 }]
   image.display{image=first256Samples_y, nrow=16, legend='Some training examples: Y channel'}
end

-- Exports
return {
   trainData = trainData,
   testData = testData,
   mean = mean,
   std = std
}

