# Copyright (c) 2014, Stuart Glenn, OMRF
# Distributed under a BSD 3-Clause
# Full license available in LICENSE.txt distributed with this software

require 'erb'

class Optical::FinalReport
  def initialize(conf)
    @conf = conf
  end


  def save_report(file)
    puts render()
    return true
  end

  private

  def render
    ERB.new(get_template().chomp,0,'-').result(binding)
  end

  def get_template()
    <<EOF
Optical Run Report
==================

Results from OPtICAL version <%= Optical::VERSION %> on <%= Time.now().iso8601() %>

Peaks
-----

<% @conf.peak_callers do |p| -%>
Caller <%= p -%> had <%= p.num_peaks() -%> peaks
<% end -%>

BAMs
----
EOF
  end
end
