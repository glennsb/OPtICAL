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
      p.peak_bed_path.map do |b|
        NamedPath.new(File.basename(b,".bed"),b)
      end
    end.flatten
  end

  def tdfs()
    samples = []
    @conf.peak_callers.each do |pc|
      samples << if 1 == pc.treatments.size
                   pc.treatments
                 else
                   @conf.sample(pc.treatments.map {|s| s.name}.join(" and ").tr(" ","_") + "_pooled")
                 end
      next if 0 == pc.controls.size || nil == pc.controls[0]
      samples << if 1 == pc.controls.size
                   pc.controls
                 else
                   @conf.sample(pc.controls.map {|s| s.name}.join(" and ").tr(" ","_") + "_pooled")
                 end
    end
    #samples = @conf.peak_callers.map {|pc| pc.treatments + pc.controls}.flatten.compact.uniq
    samples.flatten.compact.uniq.map do |s|
      if s && s.bam_visual
        NamedPath.new(File.basename(s.bam_visual.tdf_wig_path,".tdf"), s.bam_visual.tdf_wig_path)
      end
    end.compact
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
