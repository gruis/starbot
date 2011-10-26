require 'starbot/contact'

class Starbot
  class Room
    attr_accessor :id, :alias, :users, :timestamp
    # Password to use to access the room
    attr_accessor :password
    
    def initialize(id, alas, users, timestamp)
      @id        = id
      @alias     = alas
      @users     = users
      @timestamp = timestamp
    end # initialize(id, alas)

    def to_s
      @alias.nil? || @alias.empty? ? @id : @alias
    end # to_s
  end # class::Room
end # class::Starbot
