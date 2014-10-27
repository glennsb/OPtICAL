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

  def make_table(lines)
    maxes = Array.new(lines[0].size,0)
    lines.each do |l|
      l.each_with_index do |s,i|
        maxes[i] = s.length if s.length > maxes[i]
      end
    end
    lines.insert(1,%w(-)*lines[0].size)
    lines[1].each_with_index do |l,i|
      lines[1][i] = l*maxes[i]
    end
    lines.map do |l|
      line = "|"
      l.each_with_index do |s,i|
        line += " #{s.ljust(maxes[i]," ")} |"
      end
      line
    end.join("\n")
  end

  def report_peaks()
    lines = [%W(Name Caller Type File Peaks)]
    @conf.peak_callers do |p|
      paths = p.peak_path
      nums = p.num_peaks
      paths.size.times do |i|
        line = [p.to_s, p.class.to_s]
        if paths.size > 1 && i == 0
          line << "conservative"
        elsif paths.size > 1 && i == 1
          line << "optimal"
        else
          line << "*not idr*"
        end
        path = "[#{File.basename(paths[i])}](#{paths[i]})"
        line += [path,nums[i].to_s]
        lines << line
      end
    end
    make_table(lines)
  end

  def report_bams()
    lines = [%W(Bam Fragment Alignments)]
    samples = @conf.peak_callers.map {|pc| pc.treatments + pc.controls}.flatten.compact.uniq
    samples.map {|s| [s.analysis_ready_bam,s]}.each do |bam,s|
      name = File.join( File.basename(File.dirname(bam.path)), File.basename(bam.path) )
      path = "[#{name}](#{bam.path})"
      lines << [path, bam.fragment_size.to_s, bam.num_alignments.to_s]
    end
    make_table(lines)
  end

  def report_libraries()
    lines = [%W(Library)]
    @conf.samples do |s|
      s.libraries.each do |lib|
        lines << [lib.fastq_paths.join(",")]
      end
    end
    make_table(lines)
  end

  def render
    ERB.new(get_template().chomp,0,'-').result(binding)
  end

  def get_template()
    <<EOF
OPtICAL Run Report
==================

Results from OPtICAL version <%= Optical::VERSION %> on <%= Time.now().iso8601() %>

Peaks
-----

<%= report_peaks() %>

BAMs
----

<%= report_bams() %>

Libraries
---------

<%= report_libraries() %>
EOF
  end
end
