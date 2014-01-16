require 'rufus/scheduler'
require 'logger'

require 'starbot/errors'
require 'starbot/msg'
require 'starbot/contact-list'
require 'starbot/room-list'
require 'starbot/conversation'
require 'starbot/simple-conversation'


class Starbot
  
  attr_writer :answer_file
  attr_reader :name
  attr_accessor :answer_file, :helpers, :log, :settings, :memoryfile
  
  def initialize(name, *rooms)
    @opts        = rooms.last.is_a?(Hash) ? rooms.pop : {}
    @name        = name || "starbot"
    @memory_lock = Mutex.new
    @memoryfile  = @opts[:memoryfile]
    restore_memories
    @started_at = Time.new
    @room_list       = RoomList.new
    @contact_list    = ContactList.new
    @questions       = {}
    @helpers         = {}
    @ons             = {}
    @akas            = []
    @callbacks       = {}
    self.answer(:default) { "I don't understand" }
    @latest_desc = nil
    @scheduler   = Rufus::Scheduler.new
    @lock        = Mutex.new
    @log         = Logger.new(STDERR)
  end # initialize(*rooms)
  
  def uptime
    Time.new.to_i - @started_at.to_i
  end # uptime

  # Causes starbot to remember a fact. 
  # A remembered fact can be recalled from any conversation and will
  # survive a restart of the bot.
  # @param [String, Symbol] key
  # @param [Object] value
  # @return [Object] value
  def remember(key, value)
    lock_memory do
      @memories[key] = value
      store_memories
    end 
    value
  end # remember(key, value)
  
  # Recal a memory
  # @param [String, Symbol] key
  # @return [Object]
  def recal(key, dflt = nil)
    @memories[key] || dflt
  end # recal(key)
  
  # Forget a memory
  # @param [String, Symbol] key
  # @return [nil]
  def forget(key)
    lock_memory do
      @memories[key] = nil
      store_memories
    end # 
    nil
  end # forget(key)
  
  def contact_list
    @contact_list
  end # contact_list
  def room_list
    @room_list
  end # room_list
  
  # Retrieve all contacts
  def contacts
    contact_list.values
  end # contacts
  
  # Find a contact by alias or id
  # @param [String] qry
  # @param [Hash] opts
  # @option [String] :room room id
  # @return [Contact, nil]
  def contact(qry, opts = {})
    @contact_list.find(qry, opts)
  end # contact(qry)
  
  # Retrieve all rooms
  def rooms
    room_list.values
  end # rooms
  
  # Find's a room by alias or id
  # @param [String]
  # @return [Room, nil]
  def room(qry)
    @room_list.find(qry)
  end # room(qry)

  # Signals the transport to create a new room and yields it
  # once is has been created
  # @param [String] alis the alias of the room
  # @param [Contacts] *users the users to invite to the room
  # @return [nil]
  def create_room(alis, *users, &blk)
    raise ArgumentError, "a block is required" unless block_given?
    users = users.clone.map{|u| u.is_a?(String) ? contact(u) : u }
    @ons[:mkroom].nil? || @ons[:mkroom].call(alis, users[0], *users[1..-1], blk)
  end # create(alias, *users, &blk)
  
  # Leave a given room
  # @param [Room] rm
  def leave_room(rm)
    raise ArgumentError, "'#{room}' must be a Room" unless rm.is_a?(Room)
    @ons[:leave].nil? || @ons[:leave].call(rm)
    nil
  end # leave_room(rm)
  
  # Invite one or more users to a room
  # @param [Room] rm
  # @param [Contact] user
  # @param [Contacts] extra users to add to the room
  def invite(rm, user, *users, &blk)
    usrs = users.unshift(user)
    @ons[:invite].nil? || (block_given? ? @ons[:invite].call(rm, *usrs, &blk) : @ons[:invite].call(rm, *usrs))
  end # invite
  
  # All currently known answers.
  # @return [Hash]
  def answers
    Hash[@questions.map{|k,e| [(e[:name] || k), e[:desc]] }]
  end # ansers
  
  
  
  
  ##
  # DSL related methods
  ##
  
  # Defines or calls a previously defined helper.
  # If a block is provided then the helper will be defined. If a block is 
  # not provided then the helper will be called.
  # @param [Symbol] name the name of the helper
  # @param [Objects] *args optional arguments to pass to the helper when calling it.
  # @example
  #   # Define a helper called :weather
  #   router.helper :weather do |place = 'Tokyo'|
  #     Net::HTTP.start("www.google.com", 80)  do |google|
  #     # ...
  #     end
  #   end
  # @example
  #   # Call a helper with it's default arguments
  #   router.helper(:weather)
  # @example
  #   # Call a helper with custom arguments
  #   router.helper(:weather, 'Boston')
  def helper(name, *args, &blk)
    if block_given?
      @helpers[name] = blk
      nil
    else
      raise UndefinedHelper.new(name) if @helpers[name].nil?
      @helpers[name].call(*args)
    end # block_given?
  end # helper(name, *args, &blk)
  
  # Describes a question that starbot will answer.
  # @param [String, Regexp] question
  # @param [Hash] opts - not yet used
  # @block The block to evaluate in the context of starbot
  def answer(question, opts = {}, &blk)
    block_to_new_class("SimpleConversation", &blk).tap do |c|
      c.bot    = self
      c.name   = @latest_name
      c.desc   = @latest_desc
      
      start_conversation = Proc.new { |raw, *args| c.new(raw, *args, &blk); nil }
      @questions[question] = {:opts => opts, :blk => start_conversation, :desc => @lastest_desc, :name => @latest_name, 
                              :blacklist => latest_deny.clone, :whitelist => latest_allow.clone }
      @akas.each do |aka|
        @questions[aka] = @questions[question]
      end # |aka|
      
      @lastest_desc = nil
      @latest_name  = nil
      @akas         = []
    end #  |c|
    nil
  end # answer(question, opts = {}, &blk)

  # Describes a conversation that starbot can enter into with a user.
  # @param [String, Regexp] 
  def conversation(question, opts = {}, &blk)
    block_to_new_class(&blk).tap do |c|
      c.before(:all, &blk)
      c.bot    = self
      
      start_conversation = Proc.new { |raw, *args| c.new(raw, *args, &blk); nil }
      @questions[question] = {:opts => opts, :blk => start_conversation, :desc => @lastest_desc, :name => @latest_name,
                              :blacklist => latest_deny.clone, :whitelist => latest_allow.clone }
      @akas.each do |aka|
        @questions[aka] = @questions[question]
      end #  |aka|
      
      @lastest_desc = nil
      @latest_name  = nil
      @akas         = []
    end #  |c|
  end # conversation(first_q, &blk)
  
  def aka(question)
    @akas.push(question)
  end # aka(question)
  
  # Sets the help description for the next answer
  # @param [String] description
  def desc(description)
    @lastest_desc = description
  end # desc(description)
  
  # Set the name of the next answer
  # @param [String] n the name
  def name(n = nil)
    return @name if n.nil?
    @latest_name = n
  end # name(n)

  def latest_allow
    @latest_allow ||= {:rooms => {:list => [], :blk => nil}, :contacts => {:list => [], :blk => nil}}
  end # latest_allow

  def latest_deny
    @latest_deny ||= {:rooms => {:list => [], :blk => nil}, :contacts => {:list => [], :blk => nil}}
  end # latest_allow


  # Sets the white list for the following answer/conversation
  # @param [Symbol] type :contacts, :rooms
  # @param [Strings] list aliases or ids of rooms/contacts to allow
  def allow(type, *list, &blk)
    type = "#{type}"
    type = (type[-1] == 's' ? type : type + 's').to_sym
    latest_deny[type] = {:list => [], :blk => nil}
    latest_allow[type] = {:list => list, :blk => blk}
  end # allow(type, *list)
  
  # Sets the blacklist for the follow answer/conversation
  # @param [Symbol] type :contacts, :rooms
  # @param [Strings] list alias or ids of rooms/contacts to deny
  def deny(type, *list, &blk)
    type = "#{type}"
    type = (type[-1] == 's' ? type  : type + 's').to_sym
    latest_allow[type] = {:list => [], :blk => nil}
    latest_deny[type] = {:list => list, :blk => blk}
  end # deny(type, *list)
  
  
  # Schedule Starbot to do something every :weekday, :workday, :day, :holiday (TBD), second, minute, hour, etc.,.
  # @param [Symbol] day_times - :weekday, :workday, :holiday, :saturday, :sunday, etc.,.
  # @param [String] time ('00:00')
  # @param [Hash] opts
  # @todo support :workday instead of :weekday
  def every(day_times, time = '00:00', opts = {}, &blk)
    return schedule_every(day_times, opts, &blk) if day_times.is_a?(String) && ['s', 'm', 'h', 'w', 'd', 'y'].include?(day_times[-1])
    
    hr,mn = time.split(":")
    mn    = '00' if mn.nil?
    
    cron = "#{mn} #{hr} * * "
    if day_times == :weekday
      cron  += "1-5"
    elsif day_times == :weekend
      cron  += "6-7"
    elsif day_times == :day
      cron += "*"
    else
      raise ConfigurationError, "#{day_times.inspect} is not supported"
    end # days == :weekday
    
    schedule(:cron, cron, opts, &blk)
  end # every(days, time = '00:00', opts = {}, &blk)
  
  # Schedule Starbot to say something in a number of minutes, hours, etc.,.
  # @param [String] at
  # @param [Hash] opts
  # @option opts [String] :tag
  # @option opts [String] :timeout
  # @example
  #   schedule_in '20m' do
  def schedule_in(at, opts = {}, &blk)
    schedule(:in, at, opts, &blk)
  end # schedule_in(at, opts = {}, &blk)
  
  # Schedule Starbot to say something at a specific time, day, etc.,.
  # @param [String] at
  # @param [Hash] opts
  # @option opts [String] :tag
  # @option opts [String] :timeout
  # @example
  #   schedule_at 'Thu Mar 26 07:31:43 +0900 2009' do
  def schedule_at(at, opts = {}, &blk)
    schedule(:at, at, opts, &blk)
  end # schedule_at(at, opts = {}, &blk)

  # Schedule Starbot to say something every minute, hour, etc.,.
  # @param [String] ev
  # @param [Hash] opts
  # @option opts [String] :tag
  # @option opts [String] :timeout
  def schedule_every(ev, opts = {}, &blk)
    schedule(:every, ev, opts, &blk)
  end # schedule_every(at, opts = {}, &blk)
  
  # Schedule Starbot to say something based on a cron schedule
  # @param [String] at
  # @param [Hash] opts
  # @option opts [String] :tag
  # @option opts [String] :timeout
  # @example
  #   schedule_cron '0 22 * * 1-5' do
  def schedule_cron(cron, opts = {}, &blk)
    schedule(:cron, cron, opts, &blk)
  end # schedule_cron(cron, opts = {}, &blk)
  
  # Provides access to all known jobs
  # @see https://github.com/jmettraux/rufus-scheduler
  # @return [Hash] job_id => job of at/in/every jobs
  def scheduled
    @scheduler.all_jobs
  end # scheduled
  
  # Specify a block to call on a specific event
  # events:
  #   :say | Msg |
  #   :sayto | room_contact_id, Msg |
  #   :sayloud | Msg |
  #   :sayloudto | room_contact_id, Msg |
  #   :invite | Room, Contacts |
  #   :leave | Room |
  #   :mkroom | alias, Contacts |
  # @return
  def on(meth, &blk)
    raise "No block given" unless block_given?
    @ons[meth] = blk
  end # on(meth, &blk)

  def say(msg)
    @ons[:say].nil? || @ons[:say].call(msg)
  end
  def sayto(addr, msg)
    @ons[:sayto].nil? || @ons[:sayto].call(addr, msg)
  end
  def sayloud(msg)
    @ons[:sayloud].nil? ? say(msg) : @ons[:sayloud].call(msg)
  end
  def sayloudto(addr, msg)
    @ons[:sayloudto].nil? ? sayloud(msg) : @ons[:sayloudto].call(addr,msg)
  end
  
  
  ##
  # Utility methods

  # @deprecated Context used to be required to enuser that respones went to the sender by default.
  # Now all necessary response information is encapsulated in a Conversation.
  def context
    return unless block_given?
    yield self
  end # context
  
  
  def watch_until(room, contact = nil, &blk)
    (@callbacks["#{room}:#{contact}"] ||= []).push(blk)
  end # watch_until(room, contact = nil)
  def stop_watching(room, contact = nil, &blk)
    (@callbacks["#{room}:#{contact}"] ||= []).delete(blk)
  end # stop_watching(room, contact = nil, &blk)
  
  def route(msg, raw = nil)
    if raw.nil?
      raw = msg.is_a?(Msg) ? msg : Msg.new("#{msg}", "", Time.new.to_i, room(:default))
    end # raw.nil?
    
    begin
      m = msg.strip
      
      if raw.is_a?(Msg)
        if @callbacks["#{raw.room}:#{raw.contact}"].is_a?(Array) && !@callbacks["#{raw.room}:#{raw.contact}"].empty?
          @callbacks["#{raw.room}:#{raw.contact}"].clone.each do |callback|
            @callbacks["#{raw.room}:#{raw.contact}"].delete(callback) if (remove = callback.call(m, raw))
          end #  |callback|
          return nil
          
        elsif @callbacks["#{raw.room}:"].is_a?(Array) && !@callbacks["#{raw.room}:"].empty?
          @callbacks["#{raw.room}:"].clone.each do |callback|
            @callbacks["#{raw.room}:"].delete(callback) if (remove = callback.call(m, raw))
          end #  |callback|
          return nil
        end # @callbacks["#{raw.room}:#{raw.contact}"].is_a?(Array)
      end # raw.is_a?(Msg)
      
      # There's no explicit callback for this room:user or room, so just look for a generic handler
      if @questions[m]
        authorized?(raw, @questions[m]) ? @questions[m][:blk].call(raw) : unauthorized(raw, @questions[m])
      elsif (match = @questions.keys.select{|q| q.is_a?(Regexp) }.find{|q| msg.match(q) })
        # obviously this is slow - we can keep track of regexes on reloads
        mdata      = msg.match(match)
        authorized?(raw, @questions[match]) ? @questions[match][:blk].call(raw, *mdata.to_a[1..-1]) : unauthorized(raw, @questions[match])
      else 
        authorized?(raw, @questions[:default]) ? @questions[:default][:blk].call(raw) : unauthorized(raw, @questions[:default])
      end # @questions[m]
    rescue Exception => e
      report_exception(raw, e)
    end # begin
  end # route(msg)
  
  def load_answers(file = nil, &blk)
    if file.is_a?(String)
      File.expand_path(file).tap do |path|
        if File.exists?(path) 
          instance_eval(IO.read(path), path)
          @answer_file = path
        else
          raise MissingAnswerFile, path
        end
      end
    elsif file.is_a?(IO)
      instance_eval(file.read)
    end
    
    instance_eval(&blk) if block_given?
    self
  end # load_answers(file = nil, &blk)
  
  def reload_answers(file = nil)
    path = file || @answer_file
    raise "a file must be provided either now or at startup" if path.nil?
    path = File.expand_path(path)
    raise "'#{path}' not found" unless File.exists?(path)

    @lastest_desc = nil
    @latest_name  = nil
    @akas         = []
    @latest_deny  = {:contacts => {:list => [], :blk => nil}, :rooms => {:list => [], :blk => nil}}
    @latest_allow = {:contacts => {:list => [], :blk => nil}, :rooms => {:list => [], :blk => nil}}
    
    @questions = {}
    answer(:default) { "I don't understand" }
    
    scheduled.each { |job_id, job| @scheduler.unschedule(job_id) }
    @helpers = {}
    
    instance_eval(IO.read(path), path)
    @questions.keys.count
  end # reload_answers(file = nil)
  
  def lock_memory
    @memory_lock.synchronize do
      yield
    end # 
  end # lock_memory
  
  def restore_memories
    @memoryfile  ||= File.expand_path("config/#{@name}.memories")
    @memories   = File.exists?(@memoryfile) ? YAML.load_file(@memoryfile) : {}
    raise ConfigurationError, "memories must be in a Hash, not a #{@memories.class}" unless @memories.is_a?(Hash)
    @memories
  end # restore_memories
  
  def store_memories(io = nil)
    if io.nil?
      @memoryfile ||= File.expand_path("config/#{@name}.memories")
      File.open(@memoryfile, "w+") {|f| f.puts YAML.dump(@memories || {}) }
    else
      io.write(YAML.dump(@memories || {}))
    end # io.nil?
    @memories
  end # store_memories
  
  # Determines if the msg is authorized by its specified whitelist
  # and blacklist.
  # @param [Msg] msg
  # @param [Hash] opts
  # @option opts [Hash] :blacklist
  # @option opts [Hash] :whitelist
  # @todo look this over in the light of day
  def authorized?(msg, opts = {})
    log.debug("whitelist: #{opts[:whitelist]}")
    log.debug("blacklist: #{opts[:blacklist]}")
    raise ArgumentError, "opts[:blacklist] must be Hash" unless opts[:blacklist].is_a?(Hash)
    raise ArgumentError, "opts[:whitelist] must be Hash" unless opts[:whitelist].is_a?(Hash)
    raise ArgumentError, "opts[:blacklist][:rooms] must be a Hash" unless opts[:blacklist][:rooms].is_a?(Hash)
    raise ArgumentError, "opts[:whitelist][:rooms] must be a Hash" unless opts[:whitelist][:rooms].is_a?(Hash)
    raise ArgumentError, "opts[:blacklist][:contacts] must be a Hash" unless opts[:blacklist][:contacts].is_a?(Hash)
    raise ArgumentError, "opts[:whitelist][:contacts] must be a Hash" unless opts[:whitelist][:contacts].is_a?(Hash)
    
    raise ArgumentError, "opts[:blacklist][:rooms][:list] must be an Array" unless opts[:blacklist][:rooms][:list].is_a?(Array)
    raise ArgumentError, "opts[:whitelist][:rooms][:list] must be an Array" unless opts[:whitelist][:rooms][:list].is_a?(Array)
    raise ArgumentError, "opts[:blacklist][:contacts][:list] must be an Array" unless opts[:blacklist][:contacts][:list].is_a?(Array)
    raise ArgumentError, "opts[:whitelist][:contacts][:list] must be an Array" unless opts[:whitelist][:contacts][:list].is_a?(Array)
    
    blacklist = opts[:blacklist].clone
    blacklist.each { |t, lst| blacklist[t] = lst[:blk].nil? ? lst[:list] : (lst[:list] | instance_eval(&lst[:blk])) }
    whitelist = opts[:whitelist].clone
    whitelist.each { |t, lst| whitelist[t] = lst[:blk].nil? ? lst[:list] : (lst[:list] | instance_eval(&lst[:blk])) }
    
    log.debug("whitelist after block: #{whitelist}")
    log.debug("blacklist after block: #{blacklist}")
    
    return true if whitelist[:contacts].include?(:all)
    return true if whitelist[:contacts].map{|c| @contact_list.find("#{c}") }.compact.find{|wc| wc.id == msg.from.id }
    
    return false if blacklist[:contacts].include?(:all)
    return false if blacklist[:contacts].map{|c| @contact_list.find("#{c}") }.compact.find{|bc| bc.id == msg.from.id }
    
    return true if whitelist[:rooms].include?(:all)
    return true if whitelist[:rooms].map{|r| @room_list.find("#{r}") }.compact.find{|br| br.id == msg.room.id }
    
    return false if blacklist[:rooms].include?(:all)
    return false if blacklist[:rooms].map{|r| @room_list.find("#{r}") }.compact.find{|br| br.id == msg.room.id }
    
    true
  end # authorized?(msg, opts = {})
  
  def unauthorized(msg, opts = {})
    sayloudto(msg.room, "#{msg} use not authorized in this room, or by #{msg.from}")
  end # unauthorized(msg, opts = {})
  
