class Starbot
  class Contact
    
    attr_accessor :id, :alias, :status, :online
    
    # [nil, String, Object] room - in some IM systems some contacts are not directly addressable
    # outside of a room. A bot that rides on a transport for such a system should set the room
    # attribute of any contact that cannot be addressed outside of the room.
    attr_accessor :room
    
    def initialize(id, alas)
      @id = id
      @alias = alas
    end # initialize(id, alas)
    
    def is_authorized?
      @status == :authorized
    end # is_authorized?

    def to_s
      @alias.nil? || @alias.empty? ? @id : @alias
    end # to_s
    
  end # class::Contact
end # class::Starbot