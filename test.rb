require './lib'
require 'pry'
datapath = './testdata/Area40000.gwy'
gwy1 = Gwyfile.new(datapath)
binding.pry