# Copyright (c) 2014, Stuart Glenn, OMRF
# Distributed under a BSD 3-Clause
# Full license available in LICENSE.txt distributed with this software

module Optical::Filters
  Dir[File.join( File.dirname(__FILE__),"filters","*.rb")].each do |rb|
    require rb
  end
end
