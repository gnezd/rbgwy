class GwyFile
  attr_accessor :name, :data, :path
  def initialize(path)
    raise "File #{path} doesn't exist!" unless File.exist? path
    @path = path
    @name = File.basename(@path, '.gwy')
    raw = File.open(path, 'rb').read
    puts "filesize: #{raw.size}" if $debug
    raise "File header didn't seem like a gwy file" unless raw.slice!(0,4) == 'GWYP'
    @data, raw = GwyObject.new(raw, 'GWY')

  end
  
  # Plot GwyFile and return path to plot
  # options Hash convention follows spect_toolkit
  def plot(options = {})

    if options[:out_dir]
      out_dir = options[:out_dir] 
    else
      out_dir = './plots'
    end

    if @data.keys.include? "/#{options[:channel]}/data"
      channel = "/#{channel}"
    else
      puts "Selected channel #{options[:channel]} not found, plotting channel 0 instead."if options[:channel]
      channel = "/0"
    end
    
    # Extract data needed
    plot_data = @data[channel+'/data']['data']
    xres = @data[channel+'/data']['xres']
    yres = @data[channel+'/data']['yres']

    # Physical width and height
    p_width = @data[channel+'/data']['yreal']
    p_height = @data[channel+'/data']['xreal']

    # Data value limit
    min = @data[channel+'/base/min']
    max = @data[channel+'/base/max']
    
    # min/max not specified? Compute from data
    if !min || !max
      # Numeric thresholding
      if (options[:thresholding].is_a? Numeric) && options[:thresholding] < 1
        sorted = data[channel+'/data']['data'].minmax.sort
        min = sorted[0]
        max = sorted[sorted.size*options[:thresholding]]
        puts "Activating automatic higher thresholding: #{min} - #{max}"
      elsif options[:thresholding] =~ /\d\-\d/
        range = options[:thresholding].split('-').map{|str| str.to_f}
        puts range.join '-'
        sorted = data[channel+'/data']['data'].sort
        min = sorted[(sorted.size*range[0]).to_i]
        max = sorted[(sorted.size*range[1]).to_i]
        puts "Activating automatic range thresholding: #{min} - #{max}"
      else
        min, max = data[channel+'/data']['data'].minmax
      end
    end

    # Misc metadata
    mode = @data[channel+'/meta']['ImagingMode']
    freq = @data[channel+'/meta']['DriveFrequency']
    lossfreq = @data[channel+'/meta']['LossTanFreq1']
    lossphase = @data[channel+'/meta']['LossTanPhase1']
    amplitude = @data[channel+'/meta']['DriveAmplitude']
    data_history = @data[channel+'/data/log']['strings']
    plot_title = @data[channel+'/data/title']

    FileUtils.mkdir_p(out_dir)
    plot_basename = "#{@name}-#{plot_title}"
    gplot = File.open("#{out_dir}/#{plot_basename}.gplot", 'w')

    gplot.puts "$image<<EOIM"
    (0..yres-1).each do |y|
      gplot.puts plot_data[y*xres .. (y+1)*xres - 1].join " "
    end
    gplot.puts "EOIM"

    # Calculate nice xtic ytic
    order_of_mag = (Math.log10(p_width).floor)
    x_nice_scale = (p_width/(10 ** order_of_mag) * 10).to_i * (10**order_of_mag) / 10 # Math.ceil, scale can shrink but not swell
    y_nice_scale = (p_height/(10 ** order_of_mag) * 10).to_i * (10**order_of_mag) / 10 # Considered nice down to 1 digit float
    xtics = []
    ytics = []

    if order_of_mag <= -7 # Use nanometer
      unitstr = "nm"
      scale_factor = 1E9
    else #use μm
      unitstr = "μm"
      scale_factor = 1E6
    end

    # Cut five slices of the scales
    (0..5).each do |ith|
      xtic_val = (ith * x_nice_scale * scale_factor / 5.0)
      xtic_pos = (ith * x_nice_scale / 5.0)/(p_width / xres.to_f)
      xtics.push "\"#{"%.3g" % xtic_val}\" #{"%.3g" % xtic_pos}"

      ytic_val = (ith * y_nice_scale * scale_factor / 5.0)
      ytic_pos = (ith * y_nice_scale / 5.0)/(p_height / yres.to_f)
      ytics.push "\"#{"%.3g" % ytic_val}\" #{"%.3g" % ytic_pos}"
    end


    # cbtic
    cb_cuts = 5 # n color bar cuts by n-1 cbtics
    # Use nm for height
    if Math.log10([max.abs, min.abs].max) < -7 # Accomodate negative heights
      cb_scale_factor = 1E9
      cb_unit = 'nm'
    else # μm`
      cb_scale_factor = 1E6
      cb_unit = 'μm'
    end
    # Construct cbtics string. 究極一行文 as always
    cbtics = (0..cb_cuts).map {|ith| "\"#{"%.3g" % ((min+(max-min)*ith/cb_cuts)*cb_scale_factor)}\" #{min+(max-min)*ith/cb_cuts}"} # 3 significant digits

