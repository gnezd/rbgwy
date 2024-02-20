require './lib'
require 'pry'
datapath = './testdata/Area40000.gwy'
gwy1 = GwyFile.new(datapath)
gwy1.plot
#binding.pry