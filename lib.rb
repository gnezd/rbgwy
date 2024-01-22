class Gwyfile
  attr_accessor :name, :data
  def initialize(path)
    raw = File.open(path, 'rb').read
    puts "filesize: #{raw.size}" if $debug
    raise "File header didn't seem like a gwy file" unless raw.slice!(0,4) == 'GWYP'
    @data, raw = GwyObject.new(raw, 'GWY')

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