# Plot terminal: only png for now
    gpheadder=<<EOGPH
set terminal png size 800,800
set size ratio -1
set output '#{out_dir}/#{plot_basename}.png'
set palette rgbformulae 34,35,36; set title 'rgbformulae 34,35,36'

set title '#{@name.gsub('_', '\_')}'
unset key
set xtics out (#{xtics.join(", ")})
set ytics out (#{ytics.join(", ")})
set xlabel '#{unitstr}'

set cbrange [#{min}:#{max}]
set cbtics (#{cbtics.join(", ")})
set cblabel '#{cb_unit}' rotate by 0
plot $image matrix w image
EOGPH

    gplot.puts gpheadder
    gplot.close

    `gnuplot '#{out_dir}/#{plot_basename}.gplot'`
  end
end


# Deserialize Gwyobject into Hash
class GwyObject
  attr_accessor :content, :name, :type, :leftover
  def initialize(raw, name)
    puts "Initializing GwyObject called #{name}" if $debug
    @name = name
    @content = {}
    @type = raw.slice!(0, raw.index("\0")+1).chop
    @object_length = raw.slice!(0, 4).unpack1("L") # Length in bytes
    @leftover = raw[@object_length..-1]
    thisobj_raw = raw[0..@object_length-1]

    object_length = raw.slice!(0,4).unpack1("L") # Object length in bytes
    puts "obj: #{@name} length: #{@object_length} raw size: #{raw.size}" if $debug
    # Parsing content
    while thisobj_raw.size > 0 # Assumes that deserialize() eventually cuts raw down to ""
      component_name, component_content, thisobj_raw = deserialize(thisobj_raw)
      # Asserting component_name to be valid hash key. Might need to sanitize.
      @content[component_name] = component_content
      puts "Adding key #{component_name} to #{@name}" if $debug
    end
    puts "Finishing obj #{name} deserialization. raw remaining: #{thisobj_raw.size}" if $debug
  end

  # Deserialize single component
  def deserialize(raw)
    puts "Starting deserialize size #{raw.size}" if $debug
    component_name = raw.slice!(0, raw.index("\0")+1).chop
    component_type = raw.slice!(0) 
    puts "Component: #{component_name} Type: #{component_type}" if $debug
    puts "remaining size #{raw.size}" if $debug

    case component_type
    when 'b' # Boolean 1B
      component_content = raw.slice!(0).unpack1("c")

    when 'c' # Char 1B
      component_content = raw.slice!(0).unpack1("c")
    when 'C' # Array of char 1B
      array_length = raw.slice!(0, 4).unpack1("L")
      component_content = raw.slice!(0, array_length).unpack("c*")

    when 'i' # Int 4B
      component_content = raw.slice!(0, 4).unpack1("l")
    when 'I' # Array of int 4B
      array_length = raw.slice!(0, 4).unpack1("L")
      component_content = raw.slice!(0, array_length*4).unpack("l*")

    when 'q' # Int 8B
      component_content = raw.slice!(0, 8).unpack1("q")
    when 'Q' # Array of int 8B
      array_length = raw.slice!(0, 4).unpack1("L")
      component_content = raw.slice!(0, array_length*8).unpack("q*")

    when 'd' # IEEE 754 double float 8B
      component_content = raw.slice!(0, 8).unpack1("d")
    when 'D' # Array of IEEE 754 double float 8B
      array_length = raw.slice!(0, 4).unpack1("L")
      component_content = raw.slice!(0, array_length*8).unpack("d*")

    when 's' # UTF-8 string \0 terminated
      #puts raw.bytes.join " "
      component_content = raw.slice!(0, raw.index("\0")+1).chop
      #puts "string: #{component_content} "
      #puts raw.bytes.join " "
    when 'S' # Array of UTF-8 string \0 terminated
      array_length = raw.slice!(0, 4).unpack1("L")
      component_content = Array.new(array_length)
      (0..array_length-1).each do |i|
        component_content[i] = raw.slice!(0,raw.index("\0")+1).chop
      end

    when 'o' # GwyObject
      puts "Serializing a GwyObj named #{component_name}" if $debug
      component_content= GwyObject.new(raw, component_name)
      raw = component_content.leftover
      puts "Finishes component GwyObject #{component_name} of #{component_content.type}. Remaining raw: #{raw.size}" if $debug
    when 'O' # Array of GwyObject
      # This may not yet be implemented correctly
      # Afterall, who uses a GwyObject array???
      array_length = raw.slice!(0, 4).unpack1("L")
      component_content = Array.new(array_length)
      (0..array_length-1).each do |i|
        component_content[i], raw = GwyObject.new(raw)
      end
    else
      raise "Unrecognized component type #{component_type.unpack1("c").to_s(16)}, eating away the rest of this object"
      raw = "" 
    end
      
    return component_name, component_content, raw
  end

  def inspect
    "Gwyobj name: #{@name}"
  end
  
  # Might have just inherited from Hash ㄏㄏ
  def [](key)
    return @content[key]
  end

  def []=(key, value)
    @content[key] = value
  end

  def keys
    @content.keys
  end
end