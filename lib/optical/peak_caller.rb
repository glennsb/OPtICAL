# Copyright (c) 2014, Stuart Glenn, OMRF
# Distributed under a BSD 3-Clause
# Full license available in LICENSE.txt distributed with this software

class Optical::PeakCaller

  Dir[File.join( File.dirname(__FILE__),"peak_callers","*.rb")].each do |rb|
    require rb
  end

  def self.create(name,opts)
    klass = "Optical::PeakCaller::#{opts[:algorithm]}" unless klass =~ /::/
    klass = Kernel.const_get(klass)
    klass.new(name,opts)
  end

  attr_reader :cmd_args, :name

  def initialize(name,opts)
    @name = name
    @cmd_args = opts[:args]
    @pairs = []
    opts[:pairs].each do |p|
      @pairs << p
    end
  end

  def size()
    @pairs.size
  end

  def pairs()
    return @pairs.to_enum unless block_given?
    @pairs.each do |p|
      yield p
    end
  end
end