private
  
  def report_exception(raw, e)
    begin
      # put an error in the log
      log.error("In response to '#{raw.txt}' from #{raw.contact.id}, I've encountered an error: \n#{e}\n  #{e.backtrace.join("\n  ")}")

      # tell the one asking the question that we've hit an error
      sayto(raw.room || raw.contact, "I've encountered an error: #{e}")
      # @todo end the conversation ....

      # tell the default room that we've hit an error and provide a backtrace
      say("In response to '#{raw.txt}' from #{raw.contact.id}, I've encountered an error:")
      say("#{e}\n  #{e.backtrace.join("\n  ")}")
      
    rescue Exception => my_e
      puts "Error while reporting another error: #{my_e}\n#{my_e.backtrace}"
      puts "The other error: #{e}\n  #{e.backtrace.join("\n      ")}"
    end # begin
  end # report_exception(e)

  # Creates an empty class that inherits from 'parent' in the
  # Starbot::Conversation namespace. The name of the new class
  # is based on the location of the block provded by the 
  # caller.
  # @param [String] the parent class to inherit from
  # @retur [Class] the class
  def block_to_new_class(parent = "Conversation", &blk)
    name    = blk.source_location
    name[0] = name[0].split("/")[-1].split(".")[0..-2].join("")
    name    = name.join
    name    = name.gsub(/([^A-Za-z\-_0-9])/,"").split(/[\-_]/).map{|p| p.capitalize }.join
    
    name    += "0"
    while ::Starbot::Conversation.const_defined?(name)
      name = name[0..-2] + (name[-1].to_i + 1).to_s
    end # ::Starbot::Conversation.const_defined?(name)
    
    ::Starbot::Conversation.class_eval("class #{name} < #{parent}; end")
    ::Starbot::Conversation.const_get(name)
  end # block_to_new_class(&blk)
  
  # Schedule a block to be run in the context of starbot.
  # @param [Symbol] type - :every, :in, :at, :cron
  # @param [String] at
  # @param [Hash] opts all options accepted by rufus-scheduler
  # @see https://github.com/jmettraux/rufus-scheduler
  def schedule(type, at, opts = {}, &blk)
    opts = {:timeout => '1m'}.merge(opts).merge(:blocking => false)
    klass = block_to_new_class("SimpleConversation", &blk).tap do |c|
      c.bot    = self
    end #  |c|
    
    @scheduler.send(type, at, opts) do
      @lock.synchronize do
        klass.new(Msg.new("", "", Time.new.to_i, room(:default)), &blk)
      end
    end
  end # schedule(type, at, opts = {}, &blk)
end # class::Starbot
