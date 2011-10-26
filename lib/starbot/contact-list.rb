require 'starbot/contact'

class Starbot
  class ContactList
    # [Hash] the contact indexed by id
    attr_reader :contacts
    
    def initialize
      @contacts = Hash.new { |hash, cid| hash[cid] = Contact.new(cid, "") }
    end # initialize
    alias :all :contacts
    
    def values
      @contacts.values
    end # values
    def keys
      @contacts.keys
    end # keys
    
    # Creates a contact of returns one that has already been created
    def create(id, alas = nil)
      contact = contacts[id]
      unless alas.nil? || alas.empty?
        contact.alias = alas
      end # alas.nil? || alas.empty?
      contact
    end # create(id, alas = nil)
    
    # Finds a contact by alias or id
    # @param [String] qry
    # @option [String] :room room id
    # @return [Room, nil]
    def find(qry, opts = {})
      find_by_alias(qry, opts[:room]) || find_by_id(qry)
    end # find(qry)
    
    def find_by_id(cid)
      return nil unless contacts.keys.include?(cid)
      contacts[cid]
    end # find_by_id(cid)
    
    # Find a contact with an alias and optionally limit the search to a particular room
    # @param [String] alas
    # @param [String] room id of the room
    def find_by_alias(alas, room = nil)
      return contacts.values.find{|c| c.alias == alas } if room.nil?
      contacts.values.find { |c| c.alias == alas ? c.room && (c.room.id == room) : false }.tap{|c| puts c.nil? ? "nil" : "*** returning #{c.id} : #{c.room}"}
    end # find_by_alias(alas)
    
  end # class::ContactList
end # class::Starbot