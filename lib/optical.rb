# Copyright (c) 2014, Stuart Glenn, OMRF
# Distributed under a BSD 3-Clause
# Full license available in LICENSE.txt distributed with this software

require "shellwords"
require "optical/version"
require "optical/configuration"
require "optical/library"
require "optical/sample"
require "optical/chip_analysis"
require "optical/filters"
require "optical/chip_bam_visual"
require "optical/bam"
require "optical/peak_caller"
require "optical/checkpointable"
require "optical/final_report"
require "optical/igv_session"

module Optical
  def self.threader(enum,on_error)
    workers = []
    enum.each do |item|
      workers << Thread.new do
        yield item
      end
    end
    exits = []
    workers.each do |w|
      begin
        exits << w.value()
      rescue => err
        exits << false
        on_error.call("Exception in a worker thread: #{err} (#{err.backtrace.first}")
      end
    end

    if exits.any?{|e| !e}
      on_error.call("A thread failed")
      return false
    end
    return true
  end
end
