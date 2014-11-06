# Copyright (c) 2014, Stuart Glenn, OMRF
# Distributed under a BSD 3-Clause
# Full license available in LICENSE.txt distributed with this software

require 'erb'
require 'pathname'

class Optical::IgvSession
  NamedPath = Struct.new(:name, :path)

  def initialize(conf)
    @conf = conf
    @base_wd = Pathname.new(@conf.output_base)
  end


  def write(file)
    xml = render()
    File.open("#{file}.xml","w") do |out|
      out.puts xml
    end
    return true
  end

  private

  def beds()
    @conf.peak_callers.map do |p|
      NamedPath.new(File.basename(p.peak_bed_path,".bed"),p.peak_bed_path)
    end
  end

  def tdfs()
    samples = @conf.peak_callers.map {|pc| pc.treatments + pc.controls}.flatten.compact.uniq
    samples.map do |s|
      NamedPath.new(File.basename(s.bam_visual.tdf_wig_path,".tdf"), s.bam_visual.tdf_wig_path)
    end
  end

  def genome_name()
    File.basename(@conf.igv_reference,".genome")
  end

  def render
    ERB.new(get_template().chomp,0,'-').result(binding)
  end

  def get_template()
    <<EOF
<?xml version="1.0" encoding="UTF-8" standalone="no"?>
<Global genome="<%= genome_name() -%>" locus="All" version="4">
        <Resources>
                <% for bed in beds() -%>
                <Resource name="<%= bed.name -%>" path="<%= bed.path -%>" />
                <% end -%>
                <% for tdf in tdfs() -%>
                <Resource name="<%= tdf.name -%>" path="<%= tdf.path -%>" />
                <% end -%>
        </Resources>
</Global>
EOF
  end
end
