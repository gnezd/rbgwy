class Gwyfile
  attr_accessor :name, :data
  def initialize(path)
    raw = File.open(path, 'rb').read
    puts "filesize: #{raw.size}"
    raise "File header didn't seem like a gwy file" unless raw.slice!(0,4) == 'GWYP'
    @data = GwyObject.new(raw)

  end
end


# Deserialize Gwyobject into Hash
class GwyObject
  attr_accessor :content, :name
  def initialize(raw)
    @content = {}
    @name = raw.slice!(0, raw.index("\0")+1)[0..-2]
    ptr = raw.slice!(0,4).unpack1("L")
    puts "container: #{name}"
    puts "size: #{ptr}"
    puts "remaining raw: #{raw.size}"
    puts "Object size mismatch" unless ptr == raw.size
    
    # Parsing content
    while raw && raw.size > 0
      component_name = raw.slice!(0, raw.index("\0")+1)[0..-2]
      component_type = raw.slice!(0)
      puts "Type: #{component_type}"
      puts "remaining size #{raw.size}"
      
      case component_type
      when 'b' # Boolean 1B
        component_content = raw.slice!(0).unpack1("c")
      when 'c' # Char 1B
        component_content = raw.slice!(0).unpack1("c")
      when 'C' # Array of char 1B
        array_length = raw.slice!(0, 4).unpack1("L")
        component_content = raw.slice!(0, array_length).unpack("c")
      when 'i' # Int 4B
        component_content = raw.slice!(0, 4).unpack1("l")
      when 'I' # Array of int 4B
        array_length = raw.slice!(0, 4).unpack1("L")
        component_content = raw.slice!(0, array_length*4).unpack("l")
      when 'q' # Int 8B
        component_content = raw.slice!(0, 8).unpack1("q")
      when 'Q' # Array of int 8B
        array_length = raw.slice!(0, 4).unpack1("L")
        component_content = raw.slice!(0, array_length*8).unpack("q")
      when 'd' # IEEE 754 double float 8B
        component_content = raw.slice!(0, 8).unpack1("d")
      when 'D' # Array of IEEE 754 double float 8B
        puts "type D"
        array_length = raw.slice!(0, 4).unpack1("L")
        puts "of #{array_length}"
        component_content = raw.slice!(0, array_length*8).unpack("d")
      when 's' # UTF-8 string \0 terminated
        component_content = raw.slice!(0, raw.index("\0")+1)[0..-2]
      when 'S' # Array of UTF-8 string \0 terminated
        array_length = raw.slice!(0, 4).unpack1("L")
        component_content = Array.new(array_length)
        (0..array_length-1).each do |i|
          component_content[i] = raw.slice!(0,raw.index("\0")+1)[0..-2]
        end
      when 'o' # GwyObject
        puts "obj!"
        component_content, raw = GwyObject.new(raw)
      when 'O' # Array of GwyObject
        puts "Array of obj..."
        array_length = raw.slice!(0, 4).unpack1("L")
        component_content = Array.new(array_length)
        (0..array_length-1).each do |i|
          component_content, raw = Gwyfile.new(raw)
        end
      else
        raise "what?? #{component_type}"
      end
      
      # Asserting component_name to be valid hash key. Might need to sanitize.
      puts "component: #{component_name} - #{component_content}"
      @content['component_name'] = component_content
    end
    return self, raw
  end
end