class Starbot
  class Msg
    attr_reader :txt, :from, :timestamp, :room
    # Anything extra you want to add to the message
    attr_accessor :extra
    
    def initialize(txt, fuser, timestamp = nil, room = nil)
      @txt       = txt
      @from      = fuser
      @room      = room
      @timestamp = timestamp || Time.new
    end # initialize(txt, fuser, timestamp)
    alias :contact :from
    
    def to_s
      @txt
    end # to_s
    
    def to_i
      @txt.to_i
    end # to_i
    
    def ==(other)
      other.is_a?(String) ? @txt == other : super(other)
    end # ==(other)
    
    def downcase
      @txt.downcase
    end # downcase
    
    def strip
      @txt.strip
    end # strip
    
    def empty?
      @txt.empty?
    end # empty?
    
    def match(m, &blk)
      block_given? ? @txt.match(m, &blk) : @txt.match(m)
    end # match(m)
  end # class::Msg
end # class::Starbot
