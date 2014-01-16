require 'starbot/room'

class Starbot
  class RoomList
    # [Hash] rooms index by id
    attr_reader :rooms
    
    def initialize
      @rooms = Hash.new { |hash, rid| hash[rid] = Room.new(rid, "", [], nil) }
    end # initialize
    alias :all :rooms
    
    def values
      @rooms.values
    end # values
    def keys
      @rooms.keys
    end # keys
    
    def leave(rid)
      return true unless rooms.keys.include?(rid)
      rooms.delete(rid)
      rid
    end # leave(rid)
    
    # Creates a room or returns one that has already been created
    # @param [String] id
    # @param [String] alas the alias
    # @param [[Contacts]] users
    # @param [DateTime] timestamp
    def create(id, alas, users, timestamp)
      room = rooms[id]
      room.alias = alas unless alas.nil? || alas.empty?
      room.users = users unless users.nil? || users.empty?
      room.timestamp = timestamp unless timestamp.nil?
      room
    end # create(id, alas, users)
    
    # Finds a room by alias or id
    # @param [String] qry
    # @return [Room, nil]
    def find(qry)
      find_by_alias(qry) || find_by_id(qry) || find_by_jid(qry)
    end # find(qry)
    
    # Find the a room by the given id
    # @param [String] rid
    def find_by_id(rid)
      return nil unless rooms.keys.include?(rid)
      rooms[rid]
    end # find_by_id(cid)

    # Finds a XMPP room by JID (Jabber ID)
    # @param [String] qry
    # @return [Room, nil]
    def find_by_jid(qry)
      rooms.values.find {|r| r.id.is_a?(Jabber::JID) && qry.include?(r.id.node) }
    end # find_by_jid(qry)
    
    # Find the first room that has the given alias
    # @param [String] alas
    def find_by_alias(alas)
      rooms.values.find{|r| r.alias == alas }
    end # find_by_alias(alas)

    # Find rooms that include the specified user
    # @param [Contact] user
    def find_with_user(user)
      rooms.values.select{|r| r.users.include?(user) }
    end # find_with_user(user)
    
    # Find rooms that conatin just the specified user.
    # @param [Contact] user
    def find_with_only_user(user)
      uid = user.is_a?(::Starbot::Contact) ? user.id : user
      rooms.values.select{|r| r.users.count == 2 && r.users.map{|u| u.id }.include?(uid) }
    end # find_with_only_user(user)
  end # class::RoomList
end # class::Starbot