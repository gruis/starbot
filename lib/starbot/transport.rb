class Starbot
  module Transport
    def setup(bot, defroom, opts = {})
      @bot       = bot
      @defroom   = defroom
      
      opts       = {:leave_one_on_one => false, :host => '127.0.0.1', :port => 5222}.merge(opts)
      opts[:log] = Logger.new(STDERR) unless opts[:log].is_a?(Logger)
      @logger    = opts[:log]
      @opts      = opts
      
      register_sayto
      register_say
      register_sayloud
      register_sayloudto
      register_mkroom
      register_leave
      register_invite
      self
    end # setup(opts = {})
    
    # Say something to a contact
    # 
    # @return [nil] it's important that nil be the return value
    def sayto_contact(contact, msg)
      @logger.debug("sayto_room(#{contact.inspect}, #{msg})")
      raise NotImplementedError
    end # sayto_contact(contact, msg)

    # Say somethign to a room
    # @return [nil] it's important that nil be the return value
    def sayto_room(room, msg)
      @logger.debug("sayto_room(#{room.inspect}, #{msg})")
      raise NotImplementedError
    end # sayto_room(room, msg)
    
    # Start a room with one or more users
    # @param [String] name
    # @param [String] uid
    # @param [Strings] uids
    # @yield [rid, props]
    # @yieldparam [String,] rid Id of the room
    # @yieldparam [Hash] props :topic, :timestamp, :members
    def start_room(name, uid, *uids)
      raise NotImplementedError
    end # start_room(uid, *uids)
    
    def leave_room(room_id)
      raise NotImplementedError
    end # leave_room(room_id)
    
    def invite_room(rid, user, *users, &blk)
      raise NotImpelementedError
    end # invite_room(rid, user, *users, &blk)
    
    # Yields to the provided block when the given user has authorized
    # this account to contact it.
    # @param [String] user_id
    # @yield once the user_id has authorized this connection
    def when_authorized(user_id)
      yield if block_given?
    end # when_authorized(user_id)
    
    
    

    def register_say
      @bot.on(:say) { |msg| sayto_contact(@defroom, msg) unless msg.nil? or msg.empty? }
    end # register_say
    
    # register the sayto handler
    def register_sayto
      @bot.on(:sayto) do |user_room, msg|
        @logger.debug("sayto(#{user_room.inspect}, #{msg})")
        report_any_errors(msg) do
          unless msg.nil? || msg.empty?
            case user_room
            when ::Starbot::Contact
              when_authorized(user_room.id) { sayto_contact(user_room, msg) }
            when ::Starbot::Room
              sayto_room(user_room, msg)
            when nil
              sayto_room(@defroom, "Method sayto was called with a nil value for 'to': \n#{msg}")
            else
              raise "Can't sayto anything except a Contact or Room"
            end # user_room
          end # msg.nil? || msg.empty?
        end # report_any_errors(msg)
      end #  |user_room, msg|
      
      self
    end # register_sayto
    
    def register_sayloud
      @bot.on(:sayloud) { |msg| @bot.say(msg) unless msg.nil? || msg.empty? }
    end # register_sayloud
    
    def register_sayloudto
      @bot.on(:sayloudto) { |u,msg| @bot.sayto(u, msg) unless msg.nil? || msg.empty? }
    end # register_sayloud
    
    def register_leave
      @bot.on(:leave) { |room| leave_room(room.id) }
    end # register_leave
    
    def register_mkroom
      @bot.on(:mkroom) do |alas, *users|
        users = users.clone
        blk   = users.last.is_a?(Proc) ? users.pop : nil
        users = users.map{|u| u.id }
        start_room(alas, *users) do |rid, props|
          blk.call(@bot.room_list.create(rid, props[:topic], props[:members], props[:timestamp])) unless blk.nil?
        end #  |rid, props|
      end # |alas, *users|
    end # register_mkroom
    
    def register_invite
      @bot.on(:invite) do |room, *users|
        blk = users.last.is_a?(Proc) ? users.pop : nil
        users = users.clone.map{|u| u.id }
        block_given? ? invite_room(room.id, users[0], *users[1..-1], &blk) : invite_room(room.id, users[0], *users[1..-1])
      end #  |room, *users|
    end # register_invite
    
    # Register a callback with the underlying transport to recieve messages
    # then send them to the Starbot for routing.
    # @example
    #   def watch_msgs
    #     @client.add_message_callback do |m|
    #       @bot.route(m.body, ::Starbot::Msg.new(m.body, @bot.contact_list.create(m.from, ""), Time.new))
    #     end # |m|
    #   end # watch_msgs
    def watch_msgs
      raise NotImpelementedError
    end # watch_msgs
    
  private
    attr_reader :bot
    
    
    def report_any_errors(msg = nil)
      begin
        yield if block_given?
      rescue Exception => e
        report_exception(e, msg)
      end # begin
    end # report_any_errors
    
    def report_exception(e, msg = nil)
      begin
        prefix = msg.nil? ? "" : "In response to '#{msg.txt}' from #{msg.contact.id}, "
        basic_msg = "I've encountered an error: \n#{e}\n  #{e.backtrace.join("\n  ")}"

        # put an error in the log
        @logger.error("#{prefix}#{basic_msg}")
        
        # tell the one asking the question that we've hit an error
        sayto(msg.room || msg.contact, "I've encountered an error: #{e}") unless msg.nil?
        # @todo end the conversation ....
        
        # tell the default room that we've hit an error and provide a backtrace
        sayto_contact(@defroom, "#{prefix}#{basic_msg}")

      rescue Exception => my_e
        puts "Error while reporting another error: #{my_e}\n#{my_e.backtrace}"
        puts "The other error: #{e}\n  #{e.backtrace.join("\n      ")}"
      end # begin
    end # report_exception(e)
    
  end # module::Transport
end # class::Starbot